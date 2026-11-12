#!/usr/bin/env bash
# run_p5.sh — run all of Portfolio 5 (Distributed and Cloud Database Exercise).
#
# This script:
#   1. Runs the partition demo (01_partition.sql) on the primary.
#   2. Sets up the streaming replica (02_replica_setup.sh).
#   3. Runs the replica demo (03_replica_demo.sql) that switches servers with \connect.
#   4. Reminds the student to read 04_cloud_architecture.md.
#
# Codespaces rules:
#   * `sudo -u postgres` does NOT work; we use `sudo runuser -u postgres -- ...`
#   * All psql connections go through the Unix socket (/var/run/postgresql).
#   * We do NOT use postgres_fdw.
set -euo pipefail

DB=crumble
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/4] Verifying P1 data exists"
rows=$(psql -d "${DB}" -tAc "SELECT count(*) FROM sale_line")
if [ -z "${rows}" ] || [ "${rows}" -lt 1000 ]; then
    echo "ERROR: ${DB}.sale_line is empty. Run P1 first."
    exit 1
fi
echo "    sale_line has ${rows} rows — good."

echo "==> [2/4] Partition sale_line by month (01_partition.sql)"
psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/01_partition.sql"

echo "==> [3/4] Set up the streaming read replica (02_replica_setup.sh)"
bash "${HERE}/02_replica_setup.sh"

echo "==> [4/4] Run the replica demo (03_replica_demo.sql) — switches servers with \\connect"
psql -h /var/run/postgresql -p 5432 -d "${DB}" -v ON_ERROR_STOP=0 -f "${HERE}/03_replica_demo.sql" 2>&1 | tee "${HERE}/replication_output.log"

echo
echo "=================================================="
echo "Portfolio 5 (scripted part) complete."
echo
echo "Read the cloud architecture note:"
echo "  ${HERE}/04_cloud_architecture.md"
echo "  (NDPA 2023, CAP trade-offs, sync vs async, offline outlets)"
echo
echo "Suggested git commit:"
echo "  git add portfolio-5-distributed-cloud && git commit -m 'P5: sale_line partitioning + primary/replica + NDPA cloud architecture'"
echo "=================================================="
