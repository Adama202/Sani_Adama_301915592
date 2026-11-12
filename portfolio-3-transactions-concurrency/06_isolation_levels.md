> **Note:** these steps are now run automatically with two real database sessions by `run_race_demos.py` (called from `run_p3.sh`). The real output is saved in `race_demos_output.log`. The steps below explain what the script does.

# Portfolio 3 — Isolation levels: READ COMMITTED vs REPEATABLE READ

PostgreSQL has a third level (`SERIALIZABLE`) but the CA brief only asks about
`READ COMMITTED` (the default) and `REPEATABLE READ`. The interesting
differences in PostgreSQL are:

* **READ COMMITTED** (default): each statement sees a fresh snapshot, including
  commits made by other transactions since this transaction's previous
  statement. **Non-repeatable reads** and **phantom reads** are possible.
* **REPEATABLE READ**: the snapshot is taken at the **first statement** of the
  transaction and reused for every subsequent statement. No non-repeatable
  reads, no phantoms. In PostgreSQL it also prevents most write skews, but it
  can raise `could not serialize access due to concurrent update` if two
  transactions try to update the same row.

This file demonstrates both behaviours with **two interactive `psql` sessions**.
We use `psql \gset` to capture the starting value into a variable so we can
compare what T1 reads before and after T2 commits — no copy-pasting.

> Open two terminals, both `psql -d crumble`. T1 = terminal 1, T2 = terminal 2.

---

## Setup — pick a stock row to read (run in both terminals)

```sql
-- T1 and T2 (once, before the demo):
SELECT o.outlet_id  AS outlet_id,
       p.product_id AS product_id
  FROM outlet o, product p
 WHERE o.name = 'Crumble Studio Jabi'
   AND p.name = 'Croissant'
 \gset

-- give ourselves a known starting value of 50
UPDATE outlet_stock
   SET quantity_left = 50
 WHERE outlet_id  = :outlet_id
   AND product_id = :product_id
   AND stock_date = CURRENT_DATE;
```

---

## Demo 1 — non-repeatable READ under READ COMMITTED

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN;` | |
| 2 | `SHOW transaction_isolation;` → `read committed` (default) | |
| 3 | `SELECT quantity_left AS first_read FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `50` | |
| 4 | | `BEGIN;` |
| 5 | | `UPDATE outlet_stock SET quantity_left = 30 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` |
| 6 | | `COMMIT;` |
| 7 | `SELECT quantity_left AS second_read FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → **`30`** (different from first_read!) | |
| 8 | `COMMIT;` | |

**Expected outcome:** T1 reads `50`, then `30`. The same row, in the same
transaction, returned two different values — a **non-repeatable read**. This is
allowed under READ COMMITTED.

> Screenshot T1's two `SELECT` results showing `50` then `30`.

---

## Demo 2 — REPEATABLE READ sees a stable snapshot

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| 2 | `SHOW transaction_isolation;` → `repeatable read` | |
| 3 | `SELECT quantity_left AS first_read FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `30` (whatever it is now) | |
| 4 | | `BEGIN;` |
| 5 | | `UPDATE outlet_stock SET quantity_left = 99 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` |
| 6 | | `COMMIT;` |
| 7 | `SELECT quantity_left AS second_read FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → **still `30`** (snapshot frozen at first read) | |
| 8 | `COMMIT;` | |
| 9 | `-- after T1 commits, a fresh read sees the new value` | |
| 10 | `SELECT quantity_left AS third_read FROM outlet_stock WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `99` | |

**Expected outcome:** T1 reads `30`, then `30` again — the snapshot was frozen
when T1's first statement ran, so T2's commit is invisible to T1 until T1
commits. After T1 commits, a fresh read returns `99`.

> Screenshot T1's `BEGIN ISOLATION LEVEL REPEATABLE READ`, the two `SELECT`s
> returning the same value, T2's `UPDATE … COMMIT`, and T1's third read
> (after its own `COMMIT`) showing the new value.

---

## Demo 3 — concurrent UPDATE under REPEATABLE READ

If two REPEATABLE READ transactions both try to UPDATE the same row, the second
one to commit gets `could not serialize access due to concurrent update`.

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| 2 | | `BEGIN ISOLATION LEVEL REPEATABLE READ;` |
| 3 | `UPDATE outlet_stock SET quantity_left = 10 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → `UPDATE 1` | |
| 4 | | `UPDATE outlet_stock SET quantity_left = 20 WHERE outlet_id = :outlet_id AND product_id = :product_id AND stock_date = CURRENT_DATE;` → **BLOCKS** (waits for T1) |
| 5 | `COMMIT;` | (T2 unblocks with `ERROR:  could not serialize access due to concurrent update`) |
| 6 | | `ROLLBACK;` |

**Expected outcome:** T2 cannot commit its update — PostgreSQL forces T2 to
retry from a fresh snapshot. This is the "first-updater-wins" rule for
REPEATABLE READ.

> Screenshot T2 blocking, T1 committing, and T2's
> `could not serialize access` error.

---

## Trade-offs for Crumble Studio

| Choice | Pros | Cons | Use for |
|--------|------|------|---------|
| **READ COMMITTED** (default) | Best throughput; never aborts on concurrent update; counters sell fast. | Non-repeatable reads are possible; app must use `SELECT … FOR UPDATE` or atomic `UPDATE … WHERE qty >= n` to avoid lost updates. | **default for all Crumble Studio OLTP** — `sell_items()`, `bake_run()`, daily reports. |
| **REPEATABLE READ** | Stable snapshot; no non-repeatable reads; protects against most write skews. | A concurrent UPDATE on the same row aborts with `could not serialize access`; the app must be ready to retry. | end-of-day reconciliation reports that read many tables and want a consistent snapshot. |
| **SERIALIZABLE** (for reference) | Strongest guarantees; behaves like one-at-a-time execution for read/write predicates. | Most aborts; the app must always be ready to retry the whole transaction. | not used at Crumble Studio — overkill for a 3-outlet bakery. |

Crumble Studio uses **READ COMMITTED** for all OLTP work, with the
**atomic-UPDATE-WHERE-qty >= n** pattern from `04_race_condition.md` (fix 1)
to make `sell_items()` safe without row locks.
