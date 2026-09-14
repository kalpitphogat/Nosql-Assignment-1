#!/usr/bin/env python3
"""Assemble the submission folder and ZIP.

Usage: python make_package.py <path to official TPC-H Tools v3.0.1 zip> [output_dir]

Creates <output_dir>/NoSQL_A1_Submission/ and NoSQL_A1_Submission.zip containing
the report, compliance checklist, all three problems, and the unmodified official
TPC-H kit with its EULA and the legend required by EULA clause 9(b).
"""
import hashlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
KIT = Path(sys.argv[1]).resolve()
OUT_DIR = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else ROOT.parent
NAME = "NoSQL_A1_Submission"
PKG = OUT_DIR / NAME
EXPECTED_KIT_SHA256 = "97ccb34cd122d78c2e06e2419e50957f934256868b37c02d0b88aefd9d13a84a"

sha = hashlib.sha256(KIT.read_bytes()).hexdigest()
if sha != EXPECTED_KIT_SHA256:
    sys.exit(f"TPC-H kit SHA-256 {sha} does not match the recorded official archive")

for required in ["problem1_tpch/queries/sf1/SHA256SUMS", "problem1_tpch/queries/sf32/SHA256SUMS",
                 "problem1_tpch/queries/default/SHA256SUMS", "problem1_tpch/results/timings.csv"]:
    if not (ROOT / required).exists():
        sys.exit(f"missing {required} -- copy it from the server first")

if "PENDING" in (ROOT / "COMPLIANCE.md").read_text(encoding="utf-8"):
    sys.exit("COMPLIANCE.md still has PENDING rows -- finish Problem 1 first")

# Compile the LaTeX report (twice, for the table of contents) and use it as REPORT.pdf.
PDFLATEX = shutil.which("pdflatex") or str(Path.home() / "AppData/Local/Programs/MiKTeX/miktex/bin/x64/pdflatex.exe")
report_dir = ROOT / "report"
shutil.copy2(ROOT / "problem1_tpch/results/scaling_plot.png", report_dir / "figures/scaling_plot.png")
shutil.copy2(ROOT / "problem1_tpch/results/per_query_plot.png", report_dir / "figures/per_query_plot.png")
for _ in range(2):
    subprocess.run([PDFLATEX, "-interaction=nonstopmode", "-halt-on-error", "report.tex"],
                   cwd=report_dir, check=True, stdout=subprocess.DEVNULL)
shutil.copy2(report_dir / "report.pdf", ROOT / "REPORT.pdf")

IGNORE = shutil.ignore_patterns(".git", "__pycache__", "*.pyc", "data", "*.tbl", "report.aux", "report.log", "report.out", "report.toc", "report.pdf",
                                "*.malformed_rows.tsv", "make_package.py")
if PKG.exists():
    shutil.rmtree(PKG)
PKG.mkdir(parents=True)
for item in ["README.md", "REPORT.pdf", "COMPLIANCE.md", "TEAM.md", "report",
             "problem1_tpch", "problem2_integration", "problem3_unix_pipeline"]:
    src = ROOT / item
    if not src.exists():
        continue
    if src.is_dir():
        shutil.copytree(src, PKG / item, ignore=IGNORE)
    else:
        shutil.copy2(src, PKG / item)

kit_dir = PKG / "problem1_tpch" / "official_tpch_materials"
kit_dir.mkdir(parents=True, exist_ok=True)
# The kit archive (~25 MB) is left out: the LMS caps uploads at 20 MB. The EULA,
# the TPC legend and the SHA-256 are included so a fresh download can be verified.
with zipfile.ZipFile(KIT) as z:
    eula = next(n for n in z.namelist() if n.endswith("EULA.txt"))
    (kit_dir / "EULA.txt").write_bytes(z.read(eula))
shutil.copy2(ROOT / "problem1_tpch/official_tpch_materials/README.txt", kit_dir / "README.txt")

zip_path = OUT_DIR / f"{NAME}.zip"
if zip_path.exists():
    zip_path.unlink()
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(PKG.rglob("*")):
        if f.is_file():
            z.write(f, f.relative_to(OUT_DIR))
size_mb = zip_path.stat().st_size / 1048576
print(f"wrote {PKG}\nwrote {zip_path} ({size_mb:.1f} MB)")
if size_mb >= 20:
    sys.exit("ZIP is 20 MB or larger -- too big for the LMS upload limit")
