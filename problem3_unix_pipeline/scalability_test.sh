#!/usr/bin/env bash
# Generates progressively larger transaction datasets and times pipeline.sh
# on each (REPS repetitions, default 3).
#
# Usage: ./scalability_test.sh [data_dir]     (default: ./data)
# Output: scalability_results.tsv  (one row per run)
#         outputs/out_<records>.tsv

set -uo pipefail
cd "$(dirname "$0")"

DATA_DIR="${1:-data}"
REPS="${REPS:-3}"
GEN="${GEN:-./generate_transactions}"   # e.g. GEN="python ./generate_transactions" on Windows
SIZES=(2500000 6250000 12500000 25000000)  # ~100 / 250 / 500 / 1000 MB at ~43 bytes/record
export LC_ALL=C

mkdir -p "$DATA_DIR" outputs
RESULTS="scalability_results.tsv"
printf 'records\tfile_size_bytes\tfile_size_mb\trun\tseconds\n' > "$RESULTS"

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'; }

for n in "${SIZES[@]}"; do
    f="$DATA_DIR/transactions_${n}.tsv"
    if [[ ! -f "$f" ]]; then
        echo "Generating $f ..." >&2
        # tr: Python on Windows writes CRLF; keep files byte-identical across OSes
        $GEN --records "$n" --seed 42 | tr -d '\r' > "$f"
    fi
    bytes=$(wc -c < "$f" | tr -d ' ')
    mb=$(awk -v b="$bytes" 'BEGIN { printf "%.1f", b / 1048576 }')

    cat "$f" > /dev/null   # warm the OS page cache so run 1 is not an outlier

    for r in $(seq 1 "$REPS"); do
        start=$(now)
        MALFORMED="$DATA_DIR/malformed_${n}.tsv" ./pipeline.sh "$f" "outputs/out_${n}.tsv" 2>/dev/null
        secs=$(elapsed "$start" "$(now)")
        printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$bytes" "$mb" "$r" "$secs" >> "$RESULTS"
        echo "records=$n size=${mb}MB run=$r time=${secs}s" >&2
    done
done

echo "Done. See $RESULTS (per-stage breakdown: ./stage_timing.sh $DATA_DIR)" >&2
