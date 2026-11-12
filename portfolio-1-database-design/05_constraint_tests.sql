-- portfolio-1-database-design/05_constraint_tests.sql
-- Constraint tests for Crumble Studio.
--
-- Each test creates its OWN data (no dependency on specific seed rows) and
-- then attempts an operation that MUST FAIL. The test reports PASSED if the
-- operation was rejected by the constraint / trigger, FAILED if it slipped
-- through.
--
-- Run this AFTER 01_schema.sql + 02_constraints_triggers.sql + 03_seed.sql.
-- (The bulk generator is NOT required for these tests.)

\set ON_ERROR_STOP off

-- helper: a tiny temp result table we accumulate pass/fail into
DROP TABLE IF EXISTS _test_results;
CREATE TEMP TABLE _test_results (test_name TEXT PRIMARY KEY, outcome TEXT, detail TEXT);

-- =========================================================
-- Test 1: ingredient_batch.quantity_left cannot be negative
-- =========================================================
DO $$
BEGIN
    -- make a fresh ingredient + supplier + batch with negative qty_left
    INSERT INTO ingredient (name, unit, unit_cost)
    VALUES ('__test_ingredient_neg', 'kg', 1.00)
    ON CONFLICT (name) DO NOTHING;

    INSERT INTO supplier (name) VALUES ('__test_supplier_neg')
    ON CONFLICT (name) DO NOTHING;

    INSERT INTO ingredient_batch (ingredient_id, supplier_id, received_date,
                                  expiry_date, initial_qty, quantity_left)
    SELECT i.ingredient_id, s.supplier_id, CURRENT_DATE,
           CURRENT_DATE + 30, 100, -5      -- <-- negative
      FROM ingredient i, supplier s
     WHERE i.name = '__test_ingredient_neg'
       AND s.name = '__test_supplier_neg';

    INSERT INTO _test_results VALUES ('neg_ingredient_batch_qty', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('neg_ingredient_batch_qty', 'PASSED',
        'CHECK on ingredient_batch.quantity_left rejected -5: ' || SQLERRM);
END $$;

-- =========================================================
-- Test 2: outlet_stock.quantity_left cannot be negative
-- =========================================================
DO $$
DECLARE v_outlet INT; v_product INT;
BEGIN
    SELECT outlet_id INTO v_outlet FROM outlet LIMIT 1;
    SELECT product_id INTO v_product FROM product LIMIT 1;

    INSERT INTO outlet_stock (outlet_id, product_id, stock_date, quantity_left)
    VALUES (v_outlet, v_product, CURRENT_DATE, -3);   -- <-- negative

    INSERT INTO _test_results VALUES ('neg_outlet_stock_qty', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('neg_outlet_stock_qty', 'PASSED',
        'CHECK on outlet_stock.quantity_left rejected -3: ' || SQLERRM);
END $$;

-- =========================================================
-- Test 3: product.unit_price must be > 0
-- =========================================================
DO $$
BEGIN
    INSERT INTO product (name, category, unit_price, shelf_life_days, bake_time_min)
    VALUES ('__test_product_zero_price', 'bread', 0, 3, 30);

    INSERT INTO _test_results VALUES ('zero_product_price', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('zero_product_price', 'PASSED',
        'CHECK on product.unit_price rejected 0: ' || SQLERRM);
END $$;

-- =========================================================
-- Test 4: sale_line.quantity must be > 0
-- =========================================================
DO $$
DECLARE v_sale INT;
BEGIN
    -- create a valid sale first
    INSERT INTO sale (outlet_id, sale_time, channel, customer_name, total_amount)
    SELECT o.outlet_id, NOW(), 'counter', NULL, 0 FROM outlet o LIMIT 1
    RETURNING sale_id INTO v_sale;

    INSERT INTO sale_line (sale_id, product_id, quantity, unit_price)
    VALUES (v_sale, (SELECT product_id FROM product LIMIT 1), 0, 100.00);

    INSERT INTO _test_results VALUES ('zero_sale_line_qty', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('zero_sale_line_qty', 'PASSED',
        'CHECK on sale_line.quantity rejected 0: ' || SQLERRM);
END $$;

-- =========================================================
-- Test 5: an expired ingredient batch cannot be used in a production run
--         (trigger trg_check_batch_not_expired)
--
-- We give the test ingredient TWO batches: a fresh one (so the production
-- run can succeed and the AFTER-INSERT trigger doesn't fire first) and an
-- expired one. We then try to insert a batch_usage row pointing to the
-- EXPIRED batch. The trg_check_batch_not_expired trigger must reject it.
-- =========================================================
DO $$
DECLARE v_run INT; v_batch_exp INT; v_ing INT; v_prod INT;
BEGIN
    -- fresh ingredient
    INSERT INTO ingredient (name, unit, unit_cost)
    VALUES ('__test_ingredient_exp', 'kg', 1.00)
    ON CONFLICT (name) DO NOTHING;
    SELECT ingredient_id INTO v_ing FROM ingredient WHERE name = '__test_ingredient_exp';

    -- fresh product that uses it
    INSERT INTO product (name, category, unit_price, shelf_life_days, bake_time_min)
    VALUES ('__test_product_exp', 'bread', 100, 3, 30)
    ON CONFLICT (name) DO NOTHING;
    SELECT product_id INTO v_prod FROM product WHERE name = '__test_product_exp';

    INSERT INTO recipe_line (product_id, ingredient_id, quantity_per_unit)
    VALUES (v_prod, v_ing, 0.100)   -- 0.1 kg per unit
    ON CONFLICT (product_id, ingredient_id) DO NOTHING;

    -- FRESH batch (so the production_run INSERT trigger succeeds)
    INSERT INTO ingredient_batch (ingredient_id, received_date, expiry_date,
                                  initial_qty, quantity_left)
    VALUES (v_ing, CURRENT_DATE, CURRENT_DATE + 60, 100, 100);

    -- EXPIRED batch (5 days ago)
    INSERT INTO ingredient_batch (ingredient_id, received_date, expiry_date,
                                  initial_qty, quantity_left)
    VALUES (v_ing, CURRENT_DATE - 35, CURRENT_DATE - 5, 100, 100)
    RETURNING batch_id INTO v_batch_exp;

    -- production run dated today. The AFTER INSERT trigger will consume from
    -- the FRESH batch (only). This succeeds.
    INSERT INTO production_run (product_id, run_date, units_baked)
    VALUES (v_prod, CURRENT_DATE, 10)
    RETURNING run_id INTO v_run;

    -- now try to MANUALLY insert a batch_usage row pointing to the EXPIRED batch
    INSERT INTO batch_usage (run_id, batch_id, quantity_used)
    VALUES (v_run, v_batch_exp, 1.000);

    INSERT INTO _test_results VALUES ('use_expired_batch', 'FAILED',
        'expected trigger to reject expired batch but it was used');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('use_expired_batch', 'PASSED',
        'trigger trg_check_batch_not_expired rejected expired batch: ' || SQLERRM);
    -- cleanup half-inserted run
    DELETE FROM production_run WHERE run_id = v_run;
END $$;

-- =========================================================
-- Test 6: a production run that needs MORE stock than available
--         must be rejected (FIFO function raises, AFTER-INSERT trigger
--         rolls back the run)
-- =========================================================
DO $$
DECLARE v_run INT; v_ing INT; v_prod INT;
BEGIN
    -- ingredient with a tiny batch (only 0.5 kg available)
    INSERT INTO ingredient (name, unit, unit_cost)
    VALUES ('__test_ingredient_rare', 'g', 0.01)
    ON CONFLICT (name) DO NOTHING;
    SELECT ingredient_id INTO v_ing FROM ingredient WHERE name = '__test_ingredient_rare';

    INSERT INTO product (name, category, unit_price, shelf_life_days, bake_time_min)
    VALUES ('__test_product_rare', 'bread', 100, 3, 30)
    ON CONFLICT (name) DO NOTHING;
    SELECT product_id INTO v_prod FROM product WHERE name = '__test_product_rare';

    INSERT INTO recipe_line (product_id, ingredient_id, quantity_per_unit)
    VALUES (v_prod, v_ing, 0.500)   -- 0.5 kg per unit
    ON CONFLICT (product_id, ingredient_id) DO NOTHING;

    -- only 0.5 kg available, expires far in the future
    INSERT INTO ingredient_batch (ingredient_id, received_date, expiry_date,
                                  initial_qty, quantity_left)
    VALUES (v_ing, CURRENT_DATE, CURRENT_DATE + 60, 0.500, 0.500);

    -- try to bake 100 units => needs 50 kg, only 0.5 kg available
    INSERT INTO production_run (product_id, run_date, units_baked)
    VALUES (v_prod, CURRENT_DATE, 100)
    RETURNING run_id INTO v_run;

    INSERT INTO _test_results VALUES ('run_insufficient_stock', 'FAILED',
        'expected FIFO to reject run for lack of stock but it was inserted');
EXCEPTION WHEN insufficient_resources THEN
    INSERT INTO _test_results VALUES ('run_insufficient_stock', 'PASSED',
        'consume_batches_fifo correctly rejected run needing more stock than available: '
        || SQLERRM);
END $$;

-- =========================================================
-- Test 7: duplicate outlet_stock row (same outlet + product + date)
--         must be rejected by UNIQUE constraint
-- =========================================================
DO $$
DECLARE v_outlet INT; v_product INT;
BEGIN
    SELECT outlet_id INTO v_outlet FROM outlet LIMIT 1;
    SELECT product_id INTO v_product FROM product LIMIT 1;

    -- first insert (ok)
    INSERT INTO outlet_stock (outlet_id, product_id, stock_date, quantity_left)
    VALUES (v_outlet, v_product, DATE '2099-01-01', 10)
    ON CONFLICT (outlet_id, product_id, stock_date) DO NOTHING;

    -- second insert (same key) -> must fail
    INSERT INTO outlet_stock (outlet_id, product_id, stock_date, quantity_left)
    VALUES (v_outlet, v_product, DATE '2099-01-01', 5);

    INSERT INTO _test_results VALUES ('dup_outlet_stock_row', 'FAILED',
        'expected UNIQUE violation but the duplicate row was inserted');
EXCEPTION WHEN unique_violation THEN
    INSERT INTO _test_results VALUES ('dup_outlet_stock_row', 'PASSED',
        'UNIQUE (outlet_id, product_id, stock_date) rejected duplicate: ' || SQLERRM);
    -- cleanup
    DELETE FROM outlet_stock
     WHERE outlet_id = v_outlet
       AND product_id = v_product
       AND stock_date = DATE '2099-01-01';
END $$;

-- =========================================================
-- Test 8: online sale without customer_name must be rejected
-- =========================================================
DO $$
BEGIN
    INSERT INTO sale (outlet_id, sale_time, channel, customer_name, total_amount)
    SELECT outlet_id, NOW(), 'online', NULL, 500 FROM outlet LIMIT 1;

    INSERT INTO _test_results VALUES ('online_sale_no_name', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('online_sale_no_name', 'PASSED',
        'CHECK (channel/customer_name) rejected online sale with NULL name: ' || SQLERRM);
END $$;

-- =========================================================
-- Test 9: counter sale WITH a customer_name must be rejected
-- =========================================================
DO $$
BEGIN
    INSERT INTO sale (outlet_id, sale_time, channel, customer_name, total_amount)
    SELECT outlet_id, NOW(), 'counter', 'Test Person', 500 FROM outlet LIMIT 1;

    INSERT INTO _test_results VALUES ('counter_sale_with_name', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('counter_sale_with_name', 'PASSED',
        'CHECK (channel/customer_name) rejected counter sale with name: ' || SQLERRM);
END $$;

-- =========================================================
-- Test 10: ingredient_batch.expiry_date must be after received_date
-- =========================================================
DO $$
DECLARE v_ing INT;
BEGIN
    SELECT ingredient_id INTO v_ing FROM ingredient LIMIT 1;
    INSERT INTO ingredient_batch (ingredient_id, received_date, expiry_date,
                                  initial_qty, quantity_left)
    VALUES (v_ing, CURRENT_DATE, CURRENT_DATE - 1, 10, 10);  -- expiry before received

    INSERT INTO _test_results VALUES ('expiry_before_received', 'FAILED',
        'expected CHECK violation but the row was inserted');
EXCEPTION WHEN check_violation THEN
    INSERT INTO _test_results VALUES ('expiry_before_received', 'PASSED',
        'CHECK (expiry_date > received_date) rejected backwards dates: ' || SQLERRM);
END $$;

-- =========================================================
-- Cleanup test artefacts
-- =========================================================
DELETE FROM ingredient WHERE name LIKE '__test_%';
DELETE FROM product    WHERE name LIKE '__test_%';
DELETE FROM supplier   WHERE name LIKE '__test_%';

-- =========================================================
-- Report
-- =========================================================
\echo '=================================================='
\echo 'CONSTRAINT TEST RESULTS'
\echo '=================================================='
SELECT test_name, outcome, detail FROM _test_results ORDER BY test_name;
\echo '=================================================='
\echo 'Total passed:' 
SELECT count(*) FROM _test_results WHERE outcome = 'PASSED';
\echo 'Total failed:'
SELECT count(*) FROM _test_results WHERE outcome = 'FAILED';

DROP TABLE _test_results;
