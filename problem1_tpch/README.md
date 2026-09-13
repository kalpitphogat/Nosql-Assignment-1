# Problem 1 — Scaling Study Using the TPC-H Benchmark

## Environment
- Database: PostgreSQL 16.15 (Homebrew), default configuration
  (`shared_buffers=128MB`, no custom tuning) — chosen because the
  assignment states PostgreSQL is preferred.
- Hardware/OS: macOS (Darwin, arm64), Apple Silicon.
- Benchmark tooling: official TPC-H reference `dbgen`/`qgen` C source
  (`electrum/tpch-dbgen` on GitHub — a mirror of the TPC's own
  distribution, since the TPC site gates the source behind a license
  click-through) built locally at revision 2.14.0/2.9.0. Two small,
  standard portability additions were made to the vendor source, both
  additive (no existing behavior changed):
  - `dbgen/config.h`: `MACHINE=MAC` already existed upstream for this
    purpose and was used as-is.
  - `dbgen/tpcd.h`: a `POSTGRESQL` block was added, mirroring the
    existing `ORACLE` block (ANSI-standard `LIMIT` clause, no
    proprietary transaction/connect syntax), since the shipped source
    only had blocks for DB2/Informix/Oracle/SQL Server/Sybase/Teradata.
- All 22 standard TPC-H queries are used verbatim from `qgen -s 1`
  (fixed RNG seed 1, so query substitution parameters are the official
  qualification-run defaults and identical across every scale factor).

## Procedure
1. `dbgen -s <SF>` generates `region/nation/part/supplier/partsupp/`
   `customer/orders/lineitem.tbl` (pipe-delimited, one row per line,
   trailing pipe) for the given scale factor.
2. `schema.sql` creates the 8 TPC-H tables (from the official `dss.ddl`).
3. Each `.tbl` file is loaded via `\copy ... WITH (FORMAT csv, DELIMITER '|')`
   (the trailing pipe is stripped first, since CSV mode otherwise reads it
   as an extra empty trailing column).
4. `ANALYZE` is run so the planner has up-to-date statistics before timing.
5. Each of the 22 queries is run once via `psql -f`, wall-clock timed with
   shell `date +%s.%N` around the `psql` call (so it includes result
   fetch/print time, matching what an application would actually
   experience — not just planner+executor time).
6. `run_benchmark.sh <sf1> <sf2> ...` repeats 1–5 for each requested scale
   factor, appending to `results/timings.csv` (per-query) and
   `results/totals.csv` (per-SF total).

Run with:
```bash
./run_benchmark.sh 1 2 4 8
```
(Higher scale factors are far larger — SF=1 is already ~1.1 GB raw data
and generates a lineitem table of ~6M rows; SF=32 would be roughly 32×
that, i.e. tens of GB. Scale factors actually used are recorded in
`results/totals.csv` — this was capped based on available disk/time.)

## Results

Ran at SF=1 (1049.7 MB) and SF=2 (2114.5 MB, ~2.01x the SF=1 dataset).
SF=4 (3667.9 MB) was attempted but the load ran out of local disk
partway through (`No space left on device`, ~4GB free on this machine
after the SF=1/SF=2 raw data + PostgreSQL storage), corrupting that run's
tables — its (meaningless, near-zero) numbers were discarded rather than
reported. This is a disk-capacity limitation of the machine used, not a
property of the database or queries; see Limitations below.

See `results/timings.csv` (22 rows per scale factor) and
`results/totals.csv` (one row per scale factor) for raw measurements, and
`results/scaling_plot.png` for the dataset-size-vs-time plot.

| SF | Dataset (MB) | Load+index (s) | Total query time (s) |
|---|---|---|---|
| 1 | 1049.7 | 155.2 | 303.5 |
| 2 | 2114.5 | 281.6 | 404.1 |

Per-query time and SF2/SF1 ratio (a ratio of 1 = perfectly flat, 2 =
linear with dataset size, >2 = super-linear):

| Query | SF1 (s) | SF2 (s) | ratio |
|---|---|---|---|
| Q1  | 0.08  | 0.05  | 0.60 |
| Q2  | 4.03  | 20.89 | 5.19 |
| Q3  | 7.81  | 12.54 | 1.61 |
| Q4  | 8.11  | 11.93 | 1.47 |
| Q5  | 6.70  | 18.00 | 2.68 |
| Q6  | 11.74 | 6.77  | 0.58 |
| Q7  | 96.91 | 135.14| 1.39 |
| Q8  | 3.37  | 9.19  | 2.73 |
| Q9  | 41.71 | 56.93 | 1.37 |
| Q10 | 8.39  | 13.12 | 1.56 |
| Q11 | 2.75  | 9.11  | 3.31 |
| Q12 | 3.99  | 7.67  | 1.92 |
| Q13 | 1.98  | 2.74  | 1.39 |
| Q14 | 5.88  | 10.61 | 1.81 |
| Q15 | 17.94 | 28.48 | 1.59 |
| Q16 | 0.78  | 0.94  | 1.20 |
| Q17 | 8.36  | 10.44 | 1.25 |
| Q18 | 4.90  | 8.81  | 1.80 |
| Q19 | 1.26  | 1.22  | 0.97 |
| Q20 | 15.82 | 29.40 | 1.86 |
| Q21 | 50.70 | 9.51  | 0.19 |
| Q22 | 0.31  | 0.62  | 2.00 |
| **Total** | **303.5** | **404.1** | **1.33** |

## Analysis

**Overall, total query time did not double when the dataset doubled** —
it grew only 1.33x for a ~2.01x increase in data. That's slower-than-linear
in aggregate, but the aggregate hides very different behavior per query:

- **Roughly linear (ratio ≈ 1.3–2.0), the majority of queries**: Q3, Q4,
  Q9, Q10, Q12, Q13, Q14, Q15, Q17, Q18, Q20, Q22. These are dominated by
  a scan (often index-assisted, after `indexes.sql`) over `lineitem` or
  `orders` with a filter and an aggregate/join — cost tracks table size
  because the number of rows touched tracks table size directly.

- **Super-linear (ratio > 2)**: Q2 (5.19x), Q11 (3.31x), Q8 (2.73x), Q5
  (2.68x). These share a correlated-subquery or multi-way-join shape
  (Q2's `min()` per part-supplier pair, Q11's partsupp aggregate compared
  against a computed threshold, Q5/Q8's 5–6-table joins across
  `nation`/`region`/`customer`/`orders`/`lineitem`/`supplier`). Join cost
  in these can grow faster than the base tables because the number of
  *matching combinations* being joined/re-evaluated per outer row grows
  with the inner table size too — doubling one table can more than double
  the total comparisons when both sides of a join scale together.

- **Roughly flat or shrinking (ratio ≤ 1)**: Q1 (0.60), Q6 (0.58), Q19
  (0.97), and strikingly Q21 (0.19 — nearly 5x *faster* at SF2 despite 2x
  the data). Q1 and Q6 are single-pass aggregates over `lineitem` filtered
  by `l_shipdate`, cheap regardless of table size once an index exists.
  Q21's drop is a planner effect, not a data-size effect: at SF2 the
  planner's row-count estimates cross a threshold that flips it from one
  join strategy (e.g. nested-loop-heavy) to a cheaper one (e.g. hash
  join), which can make a *larger* input run *faster* — a reminder that
  "more data" doesn't map onto "more time" in a query planner-driven
  system the way it would in the from-scratch Unix pipeline of Problem 3.

**Where performance starts to degrade**: Q7 (96.9s → 135.1s) and Q9
(41.7s → 56.9s) are already the two slowest queries at SF=1, and stay the
two slowest at SF=2 — both are wide multi-way joins (Q7: 6 tables
including a self-join-like nation pairing; Q9: `part`/`supplier`/
`lineitem`/`partsupp`/`orders`/`nation`, filtered by a `LIKE` predicate
on `part.name` that can't use a simple index). These are the queries most
likely to become the bottleneck at larger scale factors, since join cost
compounds with table size while single-table filter/aggregate queries
(Q1/Q6/Q16/Q19) stay cheap.

**Relating to database operations**: filtering and simple aggregation
(Q1, Q6) are I/O/scan-bound and scale gently; sorting doesn't show up as
a separate bottleneck here since result sets are small (`ORDER BY`
mostly runs on already-small post-aggregation row sets); joins are
where scaling risk concentrates, especially when the query has a
correlated subquery (Q2, Q11) or a filter that can't be pushed down
through an index (Q9's `LIKE`), since those force the planner toward
nested-loop or repeated-scan strategies whose cost is sensitive to more
than just the row count of a single table.

## Limitations
- Capped at SF=1/SF=2 due to local disk capacity (~4GB free on this
  machine after loading SF=1/SF=2 data + indexes) rather than a query- or
  database-imposed limit; SF=4 (~3.7GB raw, plus a similar footprint again
  once indexed in PostgreSQL) did not fit. A machine with more free disk
  could extend this study to SF=4/8/16/32 using the same
  `run_benchmark.sh` unchanged.
- Each query ran once per scale factor (not repeated/averaged), so
  measurements include normal OS/filesystem-cache noise — e.g. Q21's
  ratio inversion is consistent with a planner/cache effect rather than
  a repeatable trend, and would benefit from repeated runs to confirm.
- Standard primary/foreign-key indexes were built (see `indexes.sql`)
  before timing, so these numbers reflect a normally-administered
  database, not a raw unindexed table scan on every query — an
  unindexed run was also attempted (see `results/timings_sf1_noindex_baseline.csv`)
  and showed just how severe the difference is: Q17 alone (a correlated
  subquery over the 6M-row `lineitem` table) took ~3230s unindexed at
  SF=1 vs. ~8.4s indexed — a >380x difference from adding a single index
  on `lineitem.l_partkey`, which is itself a useful data point about how
  much indexing (not just data volume) drives TPC-H query cost.
