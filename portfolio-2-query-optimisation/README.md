# Portfolio 2 — Query Processing and Optimisation

**Maps to course-note Study Session 4** (Query Optimisation in Database):
queries, query optimisation, query execution plans, cost estimation, file
organisation / indexing.

## Files in this folder

| File | What it does |
|------|--------------|
| `01_queries.sql` | 8 reporting queries: items left per outlet today, best sellers per outlet per month, ingredients expiring in 3 days, waste per product, ingredient cost per product, sales per hour, revenue per outlet per month, top product per channel. |
| `02_indexes.sql` | 13 indexes (B-tree, partial, covering) targeted at the queries above. |
| `03_explain_compare.md` | Before/after EXPLAIN ANALYZE template with `[paste real output here]` placeholders. |
| `run_p2.sh` | Runs the queries before, applies the indexes, runs the queries again. |

## Commands (Codespaces)

```bash
bash portfolio-1-database-design/run_p1.sh   # if not already done
bash portfolio-2-query-optimisation/run_p2.sh
```

To capture the EXPLAIN plans, follow the instructions in
`03_explain_compare.md` — run those `EXPLAIN (ANALYZE, BUFFERS)` blocks in
`psql -d crumble` once *before* `02_indexes.sql` and once *after*, then paste
the real output into the table.

## What to screenshot for evidence

1. The output of all 8 queries from `01_queries.sql` (showing real rows).
2. The `CREATE INDEX` list printed at the end of `02_indexes.sql`.
3. Two EXPLAIN plans per query — the BEFORE (with `Seq Scan`) and the AFTER
   (with `Index Scan` or `Index Only Scan`). Paste them into the table in
   `03_explain_compare.md`.

## Suggested git commit

```bash
git add portfolio-2-query-optimisation
git commit -m "P2: 8 reporting queries + 13 targeted indexes + EXPLAIN before/after template"
```

## What this demonstrates

The same 2-year dataset is queried in 8 different analytical shapes. For each
query we identify the dominant cost (a sequential scan on `sale_line` or
`outlet_stock`, an expiry-window filter on `ingredient_batch`, a covering join
on `sale × sale_line`). The `02_indexes.sql` file adds the minimum set of
B-tree, partial, and covering indexes that turn those Seq Scans into Index
Scans / Index-Only Scans, then `ANALYZE` is run so the planner actually uses
them. The before/after template forces an honest measurement: real EXPLAIN
output is pasted in by the student, never invented.
