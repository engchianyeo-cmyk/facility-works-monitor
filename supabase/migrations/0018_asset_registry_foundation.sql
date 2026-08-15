-- WP-ASSET-001A: governed Asset Registry foundation.
-- LOCAL CANDIDATE ONLY. A Preview fingerprint and asset_id reconciliation remain mandatory.
begin;

do $preflight$
begin
  if to_regclass('public.work_orders') is null
    or to_regclass('public.incidents') is null
    or to_regclass('public.activity_logs') is null
    or to_regprocedure('public.work_order_actor()') is null
    or to_regprocedure('public.create_incident(jsonb)') is null then
    raise exception '0018 prerequisite missing: Release 1.2 operational contract';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='work_orders'
      and column_name='asset_id' and data_type='uuid'
  ) then
    raise exception '0018 prerequisite mismatch: work_orders.asset_id must be uuid';
  end if;
  if to_regclass('public.assets') is not null or to_regclass('public.asset_systems') is not null then
    raise exception '0018 prerequisite mismatch: Asset Registry objects already exist';
  end if;
end;
$preflight$;

create table public.asset_systems (
  id uuid primary key default gen_random_uuid(),
  system_code text not null,
  name text not null,
  description text,
  site text not null,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint asset_systems_code_check check (length(pg_catalog.btrim(system_code)) between 1 and 80),
  constraint asset_systems_name_check check (length(pg_catalog.btrim(name)) between 1 and 160),
  constraint asset_systems_site_check check (length(pg_catalog.btrim(site)) between 1 and 160),
  constraint asset_systems_description_check check (description is null or length(description)<=2000)
);
create unique index asset_systems_code_unique_idx on public.asset_systems(pg_catalog.lower(system_code));
create index asset_systems_site_idx on public.asset_systems(pg_catalog.lower(site),is_active);

create table public.assets (
  id uuid primary key default gen_random_uuid(),
  asset_tag text not null,
  name text not null,
  asset_type text not null,
  criticality text not null default 'medium' check (criticality in ('critical','high','medium','low')),
  lifecycle_status text not null default 'active' check (lifecycle_status in ('active','out_of_service','decommissioned')),
  site text not null,
  location text not null,
  description text,
  system_id uuid references public.asset_systems(id) on delete restrict,
  building text,
  floor_zone text,
  room text,
  manufacturer text,
  model text,
  serial_number text,
  department_id uuid references public.departments(id) on delete restrict,
  responsible_team_id uuid references public.maintenance_teams(id) on delete restrict,
  in_service_date date,
  warranty_expiry date,
  out_of_service_at timestamptz,
  decommissioned_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  status_changed_at timestamptz not null default pg_catalog.now(),
  constraint assets_tag_check check (length(pg_catalog.btrim(asset_tag)) between 1 and 80),
  constraint assets_name_check check (length(pg_catalog.btrim(name)) between 1 and 200),
  constraint assets_type_check check (length(pg_catalog.btrim(asset_type)) between 1 and 120),
  constraint assets_site_check check (length(pg_catalog.btrim(site)) between 1 and 160),
  constraint assets_location_check check (length(pg_catalog.btrim(location)) between 1 and 255),
  constraint assets_description_check check (description is null or length(description)<=4000),
  constraint assets_decommissioned_timestamp_check check (
    (lifecycle_status='decommissioned' and decommissioned_at is not null)
    or (lifecycle_status<>'decommissioned' and decommissioned_at is null)
  )
);
create unique index assets_tag_unique_idx on public.assets(pg_catalog.lower(asset_tag));
create index assets_name_idx on public.assets(pg_catalog.lower(name));
create index assets_system_idx on public.assets(system_id) where system_id is not null;
create index assets_status_criticality_idx on public.assets(lifecycle_status,criticality);
create index assets_site_idx on public.assets(pg_catalog.lower(site));
create index assets_department_idx on public.assets(department_id) where department_id is not null;
create index assets_team_idx on public.assets(responsible_team_id) where responsible_team_id is not null;

alter table public.work_orders add constraint work_orders_asset_id_fkey
  foreign key(asset_id) references public.assets(id) on delete restrict not valid;
create index if not exists work_orders_asset_idx on public.work_orders(asset_id) where asset_id is not null;

alter table public.incidents add column asset_id uuid;
alter table public.incidents add constraint incidents_asset_id_fkey
  foreign key(asset_id) references public.assets(id) on delete restrict;
create index incidents_asset_idx on public.incidents(asset_id) where asset_id is not null;

alter table public.activity_logs add column asset_id uuid;
alter table public.activity_logs add constraint activity_logs_asset_id_fkey
  foreign key(asset_id) references public.assets(id) on delete restrict;
create index activity_logs_asset_idx on public.activity_logs(asset_id,created_at desc) where asset_id is not null;

create or replace function public.validate_new_asset_link()
returns trigger language plpgsql set search_path=pg_catalog as $fn$
begin
  if new.asset_id is not null and (tg_op='INSERT' or old.asset_id is distinct from new.asset_id)
    and not exists(select 1 from public.assets a where a.id=new.asset_id and a.lifecycle_status<>'decommissioned') then
    raise foreign_key_violation using message='Selected Asset is unavailable.';
  end if;
  return new;
end;
$fn$;
create trigger validate_work_order_asset_link before insert or update of asset_id on public.work_orders
  for each row execute function public.validate_new_asset_link();
create trigger validate_incident_asset_link before insert or update of asset_id on public.incidents
  for each row execute function public.validate_new_asset_link();

alter table public.asset_systems enable row level security;
alter table public.assets enable row level security;
create policy asset_systems_authenticated_read on public.asset_systems for select to authenticated using (
  public.current_user_role() is not null and (is_active or public.current_user_role() in ('approver','supervisor','administrator'))
);
create policy assets_authenticated_read on public.assets for select to authenticated using (
  public.current_user_role() is not null and (
    lifecycle_status<>'decommissioned'
    or public.current_user_role() in ('approver','supervisor','administrator')
    or exists(select 1 from public.work_orders w where w.asset_id=assets.id)
  )
);
drop policy if exists activity_logs_read_permitted on public.activity_logs;
create policy activity_logs_read_permitted on public.activity_logs for select to authenticated using (
  (work_order_id is not null and exists(select 1 from public.work_orders w where w.id=activity_logs.work_order_id))
  or (incident_id is not null and exists(select 1 from public.incidents i where i.id=activity_logs.incident_id))
  or (asset_id is not null and exists(select 1 from public.assets a where a.id=activity_logs.asset_id))
  or public.current_user_role()='administrator'
);

revoke all on public.asset_systems,public.assets from public,anon,authenticated;
grant select on public.asset_systems,public.assets to authenticated;

create or replace function public.asset_result_error(code text,message text)
returns jsonb language sql immutable set search_path=pg_catalog as $fn$
  select pg_catalog.jsonb_build_object('ok',false,'code',code,'message',message)
$fn$;

create or replace function public.create_asset_system(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.asset_systems; code text:=pg_catalog.upper(pg_catalog.btrim(coalesce(p_payload->>'system_code','')));
begin
  if actor is null then return public.asset_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role'<>'administrator' then return public.asset_result_error('ACCESS_DENIED','Administrator authority is required.'); end if;
  if code='' or pg_catalog.btrim(coalesce(p_payload->>'name',''))='' or pg_catalog.btrim(coalesce(p_payload->>'site',''))='' then
    return public.asset_result_error('VALIDATION_ERROR','System code, name, and site are required.');
  end if;
  insert into public.asset_systems(system_code,name,description,site,created_by,updated_by)
  values(code,pg_catalog.btrim(p_payload->>'name'),nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),''),pg_catalog.btrim(p_payload->>'site'),(actor->>'id')::uuid,(actor->>'id')::uuid)
  returning * into result;
  insert into public.activity_logs(user_id,action,actor,note)
  values((actor->>'id')::uuid,'asset_system_created',actor->>'name',pg_catalog.jsonb_build_object('system_code',result.system_code,'name',result.name,'site',result.site)::text);
  return pg_catalog.jsonb_build_object('ok',true,'asset_system',pg_catalog.to_jsonb(result));
exception when unique_violation then return public.asset_result_error('DUPLICATE_SYSTEM_CODE','System code already exists.');
when check_violation then return public.asset_result_error('VALIDATION_ERROR','One or more System values are invalid.');
when others then return public.asset_result_error('INTERNAL_ERROR','The Asset System could not be created.'); end;
$fn$;

create or replace function public.update_asset_system(p_system_id uuid,p_payload jsonb,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.asset_systems; result public.asset_systems;
  code text; name_value text; description_value text; site_value text; active_value boolean;
begin
  if actor is null or actor->>'role'<>'administrator' then return public.asset_result_error('ACCESS_DENIED','Administrator authority is required.'); end if;
  select * into previous from public.asset_systems where id=p_system_id for update;
  if not found then return public.asset_result_error('NOT_FOUND','Asset System not found.'); end if;
  code:=case when p_payload?'system_code' then pg_catalog.upper(pg_catalog.btrim(coalesce(p_payload->>'system_code',''))) else previous.system_code end;
  name_value:=case when p_payload?'name' then pg_catalog.btrim(coalesce(p_payload->>'name','')) else previous.name end;
  description_value:=case when p_payload?'description' then nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),'') else previous.description end;
  site_value:=case when p_payload?'site' then pg_catalog.btrim(coalesce(p_payload->>'site','')) else previous.site end;
  active_value:=case when p_payload?'is_active' then (p_payload->>'is_active')::boolean else previous.is_active end;
  if code='' or name_value='' or site_value='' then return public.asset_result_error('VALIDATION_ERROR','System code, name, and site are required.'); end if;
  if (code,name_value,description_value,site_value,active_value) is not distinct from (previous.system_code,previous.name,previous.description,previous.site,previous.is_active) then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','asset_system',pg_catalog.to_jsonb(previous));
  end if;
  update public.asset_systems set system_code=code,name=name_value,description=description_value,site=site_value,is_active=active_value,
    updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=p_system_id returning * into result;
  insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'asset_system_updated',actor->>'name',
    pg_catalog.jsonb_build_object('before',pg_catalog.jsonb_build_object('system_code',previous.system_code,'name',previous.name,'site',previous.site,'is_active',previous.is_active),'after',pg_catalog.jsonb_build_object('system_code',result.system_code,'name',result.name,'site',result.site,'is_active',result.is_active),'reason',nullif(pg_catalog.btrim(coalesce(p_reason,'')),''))::text);
  return pg_catalog.jsonb_build_object('ok',true,'asset_system',pg_catalog.to_jsonb(result));
exception when invalid_text_representation or check_violation then return public.asset_result_error('VALIDATION_ERROR','One or more System values are invalid.');
when unique_violation then return public.asset_result_error('DUPLICATE_SYSTEM_CODE','System code already exists.');
when others then return public.asset_result_error('INTERNAL_ERROR','The Asset System could not be updated.'); end;
$fn$;

create or replace function public.create_asset(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); result public.assets; tag text:=pg_catalog.upper(pg_catalog.btrim(coalesce(p_payload->>'asset_tag','')));
  criticality_value text:=pg_catalog.lower(coalesce(p_payload->>'criticality','medium')); status_value text:=pg_catalog.lower(coalesce(p_payload->>'lifecycle_status','active'));
  system_value uuid:=nullif(p_payload->>'system_id','')::uuid; department_value uuid:=nullif(p_payload->>'department_id','')::uuid; team_value uuid:=nullif(p_payload->>'responsible_team_id','')::uuid;
begin
  if actor is null then return public.asset_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role' not in ('supervisor','administrator') then return public.asset_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if tag='' or pg_catalog.btrim(coalesce(p_payload->>'name',''))='' or pg_catalog.btrim(coalesce(p_payload->>'asset_type',''))=''
    or pg_catalog.btrim(coalesce(p_payload->>'site',''))='' or pg_catalog.btrim(coalesce(p_payload->>'location',''))='' then
    return public.asset_result_error('VALIDATION_ERROR','Asset tag, name, type, site, and location are required.'); end if;
  if criticality_value not in ('critical','high','medium','low') or status_value not in ('active','out_of_service') then
    return public.asset_result_error('VALIDATION_ERROR','Criticality or lifecycle status is invalid.'); end if;
  if system_value is not null and not exists(select 1 from public.asset_systems s where s.id=system_value and s.is_active) then return public.asset_result_error('INVALID_REFERENCE','Asset System is unavailable.'); end if;
  if department_value is not null and not exists(select 1 from public.departments d where d.id=department_value and d.is_active and d.deleted_at is null) then return public.asset_result_error('INVALID_REFERENCE','Department is unavailable.'); end if;
  if team_value is not null and not exists(select 1 from public.maintenance_teams t where t.id=team_value and t.is_active and t.deleted_at is null) then return public.asset_result_error('INVALID_REFERENCE','Responsible team is unavailable.'); end if;
  insert into public.assets(asset_tag,name,asset_type,criticality,lifecycle_status,site,location,description,system_id,building,floor_zone,room,manufacturer,model,serial_number,department_id,responsible_team_id,in_service_date,warranty_expiry,out_of_service_at,created_by,updated_by)
  values(tag,pg_catalog.btrim(p_payload->>'name'),pg_catalog.btrim(p_payload->>'asset_type'),criticality_value,status_value,pg_catalog.btrim(p_payload->>'site'),pg_catalog.btrim(p_payload->>'location'),nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),''),system_value,nullif(pg_catalog.btrim(coalesce(p_payload->>'building','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'floor_zone','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'room','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'manufacturer','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'model','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'serial_number','')),''),department_value,team_value,nullif(p_payload->>'in_service_date','')::date,nullif(p_payload->>'warranty_expiry','')::date,case when status_value='out_of_service' then pg_catalog.now() end,(actor->>'id')::uuid,(actor->>'id')::uuid)
  returning * into result;
  insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,'asset_created',actor->>'name',pg_catalog.jsonb_build_object('asset_tag',result.asset_tag,'name',result.name,'asset_type',result.asset_type,'criticality',result.criticality,'lifecycle_status',result.lifecycle_status,'site',result.site,'location',result.location)::text);
  return pg_catalog.jsonb_build_object('ok',true,'asset',pg_catalog.to_jsonb(result));
exception when invalid_text_representation or datetime_field_overflow or check_violation then return public.asset_result_error('VALIDATION_ERROR','One or more Asset values are invalid.');
when unique_violation then return public.asset_result_error('DUPLICATE_ASSET_TAG','Asset tag already exists.');
when others then return public.asset_result_error('INTERNAL_ERROR','The Asset could not be created.'); end;
$fn$;

create or replace function public.update_asset_details(p_asset_id uuid,p_payload jsonb,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.assets; result public.assets; system_value uuid; department_value uuid; team_value uuid;
  before_values jsonb; after_values jsonb;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.asset_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  select * into previous from public.assets where id=p_asset_id for update;
  if not found then return public.asset_result_error('NOT_FOUND','Asset not found.'); end if;
  if previous.lifecycle_status='decommissioned' and actor->>'role'<>'administrator' then return public.asset_result_error('ACCESS_DENIED','Only an Administrator may correct a decommissioned Asset.'); end if;
  system_value:=case when p_payload?'system_id' then nullif(p_payload->>'system_id','')::uuid else previous.system_id end;
  department_value:=case when p_payload?'department_id' then nullif(p_payload->>'department_id','')::uuid else previous.department_id end;
  team_value:=case when p_payload?'responsible_team_id' then nullif(p_payload->>'responsible_team_id','')::uuid else previous.responsible_team_id end;
  if system_value is not null and not exists(select 1 from public.asset_systems s where s.id=system_value and s.is_active) then return public.asset_result_error('INVALID_REFERENCE','Asset System is unavailable.'); end if;
  if department_value is not null and not exists(select 1 from public.departments d where d.id=department_value and d.is_active and d.deleted_at is null) then return public.asset_result_error('INVALID_REFERENCE','Department is unavailable.'); end if;
  if team_value is not null and not exists(select 1 from public.maintenance_teams t where t.id=team_value and t.is_active and t.deleted_at is null) then return public.asset_result_error('INVALID_REFERENCE','Responsible team is unavailable.'); end if;
  before_values:=pg_catalog.jsonb_build_object('name',previous.name,'asset_type',previous.asset_type,'description',previous.description,'system_id',previous.system_id,'site',previous.site,'building',previous.building,'floor_zone',previous.floor_zone,'room',previous.room,'location',previous.location,'manufacturer',previous.manufacturer,'model',previous.model,'serial_number',previous.serial_number,'department_id',previous.department_id,'responsible_team_id',previous.responsible_team_id,'in_service_date',previous.in_service_date,'warranty_expiry',previous.warranty_expiry);
  update public.assets set
    name=case when p_payload?'name' then pg_catalog.btrim(coalesce(p_payload->>'name','')) else name end,
    asset_type=case when p_payload?'asset_type' then pg_catalog.btrim(coalesce(p_payload->>'asset_type','')) else asset_type end,
    description=case when p_payload?'description' then nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),'') else description end,
    system_id=system_value,site=case when p_payload?'site' then pg_catalog.btrim(coalesce(p_payload->>'site','')) else site end,
    building=case when p_payload?'building' then nullif(pg_catalog.btrim(coalesce(p_payload->>'building','')),'') else building end,
    floor_zone=case when p_payload?'floor_zone' then nullif(pg_catalog.btrim(coalesce(p_payload->>'floor_zone','')),'') else floor_zone end,
    room=case when p_payload?'room' then nullif(pg_catalog.btrim(coalesce(p_payload->>'room','')),'') else room end,
    location=case when p_payload?'location' then pg_catalog.btrim(coalesce(p_payload->>'location','')) else location end,
    manufacturer=case when p_payload?'manufacturer' then nullif(pg_catalog.btrim(coalesce(p_payload->>'manufacturer','')),'') else manufacturer end,
    model=case when p_payload?'model' then nullif(pg_catalog.btrim(coalesce(p_payload->>'model','')),'') else model end,
    serial_number=case when p_payload?'serial_number' then nullif(pg_catalog.btrim(coalesce(p_payload->>'serial_number','')),'') else serial_number end,
    department_id=department_value,responsible_team_id=team_value,
    in_service_date=case when p_payload?'in_service_date' then nullif(p_payload->>'in_service_date','')::date else in_service_date end,
    warranty_expiry=case when p_payload?'warranty_expiry' then nullif(p_payload->>'warranty_expiry','')::date else warranty_expiry end
  where id=p_asset_id returning * into result;
  after_values:=pg_catalog.jsonb_build_object('name',result.name,'asset_type',result.asset_type,'description',result.description,'system_id',result.system_id,'site',result.site,'building',result.building,'floor_zone',result.floor_zone,'room',result.room,'location',result.location,'manufacturer',result.manufacturer,'model',result.model,'serial_number',result.serial_number,'department_id',result.department_id,'responsible_team_id',result.responsible_team_id,'in_service_date',result.in_service_date,'warranty_expiry',result.warranty_expiry);
  if before_values=after_values then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','asset',pg_catalog.to_jsonb(previous)); end if;
  update public.assets set updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=p_asset_id returning * into result;
  insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,'asset_details_updated',actor->>'name',pg_catalog.jsonb_build_object('before',before_values,'after',after_values,'reason',nullif(pg_catalog.btrim(coalesce(p_reason,'')),''))::text);
  if (previous.site,previous.building,previous.floor_zone,previous.room,previous.location) is distinct from (result.site,result.building,result.floor_zone,result.room,result.location) then
    insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,'asset_location_changed',actor->>'name',pg_catalog.jsonb_build_object('before',pg_catalog.jsonb_build_object('site',previous.site,'building',previous.building,'floor_zone',previous.floor_zone,'room',previous.room,'location',previous.location),'after',pg_catalog.jsonb_build_object('site',result.site,'building',result.building,'floor_zone',result.floor_zone,'room',result.room,'location',result.location),'reason',nullif(pg_catalog.btrim(coalesce(p_reason,'')),''))::text);
  end if;
  if previous.system_id is distinct from result.system_id then insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,'asset_system_changed',actor->>'name',pg_catalog.jsonb_build_object('before_system_id',previous.system_id,'after_system_id',result.system_id,'reason',nullif(pg_catalog.btrim(coalesce(p_reason,'')),''))::text); end if;
  return pg_catalog.jsonb_build_object('ok',true,'asset',pg_catalog.to_jsonb(result));
exception when invalid_text_representation or datetime_field_overflow or check_violation then return public.asset_result_error('VALIDATION_ERROR','One or more Asset values are invalid.');
when others then return public.asset_result_error('INTERNAL_ERROR','The Asset could not be updated.'); end;
$fn$;

create or replace function public.change_asset_criticality(p_asset_id uuid,p_criticality text,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.assets; result public.assets; value text:=pg_catalog.lower(coalesce(p_criticality,'')); reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.asset_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.asset_result_error('REASON_REQUIRED','A criticality-change reason is required.'); end if;
  if value not in ('critical','high','medium','low') then return public.asset_result_error('VALIDATION_ERROR','Asset criticality is invalid.'); end if;
  select * into previous from public.assets where id=p_asset_id for update; if not found then return public.asset_result_error('NOT_FOUND','Asset not found.'); end if;
  if previous.criticality=value then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','asset',pg_catalog.to_jsonb(previous)); end if;
  update public.assets set criticality=value,updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=p_asset_id returning * into result;
  insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,'asset_criticality_changed',actor->>'name',pg_catalog.jsonb_build_object('before',previous.criticality,'after',result.criticality,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'asset',pg_catalog.to_jsonb(result));
end;
$fn$;

create or replace function public.change_asset_tag(p_asset_id uuid,p_asset_tag text,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.assets; result public.assets; value text:=pg_catalog.upper(pg_catalog.btrim(coalesce(p_asset_tag,''))); reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null or actor->>'role'<>'administrator' then return public.asset_result_error('ACCESS_DENIED','Administrator authority is required.'); end if;
  if reason is null then return public.asset_result_error('REASON_REQUIRED','An Asset-tag correction reason is required.'); end if;
  if value='' then return public.asset_result_error('VALIDATION_ERROR','Asset tag is required.'); end if;
  select * into previous from public.assets where id=p_asset_id for update; if not found then return public.asset_result_error('NOT_FOUND','Asset not found.'); end if;
  if previous.asset_tag=value then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','asset',pg_catalog.to_jsonb(previous)); end if;
  update public.assets set asset_tag=value,updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=p_asset_id returning * into result;
  insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,'asset_tag_changed',actor->>'name',pg_catalog.jsonb_build_object('before',previous.asset_tag,'after',result.asset_tag,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'asset',pg_catalog.to_jsonb(result));
exception when unique_violation then return public.asset_result_error('DUPLICATE_ASSET_TAG','Asset tag already exists.');
when check_violation then return public.asset_result_error('VALIDATION_ERROR','Asset tag is invalid.'); end;
$fn$;

create or replace function public.change_asset_status(p_asset_id uuid,p_status text,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.assets; result public.assets; value text:=pg_catalog.lower(coalesce(p_status,'')); reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); action_name text;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.asset_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.asset_result_error('REASON_REQUIRED','A lifecycle-status reason is required.'); end if;
  if value not in ('active','out_of_service','decommissioned') then return public.asset_result_error('VALIDATION_ERROR','Asset lifecycle status is invalid.'); end if;
  if value='decommissioned' and actor->>'role'<>'administrator' then return public.asset_result_error('ACCESS_DENIED','Only an Administrator may decommission an Asset.'); end if;
  select * into previous from public.assets where id=p_asset_id for update; if not found then return public.asset_result_error('NOT_FOUND','Asset not found.'); end if;
  if previous.lifecycle_status='decommissioned' and value<>'decommissioned' then return public.asset_result_error('TERMINAL_IMMUTABLE','A decommissioned Asset cannot be reactivated.'); end if;
  if previous.lifecycle_status=value then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','asset',pg_catalog.to_jsonb(previous)); end if;
  action_name:=case when value='decommissioned' then 'asset_decommissioned' else 'asset_status_changed' end;
  update public.assets set lifecycle_status=value,status_changed_at=pg_catalog.now(),out_of_service_at=case when value='out_of_service' then pg_catalog.now() else null end,decommissioned_at=case when value='decommissioned' then pg_catalog.now() else null end,updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=p_asset_id returning * into result;
  insert into public.activity_logs(user_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,action_name,actor->>'name',pg_catalog.jsonb_build_object('before',previous.lifecycle_status,'after',result.lifecycle_status,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'asset',pg_catalog.to_jsonb(result));
end;
$fn$;

create or replace function public.set_work_order_asset(p_work_order_id uuid,p_asset_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.work_orders; result public.work_orders; old_tag text; new_tag text; action_name text; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.asset_result_error('ACCESS_DENIED','Approver, Supervisor, or Administrator authority is required.'); end if;
  select * into previous from public.work_orders where id=p_work_order_id for update; if not found then return public.asset_result_error('NOT_FOUND','Work Order not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.asset_result_error('TERMINAL_IMMUTABLE','Closed and cancelled Work Orders cannot be relinked.'); end if;
  if previous.asset_id is not distinct from p_asset_id then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(previous)); end if;
  if previous.asset_id is not null and reason is null then return public.asset_result_error('REASON_REQUIRED','Changing or removing an Asset link requires a reason.'); end if;
  if p_asset_id is not null then select asset_tag into new_tag from public.assets where id=p_asset_id and lifecycle_status<>'decommissioned'; if new_tag is null then return public.asset_result_error('INVALID_REFERENCE','Selected Asset is unavailable.'); end if; end if;
  if previous.asset_id is not null then select asset_tag into old_tag from public.assets where id=previous.asset_id; end if;
  action_name:=case when previous.asset_id is null then 'work_order_asset_linked' when p_asset_id is null then 'work_order_asset_unlinked' else 'work_order_asset_changed' end;
  update public.work_orders set asset_id=p_asset_id,updated_at=pg_catalog.now() where id=p_work_order_id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,coalesce(p_asset_id,previous.asset_id),action_name,actor->>'name',pg_catalog.jsonb_build_object('before_asset',coalesce(old_tag,'Asset unavailable'),'after_asset',coalesce(new_tag,'None'),'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
end;
$fn$;

create or replace function public.set_incident_asset(p_incident_id uuid,p_asset_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); previous public.incidents; result public.incidents; old_tag text; new_tag text; action_name text; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.asset_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  select * into previous from public.incidents where id=p_incident_id for update; if not found then return public.asset_result_error('NOT_FOUND','Incident not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.asset_result_error('TERMINAL_IMMUTABLE','Closed and cancelled Incidents cannot be relinked.'); end if;
  if previous.asset_id is not distinct from p_asset_id then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','incident',pg_catalog.to_jsonb(previous)); end if;
  if previous.asset_id is not null and reason is null then return public.asset_result_error('REASON_REQUIRED','Changing or removing an Asset link requires a reason.'); end if;
  if p_asset_id is not null then select asset_tag into new_tag from public.assets where id=p_asset_id and lifecycle_status<>'decommissioned'; if new_tag is null then return public.asset_result_error('INVALID_REFERENCE','Selected Asset is unavailable.'); end if; end if;
  if previous.asset_id is not null then select asset_tag into old_tag from public.assets where id=previous.asset_id; end if;
  action_name:=case when previous.asset_id is null then 'incident_asset_linked' when p_asset_id is null then 'incident_asset_unlinked' else 'incident_asset_changed' end;
  update public.incidents set asset_id=p_asset_id,updated_at=pg_catalog.now() where id=p_incident_id returning * into result;
  insert into public.activity_logs(user_id,incident_id,asset_id,action,actor,note) values((actor->>'id')::uuid,result.id,coalesce(p_asset_id,previous.asset_id),action_name,actor->>'name',pg_catalog.jsonb_build_object('before_asset',coalesce(old_tag,'None'),'after_asset',coalesce(new_tag,'None'),'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(result));
end;
$fn$;

create or replace function public.create_incident_with_asset(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $fn$
declare actor jsonb:=public.work_order_actor(); selected_asset uuid:=nullif(p_payload->>'asset_id','')::uuid; selected_tag text; created jsonb; incident_row public.incidents; incident_id uuid;
begin
  if actor is null then return public.asset_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  if actor->>'role'='technician' then return public.asset_result_error('ACCESS_DENIED','Your role cannot report an Incident.'); end if;
  if selected_asset is null then return public.create_incident(p_payload-'asset_id'); end if;
  select asset_tag into selected_tag from public.assets where id=selected_asset and lifecycle_status<>'decommissioned';
  if selected_tag is null then return public.asset_result_error('INVALID_REFERENCE','Selected Asset is unavailable.'); end if;
  created:=public.create_incident(p_payload-'asset_id');
  if coalesce((created->>'ok')::boolean,false) is not true then return created; end if;
  incident_id:=(created#>>'{incident,id}')::uuid;
  update public.incidents set asset_id=selected_asset,updated_at=pg_catalog.now() where id=incident_id returning * into incident_row;
  insert into public.activity_logs(user_id,incident_id,asset_id,action,actor,note) values((actor->>'id')::uuid,incident_id,selected_asset,'incident_asset_linked',actor->>'name',pg_catalog.jsonb_build_object('before_asset','None','after_asset',selected_tag,'reason','Selected during Incident reporting')::text);
  return pg_catalog.jsonb_set(created,'{incident}',pg_catalog.to_jsonb(incident_row),true);
exception when invalid_text_representation then return public.asset_result_error('VALIDATION_ERROR','Asset reference is invalid.');
when others then return public.asset_result_error('INTERNAL_ERROR','The Incident could not be linked to the Asset.'); end;
$fn$;

revoke all on function public.validate_new_asset_link() from public,anon,authenticated,service_role;
revoke all on function public.asset_result_error(text,text) from public,anon,authenticated,service_role;
revoke all on function public.create_asset_system(jsonb) from public,anon,service_role;
revoke all on function public.update_asset_system(uuid,jsonb,text) from public,anon,service_role;
revoke all on function public.create_asset(jsonb) from public,anon,service_role;
revoke all on function public.update_asset_details(uuid,jsonb,text) from public,anon,service_role;
revoke all on function public.change_asset_criticality(uuid,text,text) from public,anon,service_role;
revoke all on function public.change_asset_tag(uuid,text,text) from public,anon,service_role;
revoke all on function public.change_asset_status(uuid,text,text) from public,anon,service_role;
revoke all on function public.set_work_order_asset(uuid,uuid,text) from public,anon,service_role;
revoke all on function public.set_incident_asset(uuid,uuid,text) from public,anon,service_role;
revoke all on function public.create_incident_with_asset(jsonb) from public,anon,service_role;
grant execute on function public.create_asset_system(jsonb),public.update_asset_system(uuid,jsonb,text),public.create_asset(jsonb),public.update_asset_details(uuid,jsonb,text),public.change_asset_criticality(uuid,text,text),public.change_asset_tag(uuid,text,text),public.change_asset_status(uuid,text,text),public.set_work_order_asset(uuid,uuid,text),public.set_incident_asset(uuid,uuid,text),public.create_incident_with_asset(jsonb) to authenticated;

commit;
