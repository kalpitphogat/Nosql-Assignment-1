#!/usr/bin/env bash
#
# Unix data-processing pipeline for transactions TSV files.
#
# Implements (without a database, and without loading the file into memory):
#
#   SELECT category, COUNT(*) AS transactions, SUM(quantity * price) AS revenue
#   FROM transactions
#   WHERE date >= '2026-01-01' AND quantity > 2
#   GROUP BY category
#   HAVING SUM(quantity * price) > 100000
#   ORDER BY revenue DESC
#   LIMIT 10;
#
# Usage:
#   ./pipeline.sh <input.tsv> [output.tsv]
#
# Input: tab-separated with a header row naming the columns. Columns are found
# by name, so both the generator's order (transaction_id date category
# quantity price) and the sample file's order work.
#
# Malformed rows are written, with the reason, to <input>.malformed_rows.tsv
# (override with MALFORMED=path) and excluded; the pipeline keeps running.

set -uo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input.tsv> [output.tsv]" >&2
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-/dev/stdout}"
MALFORMED="${MALFORMED:-${INPUT%.tsv}.malformed_rows.tsv}"

if [[ ! -f "$INPUT" ]]; then
    echo "Input file not found: $INPUT" >&2
    exit 1
fi

# Byte-wise collation: faster sort and identical results on every machine.
export LC_ALL=C

# Stage 0 (schema resolution): locate columns by name from the header.
HEADER=$(head -n 1 "$INPUT" | tr -d '\r')
col() {
    printf '%s\n' "$HEADER" | tr '\t' '\n' | grep -nx "$1" | cut -d: -f1
}
C_CAT=$(col category)
C_QTY=$(col quantity)
C_PRICE=$(col price)
C_DATE=$(col date)
NCOLS=$(printf '%s\n' "$HEADER" | awk -F'\t' '{print NF}')

for name in C_CAT C_QTY C_PRICE C_DATE; do
    if [[ -z "${!name}" ]]; then
        echo "Could not locate required column '$name' in header: $HEADER" >&2
        exit 1
    fi
done

# Stage 1  validation     : awk, one row at a time; bad rows -> $MALFORMED
# Stage 2  selection      : awk, WHERE date >= 2026-01-01 AND quantity > 2
# Stage 3  projection     : same awk, emit only category, quantity, price
# Stage 4  grouping prep  : sort by category (external merge sort)
# Stage 5  aggregation    : awk, COUNT/SUM per run of equal keys + HAVING
# Stage 6  ordering       : sort by revenue, numeric, descending
# Stage 7  top-K          : head -n 10

validate_filter_project() {
awk -F'\t' -v cat="$C_CAT" -v qty="$C_QTY" -v price="$C_PRICE" \
    -v datecol="$C_DATE" -v ncols="$NCOLS" -v malformed="$MALFORMED" '
    BEGIN {
        printf "" > malformed
        split("31 28 31 30 31 30 31 31 30 31 30 31", mdays, " ")
    }
    function valid_date(s,    y, m, d, lim) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
        y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
        if (m < 1 || m > 12 || d < 1) return 0
        lim = mdays[m]
        if (m == 2 && ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)) lim = 29
        return d <= lim
    }
    function reject(reason) { print reason "\t" $0 > malformed; bad++ }
    {
        sub(/\r$/, "")
        if (NF != ncols)                                 { reject("field_count_" NF); next }
        if ($cat == "")                                  { reject("empty_category"); next }
        if ($qty !~ /^[0-9]+$/)                          { reject("bad_quantity");   next }
        if ($price !~ /^[0-9]+(\.[0-9]+)?$/)             { reject("bad_price");      next }
        if (!($datecol in date_ok)) date_ok[$datecol] = valid_date($datecol)  # ~730 distinct dates
        if (!date_ok[$datecol])                          { reject("bad_date");       next }
        if ($datecol >= "2026-01-01" && $qty + 0 > 2)
            print $cat "\t" $qty "\t" $price
    }
    END { printf "Malformed rows excluded: %d (see %s)\n", bad, malformed > "/dev/stderr" }
'
}

sort_by_category() { sort -t $'\t' -k1,1 -S 256M; }

aggregate_having() {
awk -F'\t' '
    function emit() { if (n > 0 && rev > 100000) printf "%s\t%d\t%.2f\n", key, n, rev }
    $1 != key { emit(); key = $1; n = 0; rev = 0 }
    { n++; rev += $2 * $3 }
    END { emit() }
'
}

order_by_revenue() { sort -t $'\t' -k3,3gr; }

# STOP_AFTER=<stage> runs the pipeline only up to that stage (output discarded);
# stage_timing.sh uses it to measure how much time each stage adds.
case "${STOP_AFTER:-}" in
    read)      tail -n +2 "$INPUT" > /dev/null ;;
    validate)  tail -n +2 "$INPUT" | validate_filter_project > /dev/null ;;
    sort)      tail -n +2 "$INPUT" | validate_filter_project | sort_by_category > /dev/null ;;
    aggregate) tail -n +2 "$INPUT" | validate_filter_project | sort_by_category | aggregate_having > /dev/null ;;
    "")
        tail -n +2 "$INPUT" |
        validate_filter_project |
        sort_by_category |
        aggregate_having |
        order_by_revenue |
        head -n 10 |
        { printf 'category\ttransactions\trevenue\n'; cat; } > "$OUTPUT"
        ;;
    *)  echo "Unknown STOP_AFTER='$STOP_AFTER' (use read|validate|sort|aggregate)" >&2; exit 1 ;;
esac
