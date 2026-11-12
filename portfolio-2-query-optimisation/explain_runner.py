#!/usr/bin/env python3
"""Runs the 8 queries in 01_queries.sql with EXPLAIN ANALYZE BEFORE and AFTER the
P2 indexes and writes explain_before.txt, explain_after.txt, explain_summary.txt.
All numbers come from this machine's real runs."""
import re, subprocess, sys, pathlib
here = pathlib.Path(__file__).parent
DB = "crumble"
def psql(sql):
    r = subprocess.run(["psql", "-d", DB, "-X", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                       capture_output=True, text=True)
    if r.returncode: sys.exit("psql error: " + r.stderr)
    return r.stdout
src = (here / "01_queries.sql").read_text()
blocks = re.findall(r"\\echo '===== (Q\d+)\.[^\n]*\n(.*?);\n", src, re.S)
idx = re.findall(r"CREATE INDEX IF NOT EXISTS (\w+)", (here / "02_indexes.sql").read_text())
def phase(name):
    out, res = [], {}
    for q, sql in blocks:
        psql("EXPLAIN (ANALYZE, COSTS OFF) " + sql)            # warm-up run
        plan = psql("EXPLAIN (ANALYZE, COSTS OFF) " + sql)     # measured run
        ms = float(re.search(r"Execution Time: ([\d.]+) ms", plan).group(1))
        scans = sorted(set(re.findall(r"(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan)(?: Backward)? (?:using \w+ )?on (\w+)", plan)))
        res[q] = (ms, ", ".join(f"{t} {n}" for t, n in scans))
        out.append(f"===== {q} ({name}) =====\n{plan}")
    (here / f"explain_{name}.txt").write_text("\n".join(out))
    return res
for i in idx: psql(f"DROP INDEX IF EXISTS {i}")
psql("ANALYZE")
before = phase("before")
for sql in re.findall(r"(CREATE INDEX.*?;)", (here / "02_indexes.sql").read_text(), re.S): psql(sql)
psql("ANALYZE")
after = phase("after")
lines = ["P2 EXPLAIN ANALYZE summary (real run on this machine)", "",
         f"{'Query':<5} {'Before ms':>10} {'After ms':>10}  How tables were read AFTER indexes"]
for q, _ in blocks:
    lines.append(f"{q:<5} {before[q][0]:>10.1f} {after[q][0]:>10.1f}  {after[q][1]}")
lines += ["", "Note: where After is not faster, the planner kept a Seq Scan on purpose (full-history",
          "aggregates read most of the table) or the difference is run-to-run noise."]
(here / "explain_summary.txt").write_text("\n".join(lines) + "\n")
print("\n".join(lines))
