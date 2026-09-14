# NoSQL Systems (DAS 838) — Assignment 1

Team ID 18, 28: Kalpit (BT2024093), Cheruku Sri Charan Reddy (BT2024143),
Arnav Jain (BT2024233), D Sree Teja (BT2024160).

If you only want to read one thing, open **`REPORT.pdf`**. It walks through all
three problems: what we built, how we tested it, the measurements and what we
make of them. The LaTeX source is in `report/`.

Each problem also has its own folder with the code, the inputs, the raw
outputs and a README that goes into more detail than the report.
`COMPLIANCE.md` lists every requirement from the assignment PDF together with
the file where we address it.

## What is where

```
REPORT.pdf                     the report (compiled from report/report.tex)
COMPLIANCE.md                  requirement-by-requirement checklist
report/                        LaTeX source and figures

problem1_tpch/                 TPC-H scaling study on PostgreSQL
  setup_postgres_and_dbgen.sh  builds PostgreSQL 16.15 and the official TPC-H 3.0.1 tools
  run_benchmark.sh             generates, loads, checks and times every scale factor
  generate_queries.sh          runs qgen for one scale factor ...
  adapt_query.py               ... and turns its output into PostgreSQL SQL
  validate_answers.sh          checks SF1 results against the official answers
  queries/                     the exact qgen output and the queries we ran, per scale factor
  results/                     timings, totals, row counts, plans, plots, logs, environment
  official_tpch_materials/     the official TPC-H kit, unmodified, with its licence

problem2_integration/          matching incoming customers against the master file
  match_customers.py           the program
  customer_*.csv               the supplied input files, unchanged
  classification_results.csv   the category of every incoming record
  json_output/                 JSON for records with missing, irregular or conflicting data

problem3_unix_pipeline/        the SQL query as a Unix pipeline
  pipeline.sh                  the pipeline
  scalability_test.sh          timing runs at 100 MB, 250 MB, 500 MB and 1 GB
  stage_timing.sh              how long each stage of the pipeline takes
  evidence/                    saved outputs of our tests
```

## Where things ran

Problem 1 ran on a lab server (Intel Core i9-12900K, 62 GB RAM, NVMe SSD, Red
Hat Enterprise Linux 8.10). All scale factors used the same machine, the same
PostgreSQL build and the same configuration.

Problems 2 and 3 ran on a laptop (AMD Ryzen 7 5800H, 16 GB RAM, NVMe SSD,
Windows 11 with Git Bash, GNU awk 5.4.0, GNU coreutils 8.32, Python 3.12.10).

## Data we did not include

The generated datasets are large and can be recreated exactly, so we left them
out: the TPC-H tables come from `dbgen -s <SF>` with the included kit, and the
transaction files from `generate_transactions --records <N> --seed 42` with the
supplied generator. All files handed out with the assignment are included
unchanged.
