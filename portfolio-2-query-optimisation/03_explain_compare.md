> **Note:** `run_p2.sh` now runs EXPLAIN ANALYZE for all 8 queries before and after the indexes and saves the real plans in `explain_before.txt`, `explain_after.txt` and `explain_summary.txt`. Use those files instead of the placeholders below.

# Portfolio 2 — EXPLAIN ANALYZE: before vs after indexing

**Honesty rule:** the table below is a *template*. The actual EXPLAIN output and
timings must be pasted in by the student after running the queries live. Never
invent numbers.

## How to take the measurements

Run these in `psql -d crumble` *before* applying `02_indexes.sql`:

```sql
\pset pager off
\echo 'Q1 BEFORE'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT o.name, p.name, os.quantity_left
  FROM outlet_stock os
  JOIN outlet o ON o.outlet_id = os.outlet_id
  JOIN product p ON p.product_id = os.product_id
 WHERE os.stock_date = CURRENT_DATE
 ORDER BY o.name, os.quantity_left DESC, p.name;

\echo 'Q3 BEFORE'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT i.name, b.batch_id, b.expiry_date, b.quantity_left, s.name
  FROM ingredient_batch b
  JOIN ingredient i ON i.ingredient_id = b.ingredient_id
  LEFT JOIN supplier s ON s.supplier_id = b.supplier_id
 WHERE b.quantity_left > 0
   AND b.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '3 days'
 ORDER BY b.expiry_date, i.name;

\echo 'Q6 BEFORE'
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT EXTRACT(HOUR FROM s.sale_time)::int AS hour_of_day,
       COUNT(*) AS n_sales, SUM(sl.quantity) AS units_sold
  FROM sale s JOIN sale_line sl ON sl.sale_id = s.sale_id
 GROUP BY hour_of_day ORDER BY hour_of_day;
```

Then apply the indexes:

```sql
\i portfolio-2-query-optimisation/02_indexes.sql
```

Then run the *same* `EXPLAIN (ANALYZE, BUFFERS)` blocks again to capture the
"AFTER" plan.

## Before / after table

> Replace each `[paste real output here]` cell with the actual EXPLAIN output
> (or a screenshot). Do **not** invent numbers.

| Query | Plan / metric | BEFORE indexes | AFTER indexes | Notes |
|-------|---------------|----------------|---------------|-------|
| **Q1** items left at each outlet today | Seq Scan on `outlet_stock`? Index Scan? | [paste real output here] | [paste real output here] | Should switch from `Seq Scan` to `Index Scan` using `ix_outlet_stock_date` once the index exists. |
| **Q1** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q2** best sellers per outlet per month | Plan shape | [paste real output here] | [paste real output here] | The `ix_sale_line_sale_product_cover` covering index should turn the `sale_line` probe into an index-only scan. |
| **Q2** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q3** ingredients expiring in next 3 days | Plan shape | [paste real output here] | [paste real output here] | The partial index `ix_ingredient_batch_expiry` (WHERE `quantity_left > 0`) should make this an index-only scan over a small slice. |
| **Q3** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q4** waste per product | Plan shape | [paste real output here] | [paste real output here] | Joins on `outlet_stock(outlet_id, product_id, stock_date)` and `sale_line(sale_id)` should both be index probes. |
| **Q4** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q5** ingredient cost per product | Plan shape | [paste real output here] | [paste real output here] | Small tables (`product`, `recipe_line`, `ingredient`); planner usually picks a hash join either way. |
| **Q5** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q6** sales per hour of day | Plan shape | [paste real output here] | [paste real output here] | The big table is `sale_line`. The covering index `ix_sale_line_sale_product_cover` allows an index-only scan of `sale_line`, but the join to `sale` for `sale_time` still scans `sale`. |
| **Q6** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q7** revenue per outlet per month | Plan shape | [paste real output here] | [paste real output here] | Index on `sale(outlet_id, sale_time)` helps the GROUP BY. |
| **Q7** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |
| **Q8** top product per channel | Plan shape | [paste real output here] | [paste real output here] | Index on `sale(channel)` lets the planner hash-partition early. |
| **Q8** execution time | `Execution Time: …` | [paste real output here] ms | [paste real output here] ms | |

## Performance analysis (3–5 lines, written AFTER the real measurements)

> Fill this in after running the EXPLAIN blocks. Talk about: which Seq Scans
> turned into Index Scans / Index-Only Scans, which joins changed from
> `Hash Join` to `Nested Loop` (or vice-versa), and roughly how many times
> faster each query got. Mention any query that did *not* get faster and why
> (e.g. Q5 on tiny `product` table — index won't help).

[Student fills this in after running the real EXPLAINs]
