-- 03_replica_demo.sql - ONE script that switches between PRIMARY (5432) and REPLICA (5433).
-- Everything printed is real output from the two running servers.
\pset pager off
\set ON_ERROR_STOP off
\echo '=== STEP 1: PRIMARY - who am I? ==='
\connect -reuse-previous=off crumble - /var/run/postgresql 5432
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica,
       (SELECT count(*) FROM sale_line) AS sale_lines;
DELETE FROM supplier WHERE name = 'Replica Demo Supplier';

\echo '=== STEP 2: PRIMARY - insert one new row (a marker supplier) ==='
INSERT INTO supplier (name, phone) VALUES ('Replica Demo Supplier', '+2348000000000');
SELECT pg_current_wal_lsn() AS primary_wal_position;
SELECT pg_sleep(1);

\echo '=== STEP 3: REPLICA - who am I? ==='
\connect -reuse-previous=off crumble - /var/run/postgresql 5433
SELECT current_setting('port') AS port, pg_is_in_recovery() AS is_replica,
       (SELECT count(*) FROM sale_line) AS sale_lines;

\echo '=== STEP 4: REPLICA - the new row arrived (read works) ==='
SELECT supplier_id, name FROM supplier WHERE name = 'Replica Demo Supplier';

\echo '=== STEP 5: REPLICA - a WRITE must be rejected (read-only standby) ==='
INSERT INTO supplier (name) VALUES ('Should Fail On Replica');

\echo '=== STEP 6: REPLICA - replication position and lag ==='
SELECT pg_last_wal_replay_lsn() AS replica_replayed_lsn,
       now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_commit;

\echo '=== STEP 7: PRIMARY - replication status and cleanup ==='
\connect -reuse-previous=off crumble - /var/run/postgresql 5432
SELECT application_name, state, sync_state, sent_lsn, replay_lsn, replay_lag FROM pg_stat_replication;
DELETE FROM supplier WHERE name = 'Replica Demo Supplier';
\echo '=== Replica demo finished ==='
