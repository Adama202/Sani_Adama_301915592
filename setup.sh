#!/usr/bin/env bash
# setup.sh - install and start PostgreSQL 16 and MongoDB 8 in a Codespaces
# (Ubuntu) environment. Idempotent: safe to re-run.
#
# Codespaces notes followed:
#   * `sudo -u postgres` does NOT work (codespace user can only sudo as root);
#     we use `sudo runuser -u postgres -- ...` instead.
#   * TCP logins need a password, so all psql connections go through the Unix
#     socket at /var/run/postgresql.
#   * The yarn.list apt source breaks apt-get update on Codespaces, so we
#     remove it first.
set -euo pipefail

echo "==> [1/6] Removing broken yarn apt source (Codespaces quirk)"
sudo rm -f /etc/apt/sources.list.d/yarn.list

echo "==> [2/6] Installing PostgreSQL 16 and MongoDB 8"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg lsb-release \
    postgresql-16 postgresql-client-16

# MongoDB 8 official repo (Ubuntu 24.04 noble)
if ! dpkg -l | grep -q mongodb-server-8.0; then
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
        sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
        sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y mongodb-org
fi

echo "==> [3/6] Starting PostgreSQL 16"
sudo systemctl enable --now postgresql@16-main 2>/dev/null || sudo pg_ctlcluster 16 main start || true

echo "==> [4/6] Starting MongoDB 8"
if ! pgrep -x mongod >/dev/null; then
    sudo systemctl enable --now mongod 2>/dev/null || sudo service mongod start 2>/dev/null || \
        (sudo mkdir -p /data/db /var/log/mongodb && sudo mongod --dbpath /data/db --bind_ip 127.0.0.1 --fork --logpath /var/log/mongodb/mongod.log)
fi
sleep 3

echo "==> [5/6] Creating PostgreSQL role + database for the codespace user"
# Trust auth on the local socket: the codespace user can connect as themselves.
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user) THEN
        -- no-op: we will create role from outside
    END IF;
END $$;
SQL

# Create a role matching the codespace user so `psql` works with no flags.
CODESPACE_USER="$(whoami)"
if ! sudo runuser -u postgres -- psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${CODESPACE_USER}'" | grep -q 1; then
    sudo runuser -u postgres -- psql -c \
        "CREATE ROLE \"${CODESPACE_USER}\" WITH SUPERUSER LOGIN;"
fi

sudo runuser -u postgres -- psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='crumble'" | grep -q 1 || \
    sudo runuser -u postgres -- createdb -O "${CODESPACE_USER}" crumble

sudo runuser -u postgres -- psql -c "ALTER DATABASE crumble SET timezone TO 'Africa/Lagos'"

echo "==> [6/6] Creating MongoDB database + Python driver for P3"
mongosh --quiet --eval 'db = db.getSiblingDB("crumble"); db.init.insertOne({ok:1});' || true

# psycopg2 is needed by P3 (two real database sessions). Try several ways, then verify.
python3 -c 'import psycopg2' 2>/dev/null || pip install psycopg2-binary 2>/dev/null \
  || pip install --user psycopg2-binary 2>/dev/null \
  || pip install --break-system-packages psycopg2-binary 2>/dev/null \
  || pip install --user --break-system-packages psycopg2-binary 2>/dev/null \
  || sudo apt-get install -y python3-psycopg2 || true
python3 -c 'import psycopg2; print("psycopg2 OK")'

echo
echo "=================================================="
echo "Setup complete."
echo "  PostgreSQL 16 : psql -d crumble"
echo "  MongoDB 8     : mongosh crumble"
echo "=================================================="
