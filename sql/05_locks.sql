-- D5. Who is blocking whom. The query to run at 2 a.m. when the application is timing out.
select
    blocked.pid              as blocked_pid,
    blocked.usename          as blocked_user,
    left(regexp_replace(blocked.query, '\s+', ' ', 'g'), 60) as blocked_query,
    now() - blocked.query_start as blocked_for,
    blocking.pid             as blocking_pid,
    blocking.usename         as blocking_user,
    blocking.state           as blocking_state,
    left(regexp_replace(blocking.query, '\s+', ' ', 'g'), 60) as blocking_query
from pg_stat_activity blocked
join lateral unnest(pg_blocking_pids(blocked.pid)) as bp(pid) on true
join pg_stat_activity blocking on blocking.pid = bp.pid
where cardinality(pg_blocking_pids(blocked.pid)) > 0;
