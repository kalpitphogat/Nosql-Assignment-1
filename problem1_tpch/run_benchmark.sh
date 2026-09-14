#!/usr/bin/env bash
#
# TPC-H scaling study driver (PostgreSQL).
#
# For each scale factor:
#   1. Generate the dataset with dbgen.
#   2. Load it into a fresh schema (streamed into COPY, no temporary copies),
#      build indexes, ANALYZE, and record row counts + on-disk size.
#   3. Save the EXPLAIN plan of every query (for the analysis).
#   4. Run all 22 queries REPS times, recording wall-clock time and whether the
#      query succeeded, failed or hit the timeout.
#
# Usage:  ./run_benchmark.sh [scale_factor ...]      (default: 1 2 4 8)
#
# Environment (all optional):
#   PG_BIN      directory holding psql            (default: psql on PATH)
#   PGHOST/PGPORT/PGDATABASE  connection settings (PGDATABASE default tpch_bench)
#   DBGEN_DIR   directory with the built dbgen + dists.dss   (default: dbgen)
#   DATA_ROOT   where .tbl files are generated    (default: $DBGEN_DIR/data)
#   REPS        repetitions per query             (default: 3)
#   TIMEOUT     per-query statement_timeout       (default: 30min)

set -uo pipefail
cd "$(dirname "$0")"

[[ -n "${PG_BIN:-}" ]] && export PATH="$PG_BIN:$PATH"
export PGDATABASE="${PGDATABASE:-tpch_bench}"

SCALE_FACTORS=("$@")
[[ ${#SCALE_FACTORS[@]} -eq 0 ]] && SCALE_FACTORS=(1 2 4 8)

DBGEN_DIR="$(cd "${DBGEN_DIR:-dbgen}" && pwd)"
DATA_ROOT="${DATA_ROOT:-$DBGEN_DIR/data}"
REPS="${REPS:-3}"
TIMEOUT="${TIMEOUT:-30min}"
RESULTS_DIR="results"
TABLES=(region nation part supplier partsupp customer orders lineitem)

mkdir -p "$RESULTS_DIR/output" "$RESULTS_DIR/plans"
TIMINGS_CSV="$RESULTS_DIR/timings.csv"
TOTALS_CSV="$RESULTS_DIR/totals.csv"
ROWS_CSV="$RESULTS_DIR/row_counts.csv"
[[ -f "$TIMINGS_CSV" ]] || echo "scale_factor,query,run,seconds,status" > "$TIMINGS_CSV"
[[ -f "$TOTALS_CSV" ]]  || echo "scale_factor,dataset_size_mb,db_size_mb,load_index_seconds,run,total_query_seconds,failed_queries" > "$TOTALS_CSV"
[[ -f "$ROWS_CSV" ]]    || echo "scale_factor,table,rows" > "$ROWS_CSV"

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'; }
q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

# Record the environment once, next to the results.
{
    echo "date: $(date)"
    echo "host: $(uname -a)"
    lscpu 2>/dev/null | grep -E 'Model name|^CPU\(s\)|Thread|Socket' || sysctl -n machdep.cpu.brand_string 2>/dev/null
    free -g 2>/dev/null || true
    echo "postgres: $(q -At -c 'select version()')"
    q -At -c "select name || ' = ' || setting || coalesce(' ' || unit, '') from pg_settings
              where name in ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size',
                             'max_parallel_workers_per_gather','max_worker_processes','random_page_cost',
                             'jit','max_wal_size','synchronous_commit')"
    echo "dbgen: $("$DBGEN_DIR/dbgen" -h 2>&1 | head -1)"
    echo "reps: $REPS   timeout: $TIMEOUT"
} > "$RESULTS_DIR/environment.txt"

for sf in "${SCALE_FACTORS[@]}"; do
    echo "=== Scale factor $sf ===" >&2
    DATA_DIR="$DATA_ROOT/sf${sf}"
    mkdir -p "$DATA_DIR"
    cp "$DBGEN_DIR/dists.dss" "$DATA_DIR/"
    # Drop the previous SF's tables first so its data and the new .tbl files
    # never occupy disk at the same time.
    q -f schema.sql > /dev/null || { echo "schema.sql failed" >&2; exit 1; }
    if [[ ! -f "$DATA_DIR/lineitem.tbl" ]]; then
        echo "Generating data at SF=$sf ..." >&2
        (cd "$DATA_DIR" && "$DBGEN_DIR/dbgen" -s "$sf" -f) || { echo "dbgen failed" >&2; exit 1; }
    fi
    dataset_mb=$(wc -c "$DATA_DIR"/*.tbl | tail -n 1 | awk '{ printf "%.1f", $1 / 1048576 }')

    echo "Loading SF=$sf ($dataset_mb MB) ..." >&2
    t0=$(now)
    for t in "${TABLES[@]}"; do
        # dbgen ends every line with '|', which COPY would read as an extra column.
        sed 's/|$//' "$DATA_DIR/${t}.tbl" |
            q -c "\copy $t FROM STDIN WITH (FORMAT csv, DELIMITER '|')" ||
            { echo "COPY $t failed at SF=$sf -- aborting (results would be meaningless)" >&2; exit 1; }
        rm -f "$DATA_DIR/${t}.tbl"   # reproducible with dbgen; keeps peak disk use down
    done
    q -f indexes.sql > /dev/null || { echo "indexes.sql failed" >&2; exit 1; }
    q -c "VACUUM ANALYZE;" > /dev/null
    load_secs=$(elapsed "$t0" "$(now)")
    db_mb=$(q -At -c "select round(pg_database_size(current_database()) / 1048576.0, 1)")
    for t in "${TABLES[@]}"; do
        echo "$sf,$t,$(q -At -c "select count(*) from $t")" >> "$ROWS_CSV"
    done
    echo "Load + index + analyze: ${load_secs}s, database size ${db_mb} MB" >&2

    for n in $(seq 1 22); do
        sed 's/^select$/explain select/' "queries_final/${n}.sql" |
            q > "$RESULTS_DIR/plans/sf${sf}_q${n}.txt" 2>&1
    done

    for run in $(seq 1 "$REPS"); do
        total=0; failed=0
        for n in $(seq 1 22); do
            out="$RESULTS_DIR/output/sf${sf}_q${n}.out"
            err="$RESULTS_DIR/output/sf${sf}_q${n}.err"
            q -c "DROP VIEW IF EXISTS revenue0" > /dev/null 2>&1  # Q15 leaves it behind if it times out
            t0=$(now)
            PGOPTIONS="-c statement_timeout=$TIMEOUT" q -f "queries_final/${n}.sql" > "$out" 2> "$err"
            rc=$?
            secs=$(elapsed "$t0" "$(now)")
            if [[ $rc -eq 0 ]]; then status=ok
            elif grep -q "statement timeout" "$err"; then status=timeout; failed=$((failed + 1))
            else status=error; failed=$((failed + 1)); fi
            echo "$sf,$n,$run,$secs,$status" >> "$TIMINGS_CSV"
            total=$(awk -v a="$total" -v b="$secs" 'BEGIN { printf "%.3f", a + b }')
            echo "  SF=$sf run=$run Q$n: ${secs}s $status" >&2
            [[ $status == error ]] && cat "$err" >&2
        done
        echo "$sf,$dataset_mb,$db_mb,$load_secs,$run,$total,$failed" >> "$TOTALS_CSV"
        echo "SF=$sf run=$run total ${total}s, failed/timed-out queries: $failed" >&2
    done
done

echo "Done. See $TIMINGS_CSV, $TOTALS_CSV, $ROWS_CSV" >&2
