#!/usr/bin/env python3
"""Build REPORT.html (and REPORT.pdf, if Chrome/Edge is available) from the
per-problem READMEs, so the report and the READMEs can never disagree.

Usage: python build_report.py            (run from the repository root)
Team details are read from TEAM.md (plain Markdown, shown on the cover).
"""
import base64
import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

import mistune

ROOT = Path(__file__).resolve().parent
SECTIONS = [
    ("problem1_tpch/README.md", "problem1_tpch"),
    ("problem2_integration/README.md", "problem2_integration"),
    ("problem3_unix_pipeline/README.md", "problem3_unix_pipeline"),
    ("COMPLIANCE.md", "."),
]
md = mistune.create_markdown(plugins=["table", "strikethrough"], escape=False)


def embed_images(body_html, base):
    """Inline local images as data: URIs so the HTML/PDF is self-contained."""
    def repl(m):
        src = m.group(1)
        path = (ROOT / base / src).resolve()
        if src.startswith(("http:", "https:", "data:")) or not path.exists():
            return m.group(0)
        data = base64.b64encode(path.read_bytes()).decode()
        return f'src="data:image/png;base64,{data}"'
    return re.sub(r'src="([^"]+)"', repl, body_html)


parts, toc = [], []
for i, (rel, base) in enumerate(SECTIONS, start=1):
    path = ROOT / rel
    if not path.exists():
        sys.exit(f"missing {rel}")
    text = path.read_text(encoding="utf-8")
    title = re.search(r"^# (.+)$", text, flags=re.M).group(1)
    toc.append(f'<li><a href="#s{i}">{html.escape(title)}</a></li>')
    body = embed_images(md(text), base)
    body = body.replace("<h1>", f'<h1 id="s{i}">', 1)
    parts.append(f'<section class="chapter">{body}</section>')

team = md((ROOT / "TEAM.md").read_text(encoding="utf-8")) if (ROOT / "TEAM.md").exists() else ""

page = f"""<!doctype html><html><head><meta charset="utf-8">
<title>NoSQL Systems DAS 838 — Assignment 1 Report</title>
<style>
@page {{ size: A4; margin: 16mm 14mm; }}
body {{ font-family: "Segoe UI", Calibri, Arial, sans-serif; font-size: 10.5pt; line-height: 1.45; color: #1d1d1f; }}
h1 {{ font-size: 20pt; border-bottom: 3px solid #2b5797; padding-bottom: 4px; color: #1f3f6e; }}
h2 {{ font-size: 14pt; color: #2b5797; margin-top: 1.4em; border-bottom: 1px solid #d0d7e2; }}
h3 {{ font-size: 11.5pt; color: #333; }}
table {{ border-collapse: collapse; margin: 0.6em 0; font-size: 9pt; page-break-inside: auto; }}
th, td {{ border: 1px solid #c8ced8; padding: 3px 6px; vertical-align: top; }}
th {{ background: #eaf0f8; }}
tr {{ page-break-inside: avoid; }}
code {{ font-family: Consolas, "Courier New", monospace; font-size: 9pt; background: #f3f4f6; padding: 0 2px; }}
pre {{ background: #f6f8fa; border: 1px solid #e1e4e8; padding: 6px 8px; font-size: 8.5pt; white-space: pre-wrap; page-break-inside: avoid; }}
pre code {{ background: none; padding: 0; }}
img {{ max-width: 100%; page-break-inside: avoid; }}
.chapter {{ page-break-before: always; }}
.cover {{ text-align: center; padding-top: 50mm; }}
.cover h1 {{ border: none; font-size: 26pt; }}
.cover .sub {{ font-size: 14pt; color: #444; }}
.cover .team {{ margin: 18mm auto 0; display: inline-block; text-align: left; }}
.toc {{ margin-top: 14mm; text-align: left; display: inline-block; }}
</style></head><body>
<div class="cover">
<h1>NoSQL Systems — DAS 838</h1>
<div class="sub">Assignment 1: Data Scaling, Data Integration and Unix Data Processing</div>
<div class="sub">Instructor: Vinu E. Venugopal</div>
<div class="team">{team}</div><br>
<div class="toc"><b>Contents</b><ol>{''.join(toc)}</ol></div>
</div>
{''.join(parts)}
</body></html>"""

out_html = ROOT / "REPORT.html"
out_html.write_text(page, encoding="utf-8")
print(f"wrote {out_html}")

browsers = [shutil.which(b) for b in ("chrome", "msedge", "google-chrome", "chromium")]
browsers += [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
             r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]
browser = next((b for b in browsers if b and Path(b).exists()), None)
if browser:
    out_pdf = ROOT / "REPORT.pdf"
    subprocess.run([browser, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    f"--print-to-pdf={out_pdf}", out_html.as_uri()], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=180)
    print(f"wrote {out_pdf}")
else:
    print("no Chrome/Edge found: open REPORT.html in a browser and print to PDF")
