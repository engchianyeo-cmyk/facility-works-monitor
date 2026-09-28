create schema if not exists storage;
create table if not exists storage.buckets(
  id text primary key,name text not null,public boolean not null default false,
  file_size_limit bigint,allowed_mime_types text[]
);
create table if not exists storage.objects(
  id uuid primary key default gen_random_uuid(),bucket_id text not null,name text not null,
  metadata jsonb,created_at timestamptz not null default now(),unique(bucket_id,name)
);
