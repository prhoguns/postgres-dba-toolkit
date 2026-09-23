#!/bin/bash
# Point-in-time recovery drill: restore the newest base backup and replay WAL up to a target timestamp,
# then start the restored instance read-write on port 5442 so the result can be verified.
#
#   ./scripts/pitr_restore.sh "2026-09-22 14:05:00+00"
#
# This is the drill that matters: a backup you have never restored is not a backup.
set -euo pipefail
TARGET="${1:?usage: pitr_restore.sh '<timestamp with tz>'}"
BASE=$(ls -1d /archive/base/*/ | sort | tail -1)
RESTORE=${RESTORE_DIR:-/var/lib/postgresql/restore}  # inside the container, owned by postgres

echo "[pitr] base backup:  $BASE"
echo "[pitr] recovery to:  $TARGET"
rm -rf "${RESTORE:?}"/* 2>/dev/null || true
mkdir -p "$RESTORE"
cp -a "$BASE"/. "$RESTORE"/
rm -f "$RESTORE/postmaster.pid" "$RESTORE/BACKUP_INFO"
chmod 700 "$RESTORE"

cat >> "$RESTORE/postgresql.conf" <<CONF
restore_command = 'cp /archive/%f %p'
recovery_target_time = '$TARGET'
recovery_target_action = 'promote'
# Follow the timeline the base backup was taken on. Without this, a previous promotion's timeline
# history in the archive makes recovery pick timeline 2 and run out of WAL before the target.
recovery_target_timeline = 'current'
archive_mode = off
port = 5442
CONF
touch "$RESTORE/recovery.signal"

echo "[pitr] starting recovery"
pg_ctl -D "$RESTORE" -l /tmp/restore.log -w -t 120 start
echo "[pitr] recovered. in_recovery=$(psql -h 127.0.0.1 -p 5442 -U postgres -d appdb -tAc 'select pg_is_in_recovery()')"
