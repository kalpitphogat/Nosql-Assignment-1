#!/usr/bin/env bash
# Row-conservation check for pipeline.sh (verification only, not part of the solution).
#
# For each input file it checks that no row is lost or counted twice:
#   input lines = 1 header + malformed rows + rows removed by WHERE + rows kept
# The malformed and kept counts come from the pipeline itself (its rejected-rows
# file, and the number of rows its validate/filter stage passes on). The same
# four counts are computed independently by reference_check.py --counts, and
# both sets must agree.
#
# Usage: ./conservation_check.sh <input.tsv> [...]
# Output: one line per file; exit status 1 if any check fails.

set -uo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-python3}"
command -v "$PY" > /dev/null || PY=python

# Same pipeline code, but the validate stage's output is counted instead of discarded.
counting=$(mktemp)
sed 's#validate)  tail -n +2 "$INPUT" | validate_filter_project > /dev/null ;;#validate)  tail -n +2 "$INPUT" | validate_filter_project | wc -l ;;#' \
    pipeline.sh > "$counting"
grep -q 'validate_filter_project | wc -l' "$counting" || { echo "could not build counting copy of pipeline.sh" >&2; exit 1; }

status=0
printf 'file\tinput_lines\theader\tmalformed\tremoved_by_where\tkept\tpipeline_malformed\tpipeline_kept\tresult\n'
for f in "$@"; do
    rejects=$(mktemp)
    total=$(wc -l < "$f" | tr -d ' ')
    kept_pipe=$(STOP_AFTER=validate MALFORMED="$rejects" bash "$counting" "$f" 2>/dev/null | tr -d ' \r')
    malformed_pipe=$(wc -l < "$rejects" | tr -d ' ')
    read -r header malformed removed kept < <("$PY" reference_check.py --counts "$f" | tr -d '\r')
    ok=PASS
    [[ "$malformed_pipe" == "$malformed" && "$kept_pipe" == "$kept" ]] || ok=FAIL
    [[ $((header + malformed + removed + kept)) -eq "$total" ]] || ok=FAIL
    [[ $ok == PASS ]] || status=1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(basename "$f")" "$total" "$header" "$malformed" \
        "$removed" "$kept" "$malformed_pipe" "$kept_pipe" "$ok"
    rm -f "$rejects"
done
rm -f "$counting"
exit $status
