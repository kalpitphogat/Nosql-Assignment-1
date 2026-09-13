#!/usr/bin/env python3
"""Plots dataset size vs. total query time, and a per-query breakdown."""
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

with open("results/totals.csv") as f:
    totals = list(csv.DictReader(f))

with open("results/timings.csv") as f:
    timings = list(csv.DictReader(f))

sfs = [int(r["scale_factor"]) for r in totals]
sizes = [float(r["dataset_size_mb"]) for r in totals]
times = [float(r["total_query_seconds"]) for r in totals]

fig, axes = plt.subplots(1, 2, figsize=(12, 5))

ax = axes[0]
ax.plot(sizes, times, marker="o", linewidth=2)
for sf, x, y in zip(sfs, sizes, times):
    ax.annotate(f"SF={sf}", (x, y), textcoords="offset points", xytext=(8, 5))
ax.set_xlabel("Dataset size (MB)")
ax.set_ylabel("Total query time, all 22 queries (s)")
ax.set_title("TPC-H: dataset size vs. total query time")
ax.grid(True, alpha=0.3)

ax2 = axes[1]
by_query = {}
for r in timings:
    by_query.setdefault(int(r["query"]), {})[int(r["scale_factor"])] = float(r["seconds"])

for q in sorted(by_query):
    xs = sorted(by_query[q])
    ys = [by_query[q][sf] for sf in xs]
    ax2.plot(xs, ys, marker=".", alpha=0.6, label=f"Q{q}" if q in (2, 7, 9, 15, 20, 21) else None)
ax2.set_xlabel("Scale factor")
ax2.set_ylabel("Query time (s)")
ax2.set_title("Per-query time vs. scale factor")
ax2.set_xticks(sfs)
ax2.legend(fontsize=8, title="selected queries")
ax2.grid(True, alpha=0.3)

fig.tight_layout()
fig.savefig("results/scaling_plot.png", dpi=150)
print("Wrote results/scaling_plot.png")
