#!/usr/bin/env bash
#
# One-time setup on a Linux machine without root: builds PostgreSQL 16.15 and
# the OFFICIAL TPC-H V3.0.1 dbgen/qgen under $ROOT, records provenance
# (SHA-256 of the kit archive, binaries, dists.dss and query templates),
# creates a private database cluster (Unix socket only, C locale) and starts it.
#
# The TPC-H kit is not redistributable; download it from
#   https://www.tpc.org/tpc_documents_current_versions/current_specifications5.asp
# (TPC-H Tools v3.0.1) and pass its path:
#
# Usage:  TPCH_KIT=/path/to/<id>-TPC-H-Tool.zip ROOT=$HOME/nosql_a1 ./setup_postgres_and_dbgen.sh
# Then:   source $ROOT/env.sh && ./run_benchmark.sh 1 2 4 8 16 32

set -euo pipefail
ROOT="${ROOT:-$HOME/nosql_a1}"
TPCH_KIT="$(realpath "${TPCH_KIT:?set TPCH_KIT to the official TPC-H Tools v3.0.1 zip}")"
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

KIT_DIR="$ROOT/src/tpch_v3.0.1"
DBGEN_DIR="$KIT_DIR/dbgen"             # the kit's "TPC-H V3.0.1/dbgen", moved to a path without spaces
if [[ ! -x "$DBGEN_DIR/qgen" ]]; then
    rm -rf "$KIT_DIR" "$ROOT/src/kit_unzip" && mkdir -p "$ROOT/src/kit_unzip"
    unzip -q "$TPCH_KIT" -d "$ROOT/src/kit_unzip"
    mv "$ROOT/src/kit_unzip/TPC-H V3.0.1" "$KIT_DIR" && rmdir "$ROOT/src/kit_unzip"
    # DATABASE only selects qgen's SQL dialect (adapt_query.py converts ORACLE's
    # row-limit syntax to PostgreSQL); the generated data does not depend on it.
    make -C "$DBGEN_DIR" -f makefile.suite CC=gcc DATABASE=ORACLE MACHINE=LINUX WORKLOAD=TPCH \
        > "$ROOT/src/dbgen_make.log" 2>&1
fi

{
    echo "TPC-H kit archive: $(basename "$TPCH_KIT")"
    echo "  source: https://www.tpc.org/tpc_documents_current_versions/current_specifications5.asp (TPC-H Tools v3.0.1)"
    echo "  sha256: $(sha256sum "$TPCH_KIT" | cut -d' ' -f1)"
    echo "build: make -f makefile.suite CC=gcc DATABASE=ORACLE MACHINE=LINUX WORKLOAD=TPCH  ($(gcc --version | head -1))"
    echo "dbgen banner: $("$DBGEN_DIR/dbgen" -h 2>&1 | head -1)"
    echo "qgen banner:  $("$DBGEN_DIR/qgen" -h 2>&1 | head -1)"
    echo "sha256 of tools and inputs:"
    (cd "$DBGEN_DIR" && sha256sum dbgen qgen dists.dss queries/*.sql | sed 's/^/  /')
} > "$ROOT/tpch_provenance.txt"

cat > "$ROOT/env.sh" <<EOF
export PATH="$ROOT/pg/bin:\$PATH"
export PGHOST="$ROOT/sock" PGPORT=$PORT PGDATABASE=tpch_bench
export DBGEN_DIR="$DBGEN_DIR" DATA_ROOT="$ROOT/data" TPCH_PROVENANCE="$ROOT/tpch_provenance.txt"
EOF
source "$ROOT/env.sh"

if [[ ! -f "$ROOT/pgdata/PG_VERSION" ]]; then
    # C locale: byte-order string comparison, as assumed by the official answer set.
    initdb -D "$ROOT/pgdata" -A trust -U "$USER" --locale=C --encoding=UTF8 > "$ROOT/src/initdb.log"
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
cat "$ROOT/tpch_provenance.txt" | head -7
echo "Ready. Next: source $ROOT/env.sh && ./run_benchmark.sh 1 2 4 8 16 32"
echo "Stop the server when finished: pg_ctl -D $ROOT/pgdata stop"
