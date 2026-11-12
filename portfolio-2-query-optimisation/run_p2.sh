#!/usr/bin/env bash
# run_p2.sh - Portfolio 2: 8 queries, EXPLAIN ANALYZE before/after indexes.
set -euo pipefail
DB=crumble
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rows=$(psql -d "${DB}" -tAc "SELECT count(*) FROM sale_line")
if [ "${rows}" -lt 50000 ]; then echo "ERROR: only ${rows} sale_line rows. Run P1 first."; exit 1; fi
echo "==> sale_line has ${rows} rows"
echo "==> Running EXPLAIN ANALYZE for Q1-Q8 BEFORE and AFTER indexes"
python3 "${HERE}/explain_runner.py" | tee "${HERE}/p2_summary.log"
echo "==> Query results (after indexes)"
psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/01_queries.sql" > "${HERE}/query_results.txt"
echo "Portfolio 2 complete. Evidence: explain_before.txt, explain_after.txt, explain_summary.txt"
