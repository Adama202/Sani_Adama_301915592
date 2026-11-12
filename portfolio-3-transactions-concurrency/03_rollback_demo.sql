-- portfolio-3-transactions-concurrency/03_rollback_demo.sql
-- Demo: a bake_run() that LACKS ENOUGH FLOUR rolls back completely.
--
-- Setup:
--   * create a fresh test ingredient "Test Rare Flour" with only 1 kg in stock
--   * create a fresh test product "Test Big Loaf" that needs 0.5 kg per loaf
--   * call bake_run() for 100 loaves (needs 50 kg, only 1 kg available)
--   * bake_run() should fail with insufficient_resources
--   * verify: NO production_run row, NO batch_usage rows, NO outlet_stock
--     row were left behind — the whole transaction rolled back.

\set ON_ERROR_STOP off
\pset pager off

\echo '=================================================='
\echo 'ROLLBACK DEMO: bake_run() with insufficient flour'
\echo '=================================================='

-- ----- 1. Test setup: fresh ingredient + tiny batch + product + recipe ----
INSERT INTO ingredient (name, unit, unit_cost)
VALUES ('Test Rare Flour', 'kg', 1000.00)
ON CONFLICT (name) DO NOTHING;

INSERT INTO ingredient_batch (ingredient_id, received_date, expiry_date,
                              initial_qty, quantity_left)
SELECT i.ingredient_id, CURRENT_DATE, CURRENT_DATE + 90,
       1.000, 1.000       -- only 1 kg available
  FROM ingredient i
 WHERE i.name = 'Test Rare Flour';

INSERT INTO product (name, category, unit_price, shelf_life_days, bake_time_min)
VALUES ('Test Big Loaf', 'bread', 2000.00, 3, 60)
ON CONFLICT (name) DO NOTHING;

INSERT INTO recipe_line (product_id, ingredient_id, quantity_per_unit)
SELECT p.product_id, i.ingredient_id, 0.500   -- 0.5 kg per loaf
  FROM product p, ingredient i
 WHERE p.name = 'Test Big Loaf'
   AND i.name = 'Test Rare Flour'
ON CONFLICT (product_id, ingredient_id) DO NOTHING;

\echo 'Setup done. State BEFORE bake_run():'
SELECT 'ingredient_batch qty_left' AS what, quantity_left
  FROM ingredient_batch b
  JOIN ingredient i USING (ingredient_id)
 WHERE i.name = 'Test Rare Flour'
 ORDER BY b.batch_id DESC LIMIT 1;

SELECT count(*) AS production_runs_for_test
  FROM production_run pr
  JOIN product p ON p.product_id = pr.product_id
 WHERE p.name = 'Test Big Loaf';

SELECT count(*) AS stock_rows_for_test
  FROM outlet_stock os
  JOIN product p ON p.product_id = os.product_id
 WHERE p.name = 'Test Big Loaf';

-- ----- 2. The bake_run() that should fail --------------------------------
\echo
\echo 'Calling bake_run() for 100 loaves (needs 50 kg, only 1 kg available):'
BEGIN;
SELECT bake_run(
    (SELECT product_id FROM product WHERE name = 'Test Big Loaf'),
    100,
    CURRENT_DATE,
    (SELECT outlet_id  FROM outlet  LIMIT 1)
) AS run_id;
ROLLBACK;   -- if we reached here, undo (we won't, the call should fail first)

\echo
\echo 'Calling bake_run() in a nested transaction so we can see the exception:'
DO $$
DECLARE v_run_id INT;
BEGIN
    SELECT bake_run(
        (SELECT product_id FROM product WHERE name = 'Test Big Loaf'),
        100,
        CURRENT_DATE,
        (SELECT outlet_id  FROM outlet  LIMIT 1)
    ) INTO v_run_id;
    RAISE NOTICE 'bake_run returned % — UNEXPECTED, should have raised', v_run_id;
EXCEPTION
    WHEN insufficient_resources THEN
        RAISE NOTICE 'bake_run correctly raised insufficient_resources: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'bake_run raised (other): %', SQLERRM;
END $$;

-- ----- 3. Verify NOTHING was left behind ---------------------------------
\echo
\echo 'State AFTER the failed bake_run():'
SELECT count(*) AS production_runs_for_test
  FROM production_run pr
  JOIN product p ON p.product_id = pr.product_id
 WHERE p.name = 'Test Big Loaf';

SELECT count(*) AS stock_rows_for_test
  FROM outlet_stock os
  JOIN product p ON p.product_id = os.product_id
 WHERE p.name = 'Test Big Loaf';

SELECT 'ingredient_batch qty_left' AS what, quantity_left
  FROM ingredient_batch b
  JOIN ingredient i USING (ingredient_id)
 WHERE i.name = 'Test Rare Flour'
 ORDER BY b.batch_id DESC LIMIT 1;

\echo
\echo 'Both counts must be 0, and qty_left must still be 1.000 — i.e. the'
\echo 'whole bake_run transaction was rolled back, including the partial'
\echo 'consumption of the rare-flour batch.'

-- ----- 4. Cleanup --------------------------------------------------------
DELETE FROM recipe_line
 WHERE product_id = (SELECT product_id FROM product WHERE name = 'Test Big Loaf')
   AND ingredient_id = (SELECT ingredient_id FROM ingredient WHERE name = 'Test Rare Flour');
DELETE FROM ingredient_batch
 WHERE ingredient_id = (SELECT ingredient_id FROM ingredient WHERE name = 'Test Rare Flour');
DELETE FROM product    WHERE name = 'Test Big Loaf';
DELETE FROM ingredient WHERE name = 'Test Rare Flour';

\echo 'Test artefacts cleaned up.'
