# Runbook: backup and point-in-time recovery

## Strategy
- **Base backup**: `pg_basebackup` full copy, nightly.
- **WAL archive**: every completed WAL segment copied to `/archive` by `archive_command`.
- Together these allow recovery to any second after the first base backup completes.
- `pg_dump` is also kept for single-table restores; it is a logical export, not a PITR mechanism. Know the difference and say so in an interview.

## Take a backup
```bash
docker exec pg-primary /scripts/backup.sh
```

## Restore to a point in time
```bash
docker exec pg-primary /scripts/pitr_restore.sh "2026-09-22 14:05:00+00"
```
The script copies the newest base backup, sets `restore_command` and `recovery_target_time`,
creates `recovery.signal`, and starts the instance. `recovery_target_action = promote` makes it
read-write once the target is reached.

## Verifying a restore
Never trust a restore you have not queried. Check a row count and a value you know changed after the
target time — it must be absent. `tests/test_pitr.sh` does exactly this and is the proof in the README.

## Things that go wrong
- `archive_command` failing silently fills `pg_wal` and eventually stops the primary. Monitor `pg_stat_archiver.last_failed_time`.
- Restoring onto a data directory that is not empty. The script clears it.
- Forgetting `recovery_target_action`, so the instance sits paused in recovery and nobody notices.
