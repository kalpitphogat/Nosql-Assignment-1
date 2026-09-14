#!/usr/bin/env bash
#
# TPC-H scaling study driver (PostgreSQL, official TPC-H V3.0.1 tools).
#
# For each scale factor:
#   1. Generate the dataset with the official dbgen.
#   2. Generate the 22 queries for THIS scale factor with the official qgen
#      (generate_queries.sh: fixed seed, -s SF, so SF-dependent parameters such
#      as Q11's FRACTION = 0.0001/SF are correct) and save their SHA-256.
#   3. Load into a fresh schema (streamed into COPY), build indexes, ANALYZE,
#      record row counts and on-disk size.
#   4. Save the EXPLAIN plan of every query.
#   5. Run all 22 queries once as a warm-up (run 0, excluded from statistics),
#      then REPS measured runs, recording wall-clock time and ok/error/timeout.
#
# Usage:  ./run_benchmark.sh [scale_factor ...]      (default: 1 2 4 8)
#
# Environment (set by $ROOT/env.sh from setup_postgres_and_dbgen.sh):
#   PGHOST/PGPORT/PGDATABASE  connection settings (PGDATABASE default tpch_bench)
#   DBGEN_DIR   official kit's built dbgen directory (dbgen, qgen, dists.dss, queries/)
#   DATA_ROOT   where .tbl files are generated    (default: $DBGEN_DIR/data)
#   REPS        measured repetitions per query    (default: 3)
#   TIMEOUT     per-query statement_timeout       (default: 30min, same for every SF)

set -uo pipefail
cd "$(dirname "$0")"

[[ -n "${PG_BIN:-}" ]] && export PATH="$PG_BIN:$PATH"
export PGDATABASE="${PGDATABASE:-tpch_bench}"

SCALE_FACTORS=("$@")
[[ ${#SCALE_FACTORS[@]} -eq 0 ]] && SCALE_FACTORS=(1 2 4 8)

DBGEN_DIR="$(cd "${DBGEN_DIR:?set DBGEN_DIR (source env.sh)}" && pwd)"
export DBGEN_DIR
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
[[ -f "$ROWS_CSV" ]]    || echo "scale_factor,table,generated_rows,loaded_rows" > "$ROWS_CSV"

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'; }
q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

# Record the environment (appended once per invocation, so every run is documented).
{
    echo "===== invocation: $0 ${SCALE_FACTORS[*]} ====="
    echo "date: $(date)"
    echo "host: $(uname -a)"
    grep PRETTY_NAME /etc/os-release 2>/dev/null
    lscpu 2>/dev/null | grep -E 'Model name|^CPU\(s\)|Core\(s\) per socket|Thread|Socket'
    free -g 2>/dev/null
    lsblk -d -o NAME,ROTA,SIZE,MODEL 2>/dev/null
    df -h "$DATA_ROOT" 2>/dev/null || df -h .
    echo "load average: $(cat /proc/loadavg 2>/dev/null)"
    echo "other logged-in users: $(who | wc -l)"
    echo "gcc: $(gcc --version 2>/dev/null | head -1)"
    echo "postgres: $(q -At -c 'select version()')"
    q -At -c "select name || ' = ' || setting || coalesce(' ' || unit, '') from pg_settings
              where name in ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size',
                             'max_parallel_workers_per_gather','max_worker_processes','random_page_cost',
                             'jit','max_wal_size','synchronous_commit')"
    echo "dbgen banner: $("$DBGEN_DIR/dbgen" -h 2>&1 | head -1)"
    echo "qgen banner:  $("$DBGEN_DIR/qgen" -h 2>&1 | head -1)"
    echo "warm-up runs: 1 (run 0, excluded)   measured runs: $REPS   statement_timeout: $TIMEOUT"
} >> "$RESULTS_DIR/environment.txt"
[[ -f "${TPCH_PROVENANCE:-}" ]] && cp "$TPCH_PROVENANCE" "$RESULTS_DIR/tpch_provenance.txt"

for sf in "${SCALE_FACTORS[@]}"; do
    echo "=== Scale factor $sf ===" >&2
    DATA_DIR="$DATA_ROOT/sf${sf}"
    QDIR="queries/sf${sf}"
    mkdir -p "$DATA_DIR"
    cp "$DBGEN_DIR/dists.dss" "$DATA_DIR/"

    bash generate_queries.sh "$sf" || { echo "query generation failed at SF=$sf" >&2; exit 1; }

    # Drop the previous SF's tables first so its data and the new .tbl files
    # never occupy disk at the same time.
    q -f schema.sql > /dev/null || { echo "schema.sql failed" >&2; exit 1; }
    if [[ ! -f "$DATA_DIR/lineitem.tbl" ]]; then
        echo "Generating data at SF=$sf ..." >&2
        (cd "$DATA_DIR" && "$DBGEN_DIR/dbgen" -s "$sf" -f) || { echo "dbgen failed" >&2; exit 1; }
    fi
    dataset_mb=$(wc -c "$DATA_DIR"/*.tbl | tail -n 1 | awk '{ printf "%.1f", $1 / 1048576 }')

    echo "Loading SF=$sf ($dataset_mb MB) ..." >&2
    declare -A generated=()
    for t in "${TABLES[@]}"; do generated[$t]=$(wc -l < "$DATA_DIR/${t}.tbl"); done
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
        loaded=$(q -At -c "select count(*) from $t")
        echo "$sf,$t,${generated[$t]},$loaded" >> "$ROWS_CSV"
        [[ "$loaded" == "${generated[$t]}" ]] ||
            { echo "Row count mismatch for $t at SF=$sf (${generated[$t]} generated, $loaded loaded)" >&2; exit 1; }
    done
    echo "Load + index + analyze: ${load_secs}s, database size ${db_mb} MB" >&2

    if [[ "$sf" == 1 ]]; then
        bash validate_answers.sh ||
            echo "WARNING: SF1 official answer validation had mismatches -- see results/answer_validation.csv" >&2
    fi

    for n in $(seq 1 22); do
        q -c "DROP VIEW IF EXISTS revenue0" > /dev/null 2>&1
        sed -E 's/^select([[:space:]]|$)/explain select\1/' "$QDIR/${n}.sql" |
            q > "$RESULTS_DIR/plans/sf${sf}_q${n}.txt" 2>&1
    done

    for run in $(seq 0 "$REPS"); do          # run 0 = warm-up
        total=0; failed=0
        for n in $(seq 1 22); do
            out="$RESULTS_DIR/output/sf${sf}_q${n}.out"
            err="$RESULTS_DIR/output/sf${sf}_q${n}.err"
            q -c "DROP VIEW IF EXISTS revenue0" > /dev/null 2>&1  # Q15 leaves it behind if it fails
            t0=$(now)
            PGOPTIONS="-c statement_timeout=$TIMEOUT" q -f "$QDIR/${n}.sql" > "$out" 2> "$err"
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
        [[ $run -gt 0 ]] && echo "$sf,$dataset_mb,$db_mb,$load_secs,$run,$total,$failed" >> "$TOTALS_CSV"
        echo "SF=$sf run=$run$([[ $run -eq 0 ]] && echo ' (warm-up)') total ${total}s, failed/timed-out queries: $failed" >&2
    done
done

echo "Done. See $TIMINGS_CSV, $TOTALS_CSV, $ROWS_CSV" >&2
