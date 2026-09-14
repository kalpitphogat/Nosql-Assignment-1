#!/usr/bin/env bash
#
# Validate the SF1 database and the query adaptation against the official
# TPC-H answer set (dbgen/answers/q<n>.out in the V3.0.1 kit), using the
# official per-column tolerances (dbgen/check_answers/colprecision.txt, cmpq.pl).
#
# The official answers use qgen's *default* substitution values (qgen -d), so
# those queries are generated separately (queries/default/) and run once.
# Must be run while the SF1 database is loaded (run_benchmark.sh does this).
#
# Output: results/answer_validation/q<n>.out (our result), and
#         results/answer_validation.csv  (query, status, detail)

set -uo pipefail
cd "$(dirname "$0")"
: "${DBGEN_DIR:?set DBGEN_DIR (source env.sh)}"

bash generate_queries.sh default || exit 1
OUT="results/answer_validation"
mkdir -p "$OUT"
echo "query,status,detail" > results/answer_validation.csv

failed=0
for n in $(seq 1 22); do
    psql -X -q -v ON_ERROR_STOP=1 -c "DROP VIEW IF EXISTS revenue0" > /dev/null 2>&1
    if ! psql -X -q -v ON_ERROR_STOP=1 -A -F '|' -P footer=off \
            -f "queries/default/${n}.sql" > "$OUT/q${n}.out" 2> "$OUT/q${n}.err"; then
        detail="query error: $(head -1 "$OUT/q${n}.err")"; status=error
    elif detail=$(python3 compare_answers.py "$n" "$DBGEN_DIR/check_answers/colprecision.txt" "$DBGEN_DIR/answers/q${n}.out" "$OUT/q${n}.out"); then
        status=match
    else
        status=mismatch
    fi
    [[ $status == match ]] || failed=$((failed + 1))
    echo "Q$n,$status,\"${detail//\"/\'}\"" >> results/answer_validation.csv
    echo "  answer check Q$n: $status ($detail)" >&2
done

echo "Official SF1 answer validation: $((22 - failed))/22 match" >&2
[[ $failed -eq 0 ]]
