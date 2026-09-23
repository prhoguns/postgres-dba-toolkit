-- D3. Three index questions in one file: which foreign keys have no index (the classic cause of slow joins and
-- lock storms on delete), which indexes are never used (write overhead for nothing), and which tables are
-- getting sequential scans despite having indexes.
\echo === foreign keys with no supporting index
select c.conrelid::regclass as table_name,
       a.attname            as column_name,
       c.conname            as constraint_name
from pg_constraint c
join lateral unnest(c.conkey) k(attnum) on true
join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
where c.contype = 'f'
  and not exists (
      select 1 from pg_index i
      where i.indrelid = c.conrelid and (i.indkey::smallint[])[0] = k.attnum
  )
order by 1;

\echo === unused indexes (never scanned since stats reset; excludes constraint-backing indexes)
select s.relname as table_name, s.indexrelname as index_name,
       pg_size_pretty(pg_relation_size(s.indexrelid)) as size, s.idx_scan as scans
from pg_stat_user_indexes s
join pg_index i on i.indexrelid = s.indexrelid
where s.idx_scan = 0 and not i.indisunique and not i.indisprimary
order by pg_relation_size(s.indexrelid) desc;

\echo === tables with heavy sequential scans
select relname as table_name, seq_scan, seq_tup_read, idx_scan,
       case when seq_scan + idx_scan = 0 then null
            else round(100.0 * seq_scan / (seq_scan + idx_scan), 1) end as pct_seq,
       n_live_tup
from pg_stat_user_tables
where seq_scan > 0
order by seq_tup_read desc
limit 10;
