# PostgreSQL DBA Toolkit

_Status: Built and verified September 22–23, 2026. Every number below came from a real run on this lab._

A working PostgreSQL environment — primary, streaming replica, WAL archive — with the day-to-day
work of a DBA done against it: health and performance diagnostics, index tuning measured before and
after, a point-in-time recovery drill that proves a dropped table comes back, and a failover drill
that promotes the standby. Runbooks explain the reasoning, not just the commands.

```
  [ pg-primary :5440 ] ──WAL archive──▶ /archive ──restore_command──▶ [ restored instance :5442 ]
         │                                                             (PITR drill, promotes at target)
         └──streaming replication (slot: replica_slot)──▶ [ pg-replica :5441, hot standby ]
```

**Stack:** PostgreSQL 16, Docker Compose, `pg_basebackup`, `pg_stat_statements`, bash.
Dataset: 200,000 customers, 1,000,000 orders, 2,500,000 order items (~390 MB).

## The two drills

### Point-in-time recovery — `tests/test_pitr.sh`

Takes a base backup, writes a row, notes the time, then *damages* the database (another row plus a
`DROP TABLE` of 500,000 rows) and recovers to the timestamp in between.

```
== 5. verify
   PASS row written before the target survived
   PASS row written after the target is absent
   PASS dropped table recovered with all 500000 rows
```

A backup nobody has restored is not a backup. This is the proof, and it is repeatable — the drill
cleans up after itself and uses a throwaway table so it can run any number of times.

### Failover — `tests/test_failover.sh`

```
   PASS row reached the replica
   PASS standby rejected the write: ERROR:  cannot execute INSERT in a read-only transaction
   PASS promoted, no longer in recovery
   PASS write accepted after promotion
   rows on the new primary: 1000000
```

The drill ends by pointing out what people forget: the promoted node is on a new timeline, so the
old primary needs `pg_rewind` or a fresh base backup before it can follow.

## Tuning, measured

`sql/03_indexing.sql` flagged the problem without anyone knowing the schema:

```
=== foreign keys with no supporting index
 table_name | column_name |     constraint_name
------------+-------------+-------------------------
 orders     | customer_id | orders_customer_id_fkey
```

After `create index concurrently ix_orders_customer_placed on orders(customer_id, placed_at desc)`:

| query | before | after | change |
|---|---:|---:|---:|
| recent orders for one customer | 24.9 ms | 0.2 ms | **157× faster** |
| 90-day order summary for one country | 125.0 ms | 59.7 ms | 2.1× faster |

`concurrently` matters: the table is never locked against writes, which is the difference between a
maintenance window and a change nobody notices. Full plans in [`results/tuning.md`](results/tuning.md).

## The query library

| File | Question it answers |
|---|---|
| [01_health.sql](sql/01_health.sql) | Sizes, connections by state, cache hit ratio, oldest transaction, replication lag, checkpoint behaviour |
| [02_slow_queries.sql](sql/02_slow_queries.sql) | Slowest statements by **total** time, with call counts and cache hit rate |
| [03_indexing.sql](sql/03_indexing.sql) | Foreign keys with no index, indexes never used, tables taking sequential scans |
| [04_bloat_vacuum.sql](sql/04_bloat_vacuum.sql) | Dead tuples, dead percentage, whether autovacuum is keeping up |
| [05_locks.sql](sql/05_locks.sql) | Who is blocking whom, and for how long |
| [06_permissions.sql](sql/06_permissions.sql) | Roles, memberships, table grants, anything granted to `PUBLIC` |
| [07_capacity.sql](sql/07_capacity.sql) | Table vs index size, index-to-data ratio, growth |

On this dataset, `07_capacity.sql` shows `customers` carrying more index than data (ratio 1.06) —
which is what you would investigate next with `03_indexing.sql`.

## Runbooks

- [Streaming replication](runbooks/01-replication.md) — configuration, daily checks, what to do when the replica falls behind, planned failover, and why an inactive replication slot can fill the primary's disk.
- [Backup and PITR](runbooks/02-backup-and-pitr.md) — strategy, how to restore, how to verify a restore, and the three things that usually go wrong.
- [A query is slow](runbooks/03-performance.md) — the order to work in. Most tickets close before step 4.

## Run it

```bash
git clone https://github.com/prhoguns/postgres-dba-toolkit.git && cd postgres-dba-toolkit
./run_all.sh          # start, seed, diagnose, tune, run both drills (~5 min)
```

Or step by step:

```bash
cd compose && docker compose up -d           # primary :5440, replica :5441
docker exec pg-primary bash /scripts/seed.sh
docker exec pg-primary psql -U postgres -d appdb -Xf /sql/01_health.sql
docker exec -u postgres pg-primary bash /tests/test_pitr.sh
bash tests/test_failover.sh                  # promotes the replica; `down -v` to reset
```

## Things learned the hard way

- Docker named volumes are root-owned, and PostgreSQL refuses to run as root or to use a data
  directory it does not own. The replica bootstrap takes the base backup as root, then `chown`s and
  `exec gosu postgres` to start the server.
- `update-source`-style mistakes have a replication equivalent: without `pg_hba.conf` entries for
  `replication`, `pg_basebackup` fails with a message that does not mention replication at all.
- A restored instance defaults to `recovery_target_timeline = 'latest'`, so a *previous* promotion's
  timeline history in the archive makes recovery pick the wrong timeline and stop before the target.
  Pinning `'current'` fixes it. This one took three failed drills to find.
- Restoring onto the same port as the running primary fails with "address already in use" — obvious
  in hindsight, invisible in the pg_ctl output.

## Next

- `pgBackRest` instead of hand-rolled scripts: retention policies, parallel compression, incremental backups.
- `pg_rewind` in the failover drill so the old primary rejoins without a full base backup.
- Synchronous replication and what it costs in commit latency.
- Connection pooling (PgBouncer) and the difference between session, transaction and statement pooling.
- Prometheus `postgres_exporter` and alert rules for replication lag, long transactions and archive failures.
