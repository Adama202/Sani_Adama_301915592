# Portfolio 1 — Database Design and Modelling

**Case study:** Crumble Studio — Abuja bakery and café (central kitchen + 3 outlets:
Jabi, Wuse 2, Gwarinpa). See top-level `README.md`.

**Maps to course-note Study Session 1** (Review of Traditional Relational Databases
and Advanced Concepts): ER design, relational schema, normalisation, constraints.

## Files in this folder

| File | What it does |
|------|--------------|
| `01_schema.sql` | 10 main tables + `supplier` helper. All PK / FK / CHECK / UNIQUE. |
| `02_constraints_triggers.sql` | Triggers: expired-batch guard, FIFO consume function, after-insert trigger on `production_run`, defensive no-negative trigger on `outlet_stock`, `add_baked_stock()` helper. |
| `03_seed.sql` | 3 outlets, 5 suppliers, 16 ingredients, 10 products, ~50 recipe lines, one round of fresh ingredient batches. |
| `04_bulk_generate.sql` | Weekly ingredient-batch deliveries + ~2,400 production runs + ~30,000 sales / ~60,000 sale lines over the last 240 days. Stock never negative. Busier mornings, weekends, December, Ramadan evenings, Nigerian customer names, ₦ prices. |
| `05_constraint_tests.sql` | 10 tests that MUST FAIL (each creates its own data); reports PASSED/FAILED. |
| `er_diagram.md` | Mermaid ER diagram (renders on GitHub) + 3NF notes + constraints table. |
| `run_p1.sh` | Runs everything in order. |

## Commands (Codespaces)

```bash
bash setup.sh                                  # one-time: install Postgres 16 + Mongo 8
bash portfolio-1-database-design/run_p1.sh
```

Connect to inspect the data:

```bash
psql -d crumble
```

## What to screenshot for evidence

1. The `run_p1.sh` final block: row counts for `production_run`, `batch_usage`,
   `outlet_stock`, `sale`, `sale_line` (proves ≥5k runs and ≥50k sale lines).
2. The two "Stock never negative?" check rows from `04_bulk_generate.sql` (both must
   show `0`).
3. The full PASSED/FAILED table from `05_constraint_tests.sql` (all 10 must be
   `PASSED`).
4. The Mermaid ER diagram rendering on GitHub.

## Suggested git commit

```bash
git add portfolio-1-database-design
git commit -m "P1: schema, constraints, FIFO consume, seed, 240-day bulk data, 10 constraint tests"
```

## What this demonstrates

A 10-table relational schema in 3NF for a realistic Nigerian bakery; advanced
constraints beyond plain PK/FK — CHECK-based non-negative stock, UNIQUE per
outlet/product/day, a trigger that refuses expired ingredient batches, and a FIFO
PL/pgSQL function that consumes exactly recipe × units from the oldest unexpired
batches first. Bulk generator produces 240 days of consistent data with realistic
Nigerian demand patterns and never violates the constraints. The constraint-test
suite proves every rule actively rejects bad data.
