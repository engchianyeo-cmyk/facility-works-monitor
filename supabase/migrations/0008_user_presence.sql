-- Lightweight authenticated-user presence tracking.
-- REVIEW ONLY: apply after the live authentication reconciliation migration.
-- This migration does not expose Auth sessions or sensitive authentication data.

begin;

alter table public.profiles
  add column if not exists last_active_at timestamptz,
  add column if not exists last_seen_route text;

create index if not exists profiles_last_active_at_idx
  on public.profiles (last_active_at desc)
  where is_active = true and deleted_at is null;

create or replace function public.record_user_presence(
  presence_route text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  safe_route text;
  profile_updated boolean;
begin
  if auth.uid() is null then
    return false;
  end if;

  safe_route := case
    when left(trim(coalesce(presence_route, '')), 1) = '/'
      then left(split_part(trim(presence_route), '?', 1), 200)
    else null
  end;

  update public.profiles
  set
    last_active_at = now(),
    last_seen_route = coalesce(safe_route, last_seen_route)
  where id = auth.uid()
    and is_active = true
    and deleted_at is null
    and (
      last_active_at is null
      or last_active_at < now() - interval '90 seconds'
      or (
        safe_route is not null
        and last_seen_route is distinct from safe_route
      )
    );

  profile_updated := found;
  return profile_updated;
end;
$$;

revoke all on function public.record_user_presence(text) from public;
grant execute on function public.record_user_presence(text) to authenticated;

commit;

-- Validation:
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name = 'profiles'
--   and column_name in ('last_active_at', 'last_seen_route');
--
-- select to_regprocedure('public.record_user_presence(text)');
