-- D6. Who can do what. Run this before any audit conversation.
\echo === roles
select rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin, rolreplication, rolconnlimit,
       rolvaliduntil
from pg_roles where rolname not like 'pg\_%' order by rolsuper desc, rolname;

\echo === role memberships
select r.rolname as role, m.rolname as member_of
from pg_auth_members am
join pg_roles r on r.oid = am.member
join pg_roles m on m.oid = am.roleid
order by 1;

\echo === table privileges granted to non-owners
select grantee, table_schema, table_name, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema not in ('pg_catalog', 'information_schema') and grantee <> 'postgres'
group by 1, 2, 3 order by 1, 3;

\echo === anything granted to PUBLIC (usually a finding)
select table_schema, table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'PUBLIC' and table_schema not in ('pg_catalog', 'information_schema');
