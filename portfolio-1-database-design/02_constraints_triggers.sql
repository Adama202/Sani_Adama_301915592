-- portfolio-1-database-design/02_constraints_triggers.sql
-- Advanced constraints, triggers and the FIFO consume function for Crumble Studio.
--
-- Includes:
--   * trigger: an ingredient_batch that is expired on the run date cannot be used
--   * function consume_batches_fifo(run_id) — consumes exactly recipe × units
--     from the oldest unexpired batches first (FIFO)
--   * trigger: auto-fail a production_run INSERT if there is not enough unexpired
--     stock (so a run that lacks enough flour raises an exception immediately)
--   * trigger: outlet_stock cannot be reduced below zero (defensive, on top of CHECK)
--
-- All CHECK and UNIQUE constraints are in 01_schema.sql; this file adds the
-- behavioural rules that CHECK alone cannot express.

BEGIN;

-- =========================================================
-- A. Trigger: prevent using an expired ingredient batch
-- =========================================================
CREATE OR REPLACE FUNCTION fn_check_batch_not_expired()
RETURNS TRIGGER AS $$
DECLARE
    v_run_date DATE;
    v_batch_expiry DATE;
BEGIN
    SELECT run_date INTO v_run_date
      FROM production_run WHERE run_id = NEW.run_id;

    SELECT expiry_date INTO v_batch_expiry
      FROM ingredient_batch WHERE batch_id = NEW.batch_id;

    IF v_batch_expiry < v_run_date THEN
        RAISE EXCEPTION
            'Ingredient batch % expired on % — cannot be used in production run % (run date %)',
            NEW.batch_id, v_batch_expiry, NEW.run_id, v_run_date
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_batch_not_expired ON batch_usage;
CREATE TRIGGER trg_check_batch_not_expired
BEFORE INSERT OR UPDATE ON batch_usage
FOR EACH ROW EXECUTE FUNCTION fn_check_batch_not_expired();

-- =========================================================
-- B. FIFO consume function
--    Consumes exactly (recipe quantity × units_baked) of each ingredient
--    for a production_run, taking from the OLDEST UNEXPIRED batches first.
--    If there is not enough unexpired stock for ANY ingredient, raises an
--    exception (which rolls back the whole transaction if used inside one).
--    Does NOT touch outlet_stock — the caller (bake_run) does that.
-- =========================================================
CREATE OR REPLACE FUNCTION consume_batches_fifo(p_run_id INT)
RETURNS VOID AS $$
DECLARE
    v_product_id   INT;
    v_units_baked  INT;
    v_run_date     DATE;
    r              RECORD;
    b              RECORD;
    v_needed       NUMERIC(12,3);
    v_take         NUMERIC(12,3);
BEGIN
    SELECT product_id, units_baked, run_date
      INTO v_product_id, v_units_baked, v_run_date
      FROM production_run
     WHERE run_id = p_run_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production run % does not exist', p_run_id;
    END IF;

    -- For each ingredient the recipe needs:
    FOR r IN
        SELECT rl.ingredient_id,
               rl.quantity_per_unit * v_units_baked AS total_needed
          FROM recipe_line rl
         WHERE rl.product_id = v_product_id
    LOOP
        v_needed := r.total_needed;

        -- Walk the oldest unexpired batches with stock left, in FIFO order.
        FOR b IN
            SELECT batch_id, quantity_left
              FROM ingredient_batch
             WHERE ingredient_id = r.ingredient_id
               AND quantity_left > 0
               AND received_date <= v_run_date
               AND expiry_date >= v_run_date
             ORDER BY expiry_date ASC, received_date ASC, batch_id ASC
             FOR UPDATE OF ingredient_batch
        LOOP
            v_take := LEAST(v_needed, b.quantity_left);

            INSERT INTO batch_usage (run_id, batch_id, quantity_used)
            VALUES (p_run_id, b.batch_id, v_take);

            UPDATE ingredient_batch
               SET quantity_left = quantity_left - v_take
             WHERE batch_id = b.batch_id;

            v_needed := v_needed - v_take;
            EXIT WHEN v_needed <= 0.0001;
        END LOOP;

        IF v_needed > 0.0001 THEN
            RAISE EXCEPTION
                'Not enough unexpired stock of ingredient % for run % (still need %)',
                r.ingredient_id, p_run_id, v_needed
                USING ERRCODE = 'insufficient_resources';
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- =========================================================
-- C. Trigger: when a production_run is INSERTed, run FIFO consume
--    automatically. If FIFO fails (e.g. not enough flour), the
--    exception aborts the INSERT — the whole statement is rolled back.
-- =========================================================
CREATE OR REPLACE FUNCTION fn_production_run_after_insert()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM consume_batches_fifo(NEW.run_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_production_run_after_insert ON production_run;
CREATE TRIGGER trg_production_run_after_insert
AFTER INSERT ON production_run
FOR EACH ROW EXECUTE FUNCTION fn_production_run_after_insert();

-- =========================================================
-- D. Defensive trigger: outlet_stock can never go below zero
--    (the CHECK constraint already enforces this at the row level,
--    but this trigger gives a clearer error message for concurrent
--    updates that race the CHECK.)
-- =========================================================
CREATE OR REPLACE FUNCTION fn_outlet_stock_no_negative()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.quantity_left < 0 THEN
        RAISE EXCEPTION
            'outlet_stock would go negative for outlet % product % on % (tried %)',
            NEW.outlet_id, NEW.product_id, NEW.stock_date, NEW.quantity_left
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_outlet_stock_no_negative ON outlet_stock;
CREATE TRIGGER trg_outlet_stock_no_negative
BEFORE INSERT OR UPDATE ON outlet_stock
FOR EACH ROW EXECUTE FUNCTION fn_outlet_stock_no_negative();

-- =========================================================
-- E. Helper: add_baked_stock(outlet, product, date, qty)
--    Used by bake_run() in P3 and by the bulk generator.
--    Uses ON CONFLICT to upsert into the UNIQUE (outlet, product, date) row.
-- =========================================================
CREATE OR REPLACE FUNCTION add_baked_stock(
    p_outlet_id  INT,
    p_product_id INT,
    p_stock_date DATE,
    p_qty        INT
) RETURNS VOID AS $$
BEGIN
    IF p_qty <= 0 THEN
        RAISE EXCEPTION 'add_baked_stock: qty must be > 0, got %', p_qty;
    END IF;
    INSERT INTO outlet_stock (outlet_id, product_id, stock_date, quantity_left)
    VALUES (p_outlet_id, p_product_id, p_stock_date, p_qty)
    ON CONFLICT (outlet_id, product_id, stock_date)
    DO UPDATE SET quantity_left = outlet_stock.quantity_left + EXCLUDED.quantity_left;
END;
$$ LANGUAGE plpgsql;

COMMIT;

-- Sanity check: list every table + the advanced rules we added.
\echo 'Schema objects created. Listing constraints:'
\dT
\echo 'Triggers:'
SELECT tgname, tgrelid::regclass AS on_table, tgenabled
  FROM pg_trigger
 WHERE NOT tgisinternal
 ORDER BY on_table, tgname;
