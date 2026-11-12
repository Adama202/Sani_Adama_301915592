-- portfolio-3-transactions-concurrency/01_sell_items.sql
-- sell_items() transaction for Crumble Studio.
--
-- Behaviour:
--   1. Look up today's outlet_stock row for (outlet, product, sale_date),
--      locking it with SELECT ... FOR UPDATE so no other sale can race us.
--   2. If the row does not exist or quantity_left < requested qty, raise
--      an exception (caller can catch and the whole sale rolls back).
--   3. Insert a sale row (channel = counter | online; customer_name for online).
--   4. Insert one sale_line with the product, quantity and unit_price snapshot.
--   5. Decrement outlet_stock.quantity_left by the quantity sold.
--   6. Update sale.total_amount to the line total.
--   7. Return the new sale_id.
--
-- Designed to be called inside a BEGIN; ... COMMIT; block. If anything fails
-- the caller can ROLLBACK and the sale + stock decrement are undone.

\set ON_ERROR_STOP on

-- drop the old version if re-running
DROP FUNCTION IF EXISTS sell_items(int, int, int, text, timestamptz, text);

CREATE OR REPLACE FUNCTION sell_items(
    p_outlet_id     INT,
    p_product_id    INT,
    p_quantity      INT,
    p_channel       TEXT,
    p_sale_time     TIMESTAMPTZ DEFAULT NOW(),
    p_customer_name TEXT DEFAULT NULL
) RETURNS INT AS $$
DECLARE
    v_sale_id    INT;
    v_unit_price NUMERIC(10,2);
    v_stock_date DATE := (p_sale_time AT TIME ZONE 'Africa/Lagos')::date;
    v_current    INT;
BEGIN
    -- basic argument sanity
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'sell_items: quantity must be > 0 (got %)', p_quantity
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_channel NOT IN ('counter','online') THEN
        RAISE EXCEPTION 'sell_items: channel must be counter or online (got %)', p_channel
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_channel = 'online'  AND p_customer_name IS NULL THEN
        RAISE EXCEPTION 'sell_items: online sale requires a customer_name'
            USING ERRCODE = 'check_violation';
    END IF;
    IF p_channel = 'counter' AND p_customer_name IS NOT NULL THEN
        RAISE EXCEPTION 'sell_items: counter sale must not have a customer_name'
            USING ERRCODE = 'check_violation';
    END IF;

    -- snapshot the unit price (so historical sales keep their price)
    SELECT unit_price INTO v_unit_price FROM product WHERE product_id = p_product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sell_items: product % not found', p_product_id;
    END IF;

    -- lock the stock row for this outlet/product/day; raise if not enough
    SELECT quantity_left INTO v_current
      FROM outlet_stock
     WHERE outlet_id  = p_outlet_id
       AND product_id = p_product_id
       AND stock_date = v_stock_date
     FOR UPDATE;

    IF v_current IS NULL THEN
        RAISE EXCEPTION
            'sell_items: no stock row for outlet % product % on %',
            p_outlet_id, p_product_id, v_stock_date
            USING ERRCODE = 'insufficient_resources';
    END IF;

    IF v_current < p_quantity THEN
        RAISE EXCEPTION
            'sell_items: only % units of product % left at outlet % on % (asked for %)',
            v_current, p_product_id, p_outlet_id, v_stock_date, p_quantity
            USING ERRCODE = 'insufficient_resources';
    END IF;

    -- insert the sale (total_amount is provisional; updated at the end)
    INSERT INTO sale (outlet_id, sale_time, channel, customer_name, total_amount)
    VALUES (p_outlet_id, p_sale_time, p_channel, p_customer_name,
            v_unit_price * p_quantity)
    RETURNING sale_id INTO v_sale_id;

    -- insert the sale line
    INSERT INTO sale_line (sale_id, product_id, quantity, unit_price)
    VALUES (v_sale_id, p_product_id, p_quantity, v_unit_price);

    -- decrement stock (the CHECK + trigger will catch a race to zero)
    UPDATE outlet_stock
       SET quantity_left = quantity_left - p_quantity
     WHERE outlet_id  = p_outlet_id
       AND product_id = p_product_id
       AND stock_date = v_stock_date;

    RETURN v_sale_id;
END;
$$ LANGUAGE plpgsql;

\echo 'Created function sell_items().'
\echo 'Quick demo:'
BEGIN;
SELECT sell_items(
    (SELECT outlet_id  FROM outlet  LIMIT 1),
    (SELECT product_id FROM product  LIMIT 1),
    1, 'counter') AS demo_sale_id;
ROLLBACK;   -- undo the demo
\echo 'Demo rolled back.'
