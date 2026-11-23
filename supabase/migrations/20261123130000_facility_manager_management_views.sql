-- M41b (owner, 23 Nov 2026): the Facility Manager sees the management views a Supervisor sees.
-- The Facility Manager role was added after the SLA, reporting, incident, asset and planned-maintenance rules were
-- written; those rules still named only the Approver, Supervisor and Administrator, so the Facility Manager was sent
-- away from SLA and Exports and saw less than his Supervisors. Each rule below is restated with the Facility Manager
-- added and nothing else changed. The Staffing rules are left as they are (that page is being retired, D-78).
begin;

do $m$
declare
  v_policy record; v_fn record; v_def text; v_using text; v_check text; n_policies int := 0; n_functions int := 0;
  v_old_a constant text := '''approver''::text, ''supervisor''::text, ''administrator''::text';
  v_new_a constant text := '''approver''::text, ''supervisor''::text, ''facility_manager''::text, ''administrator''::text';
begin
  for v_policy in
    select tablename, policyname, qual, with_check from pg_policies
    where schemaname = 'public' and (tablename, policyname) in (
      ('ai_prompt_versions','ai_prompts_management_read'), ('asset_systems','asset_systems_authenticated_read'),
      ('assets','assets_authenticated_read'), ('escalation_matrix_steps','escalation_matrix_steps_management_read'),
      ('incidents','incidents_authenticated_read'), ('maintenance_requirements','maintenance_requirements_read'),
      ('pm_occurrences','pm_occurrences_read'), ('profiles','profiles_active_technicians_for_assigners'),
      ('report_runs','report_runs_management_read'), ('report_schedules','report_schedules_management_read'),
      ('service_categories','service_categories_management_read'), ('sla_agreement_versions','sla_agreement_versions_management_read'),
      ('sla_agreements','sla_agreements_management_read'), ('sla_documents','sla_documents_management_read'),
      ('sla_escalation_events','sla_escalation_events_management_read'), ('sla_extraction_proposals','sla_extraction_proposals_management_read'),
      ('sla_rules','sla_rules_management_read'), ('work_order_sla_clocks','work_order_sla_clocks_management_read'))
  loop
    v_using := replace(v_policy.qual, v_old_a, v_new_a);
    v_check := replace(v_policy.with_check, v_old_a, v_new_a);
    if v_using is distinct from v_policy.qual or v_check is distinct from v_policy.with_check then
      execute format('alter policy %I on public.%I', v_policy.policyname, v_policy.tablename)
        || case when v_using is not null then format(' using (%s)', v_using) else '' end
        || case when v_check is not null then format(' with check (%s)', v_check) else '' end;
      n_policies := n_policies + 1;
    end if;
  end loop;

  for v_fn in
    select p.oid from pg_proc p join pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.proname in ('create_report_schedule','create_sla_document','get_incident_operations',
      'incident_evidence_mutation_permitted','link_work_order_to_incident','record_ai_operation','record_sla_extraction',
      'set_sla_document_parser_result','set_work_order_asset')
  loop
    v_def := pg_get_functiondef(v_fn.oid);
    v_def := replace(replace(replace(v_def,
      '''approver'',''supervisor'',''administrator''', '''approver'',''supervisor'',''facility_manager'',''administrator'''),
      '''approver'', ''supervisor'', ''administrator''', '''approver'', ''supervisor'', ''facility_manager'', ''administrator'''),
      '''approver'',''supervisor'',''administrator'',', '''approver'',''supervisor'',''facility_manager'',''administrator'',');
    if v_def is distinct from pg_get_functiondef(v_fn.oid) then execute v_def; n_functions := n_functions + 1; end if;
  end loop;

  if n_policies <> 18 or n_functions <> 9 then
    raise exception 'M41b expected 18 read rules and 9 functions to change, found % and %', n_policies, n_functions;
  end if;
end;
$m$;

commit;
