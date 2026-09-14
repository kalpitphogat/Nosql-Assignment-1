#!/usr/bin/env python3
"""Plots and summarises results/timings.csv + results/totals.csv.

Writes:
  results/scaling_plot.png     total time vs dataset size, per-query time vs SF
  results/per_query_plot.png   one small panel per query (log-log)
  results/scaling_summary.csv  median time per query per SF, successive ratios,
                               and the log-log slope (1 = linear, >1 super-linear)
"""
import csv
import math
from collections import defaultdict
from statistics import median

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

timings = list(csv.DictReader(open("results/timings.csv")))
totals = list(csv.DictReader(open("results/totals.csv")))

size_mb = {int(r["scale_factor"]): float(r["dataset_size_mb"]) for r in totals}
sfs = sorted(size_mb)

# Median over repetitions; a query that timed out or failed in any run is
# reported as missing for that SF rather than silently averaged in.
runs = defaultdict(list)
bad = set()
for r in timings:
    key = (int(r["query"]), int(r["scale_factor"]))
    if r["status"] == "ok":
        runs[key].append(float(r["seconds"]))
    else:
        bad.add(key)
med = {k: median(v) for k, v in runs.items() if k not in bad}
queries = sorted({q for q, _ in runs} | {q for q, _ in bad})


def slope(q):
    pts = [(math.log(size_mb[sf]), math.log(med[(q, sf)])) for sf in sfs if (q, sf) in med]
    if len(pts) < 2:
        return None
    mx = sum(x for x, _ in pts) / len(pts)
    my = sum(y for _, y in pts) / len(pts)
    den = sum((x - mx) ** 2 for x, _ in pts)
    return sum((x - mx) * (y - my) for x, y in pts) / den


with open("results/scaling_summary.csv", "w", newline="") as f:
    w = csv.writer(f)
    ratio_cols = [f"ratio_sf{b}/sf{a}" for a, b in zip(sfs, sfs[1:])]
    w.writerow(["query"] + [f"median_s_sf{sf}" for sf in sfs] + ratio_cols + ["loglog_slope"])
    for q in queries:
        row = [f"Q{q}"]
        row += [f"{med[(q, sf)]:.3f}" if (q, sf) in med else "timeout/error" for sf in sfs]
        for a, b in zip(sfs, sfs[1:]):
            ok = (q, a) in med and (q, b) in med
            row.append(f"{med[(q, b)] / med[(q, a)]:.2f}" if ok else "")
        s = slope(q)
        row.append(f"{s:.2f}" if s is not None else "")
        w.writerow(row)
    tot = {sf: median(float(r["total_query_seconds"]) for r in totals if int(r["scale_factor"]) == sf) for sf in sfs}
    w.writerow(["TOTAL"] + [f"{tot[sf]:.3f}" for sf in sfs]
               + [f"{tot[b] / tot[a]:.2f}" for a, b in zip(sfs, sfs[1:])] + [""])

fig, axes = plt.subplots(1, 2, figsize=(13, 5))

ax = axes[0]
xs = [size_mb[sf] for sf in sfs]
ys = [tot[sf] for sf in sfs]
ax.plot(xs, ys, marker="o", linewidth=2, label="measured (median of runs)")
ax.plot(xs, [ys[0] * x / xs[0] for x in xs], "--", color="grey", label="linear from first SF")
for sf, x, y in zip(sfs, xs, ys):
    ax.annotate(f"SF={sf}", (x, y), textcoords="offset points", xytext=(6, -12))
ax.set_xlabel("Dataset size (MB of generated .tbl files)")
ax.set_ylabel("Total time, 22 queries (s)")
ax.set_title("TPC-H on PostgreSQL: dataset size vs total query time")
ax.grid(True, alpha=0.3)
ax.legend()

ax = axes[1]
colors = plt.get_cmap("tab10").colors
styles = ["-", "--", ":"]
markers = ["o", "s", "^"]
for i, q in enumerate(queries):
    pts = [(sf, med[(q, sf)]) for sf in sfs if (q, sf) in med]
    if pts:
        ax.plot(*zip(*pts), color=colors[i % 10], linestyle=styles[i // 10 % 3],
                marker=markers[i // 10 % 3], markersize=3, alpha=0.85, label=f"Q{q}")
ax.plot(sfs, [sf for sf in sfs], "--", color="black", linewidth=1, label="slope 1 (linear)")
ax.set_xscale("log", base=2)
ax.set_yscale("log")
ax.set_xticks(sfs, [str(s) for s in sfs])
ax.set_xlabel("Scale factor (log2)")
ax.set_ylabel("Median query time (s, log)")
ax.set_title("Per-query time vs scale factor")
ax.grid(True, which="both", alpha=0.3)
ax.legend(fontsize=7, ncol=3)
fig.tight_layout()
fig.savefig("results/scaling_plot.png", dpi=150)

cols = 6
rows = math.ceil(len(queries) / cols)
fig, axes = plt.subplots(rows, cols, figsize=(3 * cols, 2.4 * rows), squeeze=False)
for ax, q in zip(axes.flat, queries):
    pts = [(sf, med[(q, sf)]) for sf in sfs if (q, sf) in med]
    if pts:
        x, y = zip(*pts)
        ax.plot(x, y, marker="o")
        ax.plot(x, [y[0] * sf / x[0] for sf in x], "--", color="grey", linewidth=1)
    for sf in sfs:
        if (q, sf) in bad:
            ax.axvline(sf, color="red", alpha=0.3)
    s = slope(q)
    ax.set_title(f"Q{q}" + (f"  slope {s:.2f}" if s is not None else ""), fontsize=9)
    ax.set_xscale("log", base=2)
    ax.set_yscale("log")
    ax.set_xticks(sfs, [str(s) for s in sfs])
    ax.tick_params(labelsize=7)
    ax.grid(True, which="both", alpha=0.3)
for ax in list(axes.flat)[len(queries):]:
    ax.axis("off")
fig.suptitle("Per-query median time vs SF (grey = linear; red line = timeout/error at that SF)")
fig.tight_layout()
fig.savefig("results/per_query_plot.png", dpi=130)

print("Wrote results/scaling_plot.png, results/per_query_plot.png, results/scaling_summary.csv")
