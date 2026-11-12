-- portfolio-1-database-design/01_schema.sql
-- Crumble Studio — relational schema (10 main tables + supplier helper)
-- Run AFTER dropping any previous version of the database.
-- All psql connections go through the Unix socket (host=/var/run/postgresql).

-- We do NOT drop the database here (the run_p1.sh script does that).
-- This file is purely DDL: tables, keys, basic CHECKs.
-- Triggers and the FIFO function live in 02_constraints_triggers.sql.

BEGIN;

-- =========================================================
-- 1. outlet  (3 rows: Jabi, Wuse 2, Gwarinpa)
-- =========================================================
CREATE TABLE IF NOT EXISTS outlet (
    outlet_id    SERIAL PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE,
    area         TEXT NOT NULL,
    address      TEXT NOT NULL,
    phone        TEXT,
    opened_date  DATE NOT NULL,
    CHECK (opened_date <= CURRENT_DATE)
);

-- =========================================================
-- 2. product  (croissant, sourdough, meat pie, ...)
-- =========================================================
CREATE TABLE IF NOT EXISTS product (
    product_id      SERIAL PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    category        TEXT NOT NULL CHECK (category IN ('bread','pastry','pie','cookie')),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    shelf_life_days INT NOT NULL CHECK (shelf_life_days > 0),
    bake_time_min   INT NOT NULL CHECK (bake_time_min > 0)
);

-- =========================================================
-- 3. ingredient  (flour, butter, sugar, ...)
-- =========================================================
CREATE TABLE IF NOT EXISTS ingredient (
    ingredient_id SERIAL PRIMARY KEY,
    name          TEXT NOT NULL UNIQUE,
    unit          TEXT NOT NULL,                 -- kg, L, pcs, g
    unit_cost     NUMERIC(10,2) NOT NULL CHECK (unit_cost > 0)
);

-- =========================================================
-- 3b. supplier  (helper table referenced by ingredient_batch)
-- =========================================================
CREATE TABLE IF NOT EXISTS supplier (
    supplier_id SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    phone       TEXT,
    address     TEXT
);

-- =========================================================
-- 4. recipe_line  (many-to-many: product <-> ingredient)
--    quantity_per_unit = amount of ingredient needed to bake ONE unit
-- =========================================================
CREATE TABLE IF NOT EXISTS recipe_line (
    recipe_line_id     SERIAL PRIMARY KEY,
    product_id         INT NOT NULL REFERENCES product(product_id) ON DELETE CASCADE,
    ingredient_id      INT NOT NULL REFERENCES ingredient(ingredient_id),
    quantity_per_unit  NUMERIC(12,3) NOT NULL CHECK (quantity_per_unit > 0),
    UNIQUE (product_id, ingredient_id)
);

-- =========================================================
-- 5. ingredient_batch  (a received batch of one ingredient)
--    quantity_left can never go negative (CHECK).
--    expiry_date must be after received_date.
-- =========================================================
CREATE TABLE IF NOT EXISTS ingredient_batch (
    batch_id      SERIAL PRIMARY KEY,
    ingredient_id INT NOT NULL REFERENCES ingredient(ingredient_id),
    supplier_id   INT REFERENCES supplier(supplier_id),
    received_date DATE NOT NULL,
    expiry_date   DATE NOT NULL,
    initial_qty   NUMERIC(12,3) NOT NULL CHECK (initial_qty > 0),
    quantity_left NUMERIC(12,3) NOT NULL CHECK (quantity_left >= 0),
    CHECK (expiry_date > received_date),
    CHECK (quantity_left <= initial_qty)
);

-- =========================================================
-- 6. production_run  (a batch of one product baked on one date)
-- =========================================================
CREATE TABLE IF NOT EXISTS production_run (
    run_id      SERIAL PRIMARY KEY,
    product_id  INT NOT NULL REFERENCES product(product_id),
    run_date    DATE NOT NULL,
    units_baked INT NOT NULL CHECK (units_baked > 0),
    notes       TEXT
);

-- =========================================================
-- 7. batch_usage  (which ingredient batches a run consumed)
-- =========================================================
CREATE TABLE IF NOT EXISTS batch_usage (
    usage_id      SERIAL PRIMARY KEY,
    run_id        INT NOT NULL REFERENCES production_run(run_id) ON DELETE CASCADE,
    batch_id      INT NOT NULL REFERENCES ingredient_batch(batch_id),
    quantity_used NUMERIC(12,3) NOT NULL CHECK (quantity_used > 0)
);

-- =========================================================
-- 8. outlet_stock  (one row per outlet per product per day)
--    UNIQUE (outlet_id, product_id, stock_date)
--    quantity_left can never go negative (CHECK).
-- =========================================================
CREATE TABLE IF NOT EXISTS outlet_stock (
    stock_id      SERIAL PRIMARY KEY,
    outlet_id     INT NOT NULL REFERENCES outlet(outlet_id),
    product_id    INT NOT NULL REFERENCES product(product_id),
    stock_date    DATE NOT NULL,
    quantity_left INT NOT NULL CHECK (quantity_left >= 0),
    UNIQUE (outlet_id, product_id, stock_date)
);

-- =========================================================
-- 9. sale  (one sale = one transaction at one outlet at one time)
--    channel: counter | online
--    customer_name: only for online sales
-- =========================================================
CREATE TABLE IF NOT EXISTS sale (
    sale_id       SERIAL PRIMARY KEY,
    outlet_id     INT NOT NULL REFERENCES outlet(outlet_id),
    sale_time     TIMESTAMPTZ NOT NULL,
    channel       TEXT NOT NULL CHECK (channel IN ('counter','online')),
    customer_name TEXT,                          -- NULL for counter sales
    total_amount  NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    CHECK (sale_time::date <= CURRENT_DATE),
    CHECK (channel = 'counter' AND customer_name IS NULL
        OR channel = 'online' AND customer_name IS NOT NULL)
);

-- =========================================================
-- 10. sale_line  (one line inside a sale; one product, qty, price)
-- =========================================================
CREATE TABLE IF NOT EXISTS sale_line (
    sale_line_id SERIAL PRIMARY KEY,
    sale_id      INT NOT NULL REFERENCES sale(sale_id) ON DELETE CASCADE,
    product_id   INT NOT NULL REFERENCES product(product_id),
    quantity     INT NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price > 0)
);

COMMIT;
