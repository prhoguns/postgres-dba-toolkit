#!/bin/bash
# Full base backup of the primary, tarred and labelled with a timestamp. Combined with the WAL archive this
# gives point-in-time recovery to any moment after the backup completes.
#
#   ./scripts/backup.sh            -> archive/base/<timestamp>/
set -euo pipefail
STAMP="${1:-$(date -u +%Y%m%dT%H%M%SZ)}"
DEST="/archive/base/$STAMP"
mkdir -p "$DEST"
echo "[backup] base backup -> $DEST"
PGPASSWORD=postgres pg_basebackup -h primary -U postgres -D "$DEST" -Fp -Xs -P
PGPASSWORD=postgres psql -h primary -U postgres -d appdb -tAc "select now(), pg_current_wal_lsn()" > "$DEST/BACKUP_INFO"
echo "[backup] done: $(du -sh "$DEST" | cut -f1)"
cat "$DEST/BACKUP_INFO"
