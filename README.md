# NoSQL Systems (DAS 838) — Assignment 1

Team submission. Team members are listed in `TEAM.md` and on the cover of `REPORT.pdf`.

## Start here

| File | What it is |
|---|---|
| `REPORT.pdf` | the complete report: all three problems and the compliance checklist, with tables and plots (generated from the READMEs by `build_report.py`) |
| `COMPLIANCE.md` | every requirement of the assignment PDF mapped to the file that satisfies it |
| `problem1_tpch/README.md` | Problem 1: TPC-H scaling study on PostgreSQL |
| `problem2_integration/README.md` | Problem 2: incomplete data integration and JSON generation |
| `problem3_unix_pipeline/README.md` | Problem 3: SQL-like query as a Unix pipeline |

## Layout

```
problem1_tpch/
  setup_postgres_and_dbgen.sh   build PostgreSQL 16.15 + official TPC-H V3.0.1 dbgen/qgen
  run_benchmark.sh              generate, load, validate and time every scale factor
  generate_queries.sh, adapt_query.py        qgen per scale factor -> PostgreSQL SQL
  validate_answers.sh, compare_answers.py    SF1 check against the official answer set
  schema.sql, indexes.sql, plot_results.py
  queries/sf<N>/raw, queries/sf<N>/*.sql     exact qgen output and the adapted queries (+ SHA256SUMS)
  results/                      timings, totals, row counts, environment, provenance,
                                answer validation, plans, query outputs, plots, logs
  official_tpch_materials/      unmodified official TPC-H Tools v3.0.1 archive + EULA
problem2_integration/
  match_customers.py            the matching program
  customer_master.csv, customer_incoming.csv  supplied inputs (byte-identical)
  classification_results.csv, summary_statistics.txt, json_output/
problem3_unix_pipeline/
  pipeline.sh                   the pipeline
  scalability_test.sh, stage_timing.sh, reference_check.py
  transactions*.tsv, generate_transactions   supplied files (byte-identical)
  scalability_results.tsv, stage_timings.tsv, outputs/, evidence/
```

## Environments
- **Problem 1:** Intel Core i9-12900K (16 cores / 24 threads), 62 GB RAM,
  NVMe SSD, Red Hat Enterprise Linux 8.10, PostgreSQL 16.15 built from source.
  One machine and one configuration for every scale factor. Details in
  `problem1_tpch/results/environment.txt`.
- **Problems 2 and 3:** AMD Ryzen 7 5800H (8 cores / 16 threads), 16 GB RAM,
  NVMe SSD, Windows 11 with Git Bash (GNU awk 5.4.0, GNU coreutils 8.32),
  Python 3.12.10.

## Data not included
Generated benchmark data is large and exactly reproducible, so it is not
included: TPC-H tables come from `dbgen -s <SF>` (official kit, included), and
transaction files from `generate_transactions --records <N> --seed 42`
(supplied generator, included). All supplied input files are included unchanged.
