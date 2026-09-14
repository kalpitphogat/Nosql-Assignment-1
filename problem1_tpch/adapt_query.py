#!/usr/bin/env python3
"""Adapt one query produced by the official TPC-H V3.0.1 qgen to PostgreSQL.

qgen is built with DATABASE=ORACLE (no PostgreSQL option exists in the kit).
Only two dialect differences need changing; everything else is standard SQL
that PostgreSQL accepts unchanged:

1. Row limit.  qgen emits SET_ROWCOUNT for the template's ":n <count>" marker
   *after* the query's terminating ';' as the Oracle clause
       where rownum <= <count>;
   with <count> = -1 for queries that have no limit.  We remove that line and,
   for a positive count, turn the query's final ';' into "limit <count>;".
   (Q2 100, Q3 10, Q10 20, Q18 100, Q21 100.)
2. Interval precision.  Q1 uses  interval '<n>' day (3)  -- the "(3)"
   precision is not accepted by PostgreSQL, so it is dropped.

Usage: adapt_query.py <raw_qgen_output.sql>   (adapted SQL on stdout)
Fails loudly if the input does not have the expected shape.
"""
import re
import sys

raw = open(sys.argv[1], encoding="utf-8").read()

rowcount = re.findall(r"^\s*where rownum <= (-?\d+);\s*$", raw, flags=re.M)
if len(rowcount) != 1:
    sys.exit(f"{sys.argv[1]}: expected exactly one 'where rownum <= N;' line, found {len(rowcount)}")
limit = int(rowcount[0])
sql = re.sub(r"^\s*where rownum <= -?\d+;\s*$\n?", "", raw, flags=re.M).rstrip() + "\n"

if limit > 0:
    idx = sql.rfind(";")
    if idx < 0:
        sys.exit(f"{sys.argv[1]}: no ';' to attach LIMIT {limit} to")
    sql = sql[:idx].rstrip() + f"\nlimit {limit};" + sql[idx + 1:]

sql, n_interval = re.subn(r"interval '(\d+)' day \(3\)", r"interval '\1' day", sql)

if "rownum" in sql or ":" in re.sub(r"'[^']*'", "", sql):
    sys.exit(f"{sys.argv[1]}: unsubstituted qgen marker or rownum left after adaptation")

sys.stdout.write(sql)
