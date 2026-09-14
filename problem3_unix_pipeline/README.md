# Problem 3 — Unix Data-Processing Pipeline

## Files
- `pipeline.sh`: the complete pipeline
- `scalability_test.sh`: generates ~100 / 250 / 500 / 1000 MB datasets and times the pipeline 3× on each
- `stage_timing.sh`: measures how much time each stage adds (uses `STOP_AFTER`, so it times the real pipeline code)
- `scalability_results.tsv`, `stage_timings.tsv`: measurements for the final pipeline
- `*_before_date_cache.tsv`: the same measurements before the optimisation described below
- `outputs/out_<records>.tsv`: pipeline output for each generated dataset
- `evidence/`: saved outputs of the tests described below — sample and malformed-sample outputs, their rejected rows and stderr, the 200,000-row generated `--malformed` test (output, rejection reasons, first 20 rejected rows), and `reference_check_result.txt`
- `reference_check.py`: independent Python implementation of the same query, used only to verify the pipeline's results (not part of the solution)
- `transactions.tsv`, `transactions_malformed.tsv`, `generate_transactions`, `generate_transactions_README.txt`: supplied files (byte-identical)

Run:
```bash
./pipeline.sh transactions.tsv                       # prints the result
./pipeline.sh transactions_malformed.tsv out.tsv     # bad rows -> transactions_malformed.malformed_rows.tsv
./scalability_test.sh data/                          # on Windows: GEN="python ./generate_transactions" ./scalability_test.sh data/
./stage_timing.sh data/
```

The pipeline takes any input file name and any number of records. It finds
columns by name from the header, so both the generator's order (`transaction_id
date category quantity price`) and the sample file's order (`customer_id
product_id category quantity price date`) work.

## Equivalent SQL

```sql
SELECT category, COUNT(*) AS transactions, SUM(quantity * price) AS revenue
FROM transactions
WHERE date >= '2026-01-01' AND quantity > 2
GROUP BY category
HAVING SUM(quantity * price) > 100000
ORDER BY revenue DESC
LIMIT 10;
```

## Processing stages and SQL → Unix mapping

```
tail -n +2 | awk (validate + WHERE + project) | sort -k1,1 | awk (GROUP BY + HAVING) | sort -k3,3gr | head -n 10
```

| Stage | Unix command | SQL operation |
|---|---|---|
| 0 | `head -n 1` + `tr`/`grep -nx` find the column numbers from the header | schema (`FROM transactions`) |
| 1 | `tail -n +2`: skip the header, stream rows | table scan |
| 2 | `awk`: reject malformed rows into a side file | (data cleaning, not in the SQL) |
| 3 | same `awk`: `$date >= "2026-01-01" && $qty > 2` | `WHERE` (selection) |
| 4 | same `awk`: print only `category, quantity, price` | projection |
| 5 | `sort -t$'\t' -k1,1` (external merge sort, `LC_ALL=C`) | brings each `GROUP BY` key together |
| 6 | `awk`: count and sum `qty*price` while the key stays the same, emit at each key change | `GROUP BY category`, `COUNT(*)`, `SUM(quantity*price)` |
| 7 | same `awk`: emit a group only if `revenue > 100000` | `HAVING` |
| 8 | `sort -t$'\t' -k3,3gr` | `ORDER BY revenue DESC` |
| 9 | `head -n 10` | `LIMIT 10` |
| 10 | `{ printf header; cat; }` | output column names |

**Memory use:** every stage reads its input line by line. The aggregation
`awk` keeps only the current group's count and sum, not a table of all groups,
because `sort` has already put equal categories next to each other. `sort`
itself spills to temporary files beyond its 256 MB buffer (`-S 256M`). So no
stage holds the whole dataset in memory. Revenue is summed from the original
`quantity` and `price` fields and printed with `%.2f`. An earlier version
printed large sums in scientific notation (`7.2e+08`), which `sort` then
compared as 7.2 and ordered wrongly. It was fixed and checked against an
independent Python implementation.

## Sample input and output

`transactions.tsv` (supplied sample, complete file, tab-separated):
```
customer_id  product_id  category     quantity  price  date
101          P01         Electronics  3         12000  2026-01-05
102          P02         Grocery      5         800    2026-01-07
103          P03         Electronics  2         15000  2026-01-10
104          P04         Furniture    4         30000  2026-01-15
105          P05         Grocery      8         1200   2026-02-01
106          P06         Clothing     3         4500   2026-02-03
107          P07         Electronics  6         9000   2026-02-11
108          P08         Furniture    2         50000  2026-02-18
109          P09         Clothing     5         7000   2026-03-02
110          P10         Electronics  4         22000  2026-03-12
111          P11         Grocery      10        1500   2026-03-20
112          P12         Furniture    3         42000  2026-04-01
113          P13         Clothing     2         12000  2026-04-07
114          P14         Electronics  7         11000  2026-04-15
115          P15         Grocery      4         3500   2026-05-03
116          P16         Furniture    5         18000  2026-05-11
117          P17         Electronics  3         27000  2026-05-19
118          P18         Clothing     6         8000   2026-06-01
119          P19         Grocery      2         6000   2026-06-12
120          P20         Furniture    4         25000  2026-06-20
```

`./pipeline.sh transactions.tsv` (stdout):
```
category     transactions  revenue
Furniture    4             436000.00
Electronics  5             336000.00
```
and on stderr: `Malformed rows excluded: 0 (see transactions.malformed_rows.tsv)`.
Grocery (4 qualifying rows, revenue 42,600) and Clothing (3 rows, 96,500)
are removed by `HAVING > 100000`. Both results were checked with an independent
Python calculation.

Output for the 1 GB generated file (`outputs/out_25000000.tsv`):
```
category     transactions  revenue
Electronics  947613        13893935397.29
Furniture    473648        13771332023.54
Home         827826        7190100488.38
Appliances   354066        7188134284.84
Jewelry      237077        6854749898.11
Automotive   355427        6183090146.55
Outdoor      354608        5113672227.36
Sports       592870        4119927717.47
Office       473778        4109592713.89
Clothing     830069        3867625797.67
```

## Malformed-record handling

The validation `awk` checks every row, in this order, and on the first failure
writes `reason<TAB>original row` to `<input>.malformed_rows.tsv` and skips the
row (`next`). The pipeline keeps running (`set -e` is deliberately not used).

| Check | Reason written |
|---|---|
| number of fields differs from the header (missing **or extra** field) | `field_count_<n>` |
| empty category | `empty_category` |
| quantity is not a non-negative integer (`^[0-9]+$`) | `bad_quantity` |
| price is not numeric (`^[0-9]+(\.[0-9]+)?$`) | `bad_price` |
| date is not `YYYY-MM-DD` **or not a real calendar date** (month 1–12, day within the month, leap years) | `bad_date` |

A trailing `\r` (Windows line endings) is removed first. Each distinct date
string is validated once and the answer is cached, since the generator
produces only about 730 distinct dates.

`./pipeline.sh transactions_malformed.tsv` (the supplied file: the first 10
sample rows plus 4 malformed rows). The pipeline does not stop, and the
result is computed from the 10 valid rows:
```
category     transactions  revenue
Electronics  3             178000.00
Furniture    1             120000.00
```
The rejected rows are in `transactions_malformed.malformed_rows.tsv`:
```
bad_quantity   121  P21  Electronics  bad    10000  2026-06-25
bad_price      122  P22  Grocery      4             2026-06-26
bad_date       123  P23  Furniture    3      22000  invalid-date
field_count_5  124  P24  Clothing     2      5000
```

**Tested on generator output with `--malformed`** (200,000 records, seed 7).
1,907 rows were rejected: 386 `bad_date` (`2026-99-99`), 382 `bad_price`
(`N/A`), 390 `bad_quantity` (`INVALID`), 357 `field_count_4` and 392
`field_count_6` (extra field). The top-10 result matched an independent Python
implementation exactly. Calendar edge cases were also tested: `2028-02-29` is
accepted, while `2026-02-29`, `2026-04-31` and quantity `3.5` are rejected.

The team's first version missed two of the generator's five malformed kinds.
It accepted `2026-99-99` (format-only regex) and rows with an extra field
(it checked only for *fewer* fields). Those rows were counted in the result
and changed every category's count and revenue.

## Scalability measurements

Same machine and configuration for every size: AMD Ryzen 7 5800H, 16 GB RAM,
NVMe SSD, Windows 11, Git Bash (GNU awk 5.4.0, GNU sort 8.32), `LC_ALL=C`.
Data from `generate_transactions --records N --seed 42`. Each size was run 3
times, after reading the file once so it is in the OS cache.

| Records | Input size | Run 1 | Run 2 | Run 3 | Median | s per MB |
|---|---|---|---|---|---|---|
| 2,500,000 | 102.3 MB | 10.85 s | 10.65 s | 10.93 s | **10.9 s** | 0.106 |
| 6,250,000 | 255.8 MB | 27.38 s | 27.04 s | 28.05 s | **27.4 s** | 0.107 |
| 12,500,000 | 511.6 MB | 64.21 s | 58.93 s | 54.97 s | **58.9 s** | 0.115 |
| 25,000,000 | 1023.2 MB | 109.45 s | 107.86 s | 109.37 s | **109.4 s** | 0.107 |

**Execution time grows linearly with input size.** Doubling the input roughly
doubles the time, and the cost stays at about 0.11 s per MB from 100 MB to
1 GB. The 500 MB runs varied most (55–64 s), probably because other programs
were running on the laptop at the same time.

### Which stage dominates? (measured, `stage_timing.sh`)

`STOP_AFTER=<stage>` runs the pipeline only up to that stage, so the
difference between successive rows is the time that stage adds. Medians of
3 runs:

| Pipeline up to… | 100 MB | 250 MB | 500 MB | 1 GB |
|---|---|---|---|---|
| read (`tail`) | 0.7 s | 1.0 s | 1.5 s | 2.5 s |
| + validate / filter / project (`awk`) | 10.4 s | 25.7 s | 49.9 s | 97.8 s |
| + sort by category | 10.6 s | 26.6 s | 50.5 s | 108.5 s |
| + aggregate / HAVING (`awk`) | 11.1 s | 27.7 s | 53.4 s | 105.3 s |
| full pipeline (+ order + limit) | 10.9 s | 27.5 s | 55.9 s | 110.4 s |

At 1 GB, individual runs of the later prefixes vary by about ±5 s (e.g.
"+ sort": 111.4 / 101.4 / 108.5 s). So small differences between adjacent
rows, including "+ sort" coming out above "+ aggregate", are measurement
noise and not the cost of a stage.

- **The validation/filter `awk` takes about 90% of the time.** It is the only
  stage that processes every one of the millions of input rows with several
  checks (field count, two regular expressions, date check).
- **Reading the file is cheap** (0.7 s per 100 MB), so disk I/O is not the
  bottleneck.
- **`sort` adds under a second at 100–500 MB** (and at 1 GB less than the run-to-run noise). It only receives rows that
  passed the `WHERE` filter (about 45%: the generator's dates are spread
  evenly over 2025–2026, and 90% of quantities are above 2), each row is short, byte-wise
  comparison with `LC_ALL=C` is fast, and GNU sort uses several threads.
- **The aggregation, final sort and `head` add almost nothing.** Aggregation
  is a single cheap pass, and at most 20 category rows reach the final sort.
  Differences of a few tenths of a second between rows are within run-to-run
  noise.

**Optimisation guided by this measurement.** In the first version, the date
check (regex, three `substr` calls, month-length arithmetic) ran on every
row. Since there are only about 730 distinct dates, we cache the result per
date string. Before vs after, same machine and data
(`*_before_date_cache.tsv`):

| Input | Before | After | Faster |
|---|---|---|---|
| 102 MB | 14.7 s | 10.9 s | 26% |
| 256 MB | 37.0 s | 27.4 s | 26% |
| 512 MB | 71.8 s | 58.9 s | 18% |
| 1023 MB | 149.9 s | 109.4 s | 27% |

Both versions produce identical output.

## Assumptions (stated explicitly)
- **Header row.** The input has a header row naming the columns (true for
  the supplied files and for `generate_transactions` output). Columns are
  located by name, because the supplied sample (`customer_id product_id
  category quantity price date`) does not use the column order written in
  the assignment (`transaction_id date category quantity price`).
- **Output rows.** "At most 10 rows" refers to data rows. The output also
  starts with one header line naming the required columns `category
  transactions revenue`.
- **Valid values.** Quantity must be a non-negative integer. Price must be a
  non-negative decimal number without sign or exponent (e.g. `12000`,
  `799.99`). The date must be a real calendar date in `YYYY-MM-DD`
  format. Anything else, including negative numbers, is treated as
  malformed.
- **Rows with extra fields** are treated as malformed, not truncated, since
  the schema has exactly as many fields as the header.
- **Generator arguments.** The assignment's example is
  `./generate_transactions 1000000`, but the supplied generator requires
  `--records N` (and accepts `--seed`). We used the supplied generator as it
  is: `--records N --seed 42`.
- **Revenue** is `quantity * price` summed in floating point and printed
  with 2 decimals.

## What was attempted, achieved and not resolved
- **Achieved:** the full query as a streaming pipeline; malformed-row
  detection for all five malformed kinds the generator produces;
  measurements at ~100 MB, 250 MB, 500 MB and 1 GB (3 runs each); a
  measured per-stage breakdown; and one optimisation guided by that
  measurement.
- **Not attempted:** inputs larger than 1 GB (the assignment says no more
  than 1 GB is expected), and parallel splitting of the input.
- **Unresolved:** the 500 MB runs vary more (55–64 s) than the other sizes.
  We did not identify the cause.

## Limitations of the Unix approach
- **Every run is a full scan.** There are no indexes, statistics or query
  optimiser. The order of the stages is fixed by hand, whereas a database
  could use an index on `date`, or choose a hash aggregate instead of
  sort-then-group.
- **Single-threaded bottleneck.** The dominant `awk` stage uses one core. We
  could split the file and run several `awk` processes in parallel, but that
  is manual work a database would do automatically.
- **Text-based types.** Validation uses regular expressions and string
  comparison (the date filter works only because `YYYY-MM-DD` sorts as text).
  Revenue is summed as floating point, so very large totals can be off by a
  few cents.
- **Portability.** Tested with GNU awk and GNU coreutils. The results
  committed with the team's first version were wrong because of the number
  formatting described above, which shows how much output format and `sort`
  flags matter.
