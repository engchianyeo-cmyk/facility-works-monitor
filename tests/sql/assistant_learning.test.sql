\set ON_ERROR_STOP on
-- M33: the assistant keeps questions (role and page only), ratings, and answers written by the site team. Rolls back.
begin;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$
begin if value is not true then raise exception 'Assistant learning regression: %',message; end if; end;$$;
create function pg_temp.act(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub',p::text,true), set_config('request.jwt.claims',jsonb_build_object('sub',p,'role','authenticated')::text,true) $$;
create function pg_temp.u(n int) returns uuid language sql immutable as $$ select ('1d330000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid $$;
insert into auth.users(id,email,raw_user_meta_data)
select pg_temp.u(n),'m33.'||n||'@example.test',jsonb_build_object('display_name','M33 '||role||' '||n)
from (values ('administrator',1),('technician',2),('facility_manager',3)) a(role,n);
select set_config('fmworks.profile_admin_rpc','on',true),set_config('fmworks.password_change_completion','on',true);
update public.profiles p set role=a.role,is_active=true,password_change_required=false,trade_discipline=case when a.role='technician' then 'Electrical' end
from (values ('administrator',1),('technician',2),('facility_manager',3)) a(role,n) where p.id=pg_temp.u(a.n);
select set_config('fmworks.profile_admin_rpc','off',true),set_config('fmworks.password_change_completion','off',true);

select pg_temp.act(pg_temp.u(2));
select public.log_assistant_question('Explain SLA','/sla','none',null,null) as q \gset
select pg_temp.assert_true(((:'q')::jsonb->>'ok')::boolean,'a Technician''s question is kept');
select pg_temp.assert_true((public.log_assistant_question('my password: Secret12345!','/','none',null,null)->>'code')='VALIDATION_ERROR','passwords are refused');
select pg_temp.assert_true((public.log_assistant_question('card 4111 1111 1111 1111','/','none',null,null)->>'code')='VALIDATION_ERROR','card numbers are refused');
select pg_temp.assert_true((public.rate_assistant_answer(((:'q')::jsonb->>'id')::uuid,false)->>'ok')::boolean,'the asker rates the answer');
select pg_temp.assert_true((public.rate_assistant_answer(((:'q')::jsonb->>'id')::uuid,true)->>'code')='INVALID_STATE','an answer is rated once');
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.assistant_questions)=0,'a Technician cannot read the question log');
reset role;
select pg_temp.assert_true((select asker_role='technician' and page_path='/sla' and helpful=false from public.assistant_questions where id=((:'q')::jsonb->>'id')::uuid),'role, page and rating are kept');
select pg_temp.assert_true(not exists(select 1 from information_schema.columns where table_name='assistant_questions' and column_name in ('asked_by','email','profile_id')),'no person is stored with a question');

select pg_temp.assert_true((public.save_assistant_answer(null,'What does SLA mean?','SLA is the time we promise to respond and fix.','{sla}',null,true)->>'code')='ACCESS_DENIED','a Technician cannot teach the assistant');
select pg_temp.act(pg_temp.u(3));
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.assistant_questions where question='Explain SLA')=1,'a Facility Manager reads the question log');
reset role;
select public.save_assistant_answer(null,'What does SLA mean?','SLA (service level agreement) is the time we promise to respond to and fix a fault.',array['SLA','Service level',' x '],((:'q')::jsonb->>'id')::uuid,true) as a \gset
select pg_temp.assert_true(((:'a')::jsonb->>'ok')::boolean,'a Facility Manager writes an answer from the question');
select pg_temp.assert_true((select keywords='{"service level",sla}' and source_question_id=((:'q')::jsonb->>'id')::uuid from public.assistant_answers where id=((:'a')::jsonb->>'id')::uuid),'key words cleaned; source question linked');
select pg_temp.assert_true(exists(select 1 from public.activity_logs where action='assistant_answer_added'),'teaching is audited');
select pg_temp.act(pg_temp.u(1));
select pg_temp.assert_true((public.save_assistant_answer(((:'a')::jsonb->>'id')::uuid,'What does SLA mean?','SLA is the agreed time to respond and fix; see Site SLA.','{sla}',null,false)->>'ok')::boolean,'the Super-Administrator retires an answer');
select pg_temp.act(pg_temp.u(2));
set local role authenticated;
select pg_temp.assert_true((select count(*) from public.assistant_answers)=0,'a retired answer is not offered to staff');
reset role;

select 'assistant_learning tests passed' as result;
rollback;
