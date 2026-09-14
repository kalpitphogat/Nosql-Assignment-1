#!/usr/bin/env bash
#
# One-time setup on a Linux machine without root: builds PostgreSQL 16.15 and
# the TPC-H dbgen/qgen tools under $ROOT, creates a private database cluster
# (Unix socket only, no TCP) and starts it.
#
# Usage:  ROOT=$HOME/nosql_a1 ./setup_postgres_and_dbgen.sh
# Then:   source $ROOT/env.sh && ./run_benchmark.sh 1 2 4 8
#
# Server configuration below is fixed for every scale factor and recorded by
# run_benchmark.sh in results/environment.txt.

set -euo pipefail
ROOT="${ROOT:-$HOME/nosql_a1}"
PG_VERSION=16.15
PORT="${PORT:-5499}"
JOBS="$(nproc)"

mkdir -p "$ROOT/src" "$ROOT/sock"
cd "$ROOT/src"

if [[ ! -x "$ROOT/pg/bin/postgres" ]]; then
    curl -sSfLO "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2"
    tar xjf "postgresql-$PG_VERSION.tar.bz2"
    cd "postgresql-$PG_VERSION"
    ./configure --prefix="$ROOT/pg" --without-icu > "$ROOT/src/pg_configure.log"
    make -j"$JOBS" > "$ROOT/src/pg_make.log"
    make install > "$ROOT/src/pg_install.log"
    cd "$ROOT/src"
fi

if [[ ! -x "$ROOT/src/tpch-dbgen/dbgen" ]]; then
    git clone -q https://github.com/electrum/tpch-dbgen.git
    # DATABASE only affects qgen's output dialect, not the generated data.
    make -C tpch-dbgen -f makefile.suite CC=gcc DATABASE=ORACLE MACHINE=LINUX WORKLOAD=TPCH \
        > "$ROOT/src/dbgen_make.log" 2>&1
fi
echo "dbgen commit: $(git -C tpch-dbgen rev-parse HEAD)"

cat > "$ROOT/env.sh" <<EOF
export PATH="$ROOT/pg/bin:\$PATH"
export PGHOST="$ROOT/sock" PGPORT=$PORT PGDATABASE=tpch_bench
export DBGEN_DIR="$ROOT/src/tpch-dbgen" DATA_ROOT="$ROOT/data"
EOF
source "$ROOT/env.sh"

if [[ ! -f "$ROOT/pgdata/PG_VERSION" ]]; then
    initdb -D "$ROOT/pgdata" -A trust -U "$USER" > "$ROOT/src/initdb.log"
    cat >> "$ROOT/pgdata/postgresql.conf" <<EOF

# --- TPC-H scaling study (identical for all scale factors) ---
listen_addresses = ''                 # Unix socket only
port = $PORT
unix_socket_directories = '$ROOT/sock'
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 128MB
maintenance_work_mem = 1GB
max_parallel_workers_per_gather = 4
random_page_cost = 1.1                # NVMe SSD
max_wal_size = 8GB
jit = off                             # avoid JIT compile time skewing short queries
EOF
fi

pg_ctl -D "$ROOT/pgdata" -l "$ROOT/pg.log" status > /dev/null || pg_ctl -D "$ROOT/pgdata" -l "$ROOT/pg.log" -w start
createdb tpch_bench 2> /dev/null || true
psql -At -c "select version()"
echo "Ready. Next: source $ROOT/env.sh && ./run_benchmark.sh 1 2 4 8"
echo "Stop the server when finished: pg_ctl -D $ROOT/pgdata stop"
