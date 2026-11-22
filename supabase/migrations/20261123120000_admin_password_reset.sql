-- M41a (owner, 23 Nov 2026): fmworks.notices@yahoo.com could not sign in, its password was forgotten, and Supabase's
-- recovery email hit its rate limit. The Super-Administrator (any account except an administrator's) and a Facility
-- Administrator (staff of their own facility only) may set a temporary password; the person must choose a new one at
-- the next sign-in. This function checks the authority, marks the change as required and records who did it and why;
-- the server then sets the password itself through the sign-in service. The password is never stored or logged here.
begin;

create or replace function public.admin_require_password_change(p_target_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); target public.profiles%rowtype; v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  if actor is null or actor->>'role' not in ('administrator','facility_administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator or a Facility Administrator may reset a password.'); end if;
  select * into target from public.profiles where id = p_target_id for update;
  if target.id is null or target.deleted_at is not null then return public.work_order_result_error('NOT_FOUND','Person not found.'); end if;
  if target.id = (actor->>'id')::uuid then return public.work_order_result_error('ACCESS_DENIED','Change your own password under Password.'); end if;
  if target.role in ('administrator','facility_administrator') and actor->>'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED','Only the Super-Administrator may reset an administrator''s password.'); end if;
  if target.role = 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED','The Super-Administrator''s password is reset only through the sign-in page or the Supabase dashboard.'); end if;
  if actor->>'role' = 'facility_administrator' and not exists(
       select 1 from public.facility_memberships m where m.profile_id = target.id and m.active
         and m.effective_from <= pg_catalog.now() and (m.effective_to is null or m.effective_to > pg_catalog.now())
         and public.active_facility_member(m.facility_id, 'facility_administrator', (actor->>'id')::uuid)) then
    return public.work_order_result_error('ACCESS_DENIED','A Facility Administrator resets passwords for their own facility''s staff only.'); end if;
  if pg_catalog.length(v_reason) < 3 then return public.work_order_result_error('VALIDATION_ERROR','Give a reason, e.g. "forgot password".'); end if;
  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set password_change_required = true, updated_at = pg_catalog.now() where id = target.id;
  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor->>'id')::uuid, 'user_password_reset_by_administrator', coalesce(actor->>'display_name', actor->>'name'),
    pg_catalog.jsonb_build_object('profile_id', target.id, 'display_name', target.display_name, 'role', target.role, 'reason', v_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'display_name', target.display_name);
end;$function$;
revoke all on function public.admin_require_password_change(uuid, text) from public, anon, service_role;
grant execute on function public.admin_require_password_change(uuid, text) to authenticated;

commit;
