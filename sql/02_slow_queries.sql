-- D2. Slowest statements by total time (pg_stat_statements). Total time, not mean: a 5 ms query run a million
-- times costs more than a 2 s report run twice. mean_exec_time tells you which one it is.
select
    round(total_exec_time::numeric / 1000, 1)            as total_seconds,
    calls,
    round(mean_exec_time::numeric, 2)                    as mean_ms,
    round(stddev_exec_time::numeric, 2)                  as stddev_ms,
    rows,
    round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) as cache_hit_pct,
    left(regexp_replace(query, '\s+', ' ', 'g'), 110)    as query
from pg_stat_statements
where query not like '%pg_stat_statements%' and calls > 1
order by total_exec_time desc
limit 15;
