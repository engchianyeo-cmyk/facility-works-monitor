-- Repair preserved Administrator application-profile identity.
begin;

do $preflight$
declare
  target_id constant uuid := '4a8bf9d9-d7f0-482b-8b1c-1d76897bdd50';
  target_auth_email text;
  target_profile public.profiles%rowtype;
begin
  if current_user <> 'postgres' then
    raise exception '0031 must be applied as postgres';
  end if;

  select * into target_profile from public.profiles where id = target_id for update;
  if not found then
    raise exception '0031 refused: expected Administrator profile is missing';
  end if;

  if target_profile.role <> 'administrator'
     or target_profile.is_active is distinct from true
     or target_profile.deleted_at is not null then
    raise exception '0031 refused: target is not the expected active Administrator';
  end if;

  select lower(btrim(email)) into target_auth_email from auth.users where id = target_id;
  if target_auth_email is null then
    raise exception '0031 refused: matching Auth identity or email is missing';
  end if;

  if exists (
    select 1 from public.profiles p
    where p.id <> target_id and p.deleted_at is null
      and lower(btrim(coalesce(p.email, ''))) = target_auth_email
  ) then
    raise exception '0031 refused: Auth email is already assigned to another active profile';
  end if;

  if target_profile.display_name is not null
     and btrim(target_profile.display_name) <> ''
     and lower(btrim(target_profile.display_name)) not in ('pending preserved user', 'ec yeo') then
    raise exception '0031 refused: profile already has a non-placeholder display name';
  end if;

  if target_profile.email is not null
     and btrim(target_profile.email) <> ''
     and lower(btrim(target_profile.email)) <> target_auth_email then
    raise exception '0031 refused: profile has a conflicting email';
  end if;

  update public.profiles
  set display_name = 'EC Yeo', email = target_auth_email, updated_at = pg_catalog.now()
  where id = target_id;
end;
$preflight$;

commit;
