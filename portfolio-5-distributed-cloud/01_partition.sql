-- portfolio-5-distributed-cloud/01_partition.sql
-- Partition sale_line by month.
--
-- Approach: we cannot easily re-partition the existing sale_line table (it has
-- FKs and indexes from P2). So we create a SECOND, partitioned table called
-- `sale_line_partitioned` that mirrors sale_line plus a denormalised
-- `sale_time` column (the partition key), populate it from the existing data,
-- and demonstrate partition pruning with EXPLAIN.
--
-- In production we would rename sale_line -> sale_line_old, rename
-- sale_line_partitioned -> sale_line, recreate the FKs and indexes, and drop
-- sale_line_old. The same pattern, no data loss.

\set ON_ERROR_STOP on
\pset pager off

-- =========================================================
-- 1. Drop any previous version of the demo table
-- =========================================================
DROP TABLE IF EXISTS sale_line_partitioned CASCADE;

-- =========================================================
-- 2. Create the partitioned parent.
--    Partition key: sale_time (a TIMESTAMPTZ we copy from sale.sale_time).
--    The PRIMARY KEY of a partitioned table MUST include the partition key,
--    so the PK here is (sale_line_id, sale_time).
-- =========================================================
CREATE TABLE sale_line_partitioned (
    sale_line_id  BIGINT       NOT NULL,
    sale_id       INT          NOT NULL,
    product_id    INT          NOT NULL,
    quantity      INT          NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    sale_time     TIMESTAMPTZ  NOT NULL,
    PRIMARY KEY (sale_line_id, sale_time)
) PARTITION BY RANGE (sale_time);

-- =========================================================
-- 3. Create monthly partitions for the last 9 months + current + next.
--    Names like sale_line_p_202511.
-- =========================================================
DO $$
DECLARE
    m       DATE;
    next_m  DATE;
    part_nm TEXT;
BEGIN
    FOR i IN -9..1 LOOP
        m       := (DATE_TRUNC('month', CURRENT_DATE) + (i || ' months')::interval)::date;
        next_m  := (m + INTERVAL '1 month')::date;
        part_nm := 'sale_line_p_' || to_char(m, 'YYYYMM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF sale_line_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            part_nm, m, next_m
        );
    END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS sale_line_p_default PARTITION OF sale_line_partitioned DEFAULT;

\echo 'Partitions created:'
SELECT inhrelid::regclass AS partition
  FROM pg_inherits
 WHERE inhparent = 'sale_line_partitioned'::regclass
 ORDER BY partition;

-- =========================================================
-- 4. Populate from the existing sale_line + sale (to get sale_time).
--    We use a single INSERT ... SELECT so it is one statement, one transaction.
-- =========================================================
INSERT INTO sale_line_partitioned (sale_line_id, sale_id, product_id, quantity, unit_price, sale_time)
SELECT sl.sale_line_id, sl.sale_id, sl.product_id, sl.quantity, sl.unit_price, s.sale_time
  FROM sale_line sl
  JOIN sale s ON s.sale_id = sl.sale_id;

\echo 'Rows in partitioned table:'
SELECT count(*) AS total_rows FROM sale_line_partitioned;

\echo 'Rows per partition (exact counts):'
SELECT tableoid::regclass AS partition, count(*) AS rows
  FROM sale_line_partitioned GROUP BY 1 ORDER BY 1;
\echo 'Rows in the DEFAULT partition (must be 0):'
SELECT count(*) AS default_partition_rows FROM sale_line_p_default;

-- =========================================================
-- 5. Create an index on the partitioned table — Postgres propagates it.
-- =========================================================
CREATE INDEX ix_slp_product ON sale_line_partitioned (product_id);
CREATE INDEX ix_slp_sale    ON sale_line_partitioned (sale_id);
ANALYZE sale_line_partitioned;

\echo 'Indexes on partitioned table:'
SELECT tablename, indexname FROM pg_indexes
 WHERE schemaname='public'
   AND (tablename LIKE 'sale_line_p_%' OR tablename = 'sale_line_partitioned')
 ORDER BY tablename, indexname LIMIT 20;

-- =========================================================
-- 6. Demonstrate partition pruning with EXPLAIN.
--    A query filtered to a single month should scan ONLY that partition.
-- =========================================================
\echo '=================================================='
\echo 'EXPLAIN: query scoped to last month — should prune to ONE partition'
\echo '=================================================='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*), sum(quantity)
  FROM sale_line_partitioned
 WHERE sale_time >= DATE_TRUNC('month', CURRENT_DATE)::timestamptz - INTERVAL '1 month'
   AND sale_time <  DATE_TRUNC('month', CURRENT_DATE)::timestamptz
   AND product_id = 4;   -- croissants

\echo '=================================================='
\echo 'SAME one-month query on the UNPARTITIONED sale_line + sale (for comparison)'
\echo '=================================================='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*), sum(sl.quantity)
  FROM sale_line sl JOIN sale s ON s.sale_id = sl.sale_id
 WHERE s.sale_time >= DATE_TRUNC('month', CURRENT_DATE)::timestamptz - INTERVAL '1 month'
   AND s.sale_time <  DATE_TRUNC('month', CURRENT_DATE)::timestamptz
   AND sl.product_id = 4;

\echo '=================================================='
\echo 'EXPLAIN: query with NO time filter — must scan ALL partitions'
\echo '=================================================='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*) FROM sale_line_partitioned WHERE product_id = 4;

\echo '=================================================='
\echo 'EXPLAIN: query scoped to a 3-month window — 3 partitions'
\echo '=================================================='
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT count(*) FROM sale_line_partitioned
 WHERE sale_time >= DATE_TRUNC('month', CURRENT_DATE)::timestamptz - INTERVAL '3 months'
   AND sale_time <  DATE_TRUNC('month', CURRENT_DATE)::timestamptz;

-- =========================================================
-- 7. Bonus: per-month sales summary straight from the partitioned table.
-- =========================================================
\echo '=================================================='
\echo 'Per-month croissant sales (from partitioned table):'
\echo '=================================================='
SELECT TO_CHAR(DATE_TRUNC('month', sale_time), 'YYYY-MM') AS month,
       count(*) AS n_lines,
       sum(quantity) AS units_sold,
       ROUND(sum(quantity * unit_price)::numeric, 2) AS revenue_ngn
  FROM sale_line_partitioned
 WHERE product_id = 4
 GROUP BY month
 ORDER BY month DESC
 LIMIT 12;
