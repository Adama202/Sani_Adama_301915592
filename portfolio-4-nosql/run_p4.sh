#!/usr/bin/env bash
# run_p4.sh — run all of Portfolio 4 (NoSQL and Advanced Data Models).
#
# Mongosh convention: every .js file starts with `db = db.getSiblingDB("crumble")`.
# We never `use dbname;` in a script file (it does not survive past the line).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [1/6] Verifying MongoDB is running"
if ! mongosh --quiet --eval 'db.adminCommand({ping:1})' >/dev/null 2>&1; then
    echo "ERROR: mongod is not running. Run setup.sh first."
    exit 1
fi

echo "==> [2/6] Creating collections + validators (01_schema_validation.js)"
mongosh --quiet --file "${HERE}/01_schema_validation.js"

echo "==> [3/6] Seeding oven_logs (40k+ documents) — this takes ~30s (02_seed_oven_logs.js)"
mongosh --quiet --file "${HERE}/02_seed_oven_logs.js"

echo "==> [4/6] Seeding recipe_cards (03_seed_recipe_cards.js)"
mongosh --quiet --file "${HERE}/03_seed_recipe_cards.js"

echo "==> [5/6] Running aggregations (04_aggregations.js)"
mongosh --quiet --file "${HERE}/04_aggregations.js"

echo "==> [6/6] Index demo: COLLSCAN -> IXSCAN on 40k docs (05_indexes.js)"
mongosh --quiet --file "${HERE}/05_indexes.js"

echo "==> Validation tests: two bad documents must be rejected (06_validation_tests.js)"
mongosh --quiet --file "${HERE}/06_validation_tests.js"

echo
echo "=================================================="
echo "Portfolio 4 complete."
echo "  Final document counts:"
mongosh --quiet --eval 'db = db.getSiblingDB("crumble"); print("oven_logs    : " + db.oven_logs.estimatedDocumentCount()); print("recipe_cards : " + db.recipe_cards.countDocuments());'
echo
echo "  Suggested git commit:"
echo "    git add portfolio-4-nosql && git commit -m 'P4: MongoDB oven_logs + recipe_cards with oneOf validator + aggregations + index demo'"
echo "=================================================="
