#!/usr/bin/env bash
# run_p3.sh - Portfolio 3: transactions + concurrency (all demos are scripted).
set -euo pipefail
DB=crumble
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rows=$(psql -d "${DB}" -tAc "SELECT count(*) FROM outlet_stock WHERE stock_date = CURRENT_DATE")
if [ "${rows}" -lt 10 ]; then echo "ERROR: no stock for today. Run P1 first."; exit 1; fi
python3 -c 'import psycopg2' 2>/dev/null || pip install --user psycopg2-binary 2>/dev/null || pip install --break-system-packages psycopg2-binary
echo "==> [1/4] sell_items()"; psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/01_sell_items.sql"
echo "==> [2/4] bake_run()";   psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/02_bake_run.sql"
echo "==> [3/4] rollback demo"; psql -d "${DB}" -v ON_ERROR_STOP=0 -f "${HERE}/03_rollback_demo.sql"
echo "==> [4/4] race condition, deadlock and isolation demos (two real sessions)"
python3 "${HERE}/run_race_demos.py" 2>&1 | tee "${HERE}/race_demos_output.log"
echo "Portfolio 3 complete. Evidence: race_demos_output.log"
