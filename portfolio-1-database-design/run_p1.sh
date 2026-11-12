#!/usr/bin/env bash
# run_p1.sh — run all of Portfolio 1 (Crumble Studio database design).
#
# Codespaces notes:
#   * `sudo -u postgres` does not work; we use `sudo runuser -u postgres -- ...`
#   * psql connects through the Unix socket (/var/run/postgresql) — no password
set -euo pipefail

DB=crumble
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/6] (Re)creating database ${DB}"
sudo runuser -u postgres -- dropdb   --if-exists "${DB}"
sudo runuser -u postgres -- createdb "${DB}"
psql -d postgres -c "ALTER DATABASE ${DB} SET timezone TO 'Africa/Lagos'"

echo "==> [2/6] Loading schema (01_schema.sql)"
psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/01_schema.sql"

echo "==> [3/6] Loading constraints + triggers + FIFO (02_constraints_triggers.sql)"
psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/02_constraints_triggers.sql"

echo "==> [4/6] Loading seed data (03_seed.sql)"
psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/03_seed.sql"

echo "==> [5/6] Bulk-generating 240 days of data (04_bulk_generate.sql)"
psql -d "${DB}" -v ON_ERROR_STOP=1 -f "${HERE}/04_bulk_generate.sql"

echo "==> [6/6] Running constraint tests (05_constraint_tests.sql)"
psql -d "${DB}" -v ON_ERROR_STOP=0 -f "${HERE}/05_constraint_tests.sql"

echo
echo "=================================================="
echo "Portfolio 1 complete."
echo "  ER diagram: ${HERE}/er_diagram.md (renders on GitHub)"
echo "  Suggested git commit:"
echo "    git add portfolio-1-database-design && git commit -m 'P1: schema, constraints, FIFO, seed, 240-day bulk data, tests'"
echo "=================================================="
