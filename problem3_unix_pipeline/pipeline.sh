#!/usr/bin/env bash
#
# Unix data-processing pipeline for transactions.tsv
#
# Implements (without a database, and without loading the file fully into memory):
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
# Input schema (tab-separated, header row required):
#   transaction_id  product_id  category  quantity  price  date
#
# Malformed rows (missing field, non-numeric quantity/price, bad date) are
# routed to <input>.malformed.tsv instead of aborting the pipeline.

set -uo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input.tsv> [output.tsv]" >&2
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-/dev/stdout}"
MALFORMED="${INPUT%.tsv}.malformed_rows.tsv"

if [[ ! -f "$INPUT" ]]; then
    echo "Input file not found: $INPUT" >&2
    exit 1
fi

# Column positions are read from the header rather than hardcoded, since the
# supplied transactions.tsv column order (transaction_id product_id category
# quantity price date) differs from the order named in the assignment PDF
# (transaction_id date category quantity price).
HEADER=$(head -n 1 "$INPUT")
col() {
    echo "$HEADER" | tr '\t' '\n' | grep -nx "$1" | cut -d: -f1
}
C_CAT=$(col category)
C_QTY=$(col quantity)
C_PRICE=$(col price)
C_DATE=$(col date)

for name in C_CAT C_QTY C_PRICE C_DATE; do
    if [[ -z "${!name}" ]]; then
        echo "Could not locate required column in header: $HEADER" >&2
        exit 1
    fi
done

> "$MALFORMED"

# Stage 1 (validation, streaming line-by-line via awk — never buffers the
#          whole file): split into well-formed rows (stdout) and malformed
#          rows (written to $MALFORMED as they're found), skipping the header.
# Stage 2 (selection/filter): date >= 2026-01-01 AND quantity > 2.
# Stage 3 (projection): keep only category, quantity, price.
# Stage 4 (grouping + aggregation): sort by category (streaming external
#          merge sort, not full in-memory load) then awk sums quantity*price
#          and counts rows per category in one pass over the sorted stream.
# Stage 5 (HAVING): drop groups with revenue <= 100000.
# Stage 6 (ORDER BY revenue DESC + LIMIT 10): sort -rn on revenue, head -10.

NCOLS=$(echo "$HEADER" | awk -F'\t' '{print NF}')

tail -n +2 "$INPUT" | \
awk -F'\t' -v cat="$C_CAT" -v qty="$C_QTY" -v price="$C_PRICE" -v datecol="$C_DATE" \
    -v malformed="$MALFORMED" -v ncols="$NCOLS" '
    function is_number(x) { return (x ~ /^[0-9]+(\.[0-9]+)?$/) }
    function is_date(x)   { return (x ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) }
    {
        d = $datecol
        if (NF < ncols || $cat == "" || $qty == "" || $price == "" || d == "" ||
            !is_number($qty) || !is_number($price) || !is_date(d)) {
            print $0 >> malformed
            next
        }
        print $cat "\t" $qty "\t" $price "\t" d
    }
' | \
awk -F'\t' '$4 >= "2026-01-01" && $2 > 2 { print $1 "\t" $2 "\t" $3 }' | \
sort -t $'\t' -k1,1 | \
awk -F'\t' '
    {
        if ($1 != prev && prev != "") {
            if (revenue[prev] > 100000) printf "%s\t%d\t%.2f\n", prev, count[prev], revenue[prev]
        }
        prev = $1
        count[$1]++
        revenue[$1] += $2 * $3
    }
    END {
        if (prev != "" && revenue[prev] > 100000) printf "%s\t%d\t%.2f\n", prev, count[prev], revenue[prev]
    }
' | \
sort -t $'\t' -k3,3gr | \
head -n 10 | \
{ echo -e "category\ttransactions\trevenue"; cat; } > "$OUTPUT"

if [[ "$OUTPUT" != "/dev/stdout" ]]; then
    cat "$OUTPUT"
fi

n_malformed=$(wc -l < "$MALFORMED" | tr -d ' ')
echo "" >&2
echo "Malformed rows excluded: $n_malformed (see $MALFORMED)" >&2
