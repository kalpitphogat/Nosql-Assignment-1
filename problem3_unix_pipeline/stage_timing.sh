#!/usr/bin/env bash
# Measures how much time each pipeline stage adds, by running pipeline.sh with
# STOP_AFTER set to successively later stages on the datasets produced by
# scalability_test.sh. The code timed is exactly the code in pipeline.sh.
#
# Usage: ./stage_timing.sh [data_dir]     (default: ./data)
# Output: stage_timings.tsv (records, size, stage prefix, run, seconds)

set -uo pipefail
cd "$(dirname "$0")"

DATA_DIR="${1:-data}"
REPS="${REPS:-3}"
SIZES=(2500000 6250000 12500000 25000000)
OUT="stage_timings.tsv"
export LC_ALL=C

now() { date +%s.%N; }
elapsed() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", b - a }'; }

printf 'records\tfile_size_mb\tstage_prefix\trun\tseconds\n' > "$OUT"

for n in "${SIZES[@]}"; do
    f="$DATA_DIR/transactions_${n}.tsv"
    [[ -f "$f" ]] || { echo "Missing $f (run scalability_test.sh first)" >&2; exit 1; }
    mb=$(awk -v b="$(wc -c < "$f")" 'BEGIN { printf "%.1f", b / 1048576 }')
    cat "$f" > /dev/null

    for r in $(seq 1 "$REPS"); do
        for stage in read validate sort aggregate full; do
            s=$stage; [[ $s == full ]] && s=""
            t0=$(now)
            STOP_AFTER="$s" MALFORMED="$DATA_DIR/malformed_${n}.tsv" ./pipeline.sh "$f" /dev/null 2>/dev/null
            secs=$(elapsed "$t0" "$(now)")
            printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$mb" "$stage" "$r" "$secs" >> "$OUT"
            echo "records=$n stage<=$stage run=$r ${secs}s" >&2
        done
    done
done

echo "Done. See $OUT" >&2
