# Runbook: a query is slow

Work in this order. Most "database is slow" tickets are resolved before step 4.

1. **Is it the database?** `sql/01_health.sql` — connections, cache hit ratio, longest transaction, replication.
   A cache hit ratio below ~95 % on an OLTP system means the working set no longer fits in `shared_buffers`.
2. **Is one statement responsible?** `sql/02_slow_queries.sql` ranks by *total* time. A 5 ms query called a
   million times costs more than a 2 s report run twice.
3. **Is it blocked rather than slow?** `sql/05_locks.sql`. `idle in transaction` sessions hold locks and stop autovacuum.
4. **Is there an index?** `sql/03_indexing.sql` lists foreign keys with no index, unused indexes, and tables
   taking sequential scans. Then `explain (analyze, buffers)` the statement itself and compare estimated vs actual rows —
   a large gap means the planner has bad statistics, so `analyze` the table.
5. **Is the table bloated?** `sql/04_bloat_vacuum.sql`. High dead-tuple percentage with an old `last_autovacuum`
   means autovacuum is not keeping up; lower `autovacuum_vacuum_scale_factor` for that table rather than
   running manual vacuums forever.
6. **Only then** consider configuration: `work_mem` for sorts spilling to disk, `shared_buffers`, `effective_cache_size`.
