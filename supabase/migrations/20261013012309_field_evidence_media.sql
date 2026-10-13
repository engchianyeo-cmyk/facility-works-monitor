-- Keep the application, metadata and private bucket media contract aligned.
begin;
alter table public.evidence_items drop constraint evidence_items_content_type_check;
alter table public.evidence_items add constraint evidence_items_content_type_check check (
 content_type in ('image/jpeg','image/png','image/webp','application/pdf','video/mp4','video/webm','audio/mpeg','audio/wav','audio/x-wav','audio/webm','audio/mp4','audio/x-m4a','audio/ogg')
);
alter table public.evidence_items drop constraint evidence_items_byte_size_check;
alter table public.evidence_items add constraint evidence_items_byte_size_check check (byte_size between 1 and 52428800);
update storage.buckets set public=false,file_size_limit=52428800,
 allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf','video/mp4','video/webm','audio/mpeg','audio/wav','audio/x-wav','audio/webm','audio/mp4','audio/x-m4a','audio/ogg']::text[]
where id='field-evidence';
commit;
