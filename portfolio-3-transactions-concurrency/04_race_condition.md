> **Note:** these steps are now run automatically with two real database sessions by `run_race_demos.py` (called from `run_p3.sh`). The real output is saved in `race_demos_output.log`. The steps below explain what the script does.

# Portfolio 3 — Race condition: lost update on outlet_stock

This file walks through **the bug**, then **fix 1 (atomic UPDATE + CHECK)**, then
**fix 2 (SELECT … FOR UPDATE)**. All three are written as a step-by-step guide for
two **interactive `psql` sessions** running side by side. There is **no `pg_sleep`**
and no copied IDs: every value that has to flow from one statement to the next is
captured with **`psql \gset`** into a psql variable.

> Open **two terminals**, both running `psql -d crumble`. Call them **T1** and **T2**.
> Run the steps in the order shown. Lines starting with `T1:` go in terminal 1,
> lines starting with `T2:` go in terminal 2.

---

## Setup — give ourselves a clean test row (run in T1, once)

```sql
-- T1 (once, before the demo):
DELETE FROM outlet_stock
 WHERE outlet_id  = (SELECT outlet_id  FROM outlet WHERE name = 'Crumble Studio Jabi')
   AND product_id = (SELECT product_id FROM product WHERE name = 'Croissant')
   AND stock_date = CURRENT_DATE;

INSERT INTO outlet_stock (outlet_id, product_id, stock_date, quantity_left)
SELECT o.outlet_id, p.product_id, CURRENT_DATE, 3   -- only 3 croissants left
  FROM outlet o, product p
 WHERE o.name = 'Crumble Studio Jabi'
   AND p.name = 'Croissant';

-- capture the ids of the row we just made into psql variables
SELECT o.outlet_id  AS outlet_id,
       p.product_id AS product_id
  FROM outlet o, product p
 WHERE o.name = 'Crumble Studio Jabi'
   AND p.name = 'Croissant'
 \gset

\echo outlet_id  = :outlet_id
\echo product_id = :product_id
```

In **T2**, run the same `SELECT … \gset` (without re-inserting) so T2 also has the
variables `:outlet_id` and `:product_id`:

```sql
-- T2 (once, after T1's setup):
SELECT o.outlet_id  AS outlet_id,
       p.product_id AS product_id
  FROM outlet o, product p
 WHERE o.name = 'Crumble Studio Jabi'
   AND p.name = 'Croissant'
 \gset
```

Now **both** terminals can use `:outlet_id` and `:product_id` in every statement
below — no copy-pasting of IDs.

---

## THE BUG — both counters read 3, both sell 3, both write 0

The naive code does a non-locking read, then a write based on that read. Two
transactions running at the default `READ COMMITTED` isolation level can both see
the same starting value, both decrement, and lose one another's update.

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `3` | |
| 4 | | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `3` |
| 5 | `-- both saw 3, both decide to sell 3` | |
| 6 | `UPDATE outlet_stock SET quantity_left = quantity_left - 3 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` | |
| 7 | | `UPDATE outlet_stock SET quantity_left = quantity_left - 3 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` |
| 8 | `COMMIT;` | |
| 9 | | `COMMIT;` |
| 10 | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `0` (lost update!) | |
| 11 | | `-- check the actual sales recorded: SELECT count(*) FROM sale_line WHERE product_id = :product_id;` — should be `6` |

**Expected outcome:** stock shows `0`, but only one of the two `UPDATE`s took
effect (or, depending on the planner, both applied sequentially and stock went
from 3 → 0 → -3, which the CHECK rejects — see fix 1). Either way, the data is
wrong: we **sold 6 croissants from 3 in stock**, or we **lost one sale's
decrement entirely**.

> Screenshot the two `BEGIN … UPDATE … COMMIT` blocks and the final
> `SELECT quantity_left` showing the inconsistency.

---

## Fix 1 — the CHECK (quantity_left >= 0) + atomic UPDATE … WHERE quantity_left >= 3

The `CHECK (quantity_left >= 0)` constraint on `outlet_stock` (see
`01_schema.sql`) means a write that would push the column negative is rejected.
We make the `UPDATE` atomic by adding `AND quantity_left >= 3` to the `WHERE`
clause. The `UPDATE` then either moves the column from 3 to 0 (1 row affected)
or does nothing (0 rows affected), and there is no window for a race because
the read and the write happen in a single statement.

### Reset the test row (run in T1)

```sql
-- T1 (reset):
UPDATE outlet_stock
   SET quantity_left = 3
 WHERE outlet_id  = :outlet_id
   AND product_id = :product_id
   AND stock_date = CURRENT_DATE;
```

### Run the fix (alternate T1 / T2 as shown)

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `UPDATE outlet_stock SET quantity_left = quantity_left - 3 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE AND quantity_left >= 3;` → `UPDATE 1` (1 row affected) | |
| 4 | | `UPDATE outlet_stock SET quantity_left = quantity_left - 3 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE AND quantity_left >= 3;` → `UPDATE 0` (0 rows affected — the WHERE clause rejected it because stock is already 0) |
| 5 | `COMMIT;` | |
| 6 | | `-- the UPDATE 0 means the sale cannot proceed. Either ROLLBACK and tell the customer "sold out", or wait:` |
| 7 | | `ROLLBACK;` |
| 8 | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `0` | |

**Expected outcome:** T1 succeeds (sells the last 3). T2's `UPDATE` affects 0
rows — it cannot over-sell. Stock is correctly `0` and only **3** croissants
were sold, not 6. No lost update.

The same `WHERE quantity_left >= 3` pattern also protects against the case
where the starting quantity was less than 3: the `UPDATE` simply affects 0
rows and the caller knows the sale could not happen.

> Screenshot the two `UPDATE … RETURNING` (or the `UPDATE 1` / `UPDATE 0`
> status lines) and the final `SELECT quantity_left = 0`.

---

## Fix 2 — SELECT … FOR UPDATE (pessimistic row lock)

`SELECT … FOR UPDATE` acquires a `FOR UPDATE` row lock on the stock row. Any
other transaction that runs the same `SELECT … FOR UPDATE` blocks until the
first one commits or rolls back. This is the classical pessimistic-lock fix.

### Reset the test row (run in T1)

```sql
-- T1 (reset):
UPDATE outlet_stock
   SET quantity_left = 3
 WHERE outlet_id  = :outlet_id
   AND product_id = :product_id
   AND stock_date = CURRENT_DATE;
```

### Run the fix (alternate T1 / T2 as shown)

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE FOR UPDATE;` → `3` (row is now locked by T1) | |
| 4 | | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE FOR UPDATE;` → **BLOCKS** (waits for T1 to release the lock) |
| 5 | `-- T1 sees 3, sells 3` | |
| 6 | `UPDATE outlet_stock SET quantity_left = quantity_left - 3 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `UPDATE 1` | |
| 7 | `COMMIT;` | (T2's SELECT unblocks now and returns `0`) |
| 8 | | `-- T2 now sees q_left = 0` |
| 9 | | `-- T2 decides it cannot sell 3 — abort the sale` |
| 10 | | `ROLLBACK;` |
| 11 | `SELECT quantity_left AS q_left FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `0` | |

**Expected outcome:** T1 acquires the lock, sells 3, commits. T2 unblocks, sees
`0`, and decides not to sell. Stock is correct (`0`), and only 3 were sold.

> Screenshot the `SELECT … FOR UPDATE` block in T2 visibly *waiting* (the
> prompt does not return until T1 commits), then T1's `COMMIT`, then T2's
> unblock.

---

## Which fix to use?

| | Fix 1 (atomic UPDATE) | Fix 2 (SELECT FOR UPDATE) |
|---|---|---|
| Locks held | none (statement atomic) | row lock on outlet_stock |
| Code change | add `AND quantity_left >= 3` to WHERE | add `FOR UPDATE` to the read |
| Failure mode | `UPDATE 0` — caller checks rowcount | `SELECT` blocks, then sees new value |
| Concurrency | best (no waiting) | serialized per row |
| Recommendation | **default choice** for Crumble Studio — counters sell fast, atomic UPDATE is simplest and most scalable | use when you also need to *read* the old value for some other purpose (e.g. updating an audit log) and want both under one lock |

---

## Cleanup

```sql
-- either terminal, after the demo:
DELETE FROM outlet_stock
 WHERE outlet_id  = :outlet_id
   AND product_id = :product_id
   AND stock_date = CURRENT_DATE;
```
