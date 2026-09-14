# NoSQL Systems (DAS 838) — Assignment 1

Team submission. Due 15 Sept 2026, 8:00 AM.

| Folder | Problem | Status |
|---|---|---|
| `problem1_tpch/` | Scaling study with TPC-H on PostgreSQL 16.15 | SF 1, 2, 4, 8, 16, 32; 3 runs each; all 396 query runs succeeded |
| `problem2_integration/` | Incomplete data integration + JSON generation | all 2000 incoming records classified automatically; 1200 JSON documents |
| `problem3_unix_pipeline/` | SQL-like query as a Unix pipeline | correct on clean and malformed data; measured at 100 MB – 1 GB, 3 runs each |

Each folder has its own `README.md` with the approach, how to reproduce it,
raw measurements, and analysis and limitations.

## Environments
- **Problem 1:** Intel Core i9-12900K (16 cores / 24 threads), 62 GB RAM,
  NVMe SSD, RHEL 8.10, PostgreSQL 16.15 built from source. Details in
  `problem1_tpch/results/environment.txt`.
- **Problems 2 and 3:** AMD Ryzen 7 5800H (8 cores / 16 threads), 16 GB RAM,
  Windows 11 with Git Bash (GNU awk 5.4.0, GNU coreutils 8.32 `sort`),
  Python 3.12.

## Data
Generated benchmark data is not committed because it is reproducible and
large: TPC-H `.tbl` files come from `dbgen -s SF`, and transaction files from
`generate_transactions --records N --seed 42`. The supplied inputs
(`customer_master.csv`, `customer_incoming.csv`, `transactions.tsv`,
`transactions_malformed.tsv`, `generate_transactions`) are included.
