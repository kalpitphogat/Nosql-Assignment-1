# Problem 3 — Unix Data-Processing Pipeline

## Files
- `pipeline.sh` — the pipeline itself
- `scalability_test.sh` — generates 4 datasets (~100/250/500/1000 MB) and times the pipeline on each
- `transactions.tsv`, `transactions_malformed.tsv` — supplied sample/test data
- `generate_transactions` — supplied data generator
- `scalability_results.tsv` — measured results

Run with:
```bash
./pipeline.sh transactions.tsv output.tsv
./scalability_test.sh
```

## Target SQL

```sql
SELECT category, COUNT(*) AS transactions, SUM(quantity * price) AS revenue
FROM transactions
WHERE date >= '2026-01-01' AND quantity > 2
GROUP BY category
HAVING SUM(quantity * price) > 100000
ORDER BY revenue DESC
LIMIT 10;
```

## Processing stages → SQL operation mapping

| Stage | Unix command | SQL operation |
|---|---|---|
| 0 | `head -1` on header, `grep -nx` to locate column indices by name | schema resolution (handles the supplied file's actual column order, which differs from the order stated in the assignment PDF) |
| 1 | `tail -n +2` then `awk` validation pass, splitting malformed rows to a side file | implicit data-cleaning step before `FROM transactions` |
| 2 | `awk '$4 >= "2026-01-01" && $2 > 2'` | `WHERE date >= '2026-01-01' AND quantity > 2` |
| 3 | `awk '{print $1"\t"$2"\t"$3}'` (drop unused columns) | projection to `category, quantity, price` |
| 4 | `sort -k1,1` (external merge sort, streams through temp files rather than holding everything in RAM) | pre-requisite for streaming `GROUP BY category` |
| 5 | `awk` accumulating `count[]`/`revenue[]`, emitting a row each time the sorted key changes | `GROUP BY category` + `COUNT(*)` + `SUM(quantity*price)` |
| 6 | (same awk pass) `if (revenue[prev] > 100000) print ...` | `HAVING SUM(quantity*price) > 100000` |
| 7 | `sort -k3,3rn` | `ORDER BY revenue DESC` |
| 8 | `head -n 10` | `LIMIT 10` |

Because stage 4/7 use `sort` (which itself streams via external merge sort
and temp files instead of loading the whole input into memory) and every
other stage is a single `awk`/`tail` pass reading line-by-line, no stage
holds the full dataset in memory at once.

## Malformed-record handling

A row is malformed if any of: fewer fields than the header declares, any of
`category`/`quantity`/`price`/`date` is empty, `quantity` or `price` isn't
numeric, or `date` isn't in `YYYY-MM-DD` form. Stage 1's `awk` checks every
row against these rules; matches are appended to
`<input>.malformed_rows.tsv` and skipped (`next`) rather than aborting the
script (`set -uo pipefail` is used, not `-e`, specifically so a malformed
row doesn't kill the pipeline). The count of excluded rows is reported on
stderr at the end of the run.

## Scalability results

| Records | File size | Total pipeline time |
|---|---|---|
| 2.5M | 102.3 MB | 9.8 s |
| 6.25M | 255.7 MB | 26.3 s |
| 12.5M | 511.6 MB | 54.7 s |
| 25M | 1023.1 MB | 112.7 s |

Time-per-MB stays close to constant (~0.10–0.11 s/MB) across all four
sizes, i.e. total time grows roughly linearly with input size (not
super-linearly), which is what's expected: every stage in the pipeline is
either a single streaming pass (`awk`, `tail`, `head`) or an external
merge sort (`sort`, which is O(n log n) but with a small, near-constant
log-factor at these sizes since GNU/BSD `sort` uses large fixed-size
run buffers rather than scaling passes with n over this range).

The two `sort` stages (group-by prep and final ordering) are the most
expensive part of the pipeline — everything else is a single linear pass.
The second `sort` only operates on the (small) post-aggregation,
post-HAVING row set (at most a few dozen category rows), so essentially
all the cost comes from the first `sort -k1,1` over the full filtered
dataset. This lines up with the `awk`-validation pass and the sort pass
combined dominating wall-clock time, while the final aggregation/HAVING/
limit stages are comparatively free.

## Limitations of the Unix-based approach
- No indexes: every run does a full scan + full sort, unlike a database
  that could use a covering index on `(date, quantity)` or a materialized
  per-category rollup.
- No query planner/cost-based optimization — stage order is fixed by hand;
  a smarter engine might push the `HAVING` filter earlier or use a hash
  aggregate instead of sort-then-group.
- Numeric/date validation is regex-based text matching, not true type
  checking, so a superficially valid-looking but semantically wrong value
  (e.g. `9999-99-99`) would pass through undetected.
- Portability: this was developed and tested with BSD `awk`/`sort`
  (macOS); GNU coreutils on Linux behave the same for the flags used here,
  but exact `sort` performance characteristics can differ across
  implementations.
