begin;

create schema if not exists private;

create or replace function private.is_fmworks_administrator()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles
    where id = (select auth.uid())
      and role = 'administrator'
      and is_active = true
      and deleted_at is null
  );
$$;

revoke all on function private.is_fmworks_administrator() from public, anon;
grant execute on function private.is_fmworks_administrator()
  to authenticated, service_role;

alter table public.technicians enable row level security;

revoke all on table public.technicians from anon;
revoke all on table public.technicians from authenticated;

grant select, insert, update, delete
  on table public.technicians
  to authenticated;

drop policy if exists technicians_read_active_authenticated
  on public.technicians;

create policy technicians_read_active_authenticated
on public.technicians
for select
to authenticated
using (coalesce(active, true) = true);

drop policy if exists technicians_admin_manage
  on public.technicians;

create policy technicians_admin_manage
on public.technicians
for all
to authenticated
using ((select private.is_fmworks_administrator()))
with check ((select private.is_fmworks_administrator()));

alter table public.work_order_number_counters enable row level security;

revoke all on table public.work_order_number_counters from anon;
revoke all on table public.work_order_number_counters from authenticated;

alter function public.next_work_order_number(timestamp with time zone)
  security definer;

alter function public.next_work_order_number(timestamp with time zone)
  set search_path = public, pg_temp;

revoke all
  on function public.next_work_order_number(timestamp with time zone)
  from public, anon;

grant execute
  on function public.next_work_order_number(timestamp with time zone)
  to authenticated, service_role;

commit;

select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and rowsecurity = false
order by tablename;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('technicians', 'work_order_number_counters')
order by table_name, grantee, privilege_type;

select tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('technicians', 'work_order_number_counters')
order by tablename, policyname;

select
  p.proname as function_name,
  p.prosecdef as security_definer,
  p.proacl as privileges
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'next_work_order_number';
