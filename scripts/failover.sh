#!/bin/bash
# Promote the replica to primary and verify it accepts writes. Run on the replica container.
set -euo pipefail
echo "[failover] before: in_recovery=$(psql -U postgres -d appdb -tAc 'select pg_is_in_recovery()')"
pg_ctl -D /var/lib/postgresql/data promote -w -t 60
echo "[failover] after:  in_recovery=$(psql -U postgres -d appdb -tAc 'select pg_is_in_recovery()')"
psql -U postgres -d appdb -c "insert into audit_log (actor, action, payload) values ('failover-drill', 'write-after-promote', '{\"ok\": true}') returning id, happened_at"
