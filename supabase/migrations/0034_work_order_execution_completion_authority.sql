-- WP-FMW-020A: separate execution recording from formal completion authority.
-- 0033 remains an independent, intentionally paused migration.
begin;

do $preflight$
declare
  transition_oid oid;
  transition_source text;
  transition_executable text;
  actor_oid oid;
  actor_source text;
  actor_executable text;
  source_to_scan text;
  executable_source text;
  scan_target integer;
  scan_position integer;
  scan_length integer;
  scan_character text;
  scan_state text;
  block_depth integer;
  dollar_tag text;
  literal_content text;
  escape_literal boolean;
  expected_owner name := current_user;
  required_column text;
begin
  if current_user <> 'postgres' then raise exception '0034 must be applied as postgres'; end if;
  select p.oid,p.prosrc into transition_oid,transition_source
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='transition_work_order'
    and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_work_order_id uuid, p_action text, p_payload jsonb';
  if transition_oid is null or (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='transition_work_order'
        and pg_catalog.pg_get_function_identity_arguments(p.oid)='p_work_order_id uuid, p_action text, p_payload jsonb')<>1
    or to_regprocedure('public.work_order_actor()') is null
    or to_regprocedure('public.work_order_result_error(text,text)') is null
    or to_regclass('public.evidence_items') is null
  then raise exception '0034 prerequisite missing'; end if;
  if not exists(select 1 from pg_catalog.pg_proc p where p.oid=transition_oid and p.prosecdef
      and p.proowner=(select oid from pg_catalog.pg_roles where rolname=expected_owner)
      and 'search_path=pg_catalog'=any(p.proconfig)) then
    raise exception '0034 predecessor security/ownership contract mismatch';
  end if;
  if not has_function_privilege('authenticated',transition_oid,'EXECUTE')
    or has_function_privilege('anon',transition_oid,'EXECUTE')
    or has_function_privilege('service_role',transition_oid,'EXECUTE') then
    raise exception '0034 predecessor privilege contract mismatch';
  end if;
  select p.oid,p.prosrc into actor_oid,actor_source
  from pg_catalog.pg_proc p where p.oid='public.work_order_actor()'::regprocedure;
  if not exists(select 1 from pg_catalog.pg_proc p where p.oid=actor_oid and p.prosecdef) then
    raise exception '0034 actor/readiness contract mismatch';
  end if;

  -- Build a canonical executable-token stream from each PL/pgSQL body. This
  -- scanner removes comments and literal contents, but preserves quoted
  -- identifiers and removes whitespace only while in executable-code state.
  -- Consequently comments, messages and dollar-quoted data cannot satisfy a
  -- semantic predecessor assertion.
  for scan_target in 1..2 loop
    source_to_scan := case scan_target when 1 then transition_source else actor_source end;
    executable_source := '';
    scan_position := 1;
    scan_length := pg_catalog.length(source_to_scan);
    scan_state := 'code';
    block_depth := 0;
    dollar_tag := null;
    while scan_position <= scan_length loop
      scan_character := pg_catalog.substr(source_to_scan,scan_position,1);
      if scan_state = 'code' then
        if pg_catalog.substr(source_to_scan,scan_position,2) = '--' then
          scan_state := 'line_comment'; scan_position := scan_position + 2; continue;
        elsif pg_catalog.substr(source_to_scan,scan_position,2) = '/*' then
          scan_state := 'block_comment'; block_depth := 1; scan_position := scan_position + 2; continue;
        elsif scan_character = '''' then
          literal_content := '';
          escape_literal := scan_position > 1
            and pg_catalog.substr(source_to_scan,scan_position-1,1) = 'e';
          scan_state := 'single_quote'; scan_position := scan_position + 1; continue;
        elsif scan_character = '"' then
          literal_content := '';
          scan_state := 'double_quote'; scan_position := scan_position + 1; continue;
        elsif scan_character = '$' then
          dollar_tag := pg_catalog.substring(
            pg_catalog.substr(source_to_scan,scan_position),
            '^(\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$)'
          );
          if dollar_tag is not null then
            literal_content := '';
            scan_state := 'dollar_quote';
            scan_position := scan_position + pg_catalog.length(dollar_tag);
            continue;
          end if;
        end if;
        if scan_character !~ '[[:space:]]' then executable_source := executable_source || pg_catalog.lower(scan_character); end if;
        scan_position := scan_position + 1;
      elsif scan_state = 'line_comment' then
        if scan_character in (E'\n',E'\r') then scan_state := 'code'; end if;
        scan_position := scan_position + 1;
      elsif scan_state = 'block_comment' then
        if pg_catalog.substr(source_to_scan,scan_position,2) = '/*' then
          block_depth := block_depth + 1; scan_position := scan_position + 2;
        elsif pg_catalog.substr(source_to_scan,scan_position,2) = '*/' then
          block_depth := block_depth - 1; scan_position := scan_position + 2;
          if block_depth = 0 then scan_state := 'code'; end if;
        else scan_position := scan_position + 1;
        end if;
      elsif scan_state = 'single_quote' then
        if scan_character = '''' and pg_catalog.substr(source_to_scan,scan_position,2) = '''''' then
          literal_content := literal_content || '''';
          scan_position := scan_position + 2;
        elsif escape_literal and scan_character = E'\\' and scan_position < scan_length then
          literal_content := literal_content || scan_character || pg_catalog.substr(source_to_scan,scan_position+1,1);
          scan_position := scan_position + 2;
        elsif scan_character = '''' then
          executable_source := executable_source || '{s:' || pg_catalog.encode(pg_catalog.convert_to(literal_content,'UTF8'),'hex') || '}';
          scan_state := 'code'; scan_position := scan_position + 1;
        else literal_content := literal_content || scan_character; scan_position := scan_position + 1;
        end if;
      elsif scan_state = 'double_quote' then
        if scan_character = '"' and pg_catalog.substr(source_to_scan,scan_position,2) = '""' then
          literal_content := literal_content || '"'; scan_position := scan_position + 2;
        elsif scan_character = '"' then
          executable_source := executable_source || '{i:' || pg_catalog.encode(pg_catalog.convert_to(literal_content,'UTF8'),'hex') || '}';
          scan_state := 'code'; scan_position := scan_position + 1;
        else literal_content := literal_content || scan_character; scan_position := scan_position + 1;
        end if;
      elsif scan_state = 'dollar_quote' then
        if pg_catalog.substr(source_to_scan,scan_position,pg_catalog.length(dollar_tag)) = dollar_tag then
          executable_source := executable_source || '{d:' || pg_catalog.encode(pg_catalog.convert_to(literal_content,'UTF8'),'hex') || '}';
          scan_state := 'code'; scan_position := scan_position + pg_catalog.length(dollar_tag);
        else literal_content := literal_content || scan_character; scan_position := scan_position + 1;
        end if;
      end if;
    end loop;
    if scan_state not in ('code','line_comment') then
      raise exception '0034 predecessor lexical scan failed';
    end if;
    if scan_target = 1 then transition_executable := executable_source; else actor_executable := executable_source; end if;
  end loop;
  -- Material 0029 contract: lifecycle, completion data/timestamp, durable audit,
  -- notification queue, evidence requirement and terminal protection.
  if transition_executable not like '%previous.statusin({s:636c6f736564},{s:63616e63656c6c6564})%'
    or transition_executable not like '%when{s:636f6d706c657465}then{s:636f6d706c65746564}%'
    or transition_executable not like '%completed_at=casewhenaction={s:636f6d706c657465}%'
    or transition_executable not like '%completion_notes=casewhenaction={s:636f6d706c657465}%'
    or transition_executable not like '%actual_labour_hours=casewhenaction={s:636f6d706c657465}%'
    or transition_executable not like '%{s:776f726b5f6f726465725f}||action%'
    or transition_executable not like '%insertintopublic.notification_outbox%'
    or transition_executable not like '%action={s:636f6d706c657465}andprevious.statusin({s:61737369676e6564},{s:696e5f70726f6772657373})%'
    or transition_executable not like '%e.category={s:6166746572}%'
  then raise exception '0034 predecessor material transition contract mismatch'; end if;
  if actor_executable not like '%whereprofile.id=auth.uid()andpublic.pilot_account_ready(profile.id)%' then
    raise exception '0034 actor/readiness contract mismatch';
  end if;
  if not exists(select 1 from pg_catalog.pg_proc p where p.oid='public.verify_completed_work(uuid,jsonb)'::regprocedure
      and p.prosecdef and 'search_path=pg_catalog'=any(p.proconfig))
    or to_regprocedure('public.pilot_account_ready(uuid)') is null
    or to_regprocedure('public.protect_profile_authorization_fields()') is null then
    raise exception '0034 protected authorization prerequisite mismatch';
  end if;
  foreach required_column in array array['id','status','completion_notes','actual_labour_hours','completed_at','reviewed_at','updated_at'] loop
    if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='work_orders' and column_name=required_column) then
      raise exception '0034 missing work_orders column: %',required_column;
    end if;
  end loop;
  foreach required_column in array array['id','work_order_id','category','deleted_at','uploaded_at'] loop
    if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='evidence_items' and column_name=required_column) then
      raise exception '0034 missing evidence_items column: %',required_column;
    end if;
  end loop;
  if to_regprocedure('public.record_work_order_execution(uuid,jsonb)') is not null then
    raise exception '0034 conflicting state: work-record function already exists';
  end if;
  if to_regprocedure('public.transition_work_order_0034_core(uuid,text,jsonb)') is not null then
    raise exception '0034 conflicting state: protected core function already exists';
  end if;
end;
$preflight$;

-- Retain the proven transition implementation behind a non-callable internal name.
alter function public.transition_work_order(uuid,text,jsonb)
  rename to transition_work_order_0034_core;
revoke all on function public.transition_work_order_0034_core(uuid,text,jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.record_work_order_execution(
  p_work_order_id uuid,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
  work_performed text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes','')), '');
  requested_hours numeric;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status in ('completed','reviewed','closed','cancelled') then
    return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Execution cannot be changed after formal completion or cancellation.');
  end if;
  if previous.status not in ('assigned','in_progress') then
    return public.work_order_result_error('INVALID_TRANSITION', 'Work may be recorded only for an assigned or In Progress Work Order.');
  end if;
  if actor_role <> 'administrator'
    and not (actor_role='technician' and actor_id=previous.assigned_technician_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned Technician or an Administrator may record work performed.');
  end if;

  begin requested_hours := nullif(p_payload ->> 'actual_labour_hours','')::numeric;
  exception when invalid_text_representation or numeric_value_out_of_range then
    return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
  end;
  if work_performed is null or requested_hours is null or requested_hours < 0 then
    return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
  end if;
  if previous.actual_labour_hours is not null and requested_hours < previous.actual_labour_hours then
    return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED', 'Cumulative labour hours cannot be lower than the previously recorded total.');
  end if;

  update public.work_orders set
    completion_notes=work_performed,
    actual_labour_hours=requested_hours,
    updated_at=pg_catalog.now()
  where id=previous.id returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,result.id,'work_order_execution_recorded',previous.status,previous.status,actor_name,
    pg_catalog.jsonb_build_object(
      'work_performed',result.completion_notes,
      'cumulative_labour_hours',result.actual_labour_hours,
      'recorded_by',actor_id,
      'recorded_at',pg_catalog.now(),
      'status_unchanged',true
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'status_unchanged',true);
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Work execution data is invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work execution could not be recorded.');
end;
$function$;

create or replace function public.transition_work_order(
  p_work_order_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_role text;
  existing public.work_orders%rowtype;
  active_after_id uuid;
begin
  if pg_catalog.lower(coalesce(p_action,'')) <> 'complete' then
    return public.transition_work_order_0034_core(p_work_order_id,p_action,p_payload);
  end if;
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  actor_role := actor ->> 'role';
  if actor_role <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Administrator authority is required to mark a Work Order Completed.');
  end if;

  select * into existing from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if existing.status in ('closed','cancelled') then
    return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.');
  end if;
  if existing.status='completed' then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(existing));
  end if;
  if existing.status not in ('assigned','in_progress') then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only assigned or In Progress work can be marked Completed.');
  end if;
  if nullif(pg_catalog.btrim(coalesce(existing.completion_notes,'')),'') is null
    or existing.actual_labour_hours is null or existing.actual_labour_hours < 0 then
    return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED', 'Save a work-performed statement and cumulative non-negative labour hours before marking this Work Order Completed.');
  end if;

  select e.id into active_after_id
  from public.evidence_items e
  where e.work_order_id=existing.id and e.category='after' and e.deleted_at is null
  order by e.uploaded_at,e.id limit 1 for share;
  if active_after_id is null then
    return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED', 'Upload active After photo or PDF evidence before marking this Work Order Completed.');
  end if;

  return public.transition_work_order_0034_core(
    p_work_order_id,
    'complete',
    pg_catalog.jsonb_build_object(
      'completion_notes',existing.completion_notes,
      'actual_labour_hours',existing.actual_labour_hours
    )
  );
end;
$function$;

revoke all on function public.record_work_order_execution(uuid,jsonb) from public,anon,service_role;
grant execute on function public.record_work_order_execution(uuid,jsonb) to authenticated;
revoke all on function public.transition_work_order(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.transition_work_order(uuid,text,jsonb) to authenticated;

do $postconditions$
declare config text[]; function_name text; expected_authenticated boolean;
begin
  select proconfig into config from pg_proc where oid='public.record_work_order_execution(uuid,jsonb)'::regprocedure and prosecdef;
  if config is null or not ('search_path=pg_catalog'=any(config)) then raise exception '0034 work-record security postcondition failed'; end if;
  select proconfig into config from pg_proc where oid='public.transition_work_order(uuid,text,jsonb)'::regprocedure and prosecdef;
  if config is null or not ('search_path=pg_catalog'=any(config)) then raise exception '0034 transition security postcondition failed'; end if;
  for function_name,expected_authenticated in select * from (values
    ('public.transition_work_order_0034_core(uuid,text,jsonb)',false),
    ('public.record_work_order_execution(uuid,jsonb)',true),
    ('public.transition_work_order(uuid,text,jsonb)',true)
  ) as expected(function_name,expected_authenticated) loop
    if exists(select 1 from pg_catalog.pg_proc p,
        lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
        where p.oid=pg_catalog.to_regprocedure(function_name) and acl.grantee=0 and acl.privilege_type='EXECUTE')
      or has_function_privilege('anon',function_name,'EXECUTE')
      or has_function_privilege('service_role',function_name,'EXECUTE')
      or has_function_privilege('authenticated',function_name,'EXECUTE')<>expected_authenticated then
      raise exception '0034 grant postcondition failed: %',function_name;
    end if;
  end loop;
end;
$postconditions$;

commit;
