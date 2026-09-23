-- D1. The first thing to run on an unfamiliar server: size, connections, cache hit ratio, oldest transaction,
-- replication lag. If any of these is wrong, fix it before looking at queries.
\echo === database sizes
select datname, pg_size_pretty(pg_database_size(datname)) as size,
       numbackends as connections, xact_commit, xact_rollback,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) as cache_hit_pct
from pg_stat_database where datname not like 'template%' order by pg_database_size(datname) desc;

\echo === connections by state (idle in transaction is the one that hurts)
select state, count(*), max(now() - state_change) as longest
from pg_stat_activity where backend_type = 'client backend' group by 1 order by 2 desc;

\echo === oldest transaction and longest running query
select pid, usename, state, now() - xact_start as xact_age, now() - query_start as query_age,
       left(regexp_replace(query, '\s+', ' ', 'g'), 80) as query
from pg_stat_activity
where backend_type = 'client backend' and xact_start is not null
order by xact_start limit 5;

\echo === replication
select application_name, state, sync_state,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) as replay_behind,
       write_lag, flush_lag, replay_lag
from pg_stat_replication;

\echo === checkpoints and background writer
select checkpoints_timed, checkpoints_req,
       round(100.0 * checkpoints_req / nullif(checkpoints_timed + checkpoints_req, 0), 1) as pct_requested,
       buffers_checkpoint, buffers_clean, buffers_backend
from pg_stat_bgwriter;
