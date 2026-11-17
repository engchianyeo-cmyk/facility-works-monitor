-- M33 (owner, 17 Nov 2026): the assistant learns from the questions people ask.
-- 1. Every question asked in the Help panel is kept with its page, the asker's ROLE (not the person), what answered it
--    (a prepared answer, the AI, or nothing) and whether it helped. Text that looks like a password, code or card number
--    is refused. No names or emails are stored.
-- 2. The Super-Administrator, a Facility Administrator or a Facility Manager turns a question into a new answer for
--    the assistant (or edits or retires one). New answers are matched like the built-in ones and given to the AI first.
begin;

create table public.assistant_questions (
  id uuid primary key default gen_random_uuid(),
  asker_role text not null check (asker_role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance','facility_administrator')),
  page_path text not null default '/' check (length(page_path) between 1 and 200),
  question text not null check (length(btrim(question)) between 2 and 1000),
  answered_by text not null check (answered_by in ('prepared','ai','none')),
  matched_answer text check (matched_answer is null or length(matched_answer) <= 100),
  ai_answer text check (ai_answer is null or length(ai_answer) <= 8000),
  helpful boolean,
  rated_at timestamptz,
  created_at timestamptz not null default now()
);
create index assistant_questions_recent_idx on public.assistant_questions(created_at desc);
comment on table public.assistant_questions is 'M33: questions asked of the assistant, with role and page only (no person), what answered them and whether it helped.';

create table public.assistant_answers (
  id uuid primary key default gen_random_uuid(),
  question text not null check (length(btrim(question)) between 5 and 300),
  answer text not null check (length(btrim(answer)) between 10 and 3000),
  keywords text[] not null default '{}' check (cardinality(keywords) <= 20),
  source_question_id uuid references public.assistant_questions(id) on delete set null,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.assistant_answers is 'M33: answers written by the site team for the assistant, learnt from real questions.';

alter table public.assistant_questions enable row level security;
alter table public.assistant_answers enable row level security;
revoke all on public.assistant_questions, public.assistant_answers from public, anon, authenticated, service_role;
grant select on public.assistant_questions, public.assistant_answers to authenticated;

create or replace function public.assistant_editor()
returns boolean language sql stable security definer set search_path = pg_catalog as $function$
  select public.pilot_account_ready(auth.uid()) and coalesce(public.current_user_role() in ('administrator','facility_administrator','facility_manager'), false)
$function$;
revoke all on function public.assistant_editor() from public, anon, service_role;
grant execute on function public.assistant_editor() to authenticated;

create policy assistant_questions_editor_read on public.assistant_questions for select to authenticated using (public.assistant_editor());
create policy assistant_answers_read on public.assistant_answers for select to authenticated
  using (public.pilot_account_ready(auth.uid()) and (active or public.assistant_editor()));

create or replace function public.log_assistant_question(p_question text, p_path text, p_answered_by text, p_matched text, p_ai_answer text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); v_question text := pg_catalog.btrim(coalesce(p_question, '')); v_id uuid;
begin
  if actor is null or not public.pilot_account_ready(auth.uid()) then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  if pg_catalog.length(v_question) < 2 or pg_catalog.length(v_question) > 1000 then
    return public.work_order_result_error('VALIDATION_ERROR', 'The question must be 2 to 1,000 characters.');
  end if;
  if v_question ~* '(password|passcode|otp|one[- ]time code)\s*[:=]?\s*\S{4,}' or v_question ~ '(\d[ -]?){13,19}' then
    return public.work_order_result_error('VALIDATION_ERROR', 'That looks like a password, code or card number; it was not kept.');
  end if;
  if coalesce(p_answered_by, '') not in ('prepared','ai','none') then
    return public.work_order_result_error('VALIDATION_ERROR', 'Unknown answer source.');
  end if;
  insert into public.assistant_questions(asker_role, page_path, question, answered_by, matched_answer, ai_answer)
  values (actor ->> 'role', case when p_path like '/%' then pg_catalog.left(p_path, 200) else '/' end, v_question, p_answered_by,
    nullif(pg_catalog.left(coalesce(p_matched, ''), 100), ''), nullif(pg_catalog.left(coalesce(p_ai_answer, ''), 8000), ''))
  returning id into v_id;
  return pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

create or replace function public.rate_assistant_answer(p_question_id uuid, p_helpful boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
begin
  if not public.pilot_account_ready(auth.uid()) or p_helpful is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  update public.assistant_questions set helpful = p_helpful, rated_at = pg_catalog.now()
   where id = p_question_id and helpful is null and created_at > pg_catalog.now() - interval '1 day';
  if not found then return public.work_order_result_error('INVALID_STATE', 'This answer was already rated or is too old to rate.'); end if;
  return pg_catalog.jsonb_build_object('ok', true);
end;
$function$;

create or replace function public.save_assistant_answer(p_id uuid, p_question text, p_answer text, p_keywords text[], p_source_question uuid, p_active boolean)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $function$
declare actor jsonb := public.work_order_actor(); actor_id uuid; v_id uuid; v_keywords text[];
begin
  if actor is null or not public.assistant_editor() then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the Super-Administrator, a Facility Administrator or a Facility Manager can teach the assistant.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_question, ''))) not between 5 and 300 or pg_catalog.length(pg_catalog.btrim(coalesce(p_answer, ''))) not between 10 and 3000 then
    return public.work_order_result_error('VALIDATION_ERROR', 'Write a question of 5 to 300 characters and an answer of 10 to 3,000.');
  end if;
  select coalesce(array_agg(distinct pg_catalog.lower(pg_catalog.btrim(k))) filter (where pg_catalog.length(pg_catalog.btrim(k)) between 2 and 40), '{}')
    into v_keywords from pg_catalog.unnest(coalesce(p_keywords, '{}')) k;
  if cardinality(v_keywords) > 20 then return public.work_order_result_error('VALIDATION_ERROR', 'Use at most 20 key words.'); end if;
  if p_id is null then
    insert into public.assistant_answers(question, answer, keywords, source_question_id, active, created_by, updated_by)
    values (pg_catalog.btrim(p_question), pg_catalog.btrim(p_answer), v_keywords, p_source_question, coalesce(p_active, true), actor_id, actor_id)
    returning id into v_id;
  else
    update public.assistant_answers set question = pg_catalog.btrim(p_question), answer = pg_catalog.btrim(p_answer), keywords = v_keywords,
      active = coalesce(p_active, active), updated_by = actor_id, updated_at = pg_catalog.now()
     where id = p_id returning id into v_id;
    if v_id is null then return public.work_order_result_error('NOT_FOUND', 'Answer not found.'); end if;
  end if;
  insert into public.activity_logs(user_id, action, actor, note)
  values (actor_id, case when p_id is null then 'assistant_answer_added' else 'assistant_answer_changed' end, coalesce(actor ->> 'display_name', actor ->> 'name'),
    pg_catalog.jsonb_build_object('answer_id', v_id, 'question', pg_catalog.left(p_question, 300), 'active', coalesce(p_active, true))::text);
  return pg_catalog.jsonb_build_object('ok', true, 'id', v_id);
end;
$function$;

revoke all on function public.log_assistant_question(text, text, text, text, text), public.rate_assistant_answer(uuid, boolean),
  public.save_assistant_answer(uuid, text, text, text[], uuid, boolean) from public, anon, service_role;
grant execute on function public.log_assistant_question(text, text, text, text, text), public.rate_assistant_answer(uuid, boolean),
  public.save_assistant_answer(uuid, text, text, text[], uuid, boolean) to authenticated;

commit;
