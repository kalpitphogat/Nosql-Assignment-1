#!/usr/bin/env python3
"""Compare PostgreSQL query results with the official TPC-H SF1 answer files,
using the comparison rules of the official kit's checker
(dbgen/check_answers/cmpq.pl with dbgen/check_answers/colprecision.txt).

Both files: one header line (ignored), then rows of '|'-separated fields.
Rows must match in number and order. Per column type (colprecision.txt):
  str      exact match (trailing spaces ignored)
  cnt/int  exact numeric match
  num      equal when both are formatted with 2 decimals
  sum      |a - b| <= 100 after formatting with 2 decimals
  avg      |a - b| / a <= 1 %  after formatting with 2 decimals
  rat      |a - b| <= 1        after formatting with 2 decimals

Usage: compare_answers.py <query_number> <colprecision.txt> <official_qN.out> <ours_qN.out>
Exit status 0 = no violation of the spec.
"""
import sys

query, precision_file, official_file, ours_file = int(sys.argv[1]), *sys.argv[2:5]
col_types = open(precision_file, encoding="utf-8").read().splitlines()[query - 1].split()


def rows(path):
    lines = [l.rstrip("\r\n") for l in open(path, encoding="utf-8") if l.strip()]
    return [[f.rstrip() for f in l.split("|")] for l in lines[1:]]


def check(kind, a, b):
    """Return (violation, note) for official value a and our value b."""
    if kind == "str":
        return a.strip() != b.strip(), ""
    if kind in ("cnt", "int"):
        return float(a) != float(b), ""
    fa, fb = float(f"{float(a):.2f}"), float(f"{float(b):.2f}")
    diff = abs(fa - fb)
    if kind == "num":
        return fa != fb, f"diff {diff:.2f}"
    if kind == "sum":
        return diff > 100, f"diff {diff:.2f}"
    if kind == "avg":
        pct = diff / fa * 100 if fa else 0.0
        return pct > 1, f"diff {diff:.2f} ({pct:.6f} %)"
    if kind == "rat":
        return diff > 1, f"diff {diff:.2f}"
    raise SystemExit(f"unknown column type {kind}")


official, ours = rows(official_file), rows(ours_file)
violations, tolerated = [], []
if len(official) != len(ours):
    violations.append(f"row count: official {len(official)}, ours {len(ours)}")
for i, (a_row, b_row) in enumerate(zip(official, ours), start=1):
    if len(a_row) != len(b_row) or len(a_row) != len(col_types):
        violations.append(f"row {i}: column count official {len(a_row)}, ours {len(b_row)}, types {len(col_types)}")
        continue
    for col, (kind, a, b) in enumerate(zip(col_types, a_row, b_row)):
        bad, note = check(kind, a, b)
        if bad:
            violations.append(f"row {i} col {col + 1} ({kind}): official {a!r} vs ours {b!r} {note}")
        elif note and not note.startswith("diff 0.00"):
            tolerated.append(f"row {i} col {col + 1} ({kind}): official {a} vs ours {b}, {note}, within spec")
    if len(violations) >= 5:
        break

if violations:
    print("VIOLATION: " + "; ".join(violations))
    sys.exit(1)
print(f"match ({len(official)} rows)" + (f"; {len(tolerated)} value(s) differ within the official tolerance: "
                                          + "; ".join(tolerated[:3]) if tolerated else ""))
