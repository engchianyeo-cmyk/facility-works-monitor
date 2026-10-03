begin;
-- Older rule tables inherited service-role DML. Policy bands are now immutable
-- history: only the authenticated policy-change RPC may insert new bands.
revoke insert,update,delete,truncate on public.commercial_approval_rules from service_role;
-- Renaming the completion core retained authenticated EXECUTE, bypassing the
-- outer actual-cost confirmation gate. Only the wrapper may call it.
revoke all on function public.submit_physical_completion_20260921_core(uuid,jsonb) from public,anon,authenticated,service_role;
alter table public.incident_number_counters enable row level security;
alter table public.maintenance_requirement_number_counters enable row level security;
do $postconditions$
begin
 if has_table_privilege('service_role','public.commercial_approval_rules','INSERT')
    or has_table_privilege('authenticated','public.commercial_approval_rules','UPDATE') then
   raise exception 'Procurement bands must not permit direct policy mutation';
 end if;
end;$postconditions$;
commit;
