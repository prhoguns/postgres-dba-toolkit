-- D7. Capacity and growth: table sizes with index overhead, and how much of each table is index rather than data.
-- An index-to-data ratio above 1 usually means indexes nobody uses (see D3).
select
    relname                                              as table_name,
    pg_size_pretty(pg_total_relation_size(relid))        as total,
    pg_size_pretty(pg_relation_size(relid))              as table_data,
    pg_size_pretty(pg_indexes_size(relid))               as indexes,
    round(pg_indexes_size(relid)::numeric / nullif(pg_relation_size(relid), 0), 2) as index_to_data_ratio,
    n_live_tup                                           as rows
from pg_stat_user_tables
order by pg_total_relation_size(relid) desc;
