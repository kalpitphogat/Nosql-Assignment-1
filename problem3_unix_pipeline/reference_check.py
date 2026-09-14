#!/usr/bin/env python3
"""Independent reference implementation of the Problem 3 query, used ONLY to
verify pipeline.sh (it loads rows one at a time but is not part of the
solution). Applies the same validity rules and prints the same output format.

Usage: python3 reference_check.py <input.tsv>
       python3 reference_check.py --counts <input.tsv>
           prints "header malformed removed_by_where kept" (used by conservation_check.sh)
"""
import collections
import datetime
import re
import sys

counts_only = sys.argv[1] == "--counts"
path = sys.argv[2] if counts_only else sys.argv[1]
removed = kept = 0

with open(path, encoding="utf-8", newline="") as f:
    header = f.readline().rstrip("\r\n").split("\t")
    ix = {name: i for i, name in enumerate(header)}
    count, revenue, bad = collections.Counter(), collections.defaultdict(float), 0
    for line in f:
        p = line.rstrip("\r\n").split("\t")
        try:
            assert len(p) == len(header) and p[ix["category"]]
            assert re.fullmatch(r"\d+", p[ix["quantity"]])
            assert re.fullmatch(r"\d+(\.\d+)?", p[ix["price"]])
            assert re.fullmatch(r"\d{4}-\d{2}-\d{2}", p[ix["date"]])
            datetime.date.fromisoformat(p[ix["date"]])
        except (AssertionError, ValueError):
            bad += 1
            continue
        if p[ix["date"]] >= "2026-01-01" and int(p[ix["quantity"]]) > 2:
            kept += 1
            c = p[ix["category"]]
            count[c] += 1
            revenue[c] += int(p[ix["quantity"]]) * float(p[ix["price"]])
        else:
            removed += 1

if counts_only:
    print(1, bad, removed, kept)
    sys.exit(0)

print("category\ttransactions\trevenue")
for c in sorted((c for c in revenue if revenue[c] > 100000), key=lambda c: -revenue[c])[:10]:
    print(f"{c}\t{count[c]}\t{revenue[c]:.2f}")
print(f"malformed rows: {bad}", file=sys.stderr)
