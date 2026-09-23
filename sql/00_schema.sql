-- A small OLTP-ish schema with deliberate problems to find later: a missing index on a hot foreign key,
-- a table that will bloat, and a query pattern that forces a sequential scan.
create table if not exists customers (
    customer_id  bigserial primary key,
    email        text not null unique,
    full_name    text not null,
    country      text not null,
    created_at   timestamptz not null default now()
);

create table if not exists orders (
    order_id     bigserial primary key,
    customer_id  bigint not null references customers(customer_id),
    status       text not null check (status in ('pending','paid','shipped','cancelled')),
    total_cents  bigint not null,
    placed_at    timestamptz not null default now()
);
-- Note: no index on orders.customer_id. Deliberate; 03_indexing.sql finds it.

create table if not exists order_items (
    item_id      bigserial primary key,
    order_id     bigint not null references orders(order_id),
    sku          text not null,
    qty          int not null,
    price_cents  bigint not null
);
create index if not exists ix_order_items_order on order_items(order_id);

create table if not exists audit_log (
    id          bigserial primary key,
    happened_at timestamptz not null default now(),
    actor       text not null,
    action      text not null,
    payload     jsonb
);
