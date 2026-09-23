#!/bin/bash
# Failover drill: confirm the replica is a read-only standby, promote it, confirm it accepts writes.
# Run from the host: bash tests/test_failover.sh
set -euo pipefail
P="docker exec pg-primary psql -U postgres -d appdb -tAX"
R="docker exec pg-replica psql -U postgres -d appdb -tAX"
fail=0

echo "== before"
echo "   primary in_recovery = $($P -c 'select pg_is_in_recovery()')"
echo "   replica in_recovery = $($R -c 'select pg_is_in_recovery()')"
[ "$($R -c 'select pg_is_in_recovery()')" = "t" ] || { echo "   FAIL replica is not in recovery"; exit 1; }

echo "== replication is live"
$P -c "insert into audit_log (actor, action) values ('failover-drill', 'pre-promote')" >/dev/null
sleep 2
n=$($R -c "select count(*) from audit_log where action = 'pre-promote'")
[ "$n" = "1" ] && echo "   PASS row reached the replica" || { echo "   FAIL replica missing the row ($n)"; fail=1; }

echo "== the standby refuses writes"
err=$(docker exec pg-replica psql -U postgres -d appdb -tAX -c "insert into audit_log (actor, action) values ('x','y')" 2>&1 || true)
case "$err" in
  *read-only*) echo "   PASS standby rejected the write: $(printf '%s' "$err" | head -1)" ;;
  *)           echo "   FAIL standby accepted a write (output: $err)"; fail=1 ;;
esac

echo "== promote"
docker exec -u postgres pg-replica pg_ctl -D /var/lib/postgresql/data promote -w -t 60 >/dev/null
sleep 2
[ "$($R -c 'select pg_is_in_recovery()')" = "f" ] && echo "   PASS promoted, no longer in recovery" || { echo "   FAIL still in recovery"; fail=1; }

echo "== the new primary accepts writes"
if $R -c "insert into audit_log (actor, action) values ('failover-drill','post-promote')" >/dev/null 2>&1; then
  echo "   PASS write accepted after promotion"
else
  echo "   FAIL write still rejected"; fail=1
fi
echo "   rows on the new primary: $($R -c 'select count(*) from orders')"
echo
echo "Note: the promoted node is on a new timeline. The old primary cannot follow it without pg_rewind"
echo "or a fresh base backup - which is the part people forget in a real failover."
exit $fail
