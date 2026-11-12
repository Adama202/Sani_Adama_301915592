-- portfolio-1-database-design/03_seed.sql
-- Seed data for Crumble Studio.
-- Small, hand-written, representative. The bulk generator (04_bulk_generate.sql)
-- adds 2 years of production runs + sales on top of this.
--
-- All prices in Naira (₦). All names invented.

BEGIN;

-- ----- outlets ------------------------------------------------
INSERT INTO outlet (name, area, address, phone, opened_date) VALUES
    ('Crumble Studio Jabi',     'Jabi',     'Shop 14, Jabi Lake Mall, Abuja',         '0801 111 0001', DATE '2024-03-01'),
    ('Crumble Studio Wuse 2',   'Wuse 2',   '29 Aminu Kano Crescent, Wuse 2, Abuja',  '0801 111 0002', DATE '2024-06-15'),
    ('Crumble Studio Gwarinpa', 'Gwarinpa', '5B 1st Avenue, Gwarinpa, Abuja',         '0801 111 0003', DATE '2024-09-10');

-- ----- suppliers ----------------------------------------------
INSERT INTO supplier (name, phone, address) VALUES
    ('Flour Mills of Nigeria Plc',     '0801 222 0001', 'Marina, Lagos'),
    ('Honeywell Flour Mills',          '0801 222 0002', 'Tin Can Island, Lagos'),
    ('Bakers Mart Abuja',              '0801 222 0003', 'Wuse 2, Abuja'),
    ('Northern Nigeria Foods Co.',     '0801 222 0004', 'Kano'),
    ('Premium Dairy Abuja',            '0801 222 0005', 'Gwagwalada, Abuja');

-- ----- ingredients --------------------------------------------
-- unit_cost in ₦ per unit
INSERT INTO ingredient (name, unit, unit_cost) VALUES
    ('Wheat flour',         'kg', 1200.00),
    ('Butter',              'kg', 5500.00),
    ('Sugar',               'kg', 1500.00),
    ('Salt',                'kg',  600.00),
    ('Instant yeast',       'kg', 4800.00),
    ('Eggs',                'pcs', 220.00),
    ('Whole milk',          'L',  1800.00),
    ('Dark chocolate',      'kg', 9000.00),
    ('Cinnamon',            'kg', 7500.00),
    ('Vanilla extract',     'L', 18000.00),
    ('Baking powder',       'kg', 3200.00),
    ('Minced beef',         'kg', 8500.00),
    ('Onions',              'kg', 1100.00),
    ('Tomatoes',            'kg', 1600.00),
    ('Oat flakes',          'kg', 2400.00),
    ('Raisins',             'kg', 6500.00);

-- ----- products -----------------------------------------------
-- unit_price in ₦ (price the customer pays per unit)
INSERT INTO product (name, category, unit_price, shelf_life_days, bake_time_min) VALUES
    ('Sourdough loaf',    'bread',   2500.00, 3, 60),
    ('Baguette',          'bread',   1500.00, 2, 35),
    ('Brioche',           'bread',   3000.00, 3, 50),
    ('Croissant',         'pastry',  1200.00, 2, 25),
    ('Pain au chocolat',  'pastry',  1500.00, 2, 25),
    ('Cinnamon roll',     'pastry',  1300.00, 2, 30),
    ('Meat pie',          'pie',     1800.00, 2, 45),
    ('Chicken pie',       'pie',     2000.00, 2, 45),
    ('Chocolate chip cookie', 'cookie', 600.00, 5, 18),
    ('Oatmeal raisin cookie', 'cookie', 700.00, 5, 18);

-- ----- recipe lines -------------------------------------------
-- quantity_per_unit = amount of ingredient to bake ONE unit of the product.
INSERT INTO recipe_line (product_id, ingredient_id, quantity_per_unit) VALUES
    -- Sourdough loaf (product_id 1)
    (1, 1, 0.500),   -- 500g flour
    (1, 4, 0.010),   -- 10g salt
    (1, 5, 0.005),   -- 5g yeast
    (1, 7, 0.200),   -- 200ml milk
    -- Baguette (product_id 2)
    (2, 1, 0.300),
    (2, 4, 0.008),
    (2, 5, 0.004),
    (2, 7, 0.150),
    -- Brioche (product_id 3)
    (3, 1, 0.300),
    (3, 2, 0.080),   -- 80g butter
    (3, 3, 0.040),
    (3, 6, 2.000),   -- 2 eggs
    (3, 5, 0.006),
    (3, 7, 0.080),
    -- Croissant (product_id 4)
    (4, 1, 0.120),
    (4, 2, 0.060),
    (4, 6, 1.000),
    (4, 5, 0.004),
    (4, 7, 0.050),
    -- Pain au chocolat (product_id 5)
    (5, 1, 0.120),
    (5, 2, 0.060),
    (5, 8, 0.040),   -- 40g dark chocolate
    (5, 6, 1.000),
    (5, 5, 0.004),
    -- Cinnamon roll (product_id 6)
    (6, 1, 0.150),
    (6, 2, 0.050),
    (6, 3, 0.040),
    (6, 9, 0.010),   -- cinnamon
    (6, 5, 0.005),
    (6, 7, 0.060),
    -- Meat pie (product_id 7)
    (7, 1, 0.250),
    (7, 2, 0.080),
    (7, 12, 0.150),  -- minced beef
    (7, 13, 0.060),  -- onions
    (7, 14, 0.080),  -- tomatoes
    (7, 6, 1.000),
    (7, 4, 0.005),
    -- Chicken pie (product_id 8)
    (8, 1, 0.250),
    (8, 2, 0.080),
    (8, 14, 0.080),
    (8, 13, 0.060),
    (8, 6, 1.000),
    (8, 4, 0.005),
    -- Chocolate chip cookie (product_id 9)
    (9, 1, 0.080),
    (9, 2, 0.045),
    (9, 3, 0.040),
    (9, 8, 0.050),
    (9, 6, 0.500),
    (9, 10, 0.005),  -- vanilla
    (9, 11, 0.002),  -- baking powder
    -- Oatmeal raisin cookie (product_id 10)
    (10, 1, 0.060),
    (10, 2, 0.045),
    (10, 3, 0.040),
    (10, 15, 0.080), -- oats
    (10, 16, 0.040), -- raisins
    (10, 6, 0.500),
    (10, 10, 0.005);

COMMIT;

-- ----- recent ingredient batches ------------------------------
-- A handful of fresh batches the bulk generator will draw from at the start.
-- received_date is today (so they are NOT expired yet); expiry 30-90 days out.
BEGIN;
INSERT INTO ingredient_batch (ingredient_id, supplier_id, received_date, expiry_date, initial_qty, quantity_left)
SELECT i.ingredient_id, 1 + (i.ingredient_id % 5),
       CURRENT_DATE, CURRENT_DATE + (30 + (i.ingredient_id % 60)),
       50.000 + (i.ingredient_id % 50), 50.000 + (i.ingredient_id % 50)
  FROM ingredient i;
COMMIT;

\echo 'Seed data inserted. Row counts:'
SELECT 'outlet'            AS table_name, count(*) FROM outlet
UNION ALL SELECT 'supplier',        count(*) FROM supplier
UNION ALL SELECT 'ingredient',      count(*) FROM ingredient
UNION ALL SELECT 'product',         count(*) FROM product
UNION ALL SELECT 'recipe_line',     count(*) FROM recipe_line
UNION ALL SELECT 'ingredient_batch',count(*) FROM ingredient_batch;
