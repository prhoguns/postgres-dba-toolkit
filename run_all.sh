#!/usr/bin/env bash
# Bring the lab up, seed it, run the diagnostics, and execute both drills. About 5 minutes from cold.
set -euo pipefail
cd "$(dirname "$0")"

# The WAL archive is a bind mount; the container's postgres user (uid 999) must be able to write to it.
mkdir -p archive results && chmod 777 archive results

echo "### starting primary + replica"
(cd compose && docker compose up -d)
until docker exec pg-primary psql -U postgres -d appdb -tAc "select count(*) from pg_stat_replication" 2>/dev/null | grep -q '^1$'; do sleep 5; done
echo "    replication is streaming"

echo "### seeding (200k customers, 1M orders, 2.5M items)"
docker exec pg-primary bash /scripts/seed.sh >/dev/null
docker exec pg-primary psql -U postgres -d appdb -c "create extension if not exists pg_stat_statements" >/dev/null

echo "### diagnostics -> results/"
mkdir -p results
for f in compose/../sql/0*.sql; do
  n=$(basename "$f" .sql)
  case "$n" in 00_schema) continue;; esac
  docker exec pg-primary psql -U postgres -d appdb -Xf "/sql/$(basename "$f")" > "results/$n.txt" 2>&1 || true
  echo "    $n"
done

echo "### tuning demo (before/after index)"
docker exec pg-primary bash /scripts/tuning_demo.sh >/dev/null

echo "### drill: point-in-time recovery"
docker exec -u postgres pg-primary bash /tests/test_pitr.sh 2>&1 | grep -vE "^ *[0-9]+/|waiting for checkpoint" | tee results/pitr_drill.txt

echo "### drill: failover"
bash tests/test_failover.sh | tee results/failover_drill.txt

echo
echo "Done. Results in results/. Note the failover drill promotes the replica;"
echo "run 'cd compose && docker compose down -v && docker compose up -d' to reset the lab."
