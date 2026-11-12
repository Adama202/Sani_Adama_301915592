-- portfolio-2-query-optimisation/01_queries.sql
-- 8 reporting queries for Crumble Studio.
-- Each query is wrapped in a labelled \echo block so the output is easy to
-- screenshot. Run BEFORE 02_indexes.sql for the "before" timings, then again
-- AFTER for the "after" timings.
--
-- Honesty rule: where real timings / EXPLAIN plans are needed, the file
-- 03_explain_compare.md has [paste real output here] placeholders. This file
-- only runs the queries and prints their results.

\pset pager off
\set ON_ERROR_STOP on

-- =========================================================
-- Q1. Items left at each outlet TODAY (current stock snapshot)
-- =========================================================
\echo '===== Q1. Items left at each outlet today ====='
SELECT o.name  AS outlet,
       p.name  AS product,
       os.quantity_left
  FROM outlet_stock os
  JOIN outlet  o ON o.outlet_id  = os.outlet_id
  JOIN product p ON p.product_id = os.product_id
 WHERE os.stock_date = CURRENT_DATE
 ORDER BY o.name, os.quantity_left DESC, p.name;

-- =========================================================
-- Q2. Best sellers per outlet per month
--     (top product by total quantity sold, per outlet, per month)
-- =========================================================
\echo '===== Q2. Best sellers per outlet per month ====='
WITH monthly AS (
    SELECT
        o.outlet_id,
        o.name AS outlet,
        TO_CHAR(s.sale_time, 'YYYY-MM') AS yyyymm,
        p.name AS product,
        SUM(sl.quantity) AS qty_sold
    FROM sale      s
    JOIN sale_line sl ON sl.sale_id      = s.sale_id
    JOIN product   p  ON p.product_id    = sl.product_id
    JOIN outlet    o  ON o.outlet_id     = s.outlet_id
    GROUP BY o.outlet_id, o.name, yyyymm, p.name
),
ranked AS (
    SELECT monthly.*,
           ROW_NUMBER() OVER (PARTITION BY outlet_id, yyyymm
                              ORDER BY qty_sold DESC) AS rn
      FROM monthly
)
SELECT outlet, yyyymm, product, qty_sold
  FROM ranked
 WHERE rn = 1
 ORDER BY yyyymm, outlet;

-- =========================================================
-- Q3. Ingredient batches expiring in the NEXT 3 DAYS
--     (still have stock left, expiry within 3 days)
-- =========================================================
\echo '===== Q3. Ingredients expiring in the next 3 days ====='
SELECT i.name        AS ingredient,
       b.batch_id,
       b.expiry_date,
       b.quantity_left AS qty_left,
       s.name         AS supplier
  FROM ingredient_batch b
  JOIN ingredient i ON i.ingredient_id = b.ingredient_id
  LEFT JOIN supplier s ON s.supplier_id = b.supplier_id
 WHERE b.quantity_left > 0
   AND b.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '3 days'
 ORDER BY b.expiry_date, i.name;

-- =========================================================
-- Q4. WASTE per product — baked but unsold, by outlet, by day
--     (units baked minus units sold, only where positive)
-- =========================================================
\echo '===== Q4. Waste per product (baked but unsold) ====='
WITH baked AS (
    -- total units baked for each outlet per day, distributed 50/30/20
    SELECT os.outlet_id, os.product_id, os.stock_date,
           os.quantity_left AS leftover_at_end_of_day
      FROM outlet_stock os
),
sold AS (
    SELECT s.outlet_id,
           sl.product_id,
           s.sale_time::date AS sale_date,
           SUM(sl.quantity) AS qty_sold
      FROM sale s
      JOIN sale_line sl ON sl.sale_id = s.sale_id
     GROUP BY s.outlet_id, sl.product_id, sale_date
)
SELECT o.name  AS outlet,
       p.name  AS product,
       b.stock_date,
       (b.leftover_at_end_of_day) AS waste_units
  FROM baked b
  JOIN outlet  o ON o.outlet_id  = b.outlet_id
  JOIN product p ON p.product_id = b.product_id
 WHERE b.leftover_at_end_of_day > 0
   AND b.stock_date < CURRENT_DATE
 ORDER BY b.stock_date DESC, o.name, waste_units DESC
 LIMIT 50;

-- =========================================================
-- Q5. Ingredient COST per product
--     (sum of recipe_line.quantity_per_unit * ingredient.unit_cost)
-- =========================================================
\echo '===== Q5. Ingredient cost per product ====='
SELECT p.name    AS product,
       p.unit_price AS selling_price_ngn,
       ROUND(SUM(rl.quantity_per_unit * i.unit_cost)::numeric, 2) AS ingredient_cost_ngn,
       ROUND(p.unit_price - SUM(rl.quantity_per_unit * i.unit_cost)::numeric, 2) AS gross_margin_ngn,
       ROUND(
           (p.unit_price - SUM(rl.quantity_per_unit * i.unit_cost)::numeric)
           / NULLIF(p.unit_price,0) * 100, 1) AS gross_margin_pct
  FROM product p
  JOIN recipe_line rl ON rl.product_id   = p.product_id
  JOIN ingredient  i  ON i.ingredient_id = rl.ingredient_id
 GROUP BY p.product_id, p.name, p.unit_price
 ORDER BY gross_margin_pct DESC;

-- =========================================================
-- Q6. SALES PER HOUR OF DAY
--     (across all outlets, all history; counter vs online split)
-- =========================================================
\echo '===== Q6. Sales per hour of day ====='
SELECT EXTRACT(HOUR FROM s.sale_time)::int AS hour_of_day,
       COUNT(*)                            AS n_sales,
       SUM(sl.quantity)                    AS units_sold,
       ROUND(SUM(sl.quantity * sl.unit_price)::numeric, 2) AS revenue_ngn,
       COUNT(*) FILTER (WHERE s.channel = 'counter') AS counter_sales,
       COUNT(*) FILTER (WHERE s.channel = 'online')  AS online_sales
  FROM sale s
  JOIN sale_line sl ON sl.sale_id = s.sale_id
 GROUP BY hour_of_day
 ORDER BY hour_of_day;

-- =========================================================
-- Q7. (extra) Revenue per outlet per month (last 90 days)
-- =========================================================
\echo '===== Q7. Revenue per outlet per month ====='
SELECT o.name AS outlet,
       TO_CHAR(s.sale_time, 'YYYY-MM') AS yyyymm,
       COUNT(*) AS n_sales,
       ROUND(SUM(s.total_amount)::numeric, 2) AS revenue_ngn
  FROM sale s
  JOIN outlet o ON o.outlet_id = s.outlet_id
 WHERE s.sale_time >= CURRENT_DATE - 90
 GROUP BY o.name, yyyymm
 ORDER BY yyyymm, o.name;

-- =========================================================
-- Q8. (extra) Top product per channel
-- =========================================================
\echo '===== Q8. Top product per channel ====='
WITH per_channel AS (
    SELECT s.channel,
           p.name AS product,
           SUM(sl.quantity) AS qty_sold,
           SUM(sl.quantity * sl.unit_price) AS revenue
      FROM sale s
      JOIN sale_line sl ON sl.sale_id = s.sale_id
      JOIN product p    ON p.product_id = sl.product_id
     GROUP BY s.channel, p.name
),
ranked AS (
    SELECT per_channel.*,
           ROW_NUMBER() OVER (PARTITION BY channel ORDER BY qty_sold DESC) AS rn
      FROM per_channel
)
SELECT channel, product, qty_sold,
       ROUND(revenue::numeric, 2) AS revenue_ngn
  FROM ranked
 WHERE rn = 1
 ORDER BY channel;
