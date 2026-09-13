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
- All 22 standard TPC-H queries come from `qgen -s 1` (fixed RNG seed 1,
  so query substitution parameters are the official qualification-run
  defaults and identical across every scale factor). Six queries required
  the standard PostgreSQL-dialect adjustments to the raw `qgen` output
  before they would execute (these are well-known `qgen`-template
  portability artifacts, not changes to query semantics):
  - **Q1**: `interval '79' day (3)` → `interval '79' day` — the `(3)`
    datetime-precision qualifier in the template is not valid PostgreSQL
    interval syntax.
  - **Q2, Q3, Q10, Q18, Q21**: the `qgen` template placed a `;` at the end
    of the `order by` clause, *before* the `limit N;` line, so PostgreSQL
    parsed `limit N;` as a second, invalid statement. The stray `;` was
    removed so `limit N` is part of the query (and the required Top-N
    result is actually produced).

  All 22 queries have been verified to parse and execute without error on
  PostgreSQL 16 (empty-schema parse/execute check).

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

> **⚠️ Re-run required for six queries.** The committed
> `results/timings.csv`, `results/totals.csv` and the per-query table below
> were produced *before* the PostgreSQL-dialect corrections to Q1, Q2, Q3,
> Q10, Q18 and Q21 (see Environment). In that recorded run those six queries
> errored: **Q1 never executed at all** (its `results/sf1_q1.out` is empty),
> and **Q2/Q3/Q10/Q18/Q21 ran without their `LIMIT`** (returning more than
> the required Top-N rows) and each logged a stray `limit` syntax error.
> Their times in the table below are therefore **not valid measurements**
> (Q1's is just an error-return time; the other five omit the LIMIT step),
> and any conclusion resting on them must be re-derived. The queries are now
> fixed; re-run `./run_benchmark.sh 1 2` on the benchmark machine to
> regenerate valid numbers for these six rows and refresh the plot. The
> other 16 queries executed correctly and their numbers stand.

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

Rows marked **†** are from the broken pre-correction run and must be
re-measured (see the warning above); treat their numbers as invalid.

| Query | SF1 (s) | SF2 (s) | ratio |
|---|---|---|---|
| Q1 † | 0.08 (never ran) | 0.05 (never ran) | — |
| Q2 † | 4.03 (no LIMIT) | 20.89 (no LIMIT) | — |
| Q3 † | 7.81 (no LIMIT) | 12.54 (no LIMIT) | — |
| Q4  | 8.11  | 11.93 | 1.47 |
| Q5  | 6.70  | 18.00 | 2.68 |
| Q6  | 11.74 | 6.77  | 0.58 |
| Q7  | 96.91 | 135.14| 1.39 |
| Q8  | 3.37  | 9.19  | 2.73 |
| Q9  | 41.71 | 56.93 | 1.37 |
| Q10 † | 8.39 (no LIMIT) | 13.12 (no LIMIT) | — |
| Q11 | 2.75  | 9.11  | 3.31 |
| Q12 | 3.99  | 7.67  | 1.92 |
| Q13 | 1.98  | 2.74  | 1.39 |
| Q14 | 5.88  | 10.61 | 1.81 |
| Q15 | 17.94 | 28.48 | 1.59 |
| Q16 | 0.78  | 0.94  | 1.20 |
| Q17 | 8.36  | 10.44 | 1.25 |
| Q18 † | 4.90 (no LIMIT) | 8.81 (no LIMIT) | — |
| Q19 | 1.26  | 1.22  | 0.97 |
| Q20 | 15.82 | 29.40 | 1.86 |
| Q21 † | 50.70 (no LIMIT) | 9.51 (no LIMIT) | — |
| Q22 | 0.31  | 0.62  | 2.00 |
| **Total (incl. † rows, so not final)** | **303.5** | **404.1** | **1.33** |

## Analysis

**Overall, total query time did not double when the dataset doubled** —
it grew only 1.33x for a ~2.01x increase in data. That's slower-than-linear
in aggregate, but the aggregate hides very different behavior per query:

- **Roughly linear (ratio ≈ 1.3–2.0), the majority of queries**: Q4, Q9,
  Q12, Q13, Q14, Q15, Q17, Q20, Q22 (plus Q3, Q10, Q18 whose recorded
  ratios looked linear but were measured without their `LIMIT` — expected
  to stay roughly linear but **re-measure to confirm**). These are
  dominated by a scan (often index-assisted, after `indexes.sql`) over
  `lineitem` or `orders` with a filter and an aggregate/join — cost tracks
  table size because the number of rows touched tracks table size directly.

- **Super-linear (ratio > 2)**: Q11 (3.31x), Q8 (2.73x), Q5 (2.68x). These
  share a multi-way-join / correlated-subquery shape (Q11's partsupp
  aggregate compared against a computed threshold, Q5/Q8's 5–6-table joins
  across `nation`/`region`/`customer`/`orders`/`lineitem`/`supplier`). Join
  cost in these can grow faster than the base tables because the number of
  *matching combinations* being joined/re-evaluated per outer row grows
  with the inner table size too — doubling one table can more than double
  the total comparisons when both sides of a join scale together.
  (Q2, whose recorded ratio was the largest, is **excluded pending
  re-measurement** — it ran without its `LIMIT 100` in the recorded run, so
  its time is not comparable; re-check whether it is genuinely super-linear
  after re-running.)

- **Roughly flat or shrinking (ratio ≤ 1)**: Q6 (0.58) and Q19 (0.97). Q6
  is a single-pass aggregate over `lineitem` filtered by `l_shipdate`,
  cheap regardless of table size once an index exists. (Q1, a similar
  single-pass `l_shipdate` aggregate, is expected to behave the same way,
  but **it never actually executed** in the recorded run — see the warning
  above — so it is left out here until re-measured. Q21's recorded "5x
  faster at SF2" is likewise **not usable**: it ran without its `LIMIT` and
  logged an error, so re-measure before drawing any planner-flip
  conclusion from it.)

**Where performance starts to degrade**: Q7 (96.9s → 135.1s) and Q9
(41.7s → 56.9s) are already the two slowest queries at SF=1, and stay the
two slowest at SF=2 — both are wide multi-way joins (Q7: 6 tables
including a self-join-like nation pairing; Q9: `part`/`supplier`/
`lineitem`/`partsupp`/`orders`/`nation`, filtered by a `LIKE` predicate
on `part.name` that can't use a simple index). These are the queries most
likely to become the bottleneck at larger scale factors, since join cost
compounds with table size while single-table filter/aggregate queries
(Q6/Q16/Q19, and Q1 once re-measured) stay cheap.

**Relating to database operations**: filtering and simple aggregation
(Q6, and Q1 by query shape) are I/O/scan-bound and scale gently; sorting doesn't show up as
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
  measurements include normal OS/filesystem-cache noise; repeated runs
  (the assignment's "repeat the experiment as appropriate") would firm up
  the per-query ratios, especially any near the flat/linear boundary.
- With only two valid scale factors (SF=1, SF=2), a per-query ratio is a
  two-point slope, not a scaling curve. The assignment's questions about
  which queries scale super-linearly and *at what scale factor performance
  begins to degrade* really need the full doubling series (SF=4/8/16/32);
  extending the study on a machine with more free disk, using the same
  `run_benchmark.sh` unchanged, is the main outstanding work here.
- Standard primary/foreign-key indexes were built (see `indexes.sql`)
  before timing, so these numbers reflect a normally-administered
  database rather than raw unindexed scans. (An earlier README revision
  cited an unindexed baseline file with a specific speed-up figure; that
  file was not part of this submission and the claim has been removed
  rather than left unsupported — re-run without `indexes.sql` to quantify
  the index effect if that comparison is wanted.)
