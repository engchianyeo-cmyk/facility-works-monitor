-- Repair the preserved Administrator application-profile identity.
--
-- This migration is intentionally narrow:
-- * it repairs only the known preserved Administrator profile;
-- * it derives the email from the matching Supabase Auth identity;
-- * it does not alter role, activation, deletion or password state;
-- * it uses the same guarded Administrator-operation context used by the
--   audited profile-management RPCs, and records an explicit audit entry.
--
-- The earlier revision of this migration attempted a direct profile update.
-- protect_profile_authorization_fields() correctly rejected that operation.
-- This revision preserves that protection rather than disabling the trigger.

begin;

do $repair$
declare
  target_id constant uuid := '4a8bf9d9-d7f0-482b-8b1c-1d76897bdd50';
  target_auth_email text;
  target_profile public.profiles%rowtype;
  repaired_profile public.profiles%rowtype;
begin
  if current_user <> 'postgres' then
    raise exception '0031 must be applied as postgres';
  end if;

  select *
  into target_profile
  from public.profiles
  where id = target_id
  for update;

  if not found then
    raise exception '0031 refused: expected Administrator profile is missing';
  end if;

  if target_profile.role <> 'administrator'
     or target_profile.is_active is distinct from true
     or target_profile.deleted_at is not null then
    raise exception '0031 refused: target is not the expected active Administrator';
  end if;

  select lower(btrim(email))
  into target_auth_email
  from auth.users
  where id = target_id;

  if target_auth_email is null or target_auth_email = '' then
    raise exception '0031 refused: matching Auth identity or email is missing';
  end if;

  if target_auth_email <> 'engchian.yeo@gmail.com' then
    raise exception '0031 refused: matching Auth identity has an unexpected email';
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.id <> target_id
      and p.deleted_at is null
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

  -- protect_profile_authorization_fields() permits cross-profile changes only
  -- inside the established audited Administrator-operation context. The
  -- existing admin_update_profile/admin_finalize_provisioned_profile RPCs use
  -- this exact transaction-local guard before their protected profile writes.
  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);

  update public.profiles
  set
    display_name = 'EC Yeo',
    email = target_auth_email
  where id = target_id
  returning * into repaired_profile;

  if repaired_profile.id is null
     or repaired_profile.display_name <> 'EC Yeo'
     or lower(btrim(coalesce(repaired_profile.email, ''))) <> target_auth_email
     or repaired_profile.role <> target_profile.role
     or repaired_profile.is_active is distinct from target_profile.is_active
     or repaired_profile.deleted_at is distinct from target_profile.deleted_at
     or repaired_profile.password_change_required is distinct from target_profile.password_change_required then
    raise exception '0031 refused: repaired profile failed post-update invariants';
  end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    target_id,
    'user_admin_profile_updated',
    'Administrator identity reconciliation',
    pg_catalog.jsonb_build_object(
      'migration', '0031_administrator_profile_identity_repair',
      'repair', 'preserved_administrator_identity',
      'target_profile_id', target_id,
      'previous_display_name', target_profile.display_name,
      'display_name', repaired_profile.display_name,
      'previous_email', target_profile.email,
      'email', repaired_profile.email,
      'role_unchanged', repaired_profile.role,
      'is_active_unchanged', repaired_profile.is_active,
      'password_change_required_unchanged', repaired_profile.password_change_required
    )::text
  );
end;
$repair$;

commit;
