begin;

do $uat$
declare
  target_approver uuid;
begin
  perform pg_catalog.set_config('fmworks.password_change_completion', 'on', true);
  update public.profiles
  set password_change_required = false,
      updated_at = pg_catalog.now()
  where email = 'sctpec2413@gmail.com'
    and role = 'approver'
    and is_active
    and deleted_at is null
  returning id into target_approver;

  if target_approver is null then
    raise exception 'Preview UAT Approver account prerequisite missing';
  end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values (
    target_approver,
    'uat_approver_account_readied',
    'Preview UAT remediation',
    'Preview-only Approver identity enabled for authenticated Release-1 financial approval verification.'
  );
end;
$uat$;

commit;
