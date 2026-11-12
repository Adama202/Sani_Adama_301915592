# CHANGES - Adama Sani (2026/A/MIT/0340), Crumble Studio

Tested by Claude in a Codespaces-like Ubuntu (PostgreSQL 16, MongoDB 8, user `codespace`, sudo = root only). Each portfolio was run once, errors fixed, changed parts re-run.

| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | P1 `04_bulk_generate.sql` | `integer + interval` error stopped the whole generator | Cast the date and add days as an integer | Runs |
| 2 | P1 `04_bulk_generate.sql` | Sales loop was row-by-row (about 7 min) and ingredient stock ran out, so about half the production runs were skipped | Sales rewritten as set-based SQL, bigger weekly batches, 240 days of history plus today's stock | 63k sale lines, 31k sales, 2.4k production runs, stock never negative, P1 about 1 min |
| 3 | P1 `02_constraints_triggers.sql` | FIFO could use ingredient batches not yet received | Added `received_date <= run_date` | Usage after receipt |
| 4 | P1 `05_constraint_tests.sql` | Two `EXCEPTION` blocks in one `DO` caused a syntax error | Merged into one handler | All 10 tests PASSED |
| 5 | P1 `run_p1.sh`, `setup.sh` | Session time zone is UTC in Codespaces | `ALTER DATABASE crumble SET timezone TO 'Africa/Lagos'` | Dates match Lagos |
| 6 | P2 `run_p2.sh` | Queries were run but no EXPLAIN was captured (placeholders only) | New `explain_runner.py`: drops P2 indexes, ANALYZE, EXPLAIN ANALYZE before and after, writes `explain_summary.txt`. Q7 limited to last 90 days | Real before/after times; full-history queries (Q2, Q6, Q8) keep Seq Scan on purpose |
| 7 | P3 `run_p3.sh` | Race, deadlock and isolation demos were manual two-terminal steps | New `run_race_demos.py` runs all six with two real sessions and prints labelled output to `race_demos_output.log` | Oversell shown, then atomic UPDATE, FOR UPDATE, SERIALIZABLE (40001), isolation levels, deadlock and lock-order fix |
| 8 | P3 `01_sell_items.sql` | Stock date used the session time zone | Uses Africa/Lagos date | OK |
| 9 | P4 `01_schema_validation.js` | `$jsonSchema` does not support `const`; `getInfo()` is not a method; int/double types rejected seed documents | `enum: [x]`, `getCollectionInfos`, `bsonType: "number"` | Collections and seeds load |
| 10 | P4 `05_indexes.js` | Index demo ran on 10 documents (no real difference) | Copies 40k oven readings to a normal collection and indexes `{ovenId, temperature}`; summary table printed | COLLSCAN 40,320 docs / 34 ms to IXSCAN 3,396 docs / 7 ms |
| 11 | P4 `06_validation_tests.js` (new) | No proof the validator works | Two bad documents must be REJECTED, one good ACCEPTED | 2 rejected, 1 accepted |
| 12 | P5 `02_replica_setup.sh` | Replica refused to start: `max_wal_senders = 0` is lower than the primary | Set 10 and `max_replication_slots`; restart falls back to `pg_ctlcluster` | Replica streaming |
| 13 | P5 `03_replica_demo.sql` | `\connect -p` form is invalid | One script using positional `\connect`: who is who, row arrives, write rejected on replica, lag, `pg_stat_replication` | Works |
| 14 | P5 `01_partition.sql` | 26 mostly empty partitions, no DEFAULT check | 11 monthly partitions, DEFAULT partition with count (0), one-month query compared with the unpartitioned table | Pruning shown |
| 15 | `setup.sh` | Mongo start fragile; psycopg2 never installed | Start only if not running; psycopg2 install fallback chain and verify | OK |
| 16 | New `runall.sh`, `collect_results.sh` | Many boxes to paste | One file runs P1-P5, commits and pushes each, writes `my_results.txt` | Rehearsed |

Cut for speed: 2 years of data reduced to 240 days (still over 60k sale lines), per-sale exception loop removed, manual two-terminal steps replaced by a script.

Not changed: README still has `[GitHub link]`; it is filled in during documentation.
