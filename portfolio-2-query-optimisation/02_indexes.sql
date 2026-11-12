-- portfolio-2-query-optimisation/02_indexes.sql
-- Indexes to optimise the queries in 01_queries.sql.
--
-- Strategy:
--   * foreign-key columns used in joins (sale_line.sale_id, sale_line.product_id,
--     outlet_stock.outlet_id, outlet_stock.product_id, batch_usage.run_id,
--     batch_usage.batch_id) get B-tree indexes so joins stop seq-scanning.
--   * the WHERE filters that show up in every report (outlet_stock.stock_date,
--     ingredient_batch.expiry_date, sale.sale_time, sale.outlet_id, sale.channel)
--     get B-tree indexes.
--   * Q2 (best sellers per outlet per month) needs a covering index on
--     sale_line(sale_id, product_id) INCLUDE (quantity, unit_price) — partial
--     covering; the join still has to fetch sale_time from sale, but the sale_id
--     side is index-only.
--
-- Run this AFTER taking the "before" EXPLAIN measurements, then re-take the
-- "after" measurements.

\set ON_ERROR_STOP on

-- ----- outlet_stock: the per-outlet per-product per-day lookup ------------
CREATE INDEX IF NOT EXISTS ix_outlet_stock_date
    ON outlet_stock (stock_date);

CREATE INDEX IF NOT EXISTS ix_outlet_stock_outlet_product_date
    ON outlet_stock (outlet_id, product_id, stock_date);

-- ----- ingredient_batch: expiry-window lookup -----------------------------
CREATE INDEX IF NOT EXISTS ix_ingredient_batch_expiry
    ON ingredient_batch (expiry_date)
    WHERE quantity_left > 0;

-- ----- sale: filter by outlet, by date range, by channel ------------------
CREATE INDEX IF NOT EXISTS ix_sale_outlet_time
    ON sale (outlet_id, sale_time);

CREATE INDEX IF NOT EXISTS ix_sale_time
    ON sale (sale_time);

CREATE INDEX IF NOT EXISTS ix_sale_channel
    ON sale (channel);

-- ----- sale_line: join both ways, plus the covering index for Q2 ---------
CREATE INDEX IF NOT EXISTS ix_sale_line_sale
    ON sale_line (sale_id);

CREATE INDEX IF NOT EXISTS ix_sale_line_product
    ON sale_line (product_id);

CREATE INDEX IF NOT EXISTS ix_sale_line_sale_product_cover
    ON sale_line (sale_id, product_id) INCLUDE (quantity, unit_price);

-- ----- batch_usage: FK columns --------------------------------------------
CREATE INDEX IF NOT EXISTS ix_batch_usage_run
    ON batch_usage (run_id);

CREATE INDEX IF NOT EXISTS ix_batch_usage_batch
    ON batch_usage (batch_id);

-- ----- production_run: filter by date, by product -------------------------
CREATE INDEX IF NOT EXISTS ix_production_run_date
    ON production_run (run_date);

CREATE INDEX IF NOT EXISTS ix_production_run_product
    ON production_run (product_id);

-- ----- recipe_line: lookup by product -------------------------------------
CREATE INDEX IF NOT EXISTS ix_recipe_line_product
    ON recipe_line (product_id);

-- ----- ingredient_batch: FIFO consume lookup ------------------------------
-- The FIFO function orders by (ingredient_id, expiry_date, received_date, batch_id)
-- and filters by quantity_left > 0 and expiry_date >= run_date.
CREATE INDEX IF NOT EXISTS ix_ingredient_batch_fifo
    ON ingredient_batch (ingredient_id, expiry_date, received_date, batch_id)
    WHERE quantity_left > 0;

-- ----- ANALYZE so the planner sees the new indexes ------------------------
ANALYZE outlet_stock;
ANALYZE ingredient_batch;
ANALYZE sale;
ANALYZE sale_line;
ANALYZE batch_usage;
ANALYZE production_run;
ANALYZE recipe_line;

\echo 'Indexes created. Listing indexes on the main tables:'
SELECT tablename, indexname, indexdef
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND tablename IN ('outlet_stock','ingredient_batch','sale','sale_line',
                     'batch_usage','production_run','recipe_line')
 ORDER BY tablename, indexname;
