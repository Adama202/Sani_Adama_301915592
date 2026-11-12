> **Note:** these steps are now run automatically with two real database sessions by `run_race_demos.py` (called from `run_p3.sh`). The real output is saved in `race_demos_output.log`. The steps below explain what the script does.

# Portfolio 3 — Deadlock between two production runs

Two `bake_run()` calls running at the same time both need to lock ingredient
batches for the **same two ingredients** (flour + butter), but they grab the
locks in **opposite order**. PostgreSQL detects the deadlock and aborts one of
the transactions; the other one succeeds. The fix is to **always lock batches
in `batch_id` order**.

All steps are written for two **interactive `psql` sessions**. We use `psql
\gset` to capture batch IDs into variables so no IDs are copied by hand.

> Open two terminals, both `psql -d crumble`. T1 = terminal 1, T2 = terminal 2.

---

## Setup — two ingredient batches with known IDs (run in T1, once)

We need two fresh batches of `Wheat flour` and `Butter` with stable IDs that
both terminals can refer to.

```sql
-- T1 (once, before the demo):
INSERT INTO ingredient_batch (ingredient_id, received_date, expiry_date,
                              initial_qty, quantity_left)
SELECT i.ingredient_id, CURRENT_DATE, CURRENT_DATE + 90, 1000, 1000
  FROM ingredient i
 WHERE i.name IN ('Wheat flour', 'Butter')
 ORDER BY i.name
 RETURNING batch_id, (SELECT name FROM ingredient i WHERE i.ingredient_id = ingredient_batch.ingredient_id) AS ingredient
 \gset
```

This populates psql variables `batch_id` and `ingredient` for the **last** row
returned. To make sure we have BOTH batch ids captured cleanly, do it explicitly
with two separate statements:

```sql
-- T1 (cleaner): capture each batch_id into its own variable
SELECT batch_id AS flour_batch_id
  FROM ingredient_batch b
  JOIN ingredient i USING (ingredient_id)
 WHERE i.name = 'Wheat flour'
 ORDER BY batch_id DESC LIMIT 1
 \gset

SELECT batch_id AS butter_batch_id
  FROM ingredient_batch b
  JOIN ingredient i USING (ingredient_id)
 WHERE i.name = 'Butter'
 ORDER BY batch_id DESC LIMIT 1
 \gset

\echo flour_batch_id  = :flour_batch_id
\echo butter_batch_id = :butter_batch_id
```

Run the **same two `SELECT … \gset`** in **T2** so T2 also has
`:flour_batch_id` and `:butter_batch_id`:

```sql
-- T2 (mirror T1's variables):
SELECT batch_id AS flour_batch_id
  FROM ingredient_batch b
  JOIN ingredient i USING (ingredient_id)
 WHERE i.name = 'Wheat flour'
 ORDER BY batch_id DESC LIMIT 1
 \gset;

SELECT batch_id AS butter_batch_id
  FROM ingredient_batch b
  JOIN ingredient i USING (ingredient_id)
 WHERE i.name = 'Butter'
 ORDER BY batch_id DESC LIMIT 1
 \gset;
```

---

## THE BUG — opposite lock order

We simulate what `consume_batches_fifo` does internally, but we deliberately
reverse the order in T2. The two transactions end up waiting for each other —
a classic deadlock.

> Note: `consume_batches_fifo` itself orders by `(expiry_date, received_date,
> batch_id)`, which is deterministic, so two `bake_run()` calls for the SAME
> product cannot normally deadlock — they would lock in the same order. The
> deadlock requires two different recipes that share ingredients but list them
> in a different order, or — as below — a contrived manual lock sequence to
> demonstrate the issue.

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `-- lock flour first, then butter` | |
| 4 | `SELECT * FROM ingredient_batch WHERE batch_id = :flour_batch_id FOR UPDATE;` (locks flour) | |
| 5 | | `-- lock butter first, then flour (opposite order)` |
| 6 | | `SELECT * FROM ingredient_batch WHERE batch_id = :butter_batch_id FOR UPDATE;` (locks butter) |
| 7 | `-- now T1 wants butter — blocks because T2 holds it` | |
| 8 | `SELECT * FROM ingredient_batch WHERE batch_id = :butter_batch_id FOR UPDATE;` → **BLOCKS** | |
| 9 | | `-- now T2 wants flour — also blocks because T1 holds it` |
| 10 | | `SELECT * FROM ingredient_batch WHERE batch_id = :flour_batch_id FOR UPDATE;` → **BLOCKS** |
| 11 | (PostgreSQL detects the cycle) | one of the two transactions is aborted with `ERROR:  deadlock detected` |
| 12 | The other transaction unblocks and can `COMMIT;` | `ROLLBACK;` the deadlocked one |

**Expected outcome:** within a few seconds, one terminal shows:

```
ERROR:  deadlock detected
DETAIL:  Process ... waits for ShareLock on transaction ... blocked by process ....
HINT:  See server log for query details.
CONTEXT:  while locking tuple ... in relation "ingredient_batch"
```

The other terminal's `SELECT … FOR UPDATE` then succeeds.

> Screenshot both terminals: T1 blocked, T2 blocked, then the deadlock error
> on one of them, then the other unblocking.

---

## The fix — always lock batches in `batch_id` order

The rule: **before consuming from ingredient batches, sort the candidate
batches by `batch_id` ASC and lock them in that order, regardless of the
recipe order or the expiry order.** Two transactions that both follow this
rule can never deadlock on the same set of batches.

In `consume_batches_fifo` (file `02_constraints_triggers.sql`) we already lock
batches with `FOR UPDATE` inside the FIFO cursor, and the cursor is `ORDER BY
expiry_date ASC, received_date ASC, batch_id ASC`. If two runs need the same
ingredient they will hit the same first batch in the same order, so they
serialise on that batch and never deadlock.

To demonstrate the fix manually, redo the same two-step lock but this time
**both terminals lock flour first, then butter** (lowest `batch_id` first).

| Step | T1 | T2 |
|------|----|----|
| 1 | `BEGIN;` | |
| 2 | | `BEGIN;` |
| 3 | `SELECT * FROM ingredient_batch WHERE batch_id = :flour_batch_id FOR UPDATE;` (locks flour; T2 blocks if it tries the same) | |
| 4 | | `SELECT * FROM ingredient_batch WHERE batch_id = :flour_batch_id FOR UPDATE;` → **BLOCKS** (waits for T1) |
| 5 | `SELECT * FROM ingredient_batch WHERE batch_id = :butter_batch_id FOR UPDATE;` (locks butter) | (still waiting) |
| 6 | `COMMIT;` | (T2 unblocks) |
| 7 | | `-- T2 now has the flour lock, can grab butter next` |
| 8 | | `SELECT * FROM ingredient_batch WHERE batch_id = :butter_batch_id FOR UPDATE;` |
| 9 | | `COMMIT;` |

**Expected outcome:** no deadlock. T2 simply waits for T1, then proceeds. Both
transactions complete cleanly.

> Screenshot T2 visibly blocked on the first `SELECT FOR UPDATE`, then T1's
> `COMMIT`, then T2 unblocking and committing.

---

## How this maps to `bake_run()`

Inside `consume_batches_fifo(p_run_id)` (see `02_constraints_triggers.sql`),
the inner cursor is:

```sql
SELECT batch_id, quantity_left
  FROM ingredient_batch
 WHERE ingredient_id = r.ingredient_id
   AND quantity_left > 0
   AND expiry_date >= v_run_date
 ORDER BY expiry_date ASC, received_date ASC, batch_id ASC
 FOR UPDATE OF ingredient_batch
```

Two concurrent `bake_run()` calls for **the same product** walk the same
cursor in the same order, so they serialise on the first batch and never
deadlock. Two calls for **different products that share an ingredient** also
serialise on the same first batch for that ingredient — again, no deadlock.
The contrived demo above is the *only* way to provoke a deadlock against this
schema, and the fix (deterministic lock order) is already baked into the
function.

---

## Cleanup

```sql
-- either terminal:
DELETE FROM ingredient_batch
 WHERE batch_id IN (:flour_batch_id, :butter_batch_id);
```
