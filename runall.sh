#!/usr/bin/env bash
# runall.sh - run Portfolios 1-5 in order, commit + push each, then collect results.
# Usage (from your repo folder):  bash runall.sh        (or: bash runall.sh 3  to resume from P3)
set -uo pipefail
START="${1:-1}"
REPO="$(git rev-parse --show-toplevel)"; cd "$REPO"
# 1. find the kit (restore it from the zip if the Codespace restarted)
K="$(find ~/kit -maxdepth 2 -name 'portfolio-1-*' -type d 2>/dev/null | head -1 | xargs -r dirname)"
if [ -z "$K" ]; then
  Z="$(ls "$REPO"/*FIXED*.zip 2>/dev/null | head -1)"; [ -n "$Z" ] || { echo "!!! no kit and no *FIXED*.zip in the repo - send Joseph a screenshot"; exit 1; }
  mkdir -p ~/kit && unzip -oq "$Z" -d ~/kit
  K="$(find ~/kit -maxdepth 2 -name 'portfolio-1-*' -type d | head -1 | xargs -r dirname)"
fi
echo "Kit: $K"
cp -f "$K/collect_results.sh" "$K/CHANGES.md" "$K/README.md" . 2>/dev/null; cp -rf "$K/docs" . 2>/dev/null
# 2. start the databases if the Codespace slept
sudo pg_ctlcluster 16 main start 2>/dev/null || sudo systemctl start postgresql@16-main 2>/dev/null || true
pgrep -x mongod >/dev/null || { sudo mkdir -p /data/db /var/log/mongodb; sudo mongod --dbpath /data/db --bind_ip 127.0.0.1 --fork --logpath /var/log/mongodb/mongod.log >/dev/null 2>&1 || sudo service mongod start || true; }
sleep 3
if ! psql -d crumble -c 'SELECT 1' >/dev/null 2>&1; then echo "Database missing - running setup.sh"; bash "$K/setup.sh" 2>&1 | tee setup_output.log; fi
python3 -c 'import psycopg2' 2>/dev/null || pip install --user psycopg2-binary 2>/dev/null || pip install --break-system-packages psycopg2-binary 2>/dev/null || sudo apt-get install -y python3-psycopg2
python3 -c 'import psycopg2' || { echo "!!! psycopg2 missing - send Joseph this message"; exit 1; }
# 3. run each portfolio
N=0
for F in portfolio-1-database-design portfolio-2-query-optimisation portfolio-3-transactions-concurrency portfolio-4-nosql portfolio-5-distributed-cloud; do
  N=$((N+1)); [ "$N" -lt "$START" ] && continue
  echo; echo "=================== P$N: $F ==================="
  rm -rf "$REPO/$F"; cp -r "$K/$F" "$REPO/$F"
  ( cd "$REPO/$F" && bash "run_p$N.sh" ) 2>&1 | tee "$REPO/$F/p${N}_output.log"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "!!! P$N FAILED - send Joseph $F/p${N}_output.log"; exit 1; fi
  git add "$F" >/dev/null 2>&1; git commit -qm "P$N: $F - scripts and real run output" >/dev/null 2>&1; git push -q 2>&1 | tail -1
done
bash collect_results.sh && { code my_results.txt 2>/dev/null || cat my_results.txt | head -20; }
echo "DONE - copy ALL of my_results.txt (Ctrl+A, Ctrl+C) and send it to Joseph."
