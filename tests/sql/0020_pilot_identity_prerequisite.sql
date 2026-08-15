\set ON_ERROR_STOP on

create table public.account_invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  display_name text not null,
  department text,
  assigned_role text not null,
  is_active boolean not null default true,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.account_invitations enable row level security;

create or replace function public.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  insert into public.profiles(id,display_name,email,department,role,is_active)
  values(new.id,coalesce(new.raw_user_meta_data->>'display_name','Pending'),new.email,null,'reviewer',true)
  on conflict(id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_auth_user();
