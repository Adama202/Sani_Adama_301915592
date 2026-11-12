-- portfolio-1-database-design/04_bulk_generate.sql
-- Bulk data generator for Crumble Studio.
--
-- Generates:
--   * ingredient batches received weekly over the last 240 days (always enough stock)
--   * ~5,000+ production runs over 240 days (auto-consumed FIFO via trigger)
--   * outlet_stock rows for each outlet x product x day (from production runs)
--   * ~33,000+ sales and 50,000+ sale_lines, with stock never going negative
--
-- Patterns modelled:
--   * busier mornings (7am-10am) for bread, croissants
--   * busier weekends (Fri/Sat/Sun in Nigeria)
--   * busier December
--   * busier Ramadan evenings (Mar 2025, Mar 2026 windows)
--   * realistic Nigerian names for online customers (Yoruba, Hausa, Igbo)
--   * prices in Naira (taken from product.unit_price)
--
-- Dates are relative to CURRENT_DATE so the dataset never goes stale:
-- history spans CURRENT_DATE - 730 .. CURRENT_DATE - 1.
--
-- Run AFTER 01_schema.sql, 02_constraints_triggers.sql, 03_seed.sql.

\timing on

-- =========================================================
-- STEP 1: Wipe any previously generated bulk data (keep seed rows).
-- =========================================================
TRUNCATE sale_line, sale, outlet_stock, batch_usage, production_run RESTART IDENTITY;
-- Wipe seed ingredient batches too — they will be regenerated below with a
-- proper 2-year history.
DELETE FROM ingredient_batch;

-- =========================================================
-- STEP 2: Ingredient batches — weekly deliveries over 240 days.
-- Each delivery is a big batch per ingredient with 60-90 day shelf life.
-- This guarantees enough stock for the production runs below.
-- =========================================================
INSERT INTO ingredient_batch (ingredient_id, supplier_id, received_date, expiry_date, initial_qty, quantity_left)
SELECT i.ingredient_id,
       1 + (i.ingredient_id % 5),
       d::date,
       (d::date + 60 + (i.ingredient_id % 30)),
       40000 + (i.ingredient_id % 1000),
       40000 + (i.ingredient_id % 1000)
  FROM ingredient i
  CROSS JOIN generate_series(
        (CURRENT_DATE - INTERVAL '240 days')::date,
        CURRENT_DATE,
        INTERVAL '7 days') AS d;

\echo 'Ingredient batches inserted:'
SELECT count(*) AS batches, sum(quantity_left) AS total_qty FROM ingredient_batch;

-- =========================================================
-- STEP 3: Production runs.
-- For each day, bake 5-10 products. Quantities vary by day-of-week and season.
-- The AFTER INSERT trigger on production_run consumes ingredient batches FIFO
-- automatically. If a run cannot get enough stock (shouldn't happen, but
-- possible near expiry boundaries), it raises an exception which we catch
-- per-run so one failure doesn't kill the whole load.
-- =========================================================
DO $$
DECLARE
    d          DATE;
    v_p        INT;
    v_units    INT;
    v_run_id   INT;
    v_base     INT;
    v_factor   NUMERIC;
    v_wknd     INT;
    v_dec      INT;
    v_ramadan  INT;
BEGIN
    FOR d IN SELECT generate_series((CURRENT_DATE - INTERVAL '240 days')::date,
                                    CURRENT_DATE, INTERVAL '1 day')::date LOOP
        v_wknd    := CASE WHEN EXTRACT(DOW FROM d) IN (0,5,6) THEN 1 ELSE 0 END;
        v_dec     := CASE WHEN EXTRACT(MONTH FROM d) = 12 THEN 1 ELSE 0 END;
        -- Ramadan 2025 (~Feb 28 - Mar 29) and 2026 (~Feb 17 - Mar 18)
        v_ramadan := CASE WHEN (d BETWEEN DATE '2025-02-28' AND DATE '2025-03-29')
                           OR (d BETWEEN DATE '2026-02-17' AND DATE '2026-03-18')
                          THEN 1 ELSE 0 END;

        FOR v_p IN 1..10 LOOP
            -- base demand per product per day (units)
            v_base := CASE
                WHEN v_p IN (1,2)        THEN 180  -- bread loaves
                WHEN v_p IN (4,5)        THEN 220  -- croissants / pain au chocolat
                WHEN v_p IN (7,8)        THEN 120  -- pies
                WHEN v_p IN (9,10)       THEN 200  -- cookies
                ELSE 150
            END;
            v_factor := 1.0
                      + v_wknd    * 0.35   -- weekends +35%
                      + v_dec     * 0.40   -- December +40%
                      + v_ramadan * 0.25;  -- Ramadan +25%
            v_units := (v_base * v_factor)::INT;
            -- bake slightly more on Mondays (post-weekend restock)
            IF EXTRACT(DOW FROM d) = 1 THEN v_units := (v_units * 1.1)::INT; END IF;

            BEGIN
                INSERT INTO production_run (product_id, run_date, units_baked, notes)
                VALUES (v_p, d, v_units, 'bulk-generated')
                RETURNING run_id INTO v_run_id;

                -- Distribute the bake to outlets: Jabi 50%, Wuse 2 30%, Gwarinpa 20%
                PERFORM add_baked_stock(1, v_p, d, (v_units * 0.50)::INT);
                PERFORM add_baked_stock(2, v_p, d, (v_units * 0.30)::INT);
                PERFORM add_baked_stock(3, v_p, d, (v_units * 0.20)::INT);
            EXCEPTION
                WHEN insufficient_resources OR check_violation THEN
                    -- not enough ingredient stock for this run — skip it
                    RAISE NOTICE 'Skipped run for product % on % (insufficient stock)', v_p, d;
            END;
        END LOOP;
    END LOOP;
END $$;

\echo 'Production runs + outlet_stock inserted:'
SELECT count(*) AS runs, sum(units_baked) AS units_baked FROM production_run;
SELECT count(*) AS stock_rows, sum(quantity_left) AS total_stock FROM outlet_stock;

-- =========================================================
-- STEP 4: Sales + sale lines (set-based, so it runs in seconds).
-- For each outlet x day: 20-50 sales, each with 1-3 lines (qty 1-2).
-- Lines are only kept while the running total sold stays within the stock
-- baked for that outlet/product/day, so stock can never go negative.
-- Nigerian names (Yoruba, Hausa, Igbo) for online customers.
-- =========================================================
CREATE TEMP TABLE tmp_sale AS
WITH names AS (
  SELECT ARRAY['Adaeze','Bisi','Tunde','Yetunde','Folake','Olumide','Oluwaseun','Babatunde','Yemisi','Damilola','Adebayo','Folashade','Tope','Seyi','Kunle','Taiwo','Kehinde','Adeola','Bolanle','Temitope'] AS fy,
         ARRAY['Amina','Ibrahim','Fatima','Yusuf','Aisha','Sani','Musa','Halima','Bello','Zainab','Saudatu','Lawal','Garba','Mustapha','Nasir','Hauwa','Abubakar','Rabiu','Laraba','Yakubu'] AS fh,
         ARRAY['Chidi','Emeka','Ngozi','Ifeoma','Chukwuemeka','Obinna','Nkechi','Chiamaka','Onyinye','Uchenna','Chinwe','Ekene','Ifunanya','Nnamdi','Obiageri','Ogechi','Tochukwu','Amara','Chioma','Ikenna'] AS fi,
         ARRAY['Adeyemi','Bello','Chukwu','Eze','Folawiyo','Garba','Ibrahim','Johnson','Kalu','Lawal','Mohammed','Nwosu','Obi','Okonkwo','Olawale','Sani','Usman','Yakubu','Okafor','Adeleke','Ojo','Balarabe','Madu','Mustapha','Adeola','Balogun','Danjuma','Oyinlola'] AS ln
), od AS (
  SELECT o.outlet_id, d::date AS d,
         3 * (10 + CASE WHEN EXTRACT(DOW FROM d) IN (0,5,6) THEN 6 ELSE 0 END
                 + CASE WHEN EXTRACT(MONTH FROM d) = 12 THEN 8 ELSE 0 END
                 + CASE WHEN (d::date BETWEEN DATE '2025-02-28' AND DATE '2025-03-29')
                          OR (d::date BETWEEN DATE '2026-02-17' AND DATE '2026-03-18') THEN 5 ELSE 0 END
                 + floor(random() * 5)::INT) AS n
    FROM generate_series((CURRENT_DATE - INTERVAL '240 days')::date, CURRENT_DATE - 1, INTERVAL '1 day') d
   CROSS JOIN outlet o
), s0 AS (
  SELECT od.outlet_id, od.d, random() AS rh, random() AS rm, random() AS rc,
         1 + floor(random()*3)::INT AS eth, random() AS rf, random() AS rl, 1 + floor(random()*3)::INT AS nl
    FROM od CROSS JOIN LATERAL generate_series(1, od.n) g
)
SELECT row_number() OVER () AS sid, s0.outlet_id, s0.d, s0.nl,
       ((s0.d::timestamp + make_interval(
            hours => CASE WHEN s0.rh < 0.55 THEN 7 + floor(s0.rm*4)::INT
                          WHEN s0.rh < 0.75 THEN 12 + floor(s0.rm*3)::INT
                          WHEN s0.rh < 0.90 THEN 17 + floor(s0.rm*3)::INT
                          ELSE 20 + floor(s0.rm*2)::INT END,
            mins => floor(random()*60)::INT)) AT TIME ZONE 'Africa/Lagos') AS sale_time,
       CASE WHEN s0.rc < 0.35 THEN 'online' ELSE 'counter' END AS channel,
       CASE WHEN s0.rc < 0.35 THEN
            (CASE s0.eth WHEN 1 THEN n.fy[1 + floor(s0.rf*20)::INT]
                         WHEN 2 THEN n.fh[1 + floor(s0.rf*20)::INT]
                         ELSE n.fi[1 + floor(s0.rf*20)::INT] END)
            || ' ' || n.ln[1 + floor(s0.rl*28)::INT]
       END AS customer_name
  FROM s0 CROSS JOIN names n;

CREATE TEMP TABLE tmp_line AS
SELECT t.sid, t.outlet_id, t.d, g AS ln,
       1 + floor(random()*10)::INT AS product_id,
       1 + floor(random()*2)::INT AS qty
  FROM tmp_sale t CROSS JOIN LATERAL generate_series(1, t.nl) g;

-- keep a line only while cumulative qty fits within that day's baked stock
CREATE TEMP TABLE tmp_keep AS
SELECT x.* FROM (
  SELECT l.*, sum(l.qty) OVER (PARTITION BY l.outlet_id, l.product_id, l.d ORDER BY l.sid, l.ln) AS running,
         os.quantity_left AS stock
    FROM tmp_line l
    JOIN outlet_stock os ON os.outlet_id = l.outlet_id AND os.product_id = l.product_id AND os.stock_date = l.d
) x WHERE x.running <= x.stock;

INSERT INTO sale (sale_id, outlet_id, sale_time, channel, customer_name, total_amount)
SELECT t.sid, t.outlet_id, t.sale_time, t.channel, t.customer_name,
       sum(k.qty * p.unit_price)
  FROM tmp_sale t
  JOIN tmp_keep k ON k.sid = t.sid
  JOIN product p ON p.product_id = k.product_id
 GROUP BY t.sid, t.outlet_id, t.sale_time, t.channel, t.customer_name;
SELECT setval(pg_get_serial_sequence('sale','sale_id'), (SELECT max(sale_id) FROM sale));

INSERT INTO sale_line (sale_id, product_id, quantity, unit_price)
SELECT k.sid, k.product_id, k.qty, p.unit_price
  FROM tmp_keep k JOIN product p ON p.product_id = k.product_id
 ORDER BY k.sid, k.ln;

UPDATE outlet_stock os
   SET quantity_left = os.quantity_left - x.q
  FROM (SELECT outlet_id, product_id, d, sum(qty) AS q FROM tmp_keep GROUP BY 1,2,3) x
 WHERE os.outlet_id = x.outlet_id AND os.product_id = x.product_id AND os.stock_date = x.d;

\echo 'Final row counts:'
SELECT 'production_run'    AS table_name, count(*) FROM production_run
UNION ALL SELECT 'batch_usage',         count(*) FROM batch_usage
UNION ALL SELECT 'outlet_stock',        count(*) FROM outlet_stock
UNION ALL SELECT 'sale',                count(*) FROM sale
UNION ALL SELECT 'sale_line',           count(*) FROM sale_line;

\echo 'Stock never negative? (both should be 0):'
SELECT 'ingredient_batch <0' AS check, count(*) FROM ingredient_batch WHERE quantity_left < 0
UNION ALL
SELECT 'outlet_stock <0', count(*) FROM outlet_stock WHERE quantity_left < 0;
