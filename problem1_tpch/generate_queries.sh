#!/usr/bin/env bash
#
# Generate the 22 TPC-H queries for one scale factor with the official qgen.
#
#   ./generate_queries.sh <SF>          -> queries/sf<SF>/raw/<n>.sql  (exact qgen output)
#                                          queries/sf<SF>/<n>.sql      (PostgreSQL-adapted)
#                                          queries/sf<SF>/SHA256SUMS
#   ./generate_queries.sh default       -> queries/default/...  (qgen -d: the default
#                                          substitution values the official answers use)
#
# The seed is fixed (QGEN_SEED, default 42) and qgen is told the scale factor
# (-s), so SF-dependent substitutions are correct, e.g. Q11's
# FRACTION = 0.0001 / SF.  Requires DBGEN_DIR (the built official kit).

set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:?usage: generate_queries.sh <SF>|default}"
SEED="${QGEN_SEED:-42}"
: "${DBGEN_DIR:?set DBGEN_DIR (source env.sh)}"
export DSS_QUERY="$DBGEN_DIR/queries" DSS_CONFIG="$DBGEN_DIR"

if [[ "$MODE" == default ]]; then
    OUT="queries/default"; QGEN_ARGS=(-d -s 1)
else
    OUT="queries/sf${MODE}"; QGEN_ARGS=(-r "$SEED" -s "$MODE")
fi
mkdir -p "$OUT/raw"

for n in $(seq 1 22); do
    "$DBGEN_DIR/qgen" "${QGEN_ARGS[@]}" -b "$DBGEN_DIR/dists.dss" "$n" > "$OUT/raw/${n}.sql"
    python3 adapt_query.py "$OUT/raw/${n}.sql" > "$OUT/${n}.sql"
done
(cd "$OUT" && sha256sum raw/*.sql [0-9]*.sql > SHA256SUMS)
echo "qgen ${QGEN_ARGS[*]}: 22 queries -> $OUT" >&2
