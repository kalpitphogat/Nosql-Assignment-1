#!/usr/bin/env bash
# Generates progressively larger transaction datasets and times pipeline.sh
# on each. Writes results.tsv (size, record_count, seconds).

set -uo pipefail
cd "$(dirname "$0")"

SIZES=(2500000 6250000 12500000 25000000)  # ~100MB / 250MB / 500MB / 1GB at ~40 bytes/record
RESULTS="scalability_results.tsv"
echo -e "records\tfile_size_bytes\tfile_size_mb\tseconds" > "$RESULTS"

for n in "${SIZES[@]}"; do
    f="transactions_${n}.tsv"
    if [[ ! -f "$f" ]]; then
        echo "Generating $f ..." >&2
        ./generate_transactions --records "$n" --seed 42 > "$f"
    fi
    bytes=$(wc -c < "$f" | tr -d ' ')
    mb=$(echo "scale=1; $bytes/1048576" | bc)

    start=$(date +%s.%N)
    ./pipeline.sh "$f" "out_${n}.tsv" > /dev/null 2>&1
    end=$(date +%s.%N)
    secs=$(echo "scale=3; $end - $start" | bc)

    echo -e "${n}\t${bytes}\t${mb}\t${secs}" >> "$RESULTS"
    echo "records=$n size=${mb}MB time=${secs}s" >&2
done

echo "Done. See $RESULTS" >&2
