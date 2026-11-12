# Portfolio 5 — Distributed and Cloud Database Exercise

**Maps to course-note Study Session 2** (Distributed Database System:
fragmentation, replication, consistency models, CAP, ACID vs BASE,
§2.1–2.2) and **Study Session 3** (Cloud Database Systems, §3.2). The NDPA
2023 dimension adds the data-privacy angle from Study Session 6.

## Files in this folder

| File | What it does |
|------|--------------|
| `01_partition.sql` | Creates `sale_line_partitioned` partitioned by month (24 monthly partitions + current + next), populates it from the existing `sale_line` joined to `sale` (to get `sale_time`), creates indexes, and runs three `EXPLAIN ANALYZE` queries showing partition pruning (one partition, all partitions, three partitions). |
| `02_replica_setup.sh` | Sets up a streaming read replica on the same Codespaces VM: creates a `replicator` role, configures `wal_level=replica`, `max_wal_senders=10`, prepends trust lines to `pg_hba.conf`, runs `pg_basebackup` from the Unix socket, writes the replica's own `postgresql.conf` (port 5433, `hot_standby=on`), copies `pg_hba.conf` + `pg_ident.conf` from the primary (trust lines at top), `chmod 700` the data dir, starts the replica with `pg_ctl`. |
| `03_replica_demo.sql` | **One psql script** that switches between primary (5432) and replica (5433) with `\connect`. Shows: the replica is in recovery mode; writes to the replica are rejected; reads work; a row inserted on the primary arrives on the replica; a sale inserted on the primary arrives on the replica; cleanup propagates. |
| `04_cloud_architecture.md` | Cloud architecture keeping data inside Nigeria (NDPA 2023), CAP framing per workload, sync vs async trade-offs, and outlets that keep selling when the internet drops (local SQLite POS app + reconciliation via `sell_items()`). |
| `run_p5.sh` | Runs everything in order. |

## Commands (Codespaces)

```bash
bash portfolio-1-database-design/run_p1.sh   # if not already done
bash portfolio-5-distributed-cloud/run_p5.sh
```

To connect to either server manually:

```bash
# primary (read/write)
psql -h /var/run/postgresql -p 5432 -d crumble

# replica (read-only)
psql -h /var/run/postgresql -p 5433 -d crumble
```

## What to screenshot for evidence

1. The list of monthly partitions from `01_partition.sql`.
2. The three `EXPLAIN ANALYZE` outputs showing partition pruning (one
   partition for the month-scoped query, all partitions for the unscoped
   query, three partitions for the 3-month window).
3. The "Verifying replica is in recovery mode" output from
   `02_replica_setup.sh` (must show `t`).
4. The `pg_stat_replication` row on the primary showing the replica
   connected and streaming.
5. From `03_replica_demo.sql`: the rejected `INSERT` on the replica
   (`ERROR: cannot execute INSERT in a read-only transaction`), and the new
   row from the primary visible on the replica in the very next step.

## Suggested git commit

```bash
git add portfolio-5-distributed-cloud
git commit -m "P5: sale_line monthly partitioning + streaming replica + \\connect demo + NDPA cloud architecture"
```

## What this demonstrates

Two distributed-database techniques on the same Crumble Studio dataset:

1. **Declarative partitioning** — `sale_line_partitioned` partitioned by
   month, with monthly partitions covering the 240-day history. `EXPLAIN ANALYZE` shows the
   planner pruning partitions away when the query has a time filter.
2. **Streaming replication** — a primary on port 5432 and a hot-standby read
   replica on port 5433, set up with `pg_basebackup`, run with `pg_ctl`,
   configured through the Unix socket so no password is needed, with the
   replica's own `postgresql.conf`, copies of `pg_hba.conf` / `pg_ident.conf`
   with trust lines at the top, and `chmod 700` on the data dir. The demo
   script uses `psql \connect` to switch servers in one session, proving the
   replica rejects writes and accepts reads, and that primary writes
   propagate.

The cloud-architecture note ties it all together: data residency in Nigeria
for NDPA 2023, async streaming replication for low write latency, a CAP-aligned
choice per workload (CP for stock, AP for offline POS, eventual for the
dashboard), and a local-SQLite POS app so an outlet can keep selling when the
internet drops and reconcile via the `sell_items()` transaction when the link
returns.
