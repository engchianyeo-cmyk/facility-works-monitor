begin;
do $media$
declare media text; file_id uuid; owner_id uuid;
begin
 if not exists(select 1 from storage.buckets where id='field-evidence' and public=false
  and file_size_limit=52428800 and allowed_mime_types @> array['video/mp4','video/webm','audio/mpeg','audio/wav','audio/webm','audio/mp4','audio/x-m4a','audio/ogg']::text[]) then
  raise exception 'Private bucket media contract differs from application';
 end if;
 select id into owner_id from public.profiles where role='administrator' and is_active order by id limit 1;
 foreach media in array array['video/mp4','video/webm','audio/mpeg','audio/wav','audio/x-wav','audio/webm','audio/mp4','audio/x-m4a','audio/ogg'] loop
  file_id:=gen_random_uuid();
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values('work_order','08000000-0000-4000-8000-000000000003',owner_id,'media.bin',media,52428800,'before',
   'evidence/work-order/08000000-0000-4000-8000-000000000003/'||file_id::text||'/media.bin');
 end loop;
 begin
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values('work_order','08000000-0000-4000-8000-000000000003',owner_id,'large.mp4','video/mp4',52428801,'before',
   'evidence/work-order/08000000-0000-4000-8000-000000000003/'||gen_random_uuid()::text||'/large.mp4');
  raise exception 'Oversized metadata accepted';
 exception when check_violation then null; end;
 begin
  insert into public.evidence_items(parent_type,work_order_id,uploaded_by,original_filename,content_type,byte_size,category,storage_path)
  values('work_order','08000000-0000-4000-8000-000000000003',owner_id,'unsafe.exe','application/octet-stream',100,'before',
   'evidence/work-order/08000000-0000-4000-8000-000000000003/'||gen_random_uuid()::text||'/unsafe.exe');
  raise exception 'Unapproved media type accepted';
 exception when check_violation then null; end;
end;$media$;
rollback;
