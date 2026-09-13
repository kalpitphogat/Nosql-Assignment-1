#!/usr/bin/env bash
#
# TPC-H scaling study driver.
#
# For each scale factor in SCALE_FACTORS:
#   1. Generate the dataset with dbgen (if not already generated).
#   2. Load it into a fresh PostgreSQL database.
#   3. Run all 22 TPC-H queries (queries_final/*.sql), timing each one.
#   4. Record per-query and total execution time to results/timings.csv.
#
# Usage: ./run_benchmark.sh [scale_factor ...]
#        (defaults to 1 2 4 8 if no args given)

set -uo pipefail
cd "$(dirname "$0")"

export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"

SCALE_FACTORS=("$@")
if [[ ${#SCALE_FACTORS[@]} -eq 0 ]]; then
    SCALE_FACTORS=(1 2 4 8)
fi

DB=tpch_bench
DBGEN_DIR="dbgen"
RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR"
TIMINGS_CSV="$RESULTS_DIR/timings.csv"
echo "scale_factor,query,seconds" > "$TIMINGS_CSV"
TOTALS_CSV="$RESULTS_DIR/totals.csv"
echo "scale_factor,dataset_size_mb,total_query_seconds,load_seconds" > "$TOTALS_CSV"

TABLES=(region nation part supplier partsupp customer orders lineitem)

for sf in "${SCALE_FACTORS[@]}"; do
    echo "=== Scale factor $sf ===" >&2
    DATA_DIR="$DBGEN_DIR/data/sf${sf}"
    mkdir -p "$DATA_DIR"
    cp "$DBGEN_DIR/dists.dss" "$DATA_DIR/"

    if [[ ! -f "$DATA_DIR/lineitem.tbl" ]]; then
        echo "Generating data at SF=$sf ..." >&2
        (cd "$DATA_DIR" && "../../dbgen" -s "$sf" -f) >&2
    fi

    dataset_bytes=$(du -sk "$DATA_DIR"/*.tbl | awk '{s+=$1} END {print s*1024}')
    dataset_mb=$(echo "scale=1; $dataset_bytes/1048576" | bc)

    echo "Loading into PostgreSQL ($DB) ..." >&2
    psql -d "$DB" -v ON_ERROR_STOP=1 -f schema.sql > /dev/null

    load_start=$(date +%s.%N)
    for t in "${TABLES[@]}"; do
        # dbgen .tbl files are '|'-delimited with a trailing '|' on each line,
        # which CSV mode treats as an extra empty column -- strip it first.
        sed 's/|$//' "$DATA_DIR/${t}.tbl" > "$DATA_DIR/${t}.tbl.clean"
        psql -d "$DB" -c "\copy $t FROM '$(pwd)/$DATA_DIR/${t}.tbl.clean' WITH (FORMAT csv, DELIMITER '|')" > /dev/null
        rm -f "$DATA_DIR/${t}.tbl.clean"
    done
    echo "Building indexes ..." >&2
    psql -d "$DB" -v ON_ERROR_STOP=1 -f indexes.sql > /dev/null
    load_end=$(date +%s.%N)
    load_secs=$(echo "scale=3; $load_end - $load_start" | bc)
    echo "Load + index build took ${load_secs}s" >&2

    # Free disk: raw .tbl files are reproducible from dbgen -s <SF> -f and
    # are not needed once loaded (data is preserved in Postgres for as long
    # as this scale factor's queries are running).
    rm -f "$DATA_DIR"/*.tbl

    echo "Analyzing tables ..." >&2
    psql -d "$DB" -c "ANALYZE;" > /dev/null

    total=0
    for q in $(seq 1 22); do
        qfile="queries_final/${q}.sql"
        start=$(date +%s.%N)
        psql -d "$DB" -f "$qfile" > "$RESULTS_DIR/sf${sf}_q${q}.out" 2> "$RESULTS_DIR/sf${sf}_q${q}.err"
        end=$(date +%s.%N)
        secs=$(echo "scale=3; $end - $start" | bc)
        echo "${sf},${q},${secs}" >> "$TIMINGS_CSV"
        total=$(echo "scale=3; $total + $secs" | bc)
        echo "  Q${q}: ${secs}s" >&2
    done

    echo "${sf},${dataset_mb},${total},${load_secs}" >> "$TOTALS_CSV"
    echo "SF=$sf total query time: ${total}s (dataset ${dataset_mb} MB, load ${load_secs}s)" >&2
    echo >&2
done

echo "Done. See $TIMINGS_CSV and $TOTALS_CSV" >&2
