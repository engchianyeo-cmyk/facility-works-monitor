-- M31 (D-59a, D-58; owner 16 Nov 2026): the fault library ("what we learnt") and the assistant's name and picture.
-- 1. After a Work Order's work is done, the people on it share the confirmed cause, the fix that worked and a tip.
--    Anyone who may see a Work Order may see what was learnt from it; Ollie and the "Fixed before" box use it.
-- 2. A fix counts as proven once the job is Completed or Closed and no new Work Order on the same asset followed
--    within 30 days; otherwise it is flagged as a repeat fault. Nothing is learnt without a person sharing it.
-- 3. The Super-Administrator can rename the assistant and replace its picture (default: Ollie).
begin;

-- 1. Learnings ---------------------------------------------------------------------------------------------------
create table public.work_order_learnings (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.work_orders(id) on delete cascade,
  facility_id uuid references public.sites(id) on delete set null,
  asset_id uuid references public.assets(id) on delete set null,
  shared_by uuid references public.profiles(id) on delete set null,
  shared_by_name text not null check (length(btrim(shared_by_name)) between 1 and 200),
  confirmed_cause text check (confirmed_cause is null or length(btrim(confirmed_cause)) between 3 and 1000),
  fix_that_worked text check (fix_that_worked is null or length(btrim(fix_that_worked)) between 3 and 1000),
  tip text check (tip is null or length(btrim(tip)) between 3 and 1000),
  ai_suggestion text check (ai_suggestion is null or ai_suggestion in ('right','partly','wrong','not_used')),
  hidden_at timestamptz,
  hidden_by uuid references public.profiles(id) on delete set null,
  hidden_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint work_order_learnings_something check (coalesce(confirmed_cause, fix_that_worked, tip) is not null),
  constraint work_order_learnings_one_per_person unique (work_order_id, shared_by)
);
create index work_order_learnings_facility_idx on public.work_order_learnings(facility_id) where hidden_at is null;
create index work_order_learnings_asset_idx on public.work_order_learnings(asset_id) where asset_id is not null;
comment on table public.work_order_learnings is 'D-59a: what people learnt from a Work Order (cause, fix, tip); seen by whoever may see the Work Order.';

alter table public.work_order_learnings enable row level security;
revoke all on public.work_order_learnings from public, anon, authenticated, service_role;
grant select on public.work_order_learnings to authenticated;
create policy work_order_learnings_read on public.work_order_learnings for select to authenticated using (
  public.release1_work_order_visible(work_order_id)
  and (hidden_at is null or public.current_user_role() in ('administrator','facility_manager','facility_administrator'))
);

create or replace function public.share_work_order_learning(p_work_order_id uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid; actor_role text; w public.work_orders%rowtype;
  v_cause text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'confirmed_cause', '')), '');
  v_fix text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'fix_that_worked', '')), '');
  v_tip text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'tip', '')), '');
  v_ai text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'ai_suggestion', '')), '');
  result public.work_order_learnings%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_role := actor ->> 'role';
  select * into w from public.work_orders where id = p_work_order_id;
  if w.id is null or not public.release1_work_order_visible(w.id) then
    return public.work_order_result_error('NOT_FOUND', 'Work Order not found.');
  end if;
  if w.status not in ('completed','reviewed','closed') then
    return public.work_order_result_error('INVALID_STATE', 'Share what you learnt once the work is done (Submitted for Review, Completed or Closed).');
  end if;
  if not coalesce(actor_id = any(array_remove(array[w.assigned_technician_id, w.second_technician_id, w.requested_by], null))
          or (actor_role in ('approver','supervisor','facility_manager','administrator') and public.approval_facility_permitted(w.facility_id)), false) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the people on this Work Order can share what was learnt.');
  end if;
  if coalesce(v_cause, v_fix, v_tip) is null then
    return public.work_order_result_error('VALIDATION_ERROR', 'Write at least one of: the confirmed cause, the fix that worked, or a tip.');
  end if;
  if pg_catalog.length(coalesce(v_cause,'xxx')) < 3 or pg_catalog.length(coalesce(v_fix,'xxx')) < 3 or pg_catalog.length(coalesce(v_tip,'xxx')) < 3
     or pg_catalog.length(coalesce(v_cause,'')) > 1000 or pg_catalog.length(coalesce(v_fix,'')) > 1000 or pg_catalog.length(coalesce(v_tip,'')) > 1000 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Each answer must be between 3 and 1,000 characters.');
  end if;
  if v_ai is not null and v_ai not in ('right','partly','wrong','not_used') then
    return public.work_order_result_error('VALIDATION_ERROR', 'The answer about the AI suggestion is invalid.');
  end if;

  insert into public.work_order_learnings(work_order_id, facility_id, asset_id, shared_by, shared_by_name, confirmed_cause, fix_that_worked, tip, ai_suggestion)
  values (w.id, w.facility_id, w.asset_id, actor_id, coalesce(actor ->> 'display_name', actor ->> 'name', 'FMWorks user'), v_cause, v_fix, v_tip, v_ai)
  on conflict (work_order_id, shared_by) do update set confirmed_cause = excluded.confirmed_cause, fix_that_worked = excluded.fix_that_worked,
    tip = excluded.tip, ai_suggestion = excluded.ai_suggestion, updated_at = pg_catalog.now()
  returning * into result;

  insert into public.activity_logs(user_id, work_order_id, action, actor, note)
  values (actor_id, w.id, 'work_order_learning_shared', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('learning_id', result.id, 'cause', v_cause is not null, 'fix', v_fix is not null, 'tip', v_tip is not null, 'ai_suggestion', v_ai)::text);
  return pg_catalog.jsonb_build_object('ok', true, 'learning', pg_catalog.to_jsonb(result));
end;
$function$;

create or replace function public.hide_work_order_learning(p_learning_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); l public.work_order_learnings%rowtype; v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  select * into l from public.work_order_learnings where id = p_learning_id;
  if l.id is null then return public.work_order_result_error('NOT_FOUND', 'Learning not found.'); end if;
  if not coalesce(actor ->> 'role' = 'administrator'
          or (actor ->> 'role' = 'facility_administrator' and public.active_facility_member(l.facility_id, 'facility_administrator', (actor ->> 'id')::uuid))
          or (actor ->> 'role' = 'facility_manager' and public.approval_facility_permitted(l.facility_id)), false) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the Super-Administrator, the Facility Administrator or the Facility Manager can hide a learning.');
  end if;
  if pg_catalog.length(v_reason) < 5 then return public.work_order_result_error('VALIDATION_ERROR', 'Give a reason of at least 5 characters.'); end if;
  update public.work_order_learnings set hidden_at = pg_catalog.now(), hidden_by = (actor ->> 'id')::uuid, hidden_reason = v_reason, updated_at = pg_catalog.now() where id = l.id;
  insert into public.activity_logs(user_id, work_order_id, action, actor, note)
  values ((actor ->> 'id')::uuid, l.work_order_id, 'work_order_learning_hidden', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('learning_id', l.id, 'reason', v_reason)::text);
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;

-- Learnings that match a Work Order: same asset first, then shared words of the title and location (equipment tags
-- such as BC-05 count three times). Runs with the caller's rights, so row security decides what is returned.
create or replace function public.work_order_learning_matches(p_work_order_id uuid, p_limit integer default 5)
returns table(learning_id uuid, work_order_id uuid, work_order_number text, work_order_title text, confirmed_cause text,
  fix_that_worked text, tip text, shared_by_name text, shared_at timestamptz, proven boolean, repeat_fault boolean, score integer)
language sql stable security invoker set search_path = pg_catalog as $function$
  with stop(word) as (values ('the'),('and'),('for'),('not'),('with'),('from'),('unit'),('room'),('level'),('fault'),('faulty'),('work'),('area'),('floor'),('check')),
  target as (
    select w.id, w.asset_id, w.facility_id,
      array(select distinct t from pg_catalog.regexp_split_to_table(pg_catalog.lower(coalesce(w.title,'') || ' ' || coalesce(w.location,'')), '[^a-z0-9-]+') t
            where pg_catalog.length(t) >= 3 and t not in (select word from stop)) as words
    from public.work_orders w where w.id = p_work_order_id
  ),
  candidates as (
    select l.id, l.work_order_id, src.work_order_number, src.title, l.confirmed_cause, l.fix_that_worked, l.tip, l.shared_by_name, l.created_at,
      src.status, src.asset_id, coalesce(src.reviewed_at, src.completed_at, l.created_at) as done_at,
      (case when t.asset_id is not null and src.asset_id = t.asset_id then 10 else 0 end)
      + (select coalesce(sum(case when x ~ '[0-9]' then 3 else 1 end), 0)::integer
           from pg_catalog.unnest(t.words) x
          where x = any(array(select distinct s from pg_catalog.regexp_split_to_table(pg_catalog.lower(coalesce(src.title,'') || ' ' || coalesce(src.location,'')), '[^a-z0-9-]+') s)))
      + (case when src.facility_id = t.facility_id then 1 else 0 end) as score
    from public.work_order_learnings l
    join public.work_orders src on src.id = l.work_order_id
    cross join target t
    where l.hidden_at is null and l.work_order_id <> t.id
  )
  select c.id, c.work_order_id, c.work_order_number, c.title, c.confirmed_cause, c.fix_that_worked, c.tip, c.shared_by_name, c.created_at,
    c.status in ('reviewed','closed') and not repeat.found as proven,
    repeat.found as repeat_fault,
    c.score
  from candidates c
  cross join lateral (select c.asset_id is not null and exists(
      select 1 from public.work_orders r where r.asset_id = c.asset_id and r.id <> c.work_order_id
        and r.created_at > c.done_at and r.created_at <= c.done_at + interval '30 days') as found) repeat
  where c.score >= 3
  order by c.score desc, (c.status in ('reviewed','closed') and not repeat.found) desc, c.created_at desc
  limit greatest(1, least(coalesce(p_limit, 5), 20))
$function$;

revoke all on function public.share_work_order_learning(uuid, jsonb), public.hide_work_order_learning(uuid, text),
  public.work_order_learning_matches(uuid, integer) from public, anon, service_role;
grant execute on function public.share_work_order_learning(uuid, jsonb), public.hide_work_order_learning(uuid, text),
  public.work_order_learning_matches(uuid, integer) to authenticated;

-- 2. Assistant name and picture -------------------------------------------------------------------------------------
create table public.assistant_settings (
  id boolean primary key default true check (id),
  display_name text not null default 'Ollie' check (length(btrim(display_name)) between 1 and 30),
  image_data_url text check (image_data_url is null or (length(image_data_url) <= 400000
    and image_data_url ~ '^data:image/(png|jpeg|webp|svg\+xml);base64,[A-Za-z0-9+/=]+$')),
  has_image boolean generated always as (image_data_url is not null) stored,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);
comment on table public.assistant_settings is 'D-58: the in-app assistant''s name and picture (one row; no picture = the built-in Ollie).';
alter table public.assistant_settings enable row level security;
revoke all on public.assistant_settings from public, anon, authenticated, service_role;
grant select on public.assistant_settings to authenticated;
create policy assistant_settings_read on public.assistant_settings for select to authenticated using (true);

create or replace function public.set_assistant_settings(p_display_name text, p_image_data_url text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_name text := pg_catalog.btrim(coalesce(p_display_name, ''));
begin
  if actor is null or actor ->> 'role' <> 'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the Super-Administrator can change the assistant.');
  end if;
  if pg_catalog.length(v_name) not between 1 and 30 then
    return public.work_order_result_error('VALIDATION_ERROR', 'The name must be 1 to 30 characters.');
  end if;
  if p_image_data_url is not null and (pg_catalog.length(p_image_data_url) > 400000
     or p_image_data_url !~ '^data:image/(png|jpeg|webp|svg\+xml);base64,[A-Za-z0-9+/=]+$') then
    return public.work_order_result_error('VALIDATION_ERROR', 'The picture must be a PNG, JPEG, WebP or SVG of up to about 300 KB.');
  end if;
  insert into public.assistant_settings(id, display_name, image_data_url, updated_by, updated_at)
  values (true, v_name, p_image_data_url, (actor ->> 'id')::uuid, pg_catalog.now())
  on conflict (id) do update set display_name = excluded.display_name, image_data_url = excluded.image_data_url,
    updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  insert into public.activity_logs(user_id, action, actor, note)
  values ((actor ->> 'id')::uuid, 'assistant_settings_changed', coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('display_name', v_name, 'picture', case when p_image_data_url is null then 'default' else 'custom' end)::text);
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;
revoke all on function public.set_assistant_settings(text, text) from public, anon, service_role;
grant execute on function public.set_assistant_settings(text, text) to authenticated;

commit;
