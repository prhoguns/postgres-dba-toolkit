#!/bin/bash
# Load a realistic amount of data: 200k customers, 1M orders, 2.5M items. Takes about a minute.
set -euo pipefail
psql -v ON_ERROR_STOP=1 -U postgres -d appdb -f /sql/00_schema.sql
psql -v ON_ERROR_STOP=1 -U postgres -d appdb <<'SQL'
truncate order_items, orders, customers, audit_log restart identity cascade;

insert into customers (email, full_name, country, created_at)
select 'user' || i || '@example.com',
       'Customer ' || i,
       (array['CA','US','GB','DE','FR','IN','AU'])[1 + (i % 7)],
       now() - (random() * interval '900 days')
from generate_series(1, 200000) i;

insert into orders (customer_id, status, total_cents, placed_at)
select 1 + (random() * 199999)::bigint,
       (array['pending','paid','paid','paid','shipped','cancelled'])[1 + (random()*5)::int],
       (500 + random() * 50000)::bigint,
       now() - (random() * interval '365 days')
from generate_series(1, 1000000);

insert into order_items (order_id, sku, qty, price_cents)
select 1 + (random() * 999999)::bigint,
       'SKU-' || (1000 + (random()*8999)::int),
       1 + (random()*4)::int,
       (200 + random() * 20000)::bigint
from generate_series(1, 2500000);

analyze;
SQL
psql -U postgres -d appdb -c "select relname, n_live_tup from pg_stat_user_tables order by n_live_tup desc"
SQL_DONE=1
