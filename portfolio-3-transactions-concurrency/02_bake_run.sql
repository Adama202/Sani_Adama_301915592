-- portfolio-3-transactions-concurrency/02_bake_run.sql
-- bake_run() transaction for Crumble Studio.
--
-- Behaviour:
--   1. Insert a production_run row (product, date, units_baked).
--      The AFTER INSERT trigger on production_run calls consume_batches_fifo()
--      automatically, which:
--        * takes exactly recipe.quantity_per_unit * units_baked of each ingredient
--        * from the oldest unexpired batches first (FIFO)
--        * updates ingredient_batch.quantity_left
--        * inserts the corresponding batch_usage rows
--      If any ingredient has insufficient unexpired stock (e.g. not enough
--      flour), consume_batches_fifo raises 'insufficient_resources' which
--      aborts the INSERT and rolls back the whole statement.
--   2. If the consume step succeeded, add the baked units to outlet_stock
--      for the chosen outlet (using add_baked_stock, which ON CONFLICT upserts).
--   3. Return the new run_id.
--
-- Because everything runs inside one transaction, a failure in step 1 rolls
-- back step 1's partial work AND step 2 never runs. See 03_rollback_demo.sql
-- for the "not enough flour" scenario.

\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS bake_run(int, int, int, date, int);

CREATE OR REPLACE FUNCTION bake_run(
    p_product_id INT,
    p_units      INT,
    p_run_date   DATE,
    p_outlet_id  INT
) RETURNS INT AS $$
DECLARE
    v_run_id INT;
BEGIN
    IF p_units <= 0 THEN
        RAISE EXCEPTION 'bake_run: units must be > 0 (got %)', p_units
            USING ERRCODE = 'check_violation';
    END IF;

    -- Step 1: insert the production run. The AFTER INSERT trigger fires
    -- consume_batches_fifo(run_id) which atomically consumes ingredient batches
    -- FIFO. If stock is insufficient, it raises and the INSERT is rolled back.
    INSERT INTO production_run (product_id, run_date, units_baked, notes)
    VALUES (p_product_id, p_run_date, p_units, 'bake_run()')
    RETURNING run_id INTO v_run_id;

    -- Step 2: add the baked units to the outlet's stock for that day.
    PERFORM add_baked_stock(p_outlet_id, p_product_id, p_run_date, p_units);

    RETURN v_run_id;
END;
$$ LANGUAGE plpgsql;

\echo 'Created function bake_run().'
\echo 'Quick demo:'
BEGIN;
SELECT bake_run(
    (SELECT product_id FROM product LIMIT 1),
    5,
    CURRENT_DATE,
    (SELECT outlet_id  FROM outlet  LIMIT 1)
) AS demo_run_id;
ROLLBACK;
\echo 'Demo rolled back.'
