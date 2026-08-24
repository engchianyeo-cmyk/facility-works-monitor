\set ON_ERROR_STOP on

-- Minimal empty Supabase-managed contract for disposable fresh-install tests.
-- Application tables deliberately do not exist here; the committed bootstrap
-- must be the first source that creates them.

do $managed_roles$
begin
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'anon') then
    execute 'create role anon nologin noinherit';
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated') then
    execute 'create role authenticated nologin noinherit';
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'create role service_role nologin noinherit bypassrls';
  end if;
end;
$managed_roles$;

create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists realtime;
create schema if not exists storage;

create extension if not exists pgcrypto with schema extensions;

select exists(
  select 1 from pg_catalog.pg_roles where rolname = 'supabase_admin'
) as use_supabase_admin
\gset
\if :use_supabase_admin
\connect postgres supabase_admin
\endif

grant usage on schema public, auth, extensions, storage
  to postgres, anon, authenticated, service_role;

\if :use_supabase_admin
\connect postgres postgres
\endif

do $managed_auth$
begin
  if pg_catalog.to_regclass('auth.users') is null then
    execute $sql$
      create table auth.users (
        id uuid primary key,
        email text,
        created_at timestamptz not null default pg_catalog.now(),
        updated_at timestamptz not null default pg_catalog.now(),
        raw_user_meta_data jsonb not null default '{}'::jsonb
      )
    $sql$;
  end if;

  if exists (select 1 from auth.users) then
    raise exception 'Disposable Supabase prerequisite requires empty auth.users';
  end if;
  if (
    select pg_catalog.count(*)
    from information_schema.columns
    where table_schema = 'auth'
      and table_name = 'users'
      and column_name in ('id', 'email', 'created_at', 'updated_at', 'raw_user_meta_data')
  ) <> 5 then
    raise exception 'Disposable Supabase prerequisite has an incompatible auth.users table';
  end if;

  if pg_catalog.to_regprocedure('auth.uid()') is null then
    execute $sql$
      create function auth.uid()
      returns uuid
      language sql
      stable
      set search_path = pg_catalog
      as $body$
        select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid
      $body$
    $sql$;
  end if;
end;
$managed_auth$;

select exists(
  select 1 from pg_catalog.pg_roles where rolname = 'supabase_auth_admin'
) as use_supabase_auth_owner
\gset
\if :use_supabase_auth_owner
\connect postgres supabase_auth_admin
\endif

revoke all on function auth.uid() from public;
grant execute on function auth.uid() to postgres, anon, authenticated, service_role;
grant all on table auth.users to postgres, service_role;

\if :use_supabase_auth_owner
\connect postgres postgres
\endif

select exists(
  select 1 from pg_catalog.pg_roles where rolname = 'supabase_storage_admin'
) as use_supabase_storage_owner
\gset
\if :use_supabase_storage_owner
\connect postgres supabase_storage_admin
\endif

create table if not exists storage.buckets (
  id text primary key,
  name text not null unique,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists storage.objects (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  bucket_id text not null references storage.buckets(id) on delete cascade,
  name text not null,
  owner_id text,
  metadata jsonb,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique (bucket_id, name)
);

alter table storage.buckets enable row level security;
alter table storage.objects enable row level security;

grant all on table storage.buckets, storage.objects to postgres, service_role;

\if :use_supabase_storage_owner
\connect postgres postgres
\endif
