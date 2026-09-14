# Problem 1 — Scaling Study Using the TPC-H Benchmark

## Experimental setup

| Item | Value |
|---|---|
| Machine | Intel Core i9-12900K (16 cores / 24 threads), 62 GB RAM, 931 GB NVMe SSD |
| OS | Red Hat Enterprise Linux 8.10 (kernel 4.18) |
| Database | PostgreSQL 16.15, built from source (`setup_postgres_and_dbgen.sh`) |
| Benchmark tools | TPC-H `dbgen`/`qgen` 2.14.0 from `github.com/electrum/tpch-dbgen` (commit `32f1c1b`) |
| Scale factors | 1, 2, 4, 8, 16, 32 (doubling) |
| Repetitions | 3 runs of all 22 queries per SF; the **median** is reported |
| Per-query timeout | 30 min (never reached) |

PostgreSQL configuration (identical for every SF; the full list is in
`results/environment.txt`):

```
shared_buffers = 4GB            effective_cache_size = 12GB
work_mem = 128MB                maintenance_work_mem = 1GB
max_parallel_workers_per_gather = 4
random_page_cost = 1.1 (SSD)    max_wal_size = 8GB      jit = off
```

Indexes (`indexes.sql`): primary keys on all 8 tables, plus indexes on the
foreign-key columns and on `l_shipdate` / `o_orderdate`. They are built after
the bulk load and are the same at every SF.

**Note on the TPC-H version.** The assignment names TPC-H Revision 3.0.1. The
TPC website only provides the tools after a registration form, so we used the
widely used `electrum/tpch-dbgen` copy of the reference tools (version 2.14.0).
Its data generator and 22 query templates follow the same schema and
queries. Row counts match the spec exactly, e.g. `lineitem` = 6,001,215 rows at
SF1 (`results/row_counts.csv`).

## Procedure (all automated, `run_benchmark.sh`)

For each scale factor:
1. `dbgen -s SF` generates the 8 `.tbl` files.
2. `schema.sql` recreates the tables. Each file is streamed through
   `sed 's/|$//'` into `\copy ... FROM STDIN`, so no temporary copies are made.
   The script aborts if any load fails. After each load the `.tbl` file is
   deleted to keep disk use down.
3. `indexes.sql`, then `VACUUM ANALYZE`. The load time, database size and row
   count of every table are recorded.
4. The `EXPLAIN` plan of every query is saved to `results/plans/`.
5. All 22 queries (`queries_final/`) run 3 times. For each run we record the
   wall-clock time (including `psql` start-up and result transfer) and a
   status of `ok`, `error` or `timeout`.

Reproduce:
```bash
ROOT=$HOME/nosql_a1 ./setup_postgres_and_dbgen.sh   # one-time, no root needed
source $HOME/nosql_a1/env.sh
./run_benchmark.sh 1 2 4 8 16 32
python3 plot_results.py
```

## Raw measurements

- `results/benchmark.log` (SF 1–8), `benchmark_16.log`, `benchmark_32.log`:
  the console logs of the three benchmark invocations
- `results/timings.csv`: 396 rows (6 SFs × 22 queries × 3 runs), **all `ok`**
- `results/totals.csv`: per SF and run: dataset size, DB size, load time, total query time
- `results/row_counts.csv`: rows per table per SF
- `results/scaling_summary.csv`: median per query per SF, the ratio between
  successive SFs, and the log-log slope
- `results/output/`: query results; `results/plans/`: `EXPLAIN` for every
  query and SF, plus `EXPLAIN (ANALYZE, BUFFERS)` for Q1, Q9, Q13, Q16, Q18
  and Q20 at SF32
- `results/scaling_plot.png`, `results/per_query_plot.png`: plots

| SF | Raw data (MB) | DB size (MB) | Load + index (s) | Total, 22 queries (s, median) | × previous SF |
|---|---|---|---|---|---|
| 1 | 1,050 | 1,704 | 18.5 | 5.97 | — |
| 2 | 2,115 | 3,398 | 36.9 | 13.15 | 2.20 |
| 4 | 4,255 | 6,784 | 73.2 | 33.25 | 2.53 |
| 8 | 8,556 | 13,556 | 143.5 | 57.14 | 1.72 |
| 16 | 17,221 | 27,103 | 287.4 | 125.20 | 2.19 |
| 32 | 34,688 | 54,197 | 633.4 | 310.09 | 2.48 |

Per-query medians (seconds) and the ratio for each doubling:

| Query | SF1 | SF2 | SF4 | SF8 | SF16 | SF32 | ratios (2/1, 4/2, 8/4, 16/8, 32/16) | slope |
|---|---|---|---|---|---|---|---|---|
| Q1 | 0.66 | 1.34 | 2.70 | 5.35 | 10.64 | 21.21 | 2.03 2.02 1.98 1.99 1.99 | 0.99 |
| Q2 | 0.11 | 0.21 | 0.71 | 1.58 | 3.10 | 6.88 | 2.03 3.31 2.23 1.97 2.22 | 1.22 |
| Q3 | 0.20 | 0.41 | 1.04 | 1.94 | 2.56 | 5.46 | 2.04 2.57 1.86 **1.32** 2.13 | 0.93 |
| Q4 | 0.05 | 0.10 | 0.25 | 0.54 | 1.28 | 2.49 | 1.87 2.50 2.11 2.40 1.94 | 1.12 |
| Q5 | 0.12 | 0.25 | 0.56 | 0.94 | 1.69 | 6.46 | 2.15 2.23 1.69 1.80 **3.83** | 1.08 |
| Q6 | 0.11 | 0.23 | 0.58 | 1.30 | 2.80 | 2.85 | 2.08 2.48 2.25 2.16 **1.02** | 1.00 |
| Q7 | 0.34 | 0.78 | 2.79 | 3.81 | 6.33 | 15.76 | 2.30 3.60 **1.37** 1.66 2.49 | 1.05 |
| Q8 | 0.07 | 0.15 | 0.31 | 0.63 | 1.90 | 3.74 | 2.10 2.05 2.02 3.04 1.97 | 1.15 |
| Q9 | 0.48 | 1.05 | 2.35 | 5.02 | 10.94 | 22.18 | 2.17 2.24 2.14 2.18 2.03 | 1.10 |
| Q10 | 0.11 | 0.26 | 0.60 | 1.05 | 2.33 | 6.64 | 2.41 2.27 1.77 2.21 2.85 | 1.13 |
| Q11 | 0.04 | 0.10 | 0.35 | 0.62 | 1.22 | 2.43 | 2.16 3.66 1.79 1.95 2.00 | 1.16 |
| Q12 | 0.15 | 0.31 | 0.65 | 1.28 | 2.56 | 5.13 | 2.12 2.10 1.97 2.00 2.00 | 1.01 |
| Q13 | 0.44 | 1.14 | 2.99 | 6.60 | 14.08 | 62.88 | 2.60 2.62 2.21 2.13 **4.47** | 1.35 |
| Q14 | 0.05 | 0.09 | 0.24 | 0.51 | 1.07 | 2.18 | 1.96 2.50 2.17 2.09 2.04 | 1.11 |
| Q15 | 0.23 | 0.52 | 1.42 | 4.04 | 8.18 | 8.60 | 2.26 2.74 2.83 2.03 **1.05** | 1.12 |
| Q16 | 0.12 | 0.21 | 0.39 | 0.75 | 1.42 | 10.01 | 1.76 1.84 1.91 1.90 **7.06** | 1.16 |
| Q17 | 0.31 | 0.75 | 1.78 | 3.64 | 7.41 | 15.07 | 2.39 2.37 2.04 2.04 2.03 | 1.10 |
| Q18 | 1.73 | 3.96 | 10.14 | 11.89 | 26.09 | 56.54 | 2.29 2.56 **1.17** 2.19 2.17 | 0.95 |
| Q19 | 0.02 | 0.04 | 0.08 | 0.13 | 0.26 | 0.91 | 1.83 1.80 1.61 2.08 **3.45** | 0.98 |
| Q20 | 0.30 | 0.61 | 1.43 | 3.00 | 13.51 | 34.86 | 2.04 2.33 2.10 **4.51** 2.58 | 1.38 |
| Q21 | 0.28 | 0.58 | 1.94 | 2.36 | 5.31 | 10.26 | 2.06 3.34 **1.21** 2.26 1.93 | 1.01 |
| Q22 | 0.03 | 0.06 | 0.11 | 0.17 | 0.34 | 0.66 | 1.87 1.81 1.64 1.95 1.97 | 0.86 |

A ratio of 2 means time doubles when data doubles (linear). The slope is fitted
on log(time) vs log(size) over all six SFs: 1 = linear, above 1 = super-linear.

## Analysis

### Does query time double when the data doubles?

**Mostly yes.** Over the whole range, data grew 33× (1.05 GB → 34.7 GB) and
total query time grew 52× (5.97 s → 310 s), slightly faster than linear. The
per-step ratios stay between 1.7 and 2.5, and loading scales almost exactly
linearly (ratios 1.96–2.00, then 2.20 at SF32). But the total hides three
different behaviours. We checked the saved plans to explain them instead of
guessing.

### 1. Linear queries: scans, filters and aggregation

**Q1, Q12, Q9, Q17, Q14, Q4** have every ratio close to 2 (slope 0.99–1.12).
Q1 is the cleanest case (ratios 1.98–2.03). Its plan at every SF is a
parallel sequential scan of `lineitem` feeding a hash aggregate with only 4
groups. The work is proportional to the number of rows scanned, and the tiny
result makes the final sort free. At SF32, 5 processes scan all 192 M `lineitem` rows, and about 190 M pass the
date filter
(`sf32_q1_analyze.txt`). Q12 (filter + join + group by ship mode) behaves the
same way. Q9 and Q17 are also linear even though they are multi-table joins
and a correlated subquery. Their plans do not change across SFs, so their
cost tracks table size.

Q22 grows slightly slower than linear (slope 0.86). It is the fastest query
(0.03 s at SF1). For such short queries, a fixed cost (starting `psql`,
connecting, planning) is probably a noticeable part of the measured time, and
that part does not grow with the data.

### 2. Steps caused by the planner changing strategy

Several "odd" ratios happen exactly where PostgreSQL chose a different plan.
Comparing `results/plans/sfN_qM.txt` between SFs:

| Query, step | Ratio | Plan at the smaller SF → plan at the larger SF |
|---|---|---|
| Q6, SF16→32 | 1.02 | bitmap scan through the `l_shipdate` index → **parallel sequential scan** of `lineitem` |
| Q15, SF16→32 | 1.05 | serial aggregation of `lineitem` → **parallel** (Gather + partial HashAggregate) |
| Q3, SF8→16 | 1.32 | nested-loop joins with index lookups → **parallel hash joins** over seq scans |
| Q18, SF4→8 | 1.17 | serial HashAggregate over `lineitem` → **parallel partial HashAggregate** |
| Q21, SF4→8 | 1.21 | different join order and access paths |
| Q7, SF4→8 | 1.37 | ordinary hash joins → a **Parallel Hash Join** with partial (per-worker) aggregation |
| Q5, SF16→32 | 3.83 | index nested loop into `lineitem` → parallel seq scan of `lineitem` + hash joins |
| Q20, SF8→16 | 4.51 | hash semi-join → **nested-loop semi-join running a correlated subquery per row** |

With more data, the cost-based optimiser moves from index lookups (cheap
when few rows qualify) to scans, hash joins and parallelism (cheap when many
rows qualify). When it switches at the right moment, the next step looks
almost flat (Q6, Q15, Q3, Q18). When the new plan scales badly, the step is
super-linear (Q5, Q20). **No query is insensitive to dataset size overall.**
These flat steps are one-off plan switches, and the time grows again at the
next SF.

### 3. Super-linear queries and where performance degrades

SF32 is where performance clearly degrades. The total ratio rises to 2.48,
and Q16 (7.1×), Q13 (4.5×), Q5 (3.8×) and Q19 (3.5×) jump. At SF32 the
database (54 GB) approaches the machine's RAM (62 GB), and PostgreSQL's own
buffer cache is 4 GB. `EXPLAIN (ANALYZE, BUFFERS)` at SF32 shows why:

- **Q13 (customer LEFT JOIN orders, group by customer): join strategy and
  random I/O.** At SF16 the plan is a hash join over a sequential scan of
  `orders`. At SF32 it becomes a merge join that reads `orders` through
  `idx_orders_custkey`, i.e. in customer order rather than disk order. The
  index scan alone takes 60.2 s of the 66.2 s and makes 18.6 M page reads
  from outside PostgreSQL's buffer cache (`sf32_q13_analyze.txt`).
- **Q16 (join part/partsupp, `count(DISTINCT)`, sort): lost parallelism and a
  sort spilling to disk.** At SF16 it uses a parallel hash join with sorts in
  the worker processes. At SF32 the plan is serial, and the 3.8 M-row sort
  exceeds `work_mem` (128 MB). It becomes an **external merge sort using
  193 MB of temporary disk**, and the sort alone takes about 6.5 s of 10.7 s
  (`sf32_q16_analyze.txt`).
- **Q18 (group `lineitem` by order, `HAVING sum > 300`): hash aggregation
  spilling to disk.** Grouping 192 M `lineitem` rows by `l_orderkey` creates
  about 48 M groups, which cannot fit in `work_mem`. The final HashAggregate
  splits into **133 batches using about 3.9 GB of temporary disk**, and each
  parallel worker spills a further ~1.3 GB (`sf32_q18_analyze.txt`). Q18 is
  the slowest query from SF1 to SF16 and the second slowest at SF32 (56.5 s).
- **Q20 (nested `IN` + correlated subquery): per-row subquery execution.**
  After the plan switch at SF16, the correlated subquery (sum of `l_quantity`
  for each part/supplier pair) runs once per candidate `partsupp` row:
  **784,829 times** at SF32, each a bitmap index lookup into `lineitem`
  (`sf32_q20_analyze.txt`). It is also the noisiest query at SF32 (28.5 s,
  54.6 s and 34.9 s across the 3 runs), which is consistent with cache-heavy
  random I/O.
- **Q9 shows that spilling alone need not break linearity.** At SF32 each of
  its 5 parallel sorts spills about 135 MB to disk, yet its ratio is still
  2.03. The sort is a small part of a query dominated by joins over
  `lineitem`, `partsupp` and `orders`.
- **Q19** keeps the same plan at SF16 and SF32 but grows 3.45×. Its absolute
  time is small (0.26 s → 0.91 s) and varied between runs (0.65–1.51 s). We
  did not determine the cause.

### Relating the results to database operations

| Operation | Effect on scaling | Evidence |
|---|---|---|
| Filtering + scanning | linear; parallel seq scans spread it over cores | Q1, Q6, Q12, Q14 |
| Aggregation | linear while the hash table fits in `work_mem`; spills to disk in batches when it does not | Q1 (4 groups) vs Q18 (48 M groups, 133 batches) |
| Sorting | cheap for small final results; external merge once the input exceeds `work_mem` | Q16 at SF32 (193 MB on disk) |
| Joins | the planner switches between index nested loops, hash joins and merge joins. The switch points create flat steps or sudden jumps | Q3, Q7, Q13, Q20, Q21 |
| Correlated subqueries | cost = outer rows × inner lookup; super-linear when both grow | Q20 (784,829 executions); Q17 stays linear because its plan is stable |

## Limitations and honest notes

- **Q11 uses the SF1 parameter at every scale factor.** `qgen` was run once
  and the same query text was used for all SFs. Q11's threshold should be
  `0.0001 / SF`, but it stays `0.0001`. So Q11 returns 1,469 rows at SF1,
  4 at SF2 and **0 rows at SF4 and above**. It still performs the same joins
  and both aggregations, so its timing reflects the work done, but its result
  is not spec-conformant above SF1. The other 21 queries have no SF-dependent
  parameters.
- **This is not an official (audited) TPC-H run.** There are no refresh
  functions and no throughput test, and indexes were added. We measure
  single-stream query time only, as the assignment asks.
- **First-run warm-up.** The first run at an SF is sometimes slower (SF4:
  37.5 s vs 33.2 s; SF16: 135.7 s vs 125.2 s), so we report medians over 3
  runs.
- **Some jumps are not fully explained.** At SF2→SF4, Q2 (3.3×) and Q11
  (3.7×) jump even though their plan shape does not change. We report this
  without a verified cause.
- **SF32 was the largest we could run.** The disk (shared with other users)
  had about 100 GB free. SF32 already needed about 54 GB of database plus up
  to 34 GB of raw files during loading. SF64 would need more than 100 GB
  plus 70 GB of raw data, which did not fit.

## What changed from the team's earlier attempt

An earlier run (SF1 and SF2 on a MacBook) was **discarded**, because its
results were invalid:
- Q1 never ran (a PostgreSQL syntax error on `interval '79' day (3)`), so it
  reported 0.08 s.
- Q2, Q3, Q10, Q18 and Q21 had a `;` before `LIMIT`, so they ran without
  their limit and then failed.
- The script did not check query errors or failed loads, and ran each query
  only once. Its SF4 load ran out of disk, and queries were then timed on the
  broken tables (reported as about 0.03 s each).

The six query files were fixed. `run_benchmark.sh` now aborts on load errors,
records a status for each query, repeats every query 3 times and saves query
plans. All numbers above come from the new run on one machine with an
unchanged configuration.
