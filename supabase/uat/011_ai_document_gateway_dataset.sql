-- Synthetic Preview/UAT metadata only. No real contract, credential, or external provider.
begin;
update public.sla_documents set parser_status='EXTRACTED',parser_metadata=jsonb_build_object('source','synthetic UAT text','character_count',length(extracted_text))where agreement_reference='FMW-UAT-SLA-010'and extracted_text is not null;
commit;
