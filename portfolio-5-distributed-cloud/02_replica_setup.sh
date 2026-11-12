#!/usr/bin/env bash
# portfolio-5-distributed-cloud/02_replica_setup.sh
# Set up a PostgreSQL streaming read replica on the SAME Codespaces VM.
#
# Topology:
#   primary  -> port 5432 (the default cluster installed by setup.sh)
#   replica  -> port 5433 (a second cluster we create here, read-only)
#
# Codespaces rules followed:
#   * `sudo -u postgres` does NOT work; we use `sudo runuser -u postgres -- ...`
#   * Ubuntu keeps PostgreSQL config in /etc/postgresql/16/main/; the
#     pg_ctl binary is at /usr/lib/postgresql/16/bin/pg_ctl.
#   * TCP logins need a password, so we connect through the Unix socket
#     at /var/run/postgresql. The replica also listens on the Unix socket.
#   * A replica made with pg_basebackup needs its own postgresql.conf, copies
#     of pg_hba.conf and pg_ident.conf, and a data directory with chmod 700.
#   * pg_hba.conf trust lines go at the TOP of the file.
#   * We do NOT use postgres_fdw.
set -euo pipefail

REPLICA_DIR=/var/lib/postgresql/16/replica
REPLICA_PORT=5433
PRIMARY_PORT=5432
PG_BIN=/usr/lib/postgresql/16/bin
PRIMARY_CONF_DIR=/etc/postgresql/16/main

echo "==> [1/9] Create replication role on primary (idempotent)"
if ! sudo runuser -u postgres -- psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='replicator'" | grep -q 1; then
    sudo runuser -u postgres -- psql -c \
        "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replpass';"
fi

echo "==> [2/9] Configure primary: wal_level, max_wal_senders, listen_addresses"
# Use a heredoc with override include so we don't fight the packaged config.
sudo tee "${PRIMARY_CONF_DIR}/conf.d/99-crumble-replication.conf" >/dev/null <<'CONF'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
listen_addresses = 'localhost'
CONF

echo "==> [3/9] Prepend trust lines for replication to primary pg_hba.conf"
# Trust lines MUST go at the top of the file to take effect.
if ! sudo grep -q "^local.*replication.*replicator" "${PRIMARY_CONF_DIR}/pg_hba.conf"; then
    sudo sed -i '1i local   replication   replicator                          trust' "${PRIMARY_CONF_DIR}/pg_hba.conf"
fi
if ! sudo grep -q "^host.*replication.*replicator.*127.0.0.1/32" "${PRIMARY_CONF_DIR}/pg_hba.conf"; then
    sudo sed -i '2i host    replication   replicator   127.0.0.1/32          trust' "${PRIMARY_CONF_DIR}/pg_hba.conf"
fi

echo "==> [4/9] Restart primary to apply wal_level etc."
sudo pg_ctlcluster 16 main restart; sleep 5; sudo runuser -u postgres -- psql -tAc "SELECT pg_reload_conf()"
sleep 2

echo "==> [5/9] Stop any existing replica and wipe the replica data dir"
sudo runuser -u postgres -- "${PG_BIN}/pg_ctl" -D "${REPLICA_DIR}" -m fast stop 2>/dev/null || true
sudo rm -rf "${REPLICA_DIR}"
sudo mkdir -p "${REPLICA_DIR}"
sudo chown postgres:postgres "${REPLICA_DIR}"
sudo chmod 700 "${REPLICA_DIR}"

echo "==> [6/9] pg_basebackup from primary (Unix socket, no password)"
sudo PGPASSWORD=replpass runuser -u postgres -- "${PG_BIN}/pg_basebackup" \
    -h 127.0.0.1 -p "${PRIMARY_PORT}" -U replicator \
    -D "${REPLICA_DIR}" -Fp -Xs -P -R
# -R writes standby.signal + primary_conninfo into postgresql.auto.conf.

echo "==> [7/9] Write replica's own postgresql.conf (Debian layout requires it)"
# pg_basebackup on Debian/Ubuntu does NOT copy postgresql.conf (it lives in
# /etc/, not in the data dir), so we must create one ourselves in the replica
# data dir.
sudo tee "${REPLICA_DIR}/postgresql.conf" >/dev/null <<CONF
# Replica postgresql.conf — Crumble Studio P5
data_directory = '${REPLICA_DIR}'
hba_file       = '${REPLICA_DIR}/pg_hba.conf'
ident_file     = '${REPLICA_DIR}/pg_ident.conf'
external_pid_file = '/var/run/postgresql/16-replica.pid'

port = ${REPLICA_PORT}
listen_addresses = 'localhost'
unix_socket_directories = '/var/run/postgresql'

wal_level = replica
hot_standby = on
max_wal_senders = 10
max_replication_slots = 10
shared_buffers = 128MB
work_mem = 4MB
log_line_prefix = '%m [replica] %u@%d '
CONF

echo "==> [8/9] Copy pg_hba.conf + pg_ident.conf from primary; prepend trust"
sudo cp "${PRIMARY_CONF_DIR}/pg_hba.conf"   "${REPLICA_DIR}/pg_hba.conf"
sudo cp "${PRIMARY_CONF_DIR}/pg_ident.conf" "${REPLICA_DIR}/pg_ident.conf"

# Trust lines at the TOP of the replica's pg_hba.conf so we can connect
# locally without a password (TCP needs a password; Unix socket doesn't).
sudo sed -i '1i local   all   all                            trust' "${REPLICA_DIR}/pg_hba.conf"
sudo sed -i '2i host    all   all   127.0.0.1/32             trust' "${REPLICA_DIR}/pg_hba.conf"

# Make sure data dir is chmod 700 (user explicitly required)
sudo chmod 700 "${REPLICA_DIR}"
sudo chown -R postgres:postgres "${REPLICA_DIR}"

echo "==> [9/9] Start the replica"
sudo runuser -u postgres -- "${PG_BIN}/pg_ctl" \
    -D "${REPLICA_DIR}" -l /var/log/postgresql/replica.log -w start

sleep 2

echo
echo "=================================================="
echo "Streaming replica is up."
echo "  Primary : psql -h /var/run/postgresql -p ${PRIMARY_PORT} -d crumble"
echo "  Replica : psql -h /var/run/postgresql -p ${REPLICA_PORT} -d crumble"
echo "=================================================="
echo "Verifying replica is in recovery mode:"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p "${REPLICA_PORT}" -d crumble -c \
    "SELECT pg_is_in_recovery() AS in_recovery;"

echo "Replication status on primary:"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p "${PRIMARY_PORT}" -d crumble -c \
    "SELECT application_name, state, sync_state, sent_lsn, replay_lsn FROM pg_stat_replication;"
