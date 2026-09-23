#!/bin/bash
# Point-in-time recovery drill, end to end, with a verifiable outcome.
#
#   1. take a base backup
#   2. insert a row, note the time  -> this row MUST survive
#   3. wait, then insert a second row and DROP a table -> these MUST NOT survive
#   4. restore to the timestamp between them
#   5. assert: first row present, second row absent, dropped table present
#
# A backup you have never restored is not a backup. This is the proof.
set -euo pipefail
PSQL="psql -U postgres -d appdb -tAX"

echo "== 0. set up a throwaway table so the drill can be run repeatedly"
$PSQL -c "delete from audit_log where actor = 'pitr-drill'" >/dev/null
$PSQL -c "drop table if exists pitr_victim" >/dev/null
$PSQL -c "create table pitr_victim as select i as id, md5(i::text) as payload from generate_series(1, 500000) i" >/dev/null
VICTIM_ROWS=$($PSQL -c "select count(*) from pitr_victim")
echo "   pitr_victim: $VICTIM_ROWS rows"

echo "== 1. base backup (from a clean archive, so the drill is repeatable)"
rm -rf /archive/base /archive/0000* /archive/*.history 2>/dev/null || true
$PSQL -c "checkpoint" >/dev/null
/scripts/backup.sh >/dev/null
echo "   $(ls -1d /archive/base/*/ | tail -1)"

echo "== 2. write a row that must survive"
$PSQL -c "insert into audit_log (actor, action) values ('pitr-drill', 'before-target')" >/dev/null
$PSQL -c "select pg_switch_wal()" >/dev/null
sleep 2
TARGET=$($PSQL -c "select now()")
echo "   recovery target: $TARGET"
sleep 2

echo "== 3. damage the database after the target"
$PSQL -c "insert into audit_log (actor, action) values ('pitr-drill', 'after-target')" >/dev/null
$PSQL -c "drop table pitr_victim" >/dev/null
$PSQL -c "select pg_switch_wal()" >/dev/null
echo "   inserted 'after-target' and dropped pitr_victim ($VICTIM_ROWS rows)"
sleep 2

echo "== 4. restore to $TARGET"
/scripts/pitr_restore.sh "$TARGET" >/dev/null 2>&1
R="psql -h 127.0.0.1 -p 5442 -U postgres -d appdb -tAX"

echo "== 5. verify"
fail=0
before=$($R -c "select count(*) from audit_log where action = 'before-target'")
after=$($R -c "select count(*) from audit_log where action = 'after-target'")
items=$($R -c "select count(*) from pitr_victim" 2>/dev/null || echo "MISSING")
[ "$before" = "1" ] && echo "   PASS row written before the target survived" || { echo "   FAIL 'before-target' row count = $before"; fail=1; }
[ "$after" = "0" ] && echo "   PASS row written after the target is absent" || { echo "   FAIL 'after-target' row count = $after"; fail=1; }
[ "$items" = "$VICTIM_ROWS" ] && echo "   PASS dropped table recovered with all $VICTIM_ROWS rows" || { echo "   FAIL pitr_victim = $items, expected $VICTIM_ROWS"; fail=1; }
pg_ctl -D "${RESTORE_DIR:-/var/lib/postgresql/restore}" -m fast stop >/dev/null 2>&1 || true
exit $fail
