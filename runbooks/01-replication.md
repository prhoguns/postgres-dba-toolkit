# Runbook: streaming replication

## What is configured
`wal_level=replica`, a physical replication slot (`replica_slot`) so the primary keeps WAL the replica still
needs, and `hot_standby=on` so the replica serves read-only queries. The replica is built with
`pg_basebackup -R`, which writes `standby.signal` and `primary_conninfo` for you.

## Daily checks
```sql
-- on the primary
select application_name, state, sync_state,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as replay_behind, replay_lag
from pg_stat_replication;

-- on the replica
select pg_is_in_recovery(), now() - pg_last_xact_replay_timestamp() as lag;
```
`state` should be `streaming`. Lag over a few seconds on an idle system means something is wrong.

## Replica falls behind
1. Is it disk, CPU, or network? `replay_lag` high with `write_lag` low means the replica cannot apply fast enough.
2. A long read query on the replica can block replay (`max_standby_streaming_delay`). Check `pg_stat_activity` there.
3. If the slot is retaining too much WAL, `select slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) from pg_replication_slots;` — an inactive slot will fill the primary's disk. That is the main risk of slots.

## Planned failover
```bash
docker exec pg-replica /scripts/failover.sh     # pg_ctl promote
```
Then repoint the application, and rebuild the old primary as a new replica (`pg_rewind` or a fresh base backup).
A promoted replica cannot go back to being a standby without one of those.
