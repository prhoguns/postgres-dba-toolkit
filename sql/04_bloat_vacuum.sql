-- D4. Dead tuples, bloat estimate and autovacuum behaviour. Bloat is why a table that holds 1 GB of data
-- occupies 4 GB on disk and why queries slow down over time without anything "changing".
select
    relname                                  as table_name,
    n_live_tup                               as live_rows,
    n_dead_tup                               as dead_rows,
    case when n_live_tup > 0 then round(100.0 * n_dead_tup / n_live_tup, 1) end as dead_pct,
    pg_size_pretty(pg_total_relation_size(relid)) as total_size,
    last_vacuum, last_autovacuum, last_analyze, last_autoanalyze,
    vacuum_count, autovacuum_count
from pg_stat_user_tables
order by n_dead_tup desc;
