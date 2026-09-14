# Compliance checklist

Every requirement in the assignment PDF (*Nosql_Assignment1.pdf*), in the
order it appears, with the file(s) that satisfy it. ✔ = met,
◐ = met with a stated limitation, ✘ = not met (the reason is given).

## General instructions

| # | Requirement (PDF) | Status | Where / how |
|---|---|---|---|
| G1 | Team assignment; use the time to understand, analyse, implement and evaluate | ✔ | all three problems implemented, measured and analysed (see the three READMEs) |
| G2 | For problems not fully solved, state what was attempted, achieved, unresolved and why | ✔ | *Limitations* sections in each README; P3 *What was attempted, achieved and not resolved*; P1 *Limitations and honest notes* |
| G3 | Submit all programs/scripts, datasets or dataset sources, commands, configurations and experimental outputs | ✔ | P1: all scripts, generated queries, raw timings, plans, outputs, and the official TPC-H kit's SHA-256 + EULA (the kit archive itself, ~25 MB, is left out of this ZIP only because the LMS caps uploads at 20 MB — full provenance is in `official_tpch_materials/README.txt` and `results/tpch_provenance.txt`). P2: program, input CSVs, all outputs. P3: pipeline, supplied files, generator, measurements. Large generated datasets are replaced by their exact generation commands (`dbgen -s SF`, `generate_transactions --records N --seed 42`) |
| G4 | Experiments reproducible; hardware/software environment and performance measurements documented | ✔ | P1 `results/environment.txt`, `results/tpch_provenance.txt`, setup script; P3 *Scalability measurements* (machine and tool versions); P2 README (Python version) |
| G5 | Results from the team's own experiments; assumptions clearly stated | ✔ | all numbers come from the files in this package; *Assumptions* sections in P2 and P3; P1 *Limitations and honest notes* |
| G6 | AI tools only as assistance; team responsible for correctness and understanding | — | responsibility of the team members; every result is backed by a script and raw output that can be re-run |
| G7 | In-person demonstration; every member must understand every part | — | the READMEs explain the reasoning behind every design decision, as preparation for the viva |
| G8 | Supplementary package used (customer CSVs, transactions TSVs, generator) | ✔ | byte-identical copies of the supplied files: P2 `customer_master.csv`, `customer_incoming.csv`; P3 `transactions.tsv`, `transactions_malformed.tsv`, `generate_transactions`, `generate_transactions_README.txt` |
| G9 | For TPC-H use the official TPC-H benchmark materials, not the supplied sample datasets | ✔ | official *TPC-H Tools v3.0.1* archive, unmodified, SHA-256 `97ccb34cd122d78c2e06e2419e50957f934256868b37c02d0b88aefd9d13a84a` (download from tpc.org; the archive is left out of the ZIP because of the 20 MB upload limit, its EULA and provenance are in `problem1_tpch/official_tpch_materials/`); build and hashes in `problem1_tpch/results/tpch_provenance.txt` |

## Problem 1 — TPC-H scaling study

| # | Requirement (PDF) | Status | Where / how |
|---|---|---|---|
| 1.1 | Use the current TPC-H specification and tools from TPC (Revision 3.0.1) | ✔ | official kit (G9). The tools print "Version 3.0.0 build 0", the banner of the programs inside the 3.0.1 kit, recorded exactly as observed |
| 1.2 | Increase the scale factor progressively, doubling each step | ✔ | SF 1, 2, 4, 8, 16, 32 (`results/totals.csv`) |
| 1.3 | For each SF, generate and load the dataset | ✔ | official `dbgen -s SF`, streamed `COPY`; generated = loaded rows for all 48 table/SF pairs (`results/row_counts.csv`) |
| 1.4 | Execute the specified TPC-H queries | ✔ | all 22, generated per SF by official `qgen -r 42 -s SF` (`queries/sf*/raw`, adapted `queries/sf*/`, SHA-256); SF1 results pass the official answer check 22/22, confirmed by the kit's `cmpq.pl` (`results/answer_validation*`) |
| 1.5 | Measure the execution time of each query and the total | ✔ | `results/timings.csv` (528 rows, all `ok`), `results/totals.csv` |
| 1.6 | Repeat the experiment as appropriate | ✔ | 1 warm-up (excluded) + 3 measured runs per query per SF; medians, with min–max shown in the plots |
| 1.7 | Keep the experimental environment unchanged across scale factors | ◐ | same machine, PostgreSQL 16.15 build, configuration and 30 min timeout at every SF; both invocations recorded in `results/environment.txt` and identical except date/load/free space. The server is shared: SF2–SF8 runs are noisier (typical spread 13–23 % vs ≤ 1.5 % at SF1/16/32), quantified in the README and report |
| 1.8 | State the database system (PostgreSQL preferred), its configuration, hardware and software environment | ✔ | README *Experimental setup*; `results/environment.txt` |
| 1.9 | Plot dataset size against query execution time | ✔ | `results/scaling_plot.png` (total and per query vs dataset size), `results/per_query_plot.png` (22 panels) |
| 1.10 | Analyse whether time approximately doubles when the data doubles | ✔ | README *Does query time double…*: 33.0× data → 52.7× time; per-step ratios 1.72–2.67 |
| 1.11 | Which queries scale linearly or super-linearly | ✔ | README sections 1 and 3, `results/scaling_summary.csv` |
| 1.12 | Which queries are relatively insensitive to dataset size | ✔ | README section 2: no query is insensitive overall; flat single steps (Q6, Q15, Q18) coincide with plan changes |
| 1.13 | At what SF performance begins to degrade significantly | ✔ | README section 3: SF32 (total ratio 2.67; seven queries > 3×), with plan evidence |
| 1.14 | Relate observations to joins, aggregation, sorting and filtering | ✔ | README *Relating the observations to database operations*, based on `results/plans/` (EXPLAIN at every SF, EXPLAIN ANALYZE at SF32) |
| 1.15 | Submit setup, dataset-generation procedure, execution scripts, raw measurements, plots, explanation | ✔ | `problem1_tpch/` (scripts, queries, `results/`, README) |

## Problem 2 — Incomplete data integration and JSON

| # | Requirement (PDF) | Status | Where / how |
|---|---|---|---|
| 2.1 | Program that compares incoming with master and determines the relationship of **every** incoming record | ✔ | `match_customers.py`; all 2000 rows in `classification_results.csv` |
| 2.2 | Each record in exactly one of the 5 categories | ✔ | one `match_status` per row; counts 400 + 657 + 193 + 400 + 350 = 2000 (`summary_statistics.txt`) |
| 2.3 | Own matching strategy, clearly described with rule order/priority and handling of missing and conflicting values | ✔ | README *Matching strategy* and *Classifying once a candidate is (or isn't) found* |
| 2.4 | Logically justified and consistently applied to all records | ✔ | README *Evidence behind the rule order* (measured uniqueness of each attribute); one code path for every row |
| 2.5 | Records with missing or conflicting attributes: do not discard, represent as JSON preserving available, missing and conflicting information | ✔ | `json_output/` (1202 documents) with `available_information`, `missing_information`, `conflicting_information` |
| 2.6 | JSON structure may differ from the example but must explicitly identify missing/conflicting information | ✔ | explicit `missing_information` list and `conflicting_information` object (incoming vs master value) |
| 2.7 | Submit algorithm and source code | ✔ | `match_customers.py`, README |
| 2.8 | Submit matching criteria with justification | ✔ | README *Matching strategy*, *Evidence behind the rule order* |
| 2.9 | Submit the classification of all records | ✔ | `classification_results.csv` |
| 2.10 | JSON documents for records with missing, **irregular** or conflicting information | ✔ | all 1200 partial/incomplete/conflicting records, plus 2 records whose only issue is an irregular value; 41 documents carry `irregular_information` with the raw value (README *Irregular values*) |
| 2.11 | Brief explanation of why JSON suits such records | ✔ | README *Why JSON for records with missing, conflicting or irregular information* |
| 2.12 | Summary statistics for each category | ✔ | `summary_statistics.txt`; README *Results on the supplied data* |
| 2.13 | Discuss assumptions, limitations and difficulties | ✔ | README *Assumptions / limitations*, *Difficulties encountered* |
| 2.14 | Supplied CSV files used as input | ✔ | the program reads `customer_master.csv` and `customer_incoming.csv` (byte-identical to the supplied files) |
| 2.15 | Do not assume the example JSON records exist | ✔ | no hard-coded records; ids such as `C00104` are not referenced |
| 2.16 | All records processed and classified automatically, none manually | ✔ | single loop over all rows; no per-record special cases in the code |
| 2.17 | Matching rules consistent across the dataset | ✔ | same `classify()` for every row |

## Problem 3 — Unix data-processing pipeline

| # | Requirement (PDF) | Status | Where / how |
|---|---|---|---|
| 3.1 | SQL-like task using only Unix command-line tools and shell scripting | ✔ | `pipeline.sh`: `head`, `tail`, `tr`, `grep`, `cut`, `awk`, `sort` in a bash script |
| 3.2 | Process the TSV without loading the whole file into memory | ✔ | every stage streams line by line; `sort` spills to temp files beyond 256 MB; aggregation keeps one group's state at a time (README *Memory use*) |
| 3.3 | Fields `transaction_id date category quantity price`, tab-separated, typed as specified | ✔ | columns located by header name; types validated (README *Malformed-record handling*, *Assumptions*) |
| 3.4 | Implement the given `SELECT … WHERE … GROUP BY … HAVING … ORDER BY … LIMIT 10` | ✔ | README *Processing stages and SQL → Unix mapping*; results match an independent Python calculation |
| 3.5 | Do not import into a database or run the SQL directly | ✔ | no database or SQL engine is used |
| 3.6 | Multiple stages connected by pipes, reading the input progressively | ✔ | `tail \| awk \| sort \| awk \| sort \| head` |
| 3.7 | Selection, projection, filtering, grouping, aggregation, sorting and Top-K | ✔ | mapping table in the README |
| 3.8 | Demonstrate malformed-record handling (missing field, invalid date, non-numeric quantity or price); exclude them without terminating | ✔ | README *Malformed-record handling*: supplied malformed file (4 rows rejected with reasons) and a generated `--malformed` file (1,907 rows, all 5 kinds) |
| 3.9 | Use the supplied generator; it takes the number of records | ◐ | used unchanged as `generate_transactions --records N --seed 42`. The supplied generator requires `--records`, unlike the PDF's positional example (README *Assumptions*) |
| 3.10 | Develop and test on the supplied sample first | ✔ | README *Sample input and output* |
| 3.11 | At least four sizes ≈ 100 MB, 250 MB, 500 MB, 1 GB | ✔ | 102.3 / 255.8 / 511.6 / 1023.2 MB (`scalability_results.tsv`) |
| 3.12 | Record input size and total execution time; same machine and configuration | ✔ | `scalability_results.tsv` (3 runs each), machine stated in the README |
| 3.13 | Report a table; discuss how time changes with size | ✔ | README *Scalability measurements* |
| 3.14 | Explain which stages likely dominate and why | ✔ | measured per stage (`stage_timing.sh`, `stage_timings.tsv`), README *Which stage dominates?* |
| 3.15 | Output at most 10 rows with columns `category transactions revenue`, ordered by decreasing revenue | ✔ | `outputs/out_*.tsv`; header line plus ≤ 10 data rows (README *Assumptions*) |
| 3.16 | Submit the complete shell script | ✔ | `pipeline.sh` |
| 3.17 | Sample input and output | ✔ | README *Sample input and output* |
| 3.18 | Explanation of the processing stages | ✔ | README *Processing stages* |
| 3.19 | The equivalent SQL query | ✔ | README *Equivalent SQL* |
| 3.20 | Mapping of each SQL operation to Unix commands | ✔ | README mapping table |
| 3.21 | Scalability measurements and analysis of performance and limitations | ✔ | README *Scalability measurements*, *Limitations of the Unix approach* |
| 3.22 | Explain how malformed records are detected and handled | ✔ | README *Malformed-record handling* |
| 3.23 | Operate directly on TSV files; no database, dataframe library or in-memory framework | ✔ | only awk/sort/coreutils |
| 3.24 | Intermediate files only where necessary; use pipes and streaming | ✔ | the only files written besides the output are the malformed-rows log and `sort`'s own temporary files |
| 3.25 | Work with generator files; no fixed record count or input filename | ✔ | input path is an argument; tested from the 14-row supplied malformed file up to 25,000,000 generated rows, under several different file names |
