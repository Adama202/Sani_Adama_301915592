# Portfolio 3 — Transactions and Concurrency

**Maps to course-note Study Session 1** (ACID, limitations of traditional DBMS,
§1.8) and **Study Session 2** (CAP theorem, ACID vs BASE, consistency models,
§2.2.1–2.2.2).

## Files in this folder

| File | What it does |
|------|--------------|
| `01_sell_items.sql` | `sell_items(outlet, product, qty, channel, …)` transaction: locks the stock row, checks qty, inserts sale + sale_line, decrements stock. |
| `02_bake_run.sql` | `bake_run(product, units, date, outlet)` transaction: inserts a production run (which triggers FIFO consume of ingredient batches), then upserts outlet_stock. |
| `03_rollback_demo.sql` | Demonstrates a `bake_run()` that fails for lack of flour and rolls back **completely** — no production_run, no batch_usage, no outlet_stock row left behind. |
| `04_race_condition.md` | Step-by-step two-terminal guide for the **lost update** bug, then **fix 1** (atomic `UPDATE … WHERE qty >= n` + CHECK) and **fix 2** (`SELECT … FOR UPDATE`). Uses `psql \gset` for IDs, no `pg_sleep`. |
| `05_deadlock.md` | Two `bake_run()` calls locking the same two ingredient batches in opposite order → deadlock. Fix: always lock in `batch_id` order (already enforced by `consume_batches_fifo`'s cursor). |
| `06_isolation_levels.md` | `READ COMMITTED` vs `REPEATABLE READ` step-by-step: non-repeatable read demo, snapshot-stability demo, concurrent-update abort demo. |
| `run_p3.sh` | Loads the functions and runs the rollback demo; prints a reminder for the interactive demos. |

## Commands (Codespaces)

```bash
bash portfolio-1-database-design/run_p1.sh    # if not already done
bash portfolio-3-transactions-concurrency/run_p3.sh
```

For the interactive two-terminal demos, open two terminals:

```bash
# terminal 1
psql -d crumble

# terminal 2
psql -d crumble
```

Then follow the step-by-step tables in:

* `04_race_condition.md`
* `05_deadlock.md`
* `06_isolation_levels.md`

## What to screenshot for evidence

1. `03_rollback_demo.sql` final state: production_runs_for_test = 0,
   stock_rows_for_test = 0, ingredient_batch qty_left still = 1.000 (proves the
   rollback was complete).
2. From `04_race_condition.md` — the bug (both sell 3, stock ends at 0 with 6
   sold), then fix 1 (`UPDATE 1` / `UPDATE 0`), then fix 2 (T2 visibly blocked
   on `SELECT … FOR UPDATE`, then unblocking when T1 commits).
3. From `05_deadlock.md` — T1 and T2 both blocked, then the `ERROR: deadlock
   detected` on one terminal, then the fix (deterministic lock order, no
   deadlock).
4. From `06_isolation_levels.md` — T1's two `SELECT`s returning different
   values under READ COMMITTED, then the same returning the same value under
   REPEATABLE READ.

## Suggested git commit

```bash
git add portfolio-3-transactions-concurrency
git commit -m "P3: sell_items + bake_run + rollback demo + race condition + deadlock + isolation levels"
```

## What this demonstrates

Two real OLTP transactions (`sell_items` and `bake_run`) that wrap multi-statement
work into atomic units, with explicit lock handling so concurrent cashiers and
concurrent bakers cannot corrupt stock. The rollback demo proves a transaction
either fully commits or fully undoes. The race-condition walkthrough shows the
classic lost update plus the two standard fixes (atomic `UPDATE` and `FOR
UPDATE`). The deadlock walkthrough shows how non-deterministic lock order
causes a cycle and how ordering by `batch_id` removes it. The isolation-level
walkthrough contrasts the default `READ COMMITTED` with `REPEATABLE READ` and
explains why Crumble Studio picks READ COMMITTED for OLTP.
