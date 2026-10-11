set check_function_bodies=off;
create table public.profiles (id uuid not null, display_name text not null, email text, department text, role text default 'reviewer'::text not null, is_active boolean default false not null, trade_discipline text, contact_number text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, deleted_at timestamp with time zone, department_id uuid, whatsapp_number text, password_change_required boolean default false not null, last_active_at timestamp with time zone, last_seen_route text);
create table public.account_invitations (id uuid default gen_random_uuid() not null, email text not null, display_name text not null, department text, assigned_role text not null, is_active boolean default true not null, token_hash text not null, expires_at timestamp with time zone not null, used_at timestamp with time zone, created_by uuid not null, created_at timestamp with time zone default now() not null);
create table public.categories (id uuid default gen_random_uuid() not null, user_id uuid, name text not null, created_at timestamp with time zone default now() not null);
create table public.work_order_number_counters (reference_year integer not null, last_value integer not null);
create table public.work_orders (id uuid default gen_random_uuid() not null, user_id uuid, title text not null, description text, location text not null, category_id uuid, priority text default 'medium'::text not null, status text default 'submitted'::text not null, submitted_by text, assigned_to text, photo_url text, ai_priority_score numeric, ai_priority_source text, ai_priority_confidence numeric, ai_priority_review_status text default 'unreviewed'::text, assigned_technician_id uuid, assigned_vendor_id uuid, assigned_by text, assigned_at timestamp with time zone, accepted_at timestamp with time zone, completed_at timestamp with time zone, verified_at timestamp with time zone, closed_at timestamp with time zone, work_order_number text not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, requested_by uuid, department_id uuid, site text, asset_id uuid, source text default 'manual'::text not null, source_reference text, alert_id text, prediction_reference text, health_score_at_creation numeric, failure_probability numeric, predicted_failure_date date, recommended_action text, confidence_score numeric, due_date date, estimated_hours numeric, priority_rank smallint generated always as (
CASE priority
    WHEN 'low'::text THEN 1
    WHEN 'medium'::text THEN 2
    WHEN 'high'::text THEN 3
    WHEN 'critical'::text THEN 4
    ELSE 0
END) stored, actual_labour_hours numeric, completion_notes text, internal_notes text, cancellation_reason text, assigned_team_id uuid, assigned_by_user_id uuid, submitted_at timestamp with time zone, approved_at timestamp with time zone, started_at timestamp with time zone, reviewed_at timestamp with time zone, cancelled_at timestamp with time zone, contact_number text, duplicated_from_id uuid, incident_id uuid, pm_occurrence_id uuid, sla_service_category_id uuid, facility_area_id uuid, emergency_work boolean default false not null, costing_deferred boolean default false not null, facility_id uuid not null, actual_costs_confirmed_at timestamp with time zone, actual_costs_confirmed_by uuid, recommended_vendor_id uuid);
create table public.activity_logs (id uuid default gen_random_uuid() not null, user_id uuid, work_order_id uuid, action text not null, from_status text, to_status text, actor text, note text, ai_model text, ai_confidence numeric, created_at timestamp with time zone default now() not null, incident_id uuid, asset_id uuid, maintenance_requirement_id uuid, pm_occurrence_id uuid);
create table public.notification_outbox (id uuid default gen_random_uuid() not null, work_order_id uuid, event_type text not null, event_key text not null, recipient_user_id uuid, recipient_email text, payload jsonb default '{}'::jsonb not null, delivery_status text default 'pending'::text not null, attempts integer default 0 not null, last_error text, available_at timestamp with time zone default now() not null, sent_at timestamp with time zone, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, incident_id uuid, recipient_profile_id uuid, channel text, provider text default 'none'::text not null, attempted_at timestamp with time zone, delivered_at timestamp with time zone, result_code text, provider_reference text, retry_count integer default 0 not null, last_error_code text, pm_occurrence_id uuid);
create table public.departments (id uuid default gen_random_uuid() not null, code text not null, name text not null, description text, cost_centre text, manager_id uuid, parent_department_id uuid, colour_tag text, is_active boolean default true not null, created_by uuid, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, deleted_at timestamp with time zone);
create table public.vendors (id uuid default gen_random_uuid() not null, name text not null, trade text, contact_name text, contact_email text, contact_phone text, active boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, deleted_at timestamp with time zone, company_registration_no text, vendor_type text default 'specialist_contractor'::text not null, emergency_available boolean default false not null, payment_terms_days integer default 30 not null);
create table public.maintenance_teams (id uuid default gen_random_uuid() not null, name text not null, department_id uuid, is_active boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, deleted_at timestamp with time zone);
create table public.maintenance_team_members (team_id uuid not null, profile_id uuid not null, is_active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.incident_number_counters (reference_year integer not null, last_value integer not null);
create table public.incidents (id uuid default gen_random_uuid() not null, incident_number text not null, incident_type text not null, severity text default 'emergency'::text not null, status text default 'reported'::text not null, location text not null, description text not null, reported_by uuid not null, reported_at timestamp with time zone default now() not null, incident_commander_id uuid, assigned_technician_id uuid, assigned_team_id uuid, acknowledgement_deadline timestamp with time zone not null, acknowledged_at timestamp with time zone, mobilising_at timestamp with time zone, on_site_at timestamp with time zone, rescue_started_at timestamp with time zone, safe_at timestamp with time zone, recovery_started_at timestamp with time zone, closed_at timestamp with time zone, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, asset_id uuid);
create table public.emergency_response_roster (id uuid default gen_random_uuid() not null, profile_id uuid, team_id uuid, receive_emergency_alerts boolean default true not null, sms_enabled boolean default true not null, whatsapp_enabled boolean default true not null, email_enabled boolean default false not null, escalation_order integer default 100 not null, active_from timestamp with time zone, active_to timestamp with time zone, incident_type text, active boolean default true not null, created_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.evidence_items (id uuid default gen_random_uuid() not null, parent_type text not null, work_order_id uuid, incident_id uuid, uploaded_by uuid not null, original_filename text not null, content_type text not null, byte_size bigint not null, category text not null, description text, storage_path text not null, uploaded_at timestamp with time zone default now() not null, deleted_at timestamp with time zone, deleted_by uuid, deletion_reason text);
create table public.asset_systems (id uuid default gen_random_uuid() not null, system_code text not null, name text not null, description text, site text not null, is_active boolean default true not null, created_by uuid not null, updated_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.assets (id uuid default gen_random_uuid() not null, asset_tag text not null, name text not null, asset_type text not null, criticality text default 'medium'::text not null, lifecycle_status text default 'active'::text not null, site text not null, location text not null, description text, system_id uuid, building text, floor_zone text, room text, manufacturer text, model text, serial_number text, department_id uuid, responsible_team_id uuid, in_service_date date, warranty_expiry date, out_of_service_at timestamp with time zone, decommissioned_at timestamp with time zone, created_by uuid not null, updated_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, status_changed_at timestamp with time zone default now() not null, location_zone_id uuid, facility_id uuid not null);
create table public.maintenance_requirement_number_counters (reference_year integer not null, last_value integer not null);
create table public.maintenance_requirements (id uuid default gen_random_uuid() not null, requirement_number text not null, asset_id uuid not null, state text default 'draft'::text not null, current_revision_id uuid, created_by uuid not null, updated_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.maintenance_requirement_revisions (id uuid default gen_random_uuid() not null, requirement_id uuid not null, revision_number integer not null, title text not null, scope text not null, maintenance_type text not null, interval_value integer not null, interval_unit text not null, first_due_date date not null, lead_time_days integer default 0 not null, department_id uuid, responsible_team_id uuid, default_priority text default 'medium'::text not null, estimated_hours numeric, evidence_guidance text, instructions text, procedure_reference text, effective_date date not null, created_by uuid not null, created_at timestamp with time zone default now() not null);
create table public.pm_occurrences (id uuid default gen_random_uuid() not null, requirement_id uuid not null, requirement_revision_id uuid not null, asset_id uuid not null, occurrence_number integer not null, original_due_date date not null, current_due_date date not null, generation_status text default 'pending'::text not null, generated_at timestamp with time zone, generation_attempts integer default 0 not null, last_generation_error_code text, cancelled_by uuid, cancellation_reason text, cancelled_at timestamp with time zone, created_at timestamp with time zone default now() not null);
create table public.pm_occurrence_deferrals (id uuid default gen_random_uuid() not null, occurrence_id uuid not null, sequence_number integer not null, previous_due_date date not null, revised_due_date date not null, reason text not null, deferred_by uuid not null, deferred_at timestamp with time zone default now() not null);
create table public.service_categories (id uuid default gen_random_uuid() not null, code text not null, name text not null, is_active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.sla_agreements (id uuid default gen_random_uuid() not null, agreement_code text not null, name text not null, counterparty text, is_active boolean default true not null, created_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.sla_agreement_versions (id uuid default gen_random_uuid() not null, agreement_id uuid not null, version_number integer not null, effective_from date not null, effective_to date, source_reference text, approval_status text default 'draft'::text not null, approved_by uuid, approved_at timestamp with time zone, approval_note text, created_by uuid not null, created_at timestamp with time zone default now() not null);
create table public.sla_rules (id uuid default gen_random_uuid() not null, version_id uuid not null, service_category_id uuid not null, priority_class text not null, work_order_priority text not null, acknowledgement_minutes integer, response_minutes integer, attendance_minutes integer, make_safe_minutes integer, rectification_minutes integer not null, kpi_target_percent numeric(5,2) not null, source_clause text not null, is_active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.sla_extraction_proposals (id uuid default gen_random_uuid() not null, agreement_id uuid, source_page text, source_section text, source_clause text, extracted_obligation text not null, proposed_rule jsonb not null, confidence numeric(5,4), ambiguity_warning text, provider_key text not null, human_approval_state text default 'pending'::text not null, reviewed_by uuid, reviewed_at timestamp with time zone, created_by uuid not null, created_at timestamp with time zone default now() not null, document_id uuid, source_excerpt text, provider_model text, extraction_payload jsonb default '{}'::jsonb not null, extraction_warnings text[] default '{}'::text[] not null, modifications jsonb default '[]'::jsonb not null, approved_rule_id uuid, approved_by uuid, approved_at timestamp with time zone);
create table public.work_order_sla_clocks (work_order_id uuid not null, sla_rule_id uuid not null, started_at timestamp with time zone not null, acknowledgement_deadline timestamp with time zone, response_deadline timestamp with time zone, attendance_deadline timestamp with time zone, make_safe_deadline timestamp with time zone, rectification_deadline timestamp with time zone not null, acknowledged_at timestamp with time zone, responded_at timestamp with time zone, attended_at timestamp with time zone, made_safe_at timestamp with time zone, rectified_at timestamp with time zone, risk_state text default 'on_track'::text not null, consumed_percent numeric(8,2) default 0 not null, last_evaluated_at timestamp with time zone default now() not null);
create table public.escalation_matrix_steps (id uuid default gen_random_uuid() not null, version_id uuid not null, threshold_percent numeric(5,2) not null, escalation_level text not null, recipient_role text, is_immediate_for_critical_safety boolean default false not null, created_at timestamp with time zone default now() not null);
create table public.sla_escalation_events (id uuid default gen_random_uuid() not null, work_order_id uuid not null, matrix_step_id uuid not null, threshold_percent numeric(5,2) not null, escalation_level text not null, reason text not null, triggered_at timestamp with time zone default now() not null, acknowledged_by uuid, acknowledged_at timestamp with time zone, acknowledgement_note text);
create table public.sites (id uuid default gen_random_uuid() not null, code text not null, name text not null, is_active boolean default true not null);
create table public.buildings (id uuid default gen_random_uuid() not null, site_id uuid not null, code text not null, name text not null, is_active boolean default true not null);
create table public.location_levels (id uuid default gen_random_uuid() not null, building_id uuid not null, code text not null, name text not null, is_active boolean default true not null);
create table public.location_zones (id uuid default gen_random_uuid() not null, level_id uuid not null, code text not null, name text not null, zone_type text default 'zone'::text not null, is_active boolean default true not null);
create table public.report_schedules (id uuid default gen_random_uuid() not null, name text not null, cadence text not null, report_scope jsonb default '{}'::jsonb not null, recipient_roles text[] default '{}'::text[] not null, recipient_emails text[] default '{}'::text[] not null, is_active boolean default true not null, last_run_at timestamp with time zone, next_run_at timestamp with time zone not null, last_delivery_status text default 'NOT_CONFIGURED'::text not null, created_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.report_runs (id uuid default gen_random_uuid() not null, schedule_id uuid, report_type text not null, period_start date not null, period_end date not null, scope jsonb default '{}'::jsonb not null, metrics_snapshot jsonb not null, delivery_status text default 'NOT_CONFIGURED'::text not null, generated_by uuid, generated_at timestamp with time zone default now() not null);
create table public.sla_documents (id uuid default gen_random_uuid() not null, agreement_id uuid, title text not null, client_owner text, service_provider text, maintenance_model text not null, agreement_reference text not null, version_label text not null, effective_date date, expiry_date date, original_filename text not null, media_type text not null, byte_size integer not null, content_sha256 text not null, storage_provider text default 'PILOT_DATABASE'::text not null, storage_key text not null, extracted_text text, review_status text default 'NOT_EXTRACTED'::text not null, approval_status text default 'DRAFT'::text not null, superseded_at timestamp with time zone, notes text, uploaded_by uuid not null, uploaded_at timestamp with time zone default now() not null, parser_status text default 'PENDING'::text not null, parser_metadata jsonb default '{}'::jsonb not null);
create table public.staffing_assessments (id uuid default gen_random_uuid() not null, name text not null, operating_model text not null, scope jsonb default '{}'::jsonb not null, facility_inputs jsonb default '{}'::jsonb not null, asset_inputs jsonb default '{}'::jsonb not null, service_inputs jsonb default '{}'::jsonb not null, workforce_inputs jsonb default '{}'::jsonb not null, proposed_organization jsonb default '[]'::jsonb not null, status text default 'DRAFT'::text not null, created_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.staffing_recommendations (id uuid default gen_random_uuid() not null, assessment_id uuid not null, provider_key text not null, provider_model text not null, recommendation jsonb not null, assumptions jsonb default '[]'::jsonb not null, unknown_inputs text[] default '{}'::text[] not null, coverage_gaps jsonb default '[]'::jsonb not null, confidence numeric(5,4), advisory_only boolean default true not null, generated_by uuid not null, generated_at timestamp with time zone default now() not null);
create table public.ai_provider_configurations (id uuid default gen_random_uuid() not null, provider_type text not null, display_name text not null, model_identifier text, enabled boolean default false not null, approved_status text default 'NOT_APPROVED'::text not null, environment text default 'preview'::text not null, endpoint_identifier text, api_version text, timeout_ms integer default 10000 not null, max_retries integer default 1 not null, max_input_bytes integer default 10485760 not null, max_output_tokens integer, temperature numeric(4,3), data_residency_note text, retention_privacy_note text, external_processing_approved boolean default false not null, approval_date date, approved_by uuid, last_connectivity_test timestamp with time zone, configuration_status text default 'NOT_CONFIGURED'::text not null, max_requests_day integer, max_requests_month integer, max_estimated_monthly_cost numeric(12,4), created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.ai_prompt_versions (id uuid default gen_random_uuid() not null, prompt_identifier text not null, version integer not null, purpose text not null, status text not null, schema_version text not null, template_text text not null, change_reason text, created_at timestamp with time zone default now() not null, approved_at timestamp with time zone, approved_by uuid);
create table public.ai_operation_audit (id uuid default gen_random_uuid() not null, request_id uuid default gen_random_uuid() not null, operation_type text not null, provider text not null, model_identifier text, prompt_version text, document_id uuid, requesting_user uuid not null, requested_at timestamp with time zone default now() not null, completed_at timestamp with time zone, latency_ms integer, status text not null, retry_count integer default 0 not null, input_size integer default 0 not null, input_tokens integer, output_tokens integer, estimated_cost numeric(12,6), confidence numeric(5,4), validation_result text, human_review_required boolean default true not null, error_category text, safe_diagnostic text);
create table public.contractor_service_categories (id uuid default gen_random_uuid() not null, code text not null, name text not null, description text, active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.contractor_services (vendor_id uuid not null, service_category_id uuid not null, is_nominated boolean default true not null, emergency_dispatch boolean default false not null, effective_from date, effective_to date);
create table public.contractor_rate_items (id uuid default gen_random_uuid() not null, vendor_id uuid not null, service_category_id uuid, cost_type text not null, item_code text, description text not null, unit text not null, normal_unit_rate numeric(14,2) not null, emergency_unit_rate numeric(14,2), currency text default 'SGD'::text not null, effective_from date not null, effective_to date, active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.work_order_cost_lines (id uuid default gen_random_uuid() not null, work_order_id uuid not null, vendor_id uuid, rate_item_id uuid, worker_name text, cost_type text not null, description text not null, quantity numeric(14,2) not null, unit text not null, unit_rate numeric(14,2) not null, amount numeric(14,2) generated always as ((quantity * unit_rate)) stored, entered_by uuid not null, technician_certified_at timestamp with time zone, approved_by uuid, approved_at timestamp with time zone, created_at timestamp with time zone default now() not null, cost_phase text default 'proposed'::text);
create table public.contractor_payment_assessments (id uuid default gen_random_uuid() not null, work_order_id uuid not null, vendor_id uuid not null, status text default 'draft'::text not null, assessed_amount numeric(14,2) default 0 not null, completed_work_accepted_at timestamp with time zone, invoice_received_at timestamp with time zone, payment_due_at timestamp with time zone, approved_by uuid, approved_at timestamp with time zone, paid_at timestamp with time zone, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, invoice_reference text, recommendation_note text, recommended_by uuid, recommended_at timestamp with time zone, approval_note text, payment_term_started_at timestamp with time zone, completion_notified_at timestamp with time zone, paid_amount numeric(14,2), payment_reference text, paid_by uuid, payment_note text);
create table public.facility_areas (id uuid default gen_random_uuid() not null, area_code text not null, name text not null, level text, zone text, description text, drawing_reference text, map_x numeric, map_y numeric, active boolean default true not null, created_at timestamp with time zone default now() not null, facility_id uuid not null);
create table public.authorised_work_liaisons (id uuid default gen_random_uuid() not null, discipline text not null, profile_id uuid not null, is_primary boolean default true not null, effective_from date default CURRENT_DATE not null, effective_to date, active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.facility_memberships (id uuid default gen_random_uuid() not null, facility_id uuid not null, profile_id uuid not null, membership_role text not null, active boolean default true not null, effective_from timestamp with time zone default now() not null, effective_to timestamp with time zone, created_at timestamp with time zone default now() not null, created_by uuid, updated_at timestamp with time zone default now() not null);
create table public.work_order_approval_basis (work_order_id uuid not null, cost_basis text not null, execution_arrangement text not null, safety_isolation_information text not null, board_approval_reference text, board_approval_date date, board_supporting_document_reference text, updated_by uuid not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.contractor_quotations (id uuid default gen_random_uuid() not null, work_order_id uuid not null, vendor_id uuid not null, quotation_ref text, quotation_date date, version_no integer default 1 not null, status text default 'submitted'::text not null, currency text default 'SGD'::text not null, total_amount numeric(14,2) default 0 not null, source_filename text, source_sha256 text, submitted_by uuid, submitted_at timestamp with time zone default now(), approved_by uuid, approved_at timestamp with time zone, approval_note text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null, prepared_by uuid, prepared_at timestamp with time zone, draft_saved_at timestamp with time zone, scope_summary text, contractor_legal_name text, gst_treatment text, itemization_note text, submission_note text);
create table public.contractor_quotation_lines (id uuid default gen_random_uuid() not null, quotation_id uuid not null, line_no integer not null, rate_item_id uuid not null, cost_type text not null, item_code text, description text not null, unit text not null, quantity numeric(14,3) not null, agreed_unit_rate numeric(14,2) not null, quoted_unit_rate numeric(14,2) not null, amount numeric(14,2) generated always as (round((quantity * quoted_unit_rate), 2)) stored, rate_exception boolean default false not null, exception_reason text, worker_name text, remarks text, created_at timestamp with time zone default now() not null);
create table public.contractor_actual_imports (id uuid default gen_random_uuid() not null, work_order_id uuid not null, vendor_id uuid not null, quotation_id uuid, source_filename text not null, source_sha256 text, import_kind text not null, currency text default 'SGD'::text not null, total_amount numeric(14,2) default 0 not null, exception_count integer default 0 not null, confirmed_by uuid not null, confirmed_at timestamp with time zone default now() not null, created_at timestamp with time zone default now() not null);
create table public.contractor_actual_import_lines (id uuid default gen_random_uuid() not null, import_id uuid not null, line_no integer not null, rate_item_id uuid not null, cost_type text not null, item_code text, description text not null, unit text not null, worker_name text, worker_id text, work_date date, quantity numeric(14,3) not null, agreed_unit_rate numeric(14,2) not null, actual_unit_rate numeric(14,2) not null, amount numeric(14,2) generated always as (round((quantity * actual_unit_rate), 2)) stored, rate_exception boolean default false not null, exception_reason text, remarks text, created_at timestamp with time zone default now() not null);
create table public.work_order_markups (id uuid default gen_random_uuid() not null, work_order_id uuid not null, source_type text not null, source_reference text not null, page_number integer, x_percent numeric(6,3) not null, y_percent numeric(6,3) not null, note text not null, created_by uuid not null, created_at timestamp with time zone default now() not null, deleted_at timestamp with time zone, drawing_revision text not null, annotation_type text not null, geometry jsonb not null, deleted_by uuid);
create table public.work_order_procurement_commitments (id uuid default gen_random_uuid() not null, work_order_id uuid not null, vendor_id uuid, quotation_id uuid, purchase_reference text not null, description text not null, currency text default 'SGD'::text not null, committed_amount numeric(14,2) not null, status text default 'proposed'::text not null, created_by uuid not null, approved_by uuid, approved_at timestamp with time zone, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.commercial_approval_rules (id uuid default gen_random_uuid() not null, rule_code text not null, currency text default 'SGD'::text not null, minimum_amount numeric(14,2) not null, maximum_amount numeric(14,2), minimum_quotations integer not null, active boolean default true not null, created_at timestamp with time zone default now() not null);
create table public.work_order_financial_controls (work_order_id uuid not null, currency text default 'SGD'::text not null, estimated_cost numeric(14,2) default 0 not null, quoted_cost numeric(14,2), approved_budget numeric(14,2), rule_id uuid, cost_status text default 'draft'::text not null, recommended_by uuid, recommended_at timestamp with time zone, recommendation_note text, financial_approved_by uuid, financial_approved_at timestamp with time zone, financial_approval_note text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.work_order_commercial_documents (id uuid default gen_random_uuid() not null, work_order_id uuid not null, document_type text not null, quotation_id uuid, payment_assessment_id uuid, uploaded_by uuid not null, original_filename text not null, content_type text not null, byte_size bigint not null, storage_path text not null, uploaded_at timestamp with time zone default now() not null, deleted_at timestamp with time zone, superseded_by uuid, superseded_at timestamp with time zone, superseded_by_user uuid);
create table public.work_order_document_corrections (id uuid default gen_random_uuid() not null, work_order_id uuid not null, original_status text not null, status text default 'open'::text not null, reason text not null, opened_by uuid not null, opened_at timestamp with time zone default now() not null, closed_by uuid, closed_at timestamp with time zone, closure_note text, created_at timestamp with time zone default now() not null);
create table public.vendor_facility_eligibility (vendor_id uuid not null, facility_id uuid not null, procurement_prequalified boolean default false not null, facility_confirmed boolean default false not null, confirmation_basis text not null, confirmed_by uuid, confirmed_at timestamp with time zone default now() not null, active boolean default true not null);
create table public.work_order_final_cost_submissions (id uuid default gen_random_uuid() not null, work_order_id uuid not null, status text default 'draft'::text not null, actual_labour_hours numeric(12,2) not null, final_contractor_amount numeric(14,2) not null, confirmed_actual_cost numeric(14,2) not null, comments text not null, submitted_by uuid not null, submitted_at timestamp with time zone, variance_approved_by uuid, variance_approved_at timestamp with time zone, variance_approval_note text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.work_order_final_cost_documents (id uuid default gen_random_uuid() not null, final_cost_submission_id uuid not null, work_order_id uuid not null, uploaded_by uuid not null, original_filename text not null, content_type text not null, byte_size bigint not null, storage_path text not null, uploaded_at timestamp with time zone default now() not null, deleted_at timestamp with time zone, deleted_by uuid, deletion_reason text, superseded_by uuid);
create table public.work_order_financial_dispositions (id uuid default gen_random_uuid() not null, work_order_id uuid not null, disposition_type text not null, reason_code text not null, reason text not null, status text default 'proposed'::text not null, proposed_by uuid not null, proposed_at timestamp with time zone default now() not null, approved_by uuid, approved_at timestamp with time zone, approval_note text, updated_at timestamp with time zone default now() not null);
alter table profiles add constraint profiles_display_name_nonempty_check CHECK ((length(btrim(display_name)) > 0));
alter table profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table account_invitations add constraint account_invitations_pkey PRIMARY KEY (id);
alter table account_invitations add constraint account_invitations_token_hash_key UNIQUE (token_hash);
alter table categories add constraint categories_name_nonempty_check CHECK ((length(btrim(name)) > 0));
alter table categories add constraint categories_pkey PRIMARY KEY (id);
alter table work_order_number_counters add constraint work_order_number_counters_last_value_check CHECK ((last_value > 0));
alter table work_order_number_counters add constraint work_order_number_counters_pkey PRIMARY KEY (reference_year);
alter table work_orders add constraint work_orders_pkey PRIMARY KEY (id);
alter table activity_logs add constraint activity_logs_pkey PRIMARY KEY (id);
alter table notification_outbox add constraint notification_outbox_delivery_status_check CHECK ((delivery_status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text])));
alter table notification_outbox add constraint notification_outbox_attempts_check CHECK ((attempts >= 0));
alter table notification_outbox add constraint notification_outbox_pkey PRIMARY KEY (id);
alter table departments add constraint departments_code_nonempty_check CHECK ((length(TRIM(BOTH FROM code)) > 0));
alter table departments add constraint departments_name_nonempty_check CHECK ((length(TRIM(BOTH FROM name)) > 0));
alter table departments add constraint departments_colour_tag_check CHECK (((colour_tag IS NULL) OR (colour_tag ~ '^#[0-9A-Fa-f]{6}$'::text)));
alter table departments add constraint departments_not_own_parent_check CHECK (((parent_department_id IS NULL) OR (parent_department_id <> id)));
alter table departments add constraint departments_pkey PRIMARY KEY (id);
alter table vendors add constraint vendors_pkey PRIMARY KEY (id);
alter table maintenance_teams add constraint maintenance_teams_name_nonempty_check CHECK ((length(btrim(name)) > 0));
alter table maintenance_teams add constraint maintenance_teams_pkey PRIMARY KEY (id);
alter table maintenance_team_members add constraint maintenance_team_members_pkey PRIMARY KEY (team_id, profile_id);
alter table work_orders add constraint work_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'assigned'::text, 'in_progress'::text, 'completed'::text, 'reviewed'::text, 'closed'::text, 'cancelled'::text])));
alter table work_orders add constraint work_orders_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table work_orders add constraint work_orders_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'reactive'::text, 'preventive'::text, 'inspection'::text, 'condition_based'::text, 'predictive'::text])));
alter table work_orders add constraint work_orders_hours_check CHECK ((((estimated_hours IS NULL) OR (estimated_hours >= (0)::numeric)) AND ((actual_labour_hours IS NULL) OR (actual_labour_hours >= (0)::numeric))));
alter table work_orders add constraint work_orders_predictive_ranges_check CHECK ((((health_score_at_creation IS NULL) OR ((health_score_at_creation >= (0)::numeric) AND (health_score_at_creation <= (100)::numeric))) AND ((failure_probability IS NULL) OR ((failure_probability >= (0)::numeric) AND (failure_probability <= (1)::numeric))) AND ((confidence_score IS NULL) OR ((confidence_score >= (0)::numeric) AND (confidence_score <= (1)::numeric)))));
alter table incident_number_counters add constraint incident_number_counters_last_value_check CHECK ((last_value > 0));
alter table incident_number_counters add constraint incident_number_counters_pkey PRIMARY KEY (reference_year);
alter table incidents add constraint incidents_incident_type_check CHECK ((incident_type = ANY (ARRAY['lift_entrapment'::text, 'fire'::text, 'flood'::text, 'major_water_leak'::text, 'electrical_failure'::text, 'gas_leak'::text, 'chemical_spill'::text, 'medical_emergency'::text, 'security'::text, 'other'::text])));
alter table incidents add constraint incidents_severity_check CHECK ((severity = ANY (ARRAY['emergency'::text, 'critical'::text, 'high'::text, 'medium'::text, 'low'::text])));
alter table incidents add constraint incidents_status_check CHECK ((status = ANY (ARRAY['reported'::text, 'acknowledged'::text, 'mobilising'::text, 'on_site'::text, 'rescue_in_progress'::text, 'safe'::text, 'recovery'::text, 'closed'::text, 'cancelled'::text])));
alter table incidents add constraint incidents_location_check CHECK ((length(btrim(location)) > 0));
alter table incidents add constraint incidents_description_check CHECK ((length(btrim(description)) > 0));
alter table incidents add constraint incidents_one_primary_responder CHECK ((NOT ((assigned_technician_id IS NOT NULL) AND (assigned_team_id IS NOT NULL))));
alter table incidents add constraint incidents_pkey PRIMARY KEY (id);
alter table incidents add constraint incidents_incident_number_key UNIQUE (incident_number);
alter table emergency_response_roster add constraint emergency_response_roster_escalation_order_check CHECK ((escalation_order >= 0));
alter table emergency_response_roster add constraint emergency_response_roster_incident_type_check CHECK (((incident_type IS NULL) OR (incident_type = ANY (ARRAY['lift_entrapment'::text, 'fire'::text, 'flood'::text, 'major_water_leak'::text, 'electrical_failure'::text, 'gas_leak'::text, 'chemical_spill'::text, 'medical_emergency'::text, 'security'::text, 'other'::text]))));
alter table emergency_response_roster add constraint emergency_roster_one_target CHECK (((((profile_id IS NOT NULL))::integer + ((team_id IS NOT NULL))::integer) = 1));
alter table emergency_response_roster add constraint emergency_roster_valid_window CHECK (((active_to IS NULL) OR (active_from IS NULL) OR (active_to > active_from)));
alter table emergency_response_roster add constraint emergency_response_roster_pkey PRIMARY KEY (id);
alter table notification_outbox add constraint notification_outbox_channel_check CHECK (((channel IS NULL) OR (channel = ANY (ARRAY['sms'::text, 'whatsapp'::text, 'email'::text, 'teams'::text, 'push'::text]))));
alter table evidence_items add constraint evidence_items_parent_type_check CHECK ((parent_type = ANY (ARRAY['work_order'::text, 'incident'::text])));
alter table evidence_items add constraint evidence_items_original_filename_check CHECK (((length(original_filename) >= 1) AND (length(original_filename) <= 255)));
alter table evidence_items add constraint evidence_items_description_check CHECK (((description IS NULL) OR (length(description) <= 500)));
alter table evidence_items add constraint evidence_parent_exactly_one CHECK ((((parent_type = 'work_order'::text) AND (work_order_id IS NOT NULL) AND (incident_id IS NULL)) OR ((parent_type = 'incident'::text) AND (incident_id IS NOT NULL) AND (work_order_id IS NULL))));
alter table evidence_items add constraint evidence_storage_path_check CHECK ((storage_path ~ '^evidence/(work-order|incident)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[^/]+$'::text));
alter table evidence_items add constraint evidence_items_pkey PRIMARY KEY (id);
alter table evidence_items add constraint evidence_items_storage_path_key UNIQUE (storage_path);
alter table asset_systems add constraint asset_systems_code_check CHECK (((length(btrim(system_code)) >= 1) AND (length(btrim(system_code)) <= 80)));
alter table asset_systems add constraint asset_systems_name_check CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 160)));
alter table asset_systems add constraint asset_systems_site_check CHECK (((length(btrim(site)) >= 1) AND (length(btrim(site)) <= 160)));
alter table asset_systems add constraint asset_systems_description_check CHECK (((description IS NULL) OR (length(description) <= 2000)));
alter table asset_systems add constraint asset_systems_pkey PRIMARY KEY (id);
alter table assets add constraint assets_criticality_check CHECK ((criticality = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text])));
alter table assets add constraint assets_lifecycle_status_check CHECK ((lifecycle_status = ANY (ARRAY['active'::text, 'out_of_service'::text, 'decommissioned'::text])));
alter table assets add constraint assets_tag_check CHECK (((length(btrim(asset_tag)) >= 1) AND (length(btrim(asset_tag)) <= 80)));
alter table assets add constraint assets_name_check CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 200)));
alter table assets add constraint assets_type_check CHECK (((length(btrim(asset_type)) >= 1) AND (length(btrim(asset_type)) <= 120)));
alter table assets add constraint assets_site_check CHECK (((length(btrim(site)) >= 1) AND (length(btrim(site)) <= 160)));
alter table assets add constraint assets_location_check CHECK (((length(btrim(location)) >= 1) AND (length(btrim(location)) <= 255)));
alter table assets add constraint assets_description_check CHECK (((description IS NULL) OR (length(description) <= 4000)));
alter table assets add constraint assets_decommissioned_timestamp_check CHECK ((((lifecycle_status = 'decommissioned'::text) AND (decommissioned_at IS NOT NULL)) OR ((lifecycle_status <> 'decommissioned'::text) AND (decommissioned_at IS NULL))));
alter table assets add constraint assets_pkey PRIMARY KEY (id);
alter table maintenance_requirement_number_counters add constraint maintenance_requirement_number_counters_last_value_check CHECK ((last_value > 0));
alter table maintenance_requirement_number_counters add constraint maintenance_requirement_number_counters_pkey PRIMARY KEY (reference_year);
alter table maintenance_requirements add constraint maintenance_requirements_state_check CHECK ((state = ANY (ARRAY['draft'::text, 'active'::text, 'inactive'::text])));
alter table maintenance_requirements add constraint maintenance_requirements_number_check CHECK ((requirement_number ~ '^PM-[0-9]{4}-[0-9]{6}$'::text));
alter table maintenance_requirements add constraint maintenance_requirements_pkey PRIMARY KEY (id);
alter table maintenance_requirements add constraint maintenance_requirements_requirement_number_key UNIQUE (requirement_number);
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_revision_number_check CHECK ((revision_number > 0));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_title_check CHECK (((length(btrim(title)) >= 3) AND (length(btrim(title)) <= 200)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_scope_check CHECK (((length(btrim(scope)) >= 3) AND (length(btrim(scope)) <= 4000)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_maintenance_type_check CHECK ((maintenance_type = ANY (ARRAY['preventive'::text, 'inspection'::text])));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_interval_value_check CHECK (((interval_value >= 1) AND (interval_value <= 365)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_interval_unit_check CHECK ((interval_unit = ANY (ARRAY['day'::text, 'week'::text, 'month'::text, 'year'::text])));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_lead_time_days_check CHECK (((lead_time_days >= 0) AND (lead_time_days <= 365)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_default_priority_check CHECK ((default_priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_estimated_hours_check CHECK (((estimated_hours IS NULL) OR (estimated_hours >= (0)::numeric)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_evidence_guidance_check CHECK (((evidence_guidance IS NULL) OR (length(evidence_guidance) <= 2000)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_instructions_check CHECK (((instructions IS NULL) OR (length(instructions) <= 4000)));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_procedure_reference_check CHECK (((procedure_reference IS NULL) OR (length(procedure_reference) <= 500)));
alter table maintenance_requirement_revisions add constraint maintenance_revision_anchor_check CHECK ((first_due_date >= effective_date));
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_pkey PRIMARY KEY (id);
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revis_requirement_id_revision_numbe_key UNIQUE (requirement_id, revision_number);
alter table pm_occurrences add constraint pm_occurrences_occurrence_number_check CHECK ((occurrence_number > 0));
alter table pm_occurrences add constraint pm_occurrences_generation_status_check CHECK ((generation_status = ANY (ARRAY['pending'::text, 'generated'::text, 'generation_failed'::text, 'cancelled'::text])));
alter table pm_occurrences add constraint pm_occurrences_generation_attempts_check CHECK ((generation_attempts >= 0));
alter table pm_occurrences add constraint pm_occurrence_due_check CHECK ((current_due_date >= original_due_date));
alter table pm_occurrences add constraint pm_occurrence_generated_check CHECK ((((generation_status = 'generated'::text) AND (generated_at IS NOT NULL)) OR ((generation_status <> 'generated'::text) AND (generated_at IS NULL))));
alter table pm_occurrences add constraint pm_occurrence_cancelled_check CHECK ((((generation_status = 'cancelled'::text) AND (cancelled_by IS NOT NULL) AND (cancellation_reason IS NOT NULL) AND (cancelled_at IS NOT NULL)) OR ((generation_status <> 'cancelled'::text) AND (cancelled_by IS NULL) AND (cancellation_reason IS NULL) AND (cancelled_at IS NULL))));
alter table pm_occurrences add constraint pm_occurrences_pkey PRIMARY KEY (id);
alter table pm_occurrences add constraint pm_occurrences_requirement_id_original_due_date_key UNIQUE (requirement_id, original_due_date);
alter table pm_occurrences add constraint pm_occurrences_requirement_revision_id_occurrence_number_key UNIQUE (requirement_revision_id, occurrence_number);
alter table pm_occurrence_deferrals add constraint pm_occurrence_deferrals_sequence_number_check CHECK ((sequence_number > 0));
alter table pm_occurrence_deferrals add constraint pm_occurrence_deferrals_reason_check CHECK (((length(btrim(reason)) >= 3) AND (length(btrim(reason)) <= 2000)));
alter table pm_occurrence_deferrals add constraint pm_deferral_date_check CHECK ((revised_due_date > previous_due_date));
alter table pm_occurrence_deferrals add constraint pm_occurrence_deferrals_pkey PRIMARY KEY (id);
alter table pm_occurrence_deferrals add constraint pm_occurrence_deferrals_occurrence_id_sequence_number_key UNIQUE (occurrence_id, sequence_number);
alter table work_orders add constraint work_orders_due_date_check CHECK (((due_date IS NULL) OR (pm_occurrence_id IS NOT NULL) OR (due_date >= (COALESCE(submitted_at, created_at))::date)));
alter table notification_outbox add constraint notification_outbox_target_check CHECK (((work_order_id IS NOT NULL) OR (incident_id IS NOT NULL) OR (pm_occurrence_id IS NOT NULL)));
alter table service_categories add constraint service_categories_code_check CHECK (((length(btrim(code)) >= 1) AND (length(btrim(code)) <= 40)));
alter table service_categories add constraint service_categories_name_check CHECK (((length(btrim(name)) >= 1) AND (length(btrim(name)) <= 160)));
alter table service_categories add constraint service_categories_pkey PRIMARY KEY (id);
alter table service_categories add constraint service_categories_code_key UNIQUE (code);
alter table sla_agreements add constraint sla_agreements_pkey PRIMARY KEY (id);
alter table sla_agreements add constraint sla_agreements_agreement_code_key UNIQUE (agreement_code);
alter table sla_agreement_versions add constraint sla_agreement_versions_version_number_check CHECK ((version_number > 0));
alter table sla_agreement_versions add constraint sla_agreement_versions_approval_status_check CHECK ((approval_status = ANY (ARRAY['draft'::text, 'pending_approval'::text, 'approved'::text, 'rejected'::text, 'superseded'::text])));
alter table sla_agreement_versions add constraint sla_agreement_versions_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)));
alter table sla_agreement_versions add constraint sla_agreement_versions_check1 CHECK (((approval_status = 'approved'::text) = ((approved_by IS NOT NULL) AND (approved_at IS NOT NULL))));
alter table sla_agreement_versions add constraint sla_agreement_versions_pkey PRIMARY KEY (id);
alter table sla_agreement_versions add constraint sla_agreement_versions_agreement_id_version_number_key UNIQUE (agreement_id, version_number);
alter table sla_rules add constraint sla_rules_priority_class_check CHECK ((priority_class = ANY (ARRAY['P1'::text, 'P2'::text, 'P3'::text, 'P4'::text])));
alter table sla_rules add constraint sla_rules_work_order_priority_check CHECK ((work_order_priority = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text])));
alter table sla_rules add constraint sla_rules_acknowledgement_minutes_check CHECK ((acknowledgement_minutes > 0));
alter table sla_rules add constraint sla_rules_response_minutes_check CHECK ((response_minutes > 0));
alter table sla_rules add constraint sla_rules_attendance_minutes_check CHECK ((attendance_minutes > 0));
alter table sla_rules add constraint sla_rules_make_safe_minutes_check CHECK ((make_safe_minutes > 0));
alter table sla_rules add constraint sla_rules_rectification_minutes_check CHECK ((rectification_minutes > 0));
alter table sla_rules add constraint sla_rules_kpi_target_percent_check CHECK (((kpi_target_percent >= (0)::numeric) AND (kpi_target_percent <= (100)::numeric)));
alter table sla_rules add constraint sla_rules_pkey PRIMARY KEY (id);
alter table sla_rules add constraint sla_rules_version_id_service_category_id_priority_class_key UNIQUE (version_id, service_category_id, priority_class);
alter table sla_extraction_proposals add constraint sla_extraction_proposals_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
alter table sla_extraction_proposals add constraint sla_extraction_proposals_human_approval_state_check CHECK ((human_approval_state = ANY (ARRAY['pending'::text, 'approved_for_draft'::text, 'rejected'::text])));
alter table sla_extraction_proposals add constraint sla_extraction_proposals_check CHECK (((human_approval_state = 'pending'::text) OR (reviewed_by IS NOT NULL)));
alter table sla_extraction_proposals add constraint sla_extraction_proposals_pkey PRIMARY KEY (id);
alter table work_order_sla_clocks add constraint work_order_sla_clocks_risk_state_check CHECK ((risk_state = ANY (ARRAY['on_track'::text, 'at_risk'::text, 'breached'::text, 'met'::text])));
alter table work_order_sla_clocks add constraint work_order_sla_clocks_pkey PRIMARY KEY (work_order_id);
alter table escalation_matrix_steps add constraint escalation_matrix_steps_threshold_percent_check CHECK (((threshold_percent >= (0)::numeric) AND (threshold_percent <= (100)::numeric)));
alter table escalation_matrix_steps add constraint escalation_matrix_steps_escalation_level_check CHECK ((escalation_level = ANY (ARRAY['warning'::text, 'supervisor'::text, 'facilities_engineer'::text, 'facility_manager'::text, 'contract_fm_manager'::text, 'client_management'::text, 'breach'::text])));
alter table escalation_matrix_steps add constraint escalation_matrix_steps_pkey PRIMARY KEY (id);
alter table escalation_matrix_steps add constraint escalation_matrix_steps_version_id_threshold_percent_escala_key UNIQUE (version_id, threshold_percent, escalation_level);
alter table sla_escalation_events add constraint sla_escalation_events_pkey PRIMARY KEY (id);
alter table sla_escalation_events add constraint sla_escalation_events_work_order_id_matrix_step_id_key UNIQUE (work_order_id, matrix_step_id);
alter table sites add constraint sites_pkey PRIMARY KEY (id);
alter table sites add constraint sites_code_key UNIQUE (code);
alter table buildings add constraint buildings_pkey PRIMARY KEY (id);
alter table buildings add constraint buildings_site_id_code_key UNIQUE (site_id, code);
alter table location_levels add constraint location_levels_pkey PRIMARY KEY (id);
alter table location_levels add constraint location_levels_building_id_code_key UNIQUE (building_id, code);
alter table location_zones add constraint location_zones_zone_type_check CHECK ((zone_type = ANY (ARRAY['zone'::text, 'room'::text])));
alter table location_zones add constraint location_zones_pkey PRIMARY KEY (id);
alter table location_zones add constraint location_zones_level_id_code_key UNIQUE (level_id, code);
alter table report_schedules add constraint report_schedules_cadence_check CHECK ((cadence = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text])));
alter table report_schedules add constraint report_schedules_last_delivery_status_check CHECK ((last_delivery_status = ANY (ARRAY['NOT_CONFIGURED'::text, 'GENERATED'::text, 'DELIVERED'::text, 'FAILED'::text])));
alter table report_schedules add constraint report_schedules_pkey PRIMARY KEY (id);
alter table report_runs add constraint report_runs_report_type_check CHECK ((report_type = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text, 'custom'::text])));
alter table report_runs add constraint report_runs_delivery_status_check CHECK ((delivery_status = ANY (ARRAY['NOT_CONFIGURED'::text, 'GENERATED'::text, 'DELIVERED'::text, 'FAILED'::text])));
alter table report_runs add constraint report_runs_check CHECK ((period_end >= period_start));
alter table report_runs add constraint report_runs_pkey PRIMARY KEY (id);
alter table sla_documents add constraint sla_documents_maintenance_model_check CHECK ((maintenance_model = ANY (ARRAY['IN_HOUSE'::text, 'OUTSOURCED'::text, 'HYBRID'::text])));
alter table sla_documents add constraint sla_documents_media_type_check CHECK ((media_type = ANY (ARRAY['application/pdf'::text, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'::text, 'text/plain'::text])));
alter table sla_documents add constraint sla_documents_byte_size_check CHECK (((byte_size >= 1) AND (byte_size <= 10485760)));
alter table sla_documents add constraint sla_documents_content_sha256_check CHECK ((content_sha256 ~ '^[0-9a-f]{64}$'::text));
alter table sla_documents add constraint sla_documents_storage_provider_check CHECK ((storage_provider = ANY (ARRAY['PILOT_DATABASE'::text, 'FUTURE_APPROVED_PROVIDER'::text])));
alter table sla_documents add constraint sla_documents_review_status_check CHECK ((review_status = ANY (ARRAY['NOT_EXTRACTED'::text, 'EXTRACTED'::text, 'IN_REVIEW'::text, 'REVIEWED'::text, 'REJECTED'::text])));
alter table sla_documents add constraint sla_documents_approval_status_check CHECK ((approval_status = ANY (ARRAY['DRAFT'::text, 'PENDING_APPROVAL'::text, 'APPROVED'::text, 'REJECTED'::text])));
alter table sla_documents add constraint sla_documents_check CHECK (((expiry_date IS NULL) OR (effective_date IS NULL) OR (expiry_date >= effective_date)));
alter table sla_documents add constraint sla_documents_pkey PRIMARY KEY (id);
alter table sla_documents add constraint sla_documents_storage_key_key UNIQUE (storage_key);
alter table sla_documents add constraint sla_documents_agreement_reference_version_label_key UNIQUE (agreement_reference, version_label);
alter table staffing_assessments add constraint staffing_assessments_operating_model_check CHECK ((operating_model = ANY (ARRAY['IN_HOUSE'::text, 'OUTSOURCED'::text, 'HYBRID'::text])));
alter table staffing_assessments add constraint staffing_assessments_status_check CHECK ((status = ANY (ARRAY['DRAFT'::text, 'ANALYSED'::text, 'REVIEWED'::text, 'ARCHIVED'::text])));
alter table staffing_assessments add constraint staffing_assessments_pkey PRIMARY KEY (id);
alter table staffing_recommendations add constraint staffing_recommendations_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
alter table staffing_recommendations add constraint staffing_recommendations_pkey PRIMARY KEY (id);
alter table sla_documents add constraint sla_documents_parser_status_check CHECK ((parser_status = ANY (ARRAY['PENDING'::text, 'EXTRACTED'::text, 'PARTIAL'::text, 'UNSUPPORTED'::text, 'FAILED'::text, 'REQUIRES_OCR'::text])));
alter table ai_provider_configurations add constraint ai_provider_configurations_provider_type_check CHECK ((provider_type = ANY (ARRAY['DISABLED'::text, 'MOCK'::text, 'APPROVED_PROVIDER'::text])));
alter table ai_provider_configurations add constraint ai_provider_configurations_approved_status_check CHECK ((approved_status = ANY (ARRAY['NOT_APPROVED'::text, 'APPROVED'::text, 'REVOKED'::text])));
alter table ai_provider_configurations add constraint ai_provider_configurations_timeout_ms_check CHECK (((timeout_ms >= 100) AND (timeout_ms <= 120000)));
alter table ai_provider_configurations add constraint ai_provider_configurations_max_retries_check CHECK (((max_retries >= 0) AND (max_retries <= 2)));
alter table ai_provider_configurations add constraint ai_provider_configurations_pkey PRIMARY KEY (id);
alter table ai_prompt_versions add constraint ai_prompt_versions_status_check CHECK ((status = ANY (ARRAY['DRAFT'::text, 'APPROVED'::text, 'RETIRED'::text])));
alter table ai_prompt_versions add constraint ai_prompt_versions_pkey PRIMARY KEY (id);
alter table ai_prompt_versions add constraint ai_prompt_versions_prompt_identifier_version_key UNIQUE (prompt_identifier, version);
alter table ai_operation_audit add constraint ai_operation_audit_pkey PRIMARY KEY (id);
alter table profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['reviewer'::text, 'initiator'::text, 'approver'::text, 'technician'::text, 'supervisor'::text, 'facility_manager'::text, 'administrator'::text])));
alter table account_invitations add constraint account_invitations_role_check CHECK ((assigned_role = ANY (ARRAY['reviewer'::text, 'initiator'::text, 'approver'::text, 'technician'::text, 'supervisor'::text, 'facility_manager'::text, 'administrator'::text])));
alter table evidence_items add constraint evidence_items_category_check CHECK ((category = ANY (ARRAY['before'::text, 'after'::text, 'completion'::text, 'document'::text, 'other'::text])));
alter table vendors add constraint vendors_payment_terms_days_check CHECK ((payment_terms_days > 0));
alter table contractor_service_categories add constraint contractor_service_categories_pkey PRIMARY KEY (id);
alter table contractor_service_categories add constraint contractor_service_categories_code_key UNIQUE (code);
alter table contractor_services add constraint contractor_services_pkey PRIMARY KEY (vendor_id, service_category_id);
alter table contractor_rate_items add constraint contractor_rate_items_cost_type_check CHECK ((cost_type = ANY (ARRAY['labour'::text, 'material'::text, 'equipment'::text, 'service'::text, 'callout'::text])));
alter table contractor_rate_items add constraint contractor_rate_items_normal_unit_rate_check CHECK ((normal_unit_rate >= (0)::numeric));
alter table contractor_rate_items add constraint contractor_rate_items_emergency_unit_rate_check CHECK (((emergency_unit_rate IS NULL) OR (emergency_unit_rate >= (0)::numeric)));
alter table contractor_rate_items add constraint contractor_rate_items_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)));
alter table contractor_rate_items add constraint contractor_rate_items_pkey PRIMARY KEY (id);
alter table work_order_cost_lines add constraint work_order_cost_lines_cost_type_check CHECK ((cost_type = ANY (ARRAY['labour'::text, 'material'::text, 'equipment'::text, 'service'::text, 'callout'::text])));
alter table work_order_cost_lines add constraint work_order_cost_lines_quantity_check CHECK ((quantity >= (0)::numeric));
alter table work_order_cost_lines add constraint work_order_cost_lines_unit_rate_check CHECK ((unit_rate >= (0)::numeric));
alter table work_order_cost_lines add constraint work_order_cost_lines_pkey PRIMARY KEY (id);
alter table contractor_payment_assessments add constraint contractor_payment_assessments_assessed_amount_check CHECK ((assessed_amount >= (0)::numeric));
alter table contractor_payment_assessments add constraint contractor_payment_assessments_pkey PRIMARY KEY (id);
alter table contractor_payment_assessments add constraint contractor_payment_assessments_work_order_id_key UNIQUE (work_order_id);
alter table facility_areas add constraint facility_areas_pkey PRIMARY KEY (id);
alter table facility_areas add constraint facility_areas_area_code_key UNIQUE (area_code);
alter table authorised_work_liaisons add constraint authorised_work_liaisons_discipline_check CHECK ((discipline = ANY (ARRAY['building_fitout_landscaping'::text, 'electrical_mechanical'::text])));
alter table authorised_work_liaisons add constraint authorised_work_liaisons_check CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)));
alter table authorised_work_liaisons add constraint authorised_work_liaisons_pkey PRIMARY KEY (id);
alter table facility_memberships add constraint facility_memberships_membership_role_check CHECK ((membership_role = ANY (ARRAY['technician'::text, 'supervisor'::text, 'facility_manager'::text])));
alter table facility_memberships add constraint facility_memberships_period_check CHECK (((effective_to IS NULL) OR (effective_to > effective_from)));
alter table facility_memberships add constraint facility_memberships_pkey PRIMARY KEY (id);
alter table work_order_approval_basis add constraint work_order_approval_basis_cost_basis_check CHECK ((btrim(cost_basis) <> ''::text));
alter table work_order_approval_basis add constraint work_order_approval_basis_execution_arrangement_check CHECK ((btrim(execution_arrangement) <> ''::text));
alter table work_order_approval_basis add constraint work_order_approval_basis_safety_isolation_information_check CHECK ((btrim(safety_isolation_information) <> ''::text));
alter table work_order_approval_basis add constraint work_order_approval_basis_board_fields CHECK ((((board_approval_reference IS NULL) AND (board_approval_date IS NULL) AND (board_supporting_document_reference IS NULL)) OR ((NULLIF(btrim(board_approval_reference), ''::text) IS NOT NULL) AND (board_approval_date IS NOT NULL) AND (NULLIF(btrim(board_supporting_document_reference), ''::text) IS NOT NULL))));
alter table work_order_approval_basis add constraint work_order_approval_basis_pkey PRIMARY KEY (work_order_id);
alter table work_orders add constraint work_orders_primary_assignment_check CHECK (((
CASE
    WHEN (assigned_vendor_id IS NULL) THEN 0
    ELSE 1
END +
CASE
    WHEN (assigned_team_id IS NULL) THEN 0
    ELSE 1
END) <= 1));
alter table contractor_quotations add constraint contractor_quotations_version_no_check CHECK ((version_no > 0));
alter table contractor_quotations add constraint contractor_quotations_currency_check CHECK ((currency = 'SGD'::text));
alter table contractor_quotations add constraint contractor_quotations_total_amount_check CHECK ((total_amount >= (0)::numeric));
alter table contractor_quotations add constraint contractor_quotations_pkey PRIMARY KEY (id);
alter table contractor_quotations add constraint contractor_quotations_work_order_id_quotation_ref_version_n_key UNIQUE (work_order_id, quotation_ref, version_no);
alter table contractor_quotation_lines add constraint contractor_quotation_lines_line_no_check CHECK ((line_no > 0));
alter table contractor_quotation_lines add constraint contractor_quotation_lines_cost_type_check CHECK ((cost_type = ANY (ARRAY['labour'::text, 'material'::text, 'equipment'::text, 'service'::text, 'callout'::text])));
alter table contractor_quotation_lines add constraint contractor_quotation_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table contractor_quotation_lines add constraint contractor_quotation_lines_agreed_unit_rate_check CHECK ((agreed_unit_rate >= (0)::numeric));
alter table contractor_quotation_lines add constraint contractor_quotation_lines_quoted_unit_rate_check CHECK ((quoted_unit_rate >= (0)::numeric));
alter table contractor_quotation_lines add constraint contractor_quotation_lines_check CHECK ((((NOT rate_exception) AND (quoted_unit_rate = agreed_unit_rate) AND (exception_reason IS NULL)) OR (rate_exception AND (quoted_unit_rate <> agreed_unit_rate) AND (NULLIF(btrim(exception_reason), ''::text) IS NOT NULL))));
alter table contractor_quotation_lines add constraint contractor_quotation_lines_pkey PRIMARY KEY (id);
alter table contractor_quotation_lines add constraint contractor_quotation_lines_quotation_id_line_no_key UNIQUE (quotation_id, line_no);
alter table contractor_actual_imports add constraint contractor_actual_imports_import_kind_check CHECK ((import_kind = ANY (ARRAY['personnel'::text, 'materials'::text, 'equipment_services'::text, 'mixed'::text])));
alter table contractor_actual_imports add constraint contractor_actual_imports_currency_check CHECK ((currency = 'SGD'::text));
alter table contractor_actual_imports add constraint contractor_actual_imports_total_amount_check CHECK ((total_amount >= (0)::numeric));
alter table contractor_actual_imports add constraint contractor_actual_imports_exception_count_check CHECK ((exception_count >= 0));
alter table contractor_actual_imports add constraint contractor_actual_imports_pkey PRIMARY KEY (id);
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_line_no_check CHECK ((line_no > 0));
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_cost_type_check CHECK ((cost_type = ANY (ARRAY['labour'::text, 'material'::text, 'equipment'::text, 'service'::text, 'callout'::text])));
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_agreed_unit_rate_check CHECK ((agreed_unit_rate >= (0)::numeric));
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_actual_unit_rate_check CHECK ((actual_unit_rate >= (0)::numeric));
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_check CHECK ((((NOT rate_exception) AND (actual_unit_rate = agreed_unit_rate) AND (exception_reason IS NULL)) OR (rate_exception AND (actual_unit_rate <> agreed_unit_rate) AND (NULLIF(btrim(exception_reason), ''::text) IS NOT NULL))));
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_pkey PRIMARY KEY (id);
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_import_id_line_no_key UNIQUE (import_id, line_no);
alter table work_order_cost_lines add constraint work_order_cost_lines_cost_phase_check CHECK ((cost_phase = ANY (ARRAY['proposed'::text, 'actual'::text])));
alter table work_orders add constraint work_orders_actual_cost_confirmation_check CHECK ((((actual_costs_confirmed_at IS NULL) AND (actual_costs_confirmed_by IS NULL)) OR ((actual_costs_confirmed_at IS NOT NULL) AND (actual_costs_confirmed_by IS NOT NULL))));
alter table work_order_markups add constraint work_order_markups_source_type_check CHECK ((source_type = ANY (ARRAY['drawing'::text, 'pdf'::text])));
alter table work_order_markups add constraint work_order_markups_source_reference_check CHECK (((length(btrim(source_reference)) >= 1) AND (length(btrim(source_reference)) <= 200)));
alter table work_order_markups add constraint work_order_markups_page_number_check CHECK (((page_number IS NULL) OR (page_number > 0)));
alter table work_order_markups add constraint work_order_markups_x_percent_check CHECK (((x_percent >= (0)::numeric) AND (x_percent <= (100)::numeric)));
alter table work_order_markups add constraint work_order_markups_y_percent_check CHECK (((y_percent >= (0)::numeric) AND (y_percent <= (100)::numeric)));
alter table work_order_markups add constraint work_order_markups_note_check CHECK (((length(btrim(note)) >= 1) AND (length(btrim(note)) <= 1000)));
alter table work_order_markups add constraint work_order_markups_pkey PRIMARY KEY (id);
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_purchase_reference_check CHECK (((length(btrim(purchase_reference)) >= 1) AND (length(btrim(purchase_reference)) <= 120)));
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_description_check CHECK (((length(btrim(description)) >= 1) AND (length(btrim(description)) <= 1000)));
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_currency_check CHECK ((currency = 'SGD'::text));
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_committed_amount_check CHECK ((committed_amount >= (0)::numeric));
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'ordered'::text, 'received'::text, 'cancelled'::text])));
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_pkey PRIMARY KEY (id);
alter table work_order_procurement_commitments add constraint work_order_procurement_commit_work_order_id_purchase_refere_key UNIQUE (work_order_id, purchase_reference);
alter table work_order_markups add constraint work_order_markups_annotation_type_check CHECK ((annotation_type = ANY (ARRAY['marker'::text, 'arrow'::text, 'circle'::text, 'rectangle'::text, 'freehand'::text, 'text'::text])));
alter table work_order_markups add constraint work_order_markups_drawing_revision_check CHECK (((length(btrim(drawing_revision)) >= 1) AND (length(btrim(drawing_revision)) <= 80)));
alter table work_order_markups add constraint work_order_markups_geometry_check CHECK (((jsonb_typeof(geometry) = 'object'::text) AND (octet_length((geometry)::text) <= 20000)));
alter table commercial_approval_rules add constraint commercial_approval_rules_currency_check CHECK ((currency = 'SGD'::text));
alter table commercial_approval_rules add constraint commercial_approval_rules_minimum_amount_check CHECK ((minimum_amount >= (0)::numeric));
alter table commercial_approval_rules add constraint commercial_approval_rules_check CHECK (((maximum_amount IS NULL) OR (maximum_amount > minimum_amount)));
alter table commercial_approval_rules add constraint commercial_approval_rules_minimum_quotations_check CHECK ((minimum_quotations > 0));
alter table commercial_approval_rules add constraint commercial_approval_rules_pkey PRIMARY KEY (id);
alter table commercial_approval_rules add constraint commercial_approval_rules_rule_code_key UNIQUE (rule_code);
alter table work_order_financial_controls add constraint work_order_financial_controls_currency_check CHECK ((currency = 'SGD'::text));
alter table work_order_financial_controls add constraint work_order_financial_controls_estimated_cost_check CHECK ((estimated_cost >= (0)::numeric));
alter table work_order_financial_controls add constraint work_order_financial_controls_quoted_cost_check CHECK (((quoted_cost IS NULL) OR (quoted_cost >= (0)::numeric)));
alter table work_order_financial_controls add constraint work_order_financial_controls_approved_budget_check CHECK (((approved_budget IS NULL) OR (approved_budget >= (0)::numeric)));
alter table work_order_financial_controls add constraint work_order_financial_controls_cost_status_check CHECK ((cost_status = ANY (ARRAY['draft'::text, 'quotation_recorded'::text, 'recommended'::text, 'approved'::text, 'returned'::text])));
alter table work_order_financial_controls add constraint work_order_financial_controls_check CHECK ((((recommended_by IS NULL) AND (recommended_at IS NULL)) OR ((recommended_by IS NOT NULL) AND (recommended_at IS NOT NULL))));
alter table work_order_financial_controls add constraint work_order_financial_controls_check1 CHECK ((((financial_approved_by IS NULL) AND (financial_approved_at IS NULL)) OR ((financial_approved_by IS NOT NULL) AND (financial_approved_at IS NOT NULL))));
alter table work_order_financial_controls add constraint work_order_financial_controls_check2 CHECK (((financial_approved_by IS NULL) OR (financial_approved_by IS DISTINCT FROM recommended_by)));
alter table work_order_financial_controls add constraint work_order_financial_controls_pkey PRIMARY KEY (work_order_id);
alter table contractor_quotations add constraint contractor_quotations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'returned'::text, 'rejected'::text, 'superseded'::text])));
alter table contractor_payment_assessments add constraint contractor_payment_assessments_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'awaiting_approval'::text, 'approved_for_payment'::text, 'paid'::text, 'returned'::text])));
alter table contractor_payment_assessments add constraint contractor_payment_assessments_paid_amount_check CHECK (((paid_amount IS NULL) OR (paid_amount >= (0)::numeric)));
alter table work_order_commercial_documents add constraint work_order_commercial_documents_document_type_check CHECK ((document_type = ANY (ARRAY['quotation'::text, 'invoice'::text])));
alter table work_order_commercial_documents add constraint work_order_commercial_documents_original_filename_check CHECK (((length(original_filename) >= 1) AND (length(original_filename) <= 255)));
alter table work_order_commercial_documents add constraint work_order_commercial_documents_content_type_check CHECK ((content_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'application/pdf'::text])));
alter table work_order_commercial_documents add constraint work_order_commercial_documents_byte_size_check CHECK (((byte_size >= 1) AND (byte_size <= 10485760)));
alter table work_order_commercial_documents add constraint work_order_commercial_documents_check CHECK ((((document_type = 'quotation'::text) AND (quotation_id IS NOT NULL) AND (payment_assessment_id IS NULL)) OR ((document_type = 'invoice'::text) AND (quotation_id IS NULL) AND (payment_assessment_id IS NOT NULL))));
alter table work_order_commercial_documents add constraint work_order_commercial_documents_pkey PRIMARY KEY (id);
alter table work_order_commercial_documents add constraint work_order_commercial_documents_storage_path_key UNIQUE (storage_path);
alter table work_order_document_corrections add constraint work_order_document_corrections_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])));
alter table work_order_document_corrections add constraint work_order_document_corrections_reason_check CHECK (((length(reason) >= 3) AND (length(reason) <= 1000)));
alter table work_order_document_corrections add constraint work_order_document_corrections_pkey PRIMARY KEY (id);
alter table vendor_facility_eligibility add constraint vendor_facility_eligibility_confirmation_basis_check CHECK (((length(btrim(confirmation_basis)) >= 1) AND (length(btrim(confirmation_basis)) <= 1000)));
alter table vendor_facility_eligibility add constraint vendor_facility_eligibility_pkey PRIMARY KEY (vendor_id, facility_id);
alter table evidence_items add constraint evidence_items_content_type_check CHECK ((content_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'video/mp4'::text, 'video/webm'::text, 'application/pdf'::text])));
alter table evidence_items add constraint evidence_items_byte_size_check CHECK (((byte_size >= 1) AND (byte_size <= 52428800)));
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'confirmed'::text, 'variance_pending'::text, 'variance_approved'::text])));
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_actual_labour_hours_check CHECK ((actual_labour_hours >= (0)::numeric));
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_final_contractor_amount_check CHECK ((final_contractor_amount >= (0)::numeric));
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_confirmed_actual_cost_check CHECK ((confirmed_actual_cost >= (0)::numeric));
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_comments_check CHECK (((length(comments) >= 3) AND (length(comments) <= 2000)));
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_pkey PRIMARY KEY (id);
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_work_order_id_key UNIQUE (work_order_id);
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_content_type_check CHECK ((content_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text, 'application/pdf'::text])));
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_byte_size_check CHECK (((byte_size >= 1) AND (byte_size <= 10485760)));
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_pkey PRIMARY KEY (id);
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_storage_path_key UNIQUE (storage_path);
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_disposition_type_check CHECK ((disposition_type = 'no_payment_required'::text));
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_reason_code_check CHECK ((reason_code = ANY (ARRAY['in_house'::text, 'warranty'::text, 'goodwill'::text, 'zero_cost'::text, 'other'::text])));
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_reason_check CHECK (((length(btrim(reason)) >= 3) AND (length(btrim(reason)) <= 1000)));
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'approved'::text, 'rejected'::text])));
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_check CHECK (((approved_by IS NULL) OR (approved_by IS DISTINCT FROM proposed_by)));
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_check1 CHECK ((((status = 'approved'::text) AND (approved_by IS NOT NULL) AND (approved_at IS NOT NULL) AND (approval_note IS NOT NULL)) OR ((status <> 'approved'::text) AND (approved_by IS NULL) AND (approved_at IS NULL))));
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_pkey PRIMARY KEY (id);
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_work_order_id_key UNIQUE (work_order_id);
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.current_user_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select profile.role
  from public.profiles as profile
  where profile.id = auth.uid()
    and public.pilot_account_ready(profile.id)
$function$
;
CREATE OR REPLACE FUNCTION public.next_work_order_number(reference_time timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_reference_year integer := extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.work_order_number_counters (reference_year, last_value)
  values (v_reference_year, 1)
  on conflict (reference_year) do update
    set last_value = public.work_order_number_counters.last_value + 1
  returning last_value into reference_value;
  return pg_catalog.format(
    'FW-%s-%s', v_reference_year, pg_catalog.lpad(reference_value::text, 4, '0')
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_work_order_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if new.work_order_number is null or pg_catalog.btrim(new.work_order_number) = '' then
    new.work_order_number := public.next_work_order_number(
      coalesce(new.created_at, pg_catalog.now())
    );
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_row_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.updated_at := pg_catalog.now();
  return new;
end
$function$
;
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  invitation_token text := new.raw_user_meta_data ->> 'administrator_invitation_token';
  invitation public.account_invitations%rowtype;
begin
  if invitation_token is not null then
    select candidate.*
    into invitation
    from public.account_invitations as candidate
    where candidate.token_hash = pg_catalog.encode(
        extensions.digest(invitation_token, 'sha256'),
        'hex'
      )
      and pg_catalog.lower(candidate.email) = pg_catalog.lower(coalesce(new.email, ''))
      and candidate.is_active = true
      and candidate.used_at is null
      and candidate.expires_at > pg_catalog.now()
    for update;

    if invitation.id is null then
      raise exception 'Invalid, expired or previously used invitation';
    end if;

    insert into public.profiles (
      id, display_name, email, department, department_id,
      trade_discipline, contact_number, role, is_active,
      password_change_required, created_at, updated_at
    ) values (
      new.id,
      invitation.display_name,
      new.email,
      invitation.department,
      null,
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'trade_discipline'), ''),
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'contact_number'), ''),
      invitation.assigned_role,
      false,
      true,
      coalesce(new.created_at, pg_catalog.now()),
      pg_catalog.now()
    ) on conflict (id) do nothing;

    update public.account_invitations as candidate
    set used_at = pg_catalog.now()
    where candidate.id = invitation.id;

    return new;
  end if;

  insert into public.profiles (
    id, display_name, email, department, trade_discipline,
    contact_number, role, is_active, password_change_required,
    created_at, updated_at
  ) values (
    new.id,
    coalesce(
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'display_name'), ''),
      nullif(pg_catalog.split_part(coalesce(new.email, ''), '@', 1), ''),
      'Pending account'
    ),
    new.email,
    nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'department'), ''),
    null,
    null,
    'reviewer',
    false,
    true,
    coalesce(new.created_at, pg_catalog.now()),
    pg_catalog.now()
  ) on conflict (id) do nothing;

  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_department_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.code := upper(trim(new.code));
  new.name := trim(new.name);
  new.description := nullif(trim(new.description), '');
  new.cost_centre := nullif(trim(new.cost_centre), '');
  new.colour_tag := nullif(trim(new.colour_tag), '');
  new.updated_at := now();
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.sync_profile_department_label()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if new.department_id is null then return new; end if;
  select d.name into new.department
  from public.departments d
  where d.id = new.department_id and d.deleted_at is null;
  if new.department is null then raise exception 'Selected department is unavailable'; end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.create_department(p_code text, p_name text, p_description text DEFAULT NULL::text, p_cost_centre text DEFAULT NULL::text, p_manager_id uuid DEFAULT NULL::uuid, p_parent_department_id uuid DEFAULT NULL::uuid, p_colour_tag text DEFAULT NULL::text, p_is_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor_id uuid := auth.uid();
  actor_name text;
  normalized_code text := upper(trim(coalesce(p_code, '')));
  normalized_name text := trim(coalesce(p_name, ''));
  normalized_colour text := nullif(trim(coalesce(p_colour_tag, '')), '');
  result public.departments%rowtype;
begin
  select profile.display_name
    into actor_name
  from public.profiles as profile
  where profile.id = actor_id
    and profile.role = 'administrator'
    and profile.is_active = true
    and profile.deleted_at is null;

  if actor_name is null then
    return jsonb_build_object('ok', false, 'code', 'access_denied', 'message', 'Administrator access is required.');
  end if;
  if normalized_code !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_code', 'message', 'Department code is invalid.');
  end if;
  if normalized_name = '' or length(normalized_name) > 120 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name', 'message', 'Department name is invalid.');
  end if;
  if normalized_colour is not null and normalized_colour !~ '^#[0-9A-Fa-f]{6}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_colour', 'message', 'Department colour is invalid.');
  end if;
  if p_parent_department_id is not null and not exists (
    select 1 from public.departments
    where id = p_parent_department_id and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_parent', 'message', 'Parent department is unavailable.');
  end if;
  if p_manager_id is not null and not exists (
    select 1 from public.profiles
    where id = p_manager_id and is_active = true and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_manager', 'message', 'Department manager is unavailable.');
  end if;
  if exists (
    select 1 from public.departments
    where deleted_at is null
      and (lower(code) = lower(normalized_code) or lower(name) = lower(normalized_name))
  ) then
    return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
  end if;

  begin
    insert into public.departments (
      code, name, description, cost_centre, manager_id,
      parent_department_id, colour_tag, is_active, created_by
    ) values (
      normalized_code,
      normalized_name,
      nullif(trim(coalesce(p_description, '')), ''),
      nullif(trim(coalesce(p_cost_centre, '')), ''),
      p_manager_id,
      p_parent_department_id,
      normalized_colour,
      coalesce(p_is_active, true),
      actor_id
    ) returning * into result;

    insert into public.activity_logs (user_id, action, actor, note)
    values (
      actor_id,
      'department_admin_created',
      actor_name,
      jsonb_build_object('department_id', result.id, 'code', result.code, 'name', result.name)::text
    );

    return jsonb_build_object('ok', true, 'department', to_jsonb(result));
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
    when foreign_key_violation then
      return jsonb_build_object('ok', false, 'code', 'invalid_reference', 'message', 'A selected department reference is unavailable.');
    when others then
      return jsonb_build_object('ok', false, 'code', 'internal_error', 'message', 'Department creation failed.');
  end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.update_department(p_department_id uuid, p_code text, p_name text, p_description text DEFAULT NULL::text, p_cost_centre text DEFAULT NULL::text, p_manager_id uuid DEFAULT NULL::uuid, p_parent_department_id uuid DEFAULT NULL::uuid, p_colour_tag text DEFAULT NULL::text, p_is_active boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor_id uuid := auth.uid();
  actor_name text;
  normalized_code text := upper(trim(coalesce(p_code, '')));
  normalized_name text := trim(coalesce(p_name, ''));
  normalized_colour text := nullif(trim(coalesce(p_colour_tag, '')), '');
  previous public.departments%rowtype;
  result public.departments%rowtype;
begin
  select profile.display_name
    into actor_name
  from public.profiles as profile
  where profile.id = actor_id
    and profile.role = 'administrator'
    and profile.is_active = true
    and profile.deleted_at is null;

  if actor_name is null then
    return jsonb_build_object('ok', false, 'code', 'access_denied', 'message', 'Administrator access is required.');
  end if;
  if p_department_id is null then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'Department not found.');
  end if;
  if normalized_code !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_code', 'message', 'Department code is invalid.');
  end if;
  if normalized_name = '' or length(normalized_name) > 120 then
    return jsonb_build_object('ok', false, 'code', 'invalid_name', 'message', 'Department name is invalid.');
  end if;
  if normalized_colour is not null and normalized_colour !~ '^#[0-9A-Fa-f]{6}$' then
    return jsonb_build_object('ok', false, 'code', 'invalid_colour', 'message', 'Department colour is invalid.');
  end if;
  if p_parent_department_id = p_department_id then
    return jsonb_build_object('ok', false, 'code', 'self_parent', 'message', 'A department cannot be its own parent.');
  end if;
  if p_parent_department_id is not null and not exists (
    select 1 from public.departments
    where id = p_parent_department_id and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_parent', 'message', 'Parent department is unavailable.');
  end if;
  if p_manager_id is not null and not exists (
    select 1 from public.profiles
    where id = p_manager_id and is_active = true and deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'code', 'invalid_manager', 'message', 'Department manager is unavailable.');
  end if;

  select * into previous
  from public.departments
  where id = p_department_id and deleted_at is null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'Department not found.');
  end if;
  if exists (
    select 1 from public.departments
    where id <> p_department_id
      and deleted_at is null
      and (lower(code) = lower(normalized_code) or lower(name) = lower(normalized_name))
  ) then
    return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
  end if;

  begin
    update public.departments
    set code = normalized_code,
        name = normalized_name,
        description = nullif(trim(coalesce(p_description, '')), ''),
        cost_centre = nullif(trim(coalesce(p_cost_centre, '')), ''),
        manager_id = p_manager_id,
        parent_department_id = p_parent_department_id,
        colour_tag = normalized_colour,
        is_active = coalesce(p_is_active, true)
    where id = p_department_id
    returning * into result;

    if previous.name is distinct from result.name then
      update public.profiles
      set department = result.name
      where department_id = p_department_id;
    end if;

    insert into public.activity_logs (user_id, action, actor, note)
    values (
      actor_id,
      'department_admin_updated',
      actor_name,
      jsonb_build_object(
        'department_id', result.id,
        'previous_code', previous.code,
        'code', result.code,
        'previous_name', previous.name,
        'name', result.name
      )::text
    );

    return jsonb_build_object('ok', true, 'department', to_jsonb(result));
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'code', 'duplicate_department', 'message', 'An active department already uses that code or name.');
    when foreign_key_violation then
      return jsonb_build_object('ok', false, 'code', 'invalid_reference', 'message', 'A selected department reference is unavailable.');
    when others then
      return jsonb_build_object('ok', false, 'code', 'internal_error', 'message', 'Department update failed.');
  end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.archive_department(p_department_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor_id uuid := auth.uid();
  actor_name text;
  active_user_count bigint;
  result public.departments%rowtype;
begin
  select profile.display_name
    into actor_name
  from public.profiles as profile
  where profile.id = actor_id
    and profile.role = 'administrator'
    and profile.is_active = true
    and profile.deleted_at is null;

  if actor_name is null then
    return jsonb_build_object('ok', false, 'code', 'access_denied', 'message', 'Administrator access is required.');
  end if;

  select * into result
  from public.departments
  where id = p_department_id and deleted_at is null
  for update;
  if not found then
    return jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'Department not found.');
  end if;

  select count(*) into active_user_count
  from public.profiles
  where department_id = p_department_id
    and is_active = true
    and deleted_at is null;
  if active_user_count > 0 then
    return jsonb_build_object(
      'ok', false,
      'code', 'active_users_assigned',
      'message', 'Department cannot be archived while active users are assigned.',
      'active_user_count', active_user_count
    );
  end if;

  begin
    update public.departments
    set is_active = false, deleted_at = now()
    where id = p_department_id
    returning * into result;

    insert into public.activity_logs (user_id, action, actor, note)
    values (
      actor_id,
      'department_admin_archived',
      actor_name,
      jsonb_build_object('department_id', result.id, 'code', result.code, 'name', result.name)::text
    );

    return jsonb_build_object('ok', true, 'department', to_jsonb(result));
  exception
    when others then
      return jsonb_build_object('ok', false, 'code', 'internal_error', 'message', 'Department archive failed.');
  end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.work_order_actor()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select pg_catalog.jsonb_build_object(
    'id', profile.id,
    'display_name', profile.display_name,
    'role', profile.role,
    'department_id', profile.department_id
  )
  from public.profiles as profile
  where profile.id = auth.uid()
    and public.pilot_account_ready(profile.id)
$function$
;
CREATE OR REPLACE FUNCTION public.protect_terminal_work_order()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if old.status in ('closed', 'cancelled')
    and coalesce(
      pg_catalog.current_setting('fmworks.admin_correction', true),
      'off'
    ) <> 'on'
  then
    raise exception using errcode = '55000', message = 'TERMINAL_IMMUTABLE';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.work_order_result_error(p_code text, p_message text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select pg_catalog.jsonb_build_object(
    'ok', false,
    'code', p_code,
    'message', p_message
  )
$function$
;
CREATE OR REPLACE FUNCTION public.create_work_order(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  requested_status text := pg_catalog.lower(coalesce(p_payload ->> 'status', 'draft'));
  requested_source text := pg_catalog.lower(coalesce(p_payload ->> 'source', 'manual'));
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := actor ->> 'name';
  actor_role := actor ->> 'role';
  if actor_role = 'technician' then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot create work orders.'); end if;
  if requested_status not in ('draft', 'submitted') then return public.work_order_result_error('VALIDATION_ERROR', 'A new work order must be Draft or Submitted.'); end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', ''))) > 200
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', ''))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')) not in ('low','medium','high','critical')
    or requested_source not in ('manual','reactive','preventive','inspection','condition_based','predictive')
  then return public.work_order_result_error('VALIDATION_ERROR', 'Priority or source is invalid.'); end if;
  if p_payload ? 'estimated_hours' and (p_payload ->> 'estimated_hours')::numeric < 0
    or p_payload ? 'health_score_at_creation' and (p_payload ->> 'health_score_at_creation')::numeric not between 0 and 100
    or p_payload ? 'failure_probability' and (p_payload ->> 'failure_probability')::numeric not between 0 and 1
    or p_payload ? 'confidence_score' and (p_payload ->> 'confidence_score')::numeric not between 0 and 1
  then return public.work_order_result_error('VALIDATION_ERROR', 'A numeric work-order value is outside its allowed range.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;

  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id,
      priority, status, source, source_reference, alert_id, prediction_reference,
      asset_id, health_score_at_creation, failure_probability,
      predicted_failure_date, recommended_action, confidence_score,
      department_id, due_date, estimated_hours, internal_notes,
      submitted_by, submitted_at, contact_number
    ) values (
      actor_id, actor_id,
      pg_catalog.btrim(p_payload ->> 'title'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), ''),
      pg_catalog.btrim(p_payload ->> 'location'),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), ''),
      nullif(p_payload ->> 'category_id', '')::uuid,
      pg_catalog.lower(coalesce(p_payload ->> 'priority', 'medium')),
      requested_status, requested_source,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), ''),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'alert_id', '')), ''),
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'prediction_reference', '')), ''),
      nullif(p_payload ->> 'asset_id', '')::uuid,
      nullif(p_payload ->> 'health_score_at_creation', '')::numeric,
      nullif(p_payload ->> 'failure_probability', '')::numeric,
      nullif(p_payload ->> 'predicted_failure_date', '')::date,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'recommended_action', '')), ''),
      nullif(p_payload ->> 'confidence_score', '')::numeric,
      nullif(p_payload ->> 'department_id', '')::uuid,
      nullif(p_payload ->> 'due_date', '')::date,
      nullif(p_payload ->> 'estimated_hours', '')::numeric,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), ''),
      actor_name,
      case when requested_status = 'submitted' then pg_catalog.now() else null end,
      nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), '')
    ) returning * into result;

    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (
      actor_id, result.id, 'work_order_created', null, result.status, actor_name,
      pg_catalog.jsonb_build_object('source', result.source, 'submitted', result.status = 'submitted')::text
    );
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception
    when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
      return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
    when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order creation failed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.update_work_order(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status in ('closed','cancelled') then return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.'); end if;
  if actor_role <> 'administrator' and not (actor_id = previous.requested_by and actor_role in ('reviewer','initiator') and previous.status = 'draft') then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot edit this work order.');
  end if;
  if pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'title', previous.title))) < 3
    or pg_catalog.length(pg_catalog.btrim(coalesce(p_payload ->> 'location', previous.location))) = 0
  then return public.work_order_result_error('VALIDATION_ERROR', 'Title and location are required.'); end if;
  if nullif(p_payload ->> 'department_id', '') is not null and not exists (
    select 1 from public.departments where id = (p_payload ->> 'department_id')::uuid and is_active = true and deleted_at is null
  ) then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected department is unavailable.'); end if;

  begin
    update public.work_orders set
      title = pg_catalog.btrim(coalesce(p_payload ->> 'title', title)),
      description = case when p_payload ? 'description' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'description', '')), '') else description end,
      location = pg_catalog.btrim(coalesce(p_payload ->> 'location', location)),
      site = case when p_payload ? 'site' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'site', '')), '') else site end,
      category_id = case when p_payload ? 'category_id' then nullif(p_payload ->> 'category_id', '')::uuid else category_id end,
      priority = case when p_payload ? 'priority' then pg_catalog.lower(p_payload ->> 'priority') else priority end,
      source = case when p_payload ? 'source' then pg_catalog.lower(p_payload ->> 'source') else source end,
      department_id = case when p_payload ? 'department_id' then nullif(p_payload ->> 'department_id', '')::uuid else department_id end,
      asset_id = case when p_payload ? 'asset_id' then nullif(p_payload ->> 'asset_id', '')::uuid else asset_id end,
      source_reference = case when p_payload ? 'source_reference' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'source_reference', '')), '') else source_reference end,
      alert_id = case when p_payload ? 'alert_id' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'alert_id', '')), '') else alert_id end,
      prediction_reference = case when p_payload ? 'prediction_reference' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'prediction_reference', '')), '') else prediction_reference end,
      health_score_at_creation = case when p_payload ? 'health_score_at_creation' then nullif(p_payload ->> 'health_score_at_creation', '')::numeric else health_score_at_creation end,
      failure_probability = case when p_payload ? 'failure_probability' then nullif(p_payload ->> 'failure_probability', '')::numeric else failure_probability end,
      predicted_failure_date = case when p_payload ? 'predicted_failure_date' then nullif(p_payload ->> 'predicted_failure_date', '')::date else predicted_failure_date end,
      recommended_action = case when p_payload ? 'recommended_action' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'recommended_action', '')), '') else recommended_action end,
      confidence_score = case when p_payload ? 'confidence_score' then nullif(p_payload ->> 'confidence_score', '')::numeric else confidence_score end,
      due_date = case when p_payload ? 'due_date' then nullif(p_payload ->> 'due_date', '')::date else due_date end,
      estimated_hours = case when p_payload ? 'estimated_hours' then nullif(p_payload ->> 'estimated_hours', '')::numeric else estimated_hours end,
      internal_notes = case when p_payload ? 'internal_notes' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'internal_notes', '')), '') else internal_notes end,
      contact_number = case when p_payload ? 'contact_number' then nullif(pg_catalog.btrim(coalesce(p_payload ->> 'contact_number', '')), '') else contact_number end,
      updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_updated', actor_name,
      pg_catalog.jsonb_build_object('before', pg_catalog.to_jsonb(previous), 'after', pg_catalog.to_jsonb(result))::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when check_violation or invalid_text_representation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order update failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation or foreign_key_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more work-order values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order update failed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_work_order(p_work_order_id uuid, p_assignment_type text, p_assignee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  previous public.work_orders%rowtype; result public.work_orders%rowtype; assignee_name text;
  mode text := pg_catalog.lower(coalesce(p_assignment_type, ''));
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  if actor_role not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot assign work orders.'); end if;
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status not in ('approved','assigned') then return public.work_order_result_error('INVALID_TRANSITION', 'Assignment is allowed only after approval.'); end if;
  if mode = 'technician' then
    select display_name into assignee_name from public.profiles where id = p_assignee_id and role = 'technician' and is_active = true and deleted_at is null;
  elsif mode = 'vendor' then
    select name into assignee_name from public.vendors where id = p_assignee_id and active = true and deleted_at is null;
  elsif mode = 'team' then
    select name into assignee_name from public.maintenance_teams where id = p_assignee_id and is_active = true and deleted_at is null;
  else return public.work_order_result_error('INVALID_ASSIGNMENT', 'Assignment type is invalid.');
  end if;
  if assignee_name is null then return public.work_order_result_error('INACTIVE_REFERENCE', 'The selected assignee is unavailable.'); end if;
  if previous.status = 'assigned' and (
    (mode = 'technician' and previous.assigned_technician_id = p_assignee_id and previous.assigned_vendor_id is null and previous.assigned_team_id is null)
    or (mode = 'vendor' and previous.assigned_vendor_id = p_assignee_id and previous.assigned_technician_id is null and previous.assigned_team_id is null)
    or (mode = 'team' and previous.assigned_team_id = p_assignee_id and previous.assigned_technician_id is null and previous.assigned_vendor_id is null)
  ) then
    return pg_catalog.jsonb_build_object(
      'ok', true,
      'code', 'NO_CHANGE',
      'message', 'The work order is already assigned to this assignee.',
      'work_order', pg_catalog.to_jsonb(previous)
    );
  end if;
  begin
    update public.work_orders set
      assigned_technician_id = case when mode = 'technician' then p_assignee_id else null end,
      assigned_vendor_id = case when mode = 'vendor' then p_assignee_id else null end,
      assigned_team_id = case when mode = 'team' then p_assignee_id else null end,
      assigned_to = assignee_name, assigned_by = actor_name, assigned_by_user_id = actor_id,
      assigned_at = pg_catalog.now(), accepted_at = null, status = 'assigned', updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, case when previous.status = 'assigned' then 'work_order_reassigned' else 'work_order_assigned' end,
      previous.status, result.status, actor_name,
      pg_catalog.jsonb_build_object('assignment_type', mode, 'assignee_id', p_assignee_id, 'assignee_name', assignee_name)::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order assignment failed.'); end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.transition_work_order_0034_core(p_work_order_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
  action text := pg_catalog.lower(coalesce(p_action, ''));
  target_status text;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  cycle_number integer;
  evidence_ids jsonb := '[]'::jsonb;
  transition_activity_id uuid;
  completion_activity_id uuid;
  completion_actor_id uuid;
  completion_note_text text;
  completion_note jsonb := '{}'::jsonb;
  prior_hours numeric;
  requested_hours numeric;
  direct_completed_from_assigned boolean := false;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;

  if (action='complete' and previous.status='completed')
    or (action='review' and previous.status='reviewed')
    or (action='return_for_rework' and previous.status='in_progress' and exists(
      select 1 from public.activity_logs l where l.work_order_id=previous.id
        and l.action='work_order_returned_for_rework'
        and not exists(select 1 from public.activity_logs later where later.work_order_id=previous.id and later.created_at>l.created_at and later.action='work_order_complete')
    )) then
    return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(previous));
  end if;

  if previous.status in ('closed','cancelled') then
    return public.work_order_result_error('TERMINAL_IMMUTABLE', 'Closed and cancelled work orders are immutable.');
  end if;

  target_status := case action
    when 'submit' then 'submitted'
    when 'approve' then 'approved'
    when 'accept' then 'assigned'
    when 'start' then 'in_progress'
    when 'complete' then 'completed'
    when 'return_for_rework' then 'in_progress'
    when 'review' then 'reviewed'
    when 'close' then 'closed'
    when 'cancel' then 'cancelled'
    else null
  end;

  if target_status is null or not (
    (action='submit' and previous.status='draft')
    or (action='approve' and previous.status='submitted')
    or (action='accept' and previous.status='assigned' and previous.accepted_at is null)
    or (action='start' and previous.status='assigned')
    or (action='complete' and previous.status in ('assigned','in_progress'))
    or (action='return_for_rework' and previous.status='completed')
    or (action='review' and previous.status='completed')
    or (action='close' and previous.status='reviewed')
    or (action='cancel' and previous.status in ('draft','submitted','approved','assigned','in_progress','completed','reviewed'))
  ) then
    return public.work_order_result_error('INVALID_TRANSITION', 'The requested workflow transition is not allowed.');
  end if;

  if action='submit'
    and not (actor_id=previous.requested_by and actor_role in ('reviewer','initiator','approver','supervisor','facility_manager'))
    and actor_role<>'administrator' then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the requester may submit this work order.');
  elsif action='approve' and actor_role not in ('approver','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Approver, Facility Manager or Administrator authority is required.');
  elsif action='approve' and actor_id=previous.requested_by then
    if actor_role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED', 'Requesters cannot approve their own work orders.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-approval requires an override reason.'); end if;
  elsif action in ('review','return_for_rework','close') and actor_role not in ('supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Supervisor, Facility Manager or Administrator authority is required.');
  elsif action in ('accept','start','complete') and actor_role<>'administrator'
    and not (actor_role='technician' and actor_id=previous.assigned_technician_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Only the assigned Technician-in-Charge or an Administrator may perform this action.');
  elsif action='cancel' and actor_role not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot cancel work orders.');
  end if;

  if action='cancel' and reason is null then
    return public.work_order_result_error('CANCELLATION_REASON_REQUIRED', 'A cancellation reason is required.');
  end if;
  if action='return_for_rework' and reason is null then
    return public.work_order_result_error('REWORK_REASON_REQUIRED', 'A rework reason is required.');
  end if;
  if action='return_for_rework' and not exists(
    select 1 from public.profiles p where p.id=previous.assigned_technician_id
      and p.role='technician' and p.is_active and p.deleted_at is null
  ) then
    return public.work_order_result_error('INVALID_ASSIGNMENT', 'Return for rework requires an active assigned Technician.');
  end if;

  if action='complete' then
    begin requested_hours := nullif(p_payload ->> 'actual_labour_hours','')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      return public.work_order_result_error('COMPLETED_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
    end;
    if nullif(pg_catalog.btrim(coalesce(p_payload ->> 'completion_notes','')),'') is null
      or requested_hours is null or requested_hours<0 then
      return public.work_order_result_error('COMPLETED_DETAILS_REQUIRED', 'Work performed statement and cumulative non-negative labour hours are required.');
    end if;
    if not exists(select 1 from public.evidence_items e where e.work_order_id=previous.id and e.category='after') then
      return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED', 'Upload After photo or PDF evidence before marking this Work Order Completed.');
    end if;
    select count(*)+1 into cycle_number from public.activity_logs l
      where l.work_order_id=previous.id and l.action='work_order_returned_for_rework';
    prior_hours := previous.actual_labour_hours;
    if cycle_number>1 and prior_hours is not null and requested_hours<prior_hours then
      return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED', 'Resubmitted labour hours must be the cumulative total and cannot be lower than the previous submission.');
    end if;
    select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb)
      into evidence_ids from public.evidence_items e where e.work_order_id=previous.id;
    direct_completed_from_assigned := previous.status='assigned';
  end if;

  if action in ('review','return_for_rework') then
    select count(*)+1 into cycle_number from public.activity_logs l
      where l.work_order_id=previous.id and l.action='work_order_returned_for_rework';
    select l.id,l.user_id,l.note
      into completion_activity_id,completion_actor_id,completion_note_text
    from public.activity_logs l
    where l.work_order_id=previous.id and l.action='work_order_complete'
    order by l.created_at desc,l.id desc limit 1;
    begin completion_note := coalesce(nullif(completion_note_text,'')::jsonb,'{}'::jsonb);
    exception when invalid_text_representation then completion_note := '{}'::jsonb; end;
    evidence_ids := case when pg_catalog.jsonb_typeof(completion_note -> 'evidence_ids')='array'
      then completion_note -> 'evidence_ids' else '[]'::jsonb end;
  end if;

  if action='review' and actor_id=completion_actor_id then
    return public.work_order_result_error('SELF_REVIEW_DENIED', 'Completed Work must be accepted by a different Supervisor, Facility Manager or Administrator.');
  end if;

  begin
    if action='return_for_rework' then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,previous.id,'work_order_returned_for_rework','completed','in_progress',actor_name,
        pg_catalog.jsonb_build_object('cycle',cycle_number,'reason',reason,'previous_completion_activity_id',completion_activity_id,
          'previous_completion',pg_catalog.jsonb_build_object('completion_notes',previous.completion_notes,'cumulative_labour_hours',previous.actual_labour_hours,'completed_at',previous.completed_at,'evidence_ids',evidence_ids,'actor_id',completion_actor_id,'activity_note',completion_note),
          'returned_by',actor_id,'returned_at',pg_catalog.now())::text)
      returning id into transition_activity_id;
    end if;

    update public.work_orders set
      status=target_status,
      submitted_at=case when action='submit' then pg_catalog.now() else submitted_at end,
      approved_at=case when action='approve' then pg_catalog.now() else approved_at end,
      accepted_at=case when action='accept' then pg_catalog.now() else accepted_at end,
      started_at=case when action='start' then pg_catalog.now() when action='complete' and started_at is null then pg_catalog.now() else started_at end,
      completed_at=case when action='complete' then pg_catalog.now() when action='return_for_rework' then null else completed_at end,
      reviewed_at=case when action='review' then pg_catalog.now() else reviewed_at end,
      closed_at=case when action='close' then pg_catalog.now() else closed_at end,
      cancelled_at=case when action='cancel' then pg_catalog.now() else cancelled_at end,
      completion_notes=case when action='complete' then pg_catalog.btrim(p_payload ->> 'completion_notes') else completion_notes end,
      actual_labour_hours=case when action='complete' then requested_hours else actual_labour_hours end,
      cancellation_reason=case when action='cancel' then reason else cancellation_reason end,
      updated_at=pg_catalog.now()
    where id=previous.id returning * into result;

    if action<>'return_for_rework' then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,result.id,'work_order_'||action,previous.status,result.status,actor_name,
        case when action='complete' then pg_catalog.jsonb_build_object(
          'cycle',cycle_number,'completion_notes',result.completion_notes,'cumulative_labour_hours',result.actual_labour_hours,
          'completed_at',result.completed_at,'evidence_ids',evidence_ids,'submitted_by',actor_id,'submitted_at',pg_catalog.now(),
          'resubmission',cycle_number>1,'direct_completed_from_assigned',direct_completed_from_assigned)
        when action='review' then pg_catalog.jsonb_build_object('cycle',cycle_number,'decision','accepted','reason',reason,'completion_activity_id',completion_activity_id,'independent_review',true)
        else pg_catalog.jsonb_build_object('reason',reason,'payload',p_payload,'administrator_override',action='approve' and actor_id=previous.requested_by and actor_role='administrator') end::text)
      returning id into transition_activity_id;
    end if;

    if action='complete' then
      with primary_recipients as (
        select p.id,p.email from public.profiles p where p.is_active and p.deleted_at is null
          and p.role in ('supervisor','facility_manager') and p.id<>actor_id
      ), recipients as (
        select * from primary_recipients
        union all
        select p.id,p.email from public.profiles p where p.is_active and p.deleted_at is null
          and p.role='administrator' and p.id<>actor_id and not exists(select 1 from primary_recipients)
      )
      insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select result.id,case when cycle_number=1 then 'work_order_completion_submitted' else 'work_order_completion_resubmitted' end,
        'work_order:'||result.id::text||':completion:'||cycle_number::text||':submitted',r.id,r.id,r.email,'email',
        pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
      from recipients r on conflict do nothing;
    elsif action='return_for_rework' then
      insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select result.id,'work_order_completion_returned_for_rework','work_order:'||result.id::text||':completion:'||cycle_number::text||':returned',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
      from public.profiles p where p.id=result.assigned_technician_id on conflict do nothing;
    elsif action='review' then
      if result.assigned_technician_id is not null then
        insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
        select result.id,'work_order_completion_accepted','work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
        from public.profiles p where p.id=result.assigned_technician_id and p.is_active and p.deleted_at is null on conflict do nothing;
      end if;
      if result.assigned_vendor_id is not null then
        insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_due_at)
        values(result.id,result.assigned_vendor_id,'awaiting_approval',coalesce((select sum(amount) from public.work_order_cost_lines where work_order_id=result.id),0),pg_catalog.now(),pg_catalog.now()+interval '30 days')
        on conflict(work_order_id) do update set status='awaiting_approval',assessed_amount=excluded.assessed_amount,completed_work_accepted_at=excluded.completed_work_accepted_at,payment_due_at=excluded.payment_due_at,updated_at=pg_catalog.now();
      end if;
    end if;

    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',case when action in ('complete','return_for_rework','review') then cycle_number else null end,'notification_status',case when action in ('complete','return_for_rework','review') then 'queued' else null end);
  exception when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
  end;
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'One or more transition values are invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Work-order transition failed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.duplicate_work_order(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; actor_role text;
  source_order public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name'; actor_role := actor ->> 'role';
  if actor_role = 'technician' then return public.work_order_result_error('ACCESS_DENIED', 'Your role cannot duplicate work orders.'); end if;
  select * into source_order from public.work_orders where id = p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  begin
    insert into public.work_orders (
      user_id, requested_by, title, description, location, site, category_id,
      priority, status, source, source_reference, alert_id, prediction_reference,
      asset_id, health_score_at_creation, failure_probability,
      predicted_failure_date, recommended_action, confidence_score,
      department_id, due_date, estimated_hours, internal_notes,
      submitted_by, contact_number, duplicated_from_id
    ) values (
      actor_id, actor_id, source_order.title, source_order.description,
      source_order.location, source_order.site, source_order.category_id,
      source_order.priority, 'draft', source_order.source,
      source_order.source_reference, source_order.alert_id, source_order.prediction_reference,
      source_order.asset_id, source_order.health_score_at_creation,
      source_order.failure_probability, source_order.predicted_failure_date,
      source_order.recommended_action, source_order.confidence_score,
      source_order.department_id, source_order.due_date, source_order.estimated_hours,
      source_order.internal_notes, actor_name, source_order.contact_number, source_order.id
    ) returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, actor, note)
    values (actor_id, result.id, 'work_order_duplicated', actor_name,
      pg_catalog.jsonb_build_object('source_work_order_id', source_order.id, 'source_work_order_number', source_order.work_order_number)::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Work-order duplication failed.'); end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_correct_work_order(p_work_order_id uuid, p_changes jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor(); actor_id uuid; actor_name text; previous public.work_orders%rowtype; result public.work_orders%rowtype;
begin
  if actor is null or actor ->> 'role' <> 'administrator' then return public.work_order_result_error('ACCESS_DENIED', 'Administrator authority is required.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'An administrative correction reason is required.'); end if;
  actor_id := (actor ->> 'id')::uuid; actor_name := actor ->> 'name';
  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  begin
    perform pg_catalog.set_config('fmworks.admin_correction', 'on', true);
    update public.work_orders set
      title = case when p_changes ? 'title' then pg_catalog.btrim(p_changes ->> 'title') else title end,
      description = case when p_changes ? 'description' then nullif(pg_catalog.btrim(coalesce(p_changes ->> 'description', '')), '') else description end,
      location = case when p_changes ? 'location' then pg_catalog.btrim(p_changes ->> 'location') else location end,
      internal_notes = case when p_changes ? 'internal_notes' then nullif(pg_catalog.btrim(coalesce(p_changes ->> 'internal_notes', '')), '') else internal_notes end,
      cancellation_reason = case when p_changes ? 'cancellation_reason' then nullif(pg_catalog.btrim(coalesce(p_changes ->> 'cancellation_reason', '')), '') else cancellation_reason end,
      updated_at = pg_catalog.now()
    where id = p_work_order_id returning * into result;
    insert into public.activity_logs (user_id, work_order_id, action, from_status, to_status, actor, note)
    values (actor_id, result.id, 'work_order_admin_corrected', previous.status, result.status, actor_name,
      pg_catalog.jsonb_build_object('reason', pg_catalog.btrim(p_reason), 'before', pg_catalog.to_jsonb(previous), 'after', pg_catalog.to_jsonb(result))::text);
    return pg_catalog.jsonb_build_object('ok', true, 'work_order', pg_catalog.to_jsonb(result));
  exception when others then return public.work_order_result_error('INTERNAL_ERROR', 'Administrative correction failed.'); end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_public_work_orders()
 RETURNS TABLE(id uuid, work_order_number text, title text, location text, site text, category_name text, priority text, status text, source text, due_date date, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select
    work_order.id,
    work_order.work_order_number,
    work_order.title,
    work_order.location,
    work_order.site,
    category.name,
    work_order.priority,
    work_order.status,
    work_order.source,
    work_order.due_date,
    work_order.created_at
  from public.work_orders as work_order
  left join public.categories as category on category.id = work_order.category_id
  where work_order.status <> 'draft'
  order by work_order.created_at desc
  limit 200
$function$
;
CREATE OR REPLACE FUNCTION public.next_incident_number(reference_time timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_reference_year integer := extract(year from reference_time at time zone 'UTC');
  reference_value integer;
begin
  insert into public.incident_number_counters(reference_year,last_value)
  values(v_reference_year,1)
  on conflict(reference_year) do update
    set last_value=public.incident_number_counters.last_value+1
  returning last_value into reference_value;
  return 'INC-'||v_reference_year::text||'-'||pg_catalog.lpad(reference_value::text,6,'0');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_incident_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if new.incident_number is null or pg_catalog.btrim(new.incident_number) = '' then
    new.incident_number := public.next_incident_number(coalesce(new.reported_at,pg_catalog.now()));
  end if;
  if new.acknowledgement_deadline is null then
    new.acknowledgement_deadline := coalesce(new.reported_at,pg_catalog.now()) + interval '5 minutes';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.validate_emergency_roster_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare target_role text;
begin
  if tg_op='INSERT' then new.created_by:=auth.uid();
  else new.created_by:=old.created_by; end if;
  if new.profile_id is not null then
    select role into target_role from public.profiles
      where id=new.profile_id and is_active and deleted_at is null;
    if target_role not in ('technician','supervisor','administrator') then
      raise exception using errcode='23514', message='Roster profile must be an active Technician, Supervisor, or Administrator.';
    end if;
  elsif not exists(select 1 from public.maintenance_teams where id=new.team_id and is_active and deleted_at is null) then
    raise exception using errcode='23514', message='Roster team must be active.';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.incident_result_error(p_code text, p_message text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select pg_catalog.jsonb_build_object('ok', false, 'code', p_code, 'message', p_message)
$function$
;
CREATE OR REPLACE FUNCTION public.create_incident(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_id uuid := auth.uid(); actor_role text := public.current_user_role();
  incident public.incidents; responder_profile uuid; responder_team uuid;
  roster_count integer; responder_sms boolean:=true; responder_whatsapp boolean:=true;
begin
  if actor_id is null or actor_role is null then
    return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.');
  end if;
  if actor_role = 'technician' then
    return public.incident_result_error('ACCESS_DENIED','Your role cannot report an incident.');
  end if;
  if pg_catalog.lower(coalesce(p_payload->>'incident_type','')) not in
    ('lift_entrapment','fire','flood','major_water_leak','electrical_failure','gas_leak','chemical_spill','medical_emergency','security','other') then
    return public.incident_result_error('VALIDATION_ERROR','Incident type is invalid.');
  end if;
  if pg_catalog.lower(coalesce(p_payload->>'severity','emergency')) not in ('emergency','critical','high','medium','low') then
    return public.incident_result_error('VALIDATION_ERROR','Incident severity is invalid.');
  end if;
  if pg_catalog.btrim(coalesce(p_payload->>'location','')) = '' or pg_catalog.btrim(coalesce(p_payload->>'description','')) = '' then
    return public.incident_result_error('VALIDATION_ERROR','Location and description are required.');
  end if;

  with valid_roster as (
    select r.* from public.emergency_response_roster r
    left join public.profiles p on p.id=r.profile_id
    left join public.maintenance_teams t on t.id=r.team_id
    where r.active and r.receive_emergency_alerts
      and (r.active_from is null or r.active_from<=pg_catalog.now())
      and (r.active_to is null or r.active_to>pg_catalog.now())
      and (r.incident_type is null or r.incident_type=pg_catalog.lower(p_payload->>'incident_type'))
      and ((p.id is not null and p.role='technician' and p.is_active and p.deleted_at is null)
        or (t.id is not null and t.is_active and t.deleted_at is null))
  )
  select count(*), (pg_catalog.array_agg(r.profile_id))[1], (pg_catalog.array_agg(r.team_id))[1],
    (pg_catalog.array_agg(r.sms_enabled))[1],(pg_catalog.array_agg(r.whatsapp_enabled))[1]
    into roster_count, responder_profile, responder_team,responder_sms,responder_whatsapp
  from valid_roster r where r.escalation_order=(select min(escalation_order) from valid_roster);
  if roster_count <> 1 then responder_profile:=null; responder_team:=null; responder_sms:=false; responder_whatsapp:=false; end if;

  insert into public.incidents (
    incident_number, incident_type, severity, location, description, reported_by,
    incident_commander_id, assigned_technician_id, assigned_team_id,
    acknowledgement_deadline
  ) values (
    null, pg_catalog.lower(p_payload->>'incident_type'),
    pg_catalog.lower(coalesce(p_payload->>'severity','emergency')),
    pg_catalog.btrim(p_payload->>'location'), pg_catalog.btrim(p_payload->>'description'), actor_id,
    case when actor_role in ('administrator','supervisor') then actor_id else null end,
    responder_profile, responder_team, pg_catalog.now() + interval '5 minutes'
  ) returning * into incident;

  insert into public.activity_logs (user_id, incident_id, action, from_status, to_status, actor, note)
  select actor_id, incident.id, 'incident_created', null, 'reported', p.display_name,
    pg_catalog.jsonb_build_object('severity',incident.severity,'incident_type',incident.incident_type,
      'assignment_state',case when responder_profile is null and responder_team is null then 'UNASSIGNED_EMERGENCY' else 'ASSIGNED' end)::text
  from public.profiles p where p.id = actor_id;

  insert into public.notification_outbox (
    incident_id,event_type,event_key,recipient_user_id,recipient_profile_id,
    recipient_email,channel,payload,delivery_status,provider,result_code
  )
  select incident.id,'emergency_incident_reported',incident.id::text||':emergency',recipient.id,recipient.id,
    recipient.email,channel.name,
    pg_catalog.jsonb_build_object('incident_number',incident.incident_number,'incident_path','/incidents/'||incident.id::text),
    'pending','none','PENDING'
  from (
    select p.id,p.email,true as sms_enabled,true as whatsapp_enabled from public.profiles p
      where p.is_active and p.deleted_at is null and p.role in ('administrator','supervisor')
    union
    select p.id,p.email,responder_sms,responder_whatsapp from public.profiles p where p.id=responder_profile
    union
    select p.id,p.email,responder_sms,responder_whatsapp from public.maintenance_team_members m join public.profiles p on p.id=m.profile_id
      where m.team_id=responder_team and m.is_active and p.is_active and p.deleted_at is null
  ) recipient cross join (values ('sms'),('whatsapp')) channel(name)
  where (channel.name='sms' and recipient.sms_enabled) or (channel.name='whatsapp' and recipient.whatsapp_enabled)
  on conflict do nothing;

  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident),
    'assignment_state',case when responder_profile is null and responder_team is null then 'UNASSIGNED_EMERGENCY' else 'ASSIGNED' end);
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The emergency incident could not be created.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.link_work_order_to_incident(p_work_order_id uuid, p_incident_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor_id uuid:=auth.uid(); actor_role text:=public.current_user_role(); work_order public.work_orders;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('approver','supervisor','administrator') then
    return public.incident_result_error('ACCESS_DENIED','Your role cannot link corrective work.');
  end if;
  if not exists(select 1 from public.incidents where id=p_incident_id) then
    return public.incident_result_error('NOT_FOUND','Incident was not found.');
  end if;
  update public.work_orders set incident_id=p_incident_id,updated_at=pg_catalog.now()
    where id=p_work_order_id and status not in ('closed','cancelled') returning * into work_order;
  if work_order.id is null then return public.incident_result_error('NOT_FOUND','Active work order was not found.'); end if;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note)
    select actor_id,work_order.id,p_incident_id,'work_order_linked_to_incident',p.display_name,
      pg_catalog.jsonb_build_object('incident_id',p_incident_id)::text from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(work_order));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The corrective work order could not be linked.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.record_incident_notification_result(p_incident_id uuid, p_channel text, p_delivered boolean, p_code text, p_provider text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  affected integer;
  safe_provider text := pg_catalog.left(coalesce(nullif(trim(p_provider), ''), 'none'), 100);
begin
  if p_channel not in ('sms','whatsapp')
    or p_code not in ('DELIVERED','NOT_CONFIGURED','DELIVERY_FAILED')
    or p_delivered is distinct from (p_code = 'DELIVERED')
  then return public.incident_result_error('VALIDATION_ERROR','Notification result is invalid.'); end if;
  if not exists(select 1 from public.incidents where id = p_incident_id) then
    return public.incident_result_error('NOT_FOUND','Incident was not found.');
  end if;

  update public.notification_outbox set
    delivery_status = case when p_delivered then 'sent' else 'failed' end,
    provider = safe_provider,
    attempted_at = pg_catalog.now(),
    delivered_at = case when p_delivered then pg_catalog.now() else null end,
    result_code = p_code,
    attempts = attempts + 1,
    retry_count = retry_count + 1,
    last_error_code = case when p_delivered then null else p_code end,
    last_error = null
  where incident_id = p_incident_id
    and channel = p_channel
    and delivery_status = 'pending';
  get diagnostics affected = row_count;

  insert into public.activity_logs(user_id, incident_id, action, actor, note)
  values (
    null,
    p_incident_id,
    'incident_notification_result',
    'Trusted notification worker',
    pg_catalog.jsonb_build_object(
      'channel', p_channel,
      'delivered', p_delivered,
      'code', p_code,
      'provider', safe_provider,
      'recipients', affected
    )::text
  );
  return pg_catalog.jsonb_build_object('ok', true, 'updated', affected);
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The notification result could not be recorded.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_incident(p_incident_id uuid, p_assignment_type text, p_assignee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor_id uuid := auth.uid(); actor_role text := public.current_user_role(); incident public.incidents;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('supervisor','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster authority is required.'); end if;
  if p_assignment_type = 'technician' and not exists(select 1 from public.profiles where id=p_assignee_id and role='technician' and is_active and deleted_at is null) then
    return public.incident_result_error('INVALID_ASSIGNMENT','Select a valid active technician.');
  elsif p_assignment_type = 'team' and not exists(select 1 from public.maintenance_teams where id=p_assignee_id and is_active and deleted_at is null) then
    return public.incident_result_error('INVALID_ASSIGNMENT','Select a valid active maintenance team.');
  elsif p_assignment_type not in ('technician','team') then
    return public.incident_result_error('INVALID_ASSIGNMENT','Assignment type is invalid.');
  end if;
  update public.incidents set
    assigned_technician_id=case when p_assignment_type='technician' then p_assignee_id else null end,
    assigned_team_id=case when p_assignment_type='team' then p_assignee_id else null end
  where id=p_incident_id and status not in ('closed','cancelled') returning * into incident;
  if incident.id is null then return public.incident_result_error('NOT_FOUND','Active incident was not found.'); end if;
  insert into public.activity_logs(user_id,incident_id,action,from_status,to_status,actor,note)
    select actor_id,incident.id,'incident_assigned',incident.status,incident.status,p.display_name,
      pg_catalog.jsonb_build_object('assignment_type',p_assignment_type,'assignee_id',p_assignee_id)::text
    from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The incident assignment could not be updated.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.transition_incident(p_incident_id uuid, p_action text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor_id uuid := auth.uid(); actor_role text := public.current_user_role(); previous public.incidents; incident public.incidents; target text; authorized boolean := false;
begin
  if actor_id is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  select * into previous from public.incidents where id=p_incident_id for update;
  if previous.id is null then return public.incident_result_error('NOT_FOUND','Incident was not found.'); end if;
  target := case pg_catalog.lower(p_action)
    when 'acknowledge' then 'acknowledged' when 'mobilise' then 'mobilising'
    when 'arrive' then 'on_site' when 'start_rescue' then 'rescue_in_progress'
    when 'make_safe' then 'safe' when 'start_recovery' then 'recovery'
    when 'close' then 'closed' when 'cancel' then 'cancelled' end;
  if not ((previous.status='reported' and target='acknowledged') or (previous.status='acknowledged' and target='mobilising')
    or (previous.status='mobilising' and target='on_site') or (previous.status='on_site' and target='rescue_in_progress')
    or (previous.status='rescue_in_progress' and target='safe') or (previous.status='safe' and target='recovery')
    or (previous.status='recovery' and target='closed') or (target='cancelled' and previous.status not in ('closed','cancelled'))) then
    return public.incident_result_error('INVALID_TRANSITION','The incident transition is not allowed.');
  end if;
  authorized := actor_role='administrator'
    or (actor_role='supervisor' and target in ('closed','cancelled'))
    or (actor_role='technician' and actor_id=previous.assigned_technician_id)
    or (actor_role='technician' and previous.assigned_team_id is not null and exists(
      select 1 from public.maintenance_team_members m where m.team_id=previous.assigned_team_id and m.profile_id=actor_id and m.is_active));
  if not authorized then return public.incident_result_error('ACCESS_DENIED','You cannot update this incident.'); end if;
  update public.incidents set status=target,
    acknowledged_at=case when target='acknowledged' then pg_catalog.now() else acknowledged_at end,
    mobilising_at=case when target='mobilising' then pg_catalog.now() else mobilising_at end,
    on_site_at=case when target='on_site' then pg_catalog.now() else on_site_at end,
    rescue_started_at=case when target='rescue_in_progress' then pg_catalog.now() else rescue_started_at end,
    safe_at=case when target='safe' then pg_catalog.now() else safe_at end,
    recovery_started_at=case when target='recovery' then pg_catalog.now() else recovery_started_at end,
    closed_at=case when target='closed' then pg_catalog.now() else closed_at end
    where id=p_incident_id returning * into incident;
  insert into public.activity_logs(user_id,incident_id,action,from_status,to_status,actor)
    select actor_id,incident.id,'incident_'||pg_catalog.lower(p_action),previous.status,target,p.display_name from public.profiles p where p.id=actor_id;
  return pg_catalog.jsonb_build_object('ok',true,'incident',pg_catalog.to_jsonb(incident));
exception when others then
  return public.incident_result_error('INTERNAL_ERROR','The incident transition could not be completed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_incident_operations(p_incident_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(incident_id uuid, responder_display_name text, responder_role text, team_name text, commander_display_name text, commander_role text, assignment_state text, sms_status text, whatsapp_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with visible_incidents as (
    select incident.* from public.incidents as incident
    where public.pilot_account_ready(auth.uid())
      and (p_incident_id is null or incident.id = p_incident_id)
      and (public.current_user_role() in ('approver','supervisor','administrator')
        or incident.reported_by = auth.uid() or incident.assigned_technician_id = auth.uid()
        or (incident.assigned_team_id is not null and exists (
          select 1 from public.maintenance_team_members as member
          where member.team_id=incident.assigned_team_id and member.profile_id=auth.uid() and member.is_active
        )))
  ), channel_summary as (
    select outbox.incident_id, outbox.channel,
      case
        when pg_catalog.bool_or(outbox.delivery_status='failed' and outbox.result_code='NOT_CONFIGURED') then 'not_configured'
        when pg_catalog.bool_or(outbox.delivery_status='failed') then 'failed'
        when pg_catalog.bool_or(outbox.delivery_status in ('pending','processing')) then 'pending'
        when pg_catalog.bool_and(outbox.delivery_status='sent') then 'delivered'
        else 'unavailable'
      end as channel_status
    from public.notification_outbox as outbox
    join visible_incidents as incident on incident.id=outbox.incident_id
    where outbox.channel in ('sms','whatsapp')
    group by outbox.incident_id,outbox.channel
  )
  select incident.id, technician.display_name, technician.role, team.name,
    commander.display_name, commander.role,
    case when incident.assigned_technician_id is not null then 'technician'
      when incident.assigned_team_id is not null then 'team' else 'unassigned' end,
    coalesce(sms.channel_status,'unavailable'),coalesce(whatsapp.channel_status,'unavailable')
  from visible_incidents as incident
  left join public.profiles as technician on technician.id=incident.assigned_technician_id
  left join public.maintenance_teams as team on team.id=incident.assigned_team_id
  left join public.profiles as commander on commander.id=incident.incident_commander_id
  left join channel_summary as sms on sms.incident_id=incident.id and sms.channel='sms'
  left join channel_summary as whatsapp on whatsapp.incident_id=incident.id and whatsapp.channel='whatsapp'
$function$
;
CREATE OR REPLACE FUNCTION public.get_emergency_roster()
 RETURNS TABLE(id uuid, profile_id uuid, profile_display_name text, profile_role text, team_id uuid, team_name text, receive_emergency_alerts boolean, sms_enabled boolean, whatsapp_enabled boolean, email_enabled boolean, escalation_order integer, active_from timestamp with time zone, active_to timestamp with time zone, incident_type text, active boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.id,r.profile_id,p.display_name,p.role,r.team_id,t.name,
    r.receive_emergency_alerts,r.sms_enabled,r.whatsapp_enabled,r.email_enabled,
    r.escalation_order,r.active_from,r.active_to,r.incident_type,r.active,r.created_at,r.updated_at
  from public.emergency_response_roster r
  left join public.profiles p on p.id=r.profile_id
  left join public.maintenance_teams t on t.id=r.team_id
  where auth.uid() is not null and public.current_user_role() in ('approver','supervisor','administrator')
  order by r.active desc,r.escalation_order,r.created_at
$function$
;
CREATE OR REPLACE FUNCTION public.get_emergency_response_options()
 RETURNS TABLE(target_type text, target_id uuid, display_name text, role text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select 'technician',p.id,p.display_name,p.role from public.profiles p
  where auth.uid() is not null and public.current_user_role() in ('supervisor','administrator')
    and p.role='technician' and p.is_active and p.deleted_at is null
  union all
  select 'team',t.id,t.name,null from public.maintenance_teams t
  where auth.uid() is not null and public.current_user_role() in ('supervisor','administrator')
    and t.is_active and t.deleted_at is null
$function$
;
CREATE OR REPLACE FUNCTION public.upsert_emergency_roster(p_roster_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor_role text:=public.current_user_role(); target_profile uuid; target_team uuid;
  start_at timestamptz; end_at timestamptz; incident_category text; ranking integer; result public.emergency_response_roster;
begin
  if auth.uid() is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if actor_role not in ('supervisor','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster management permission is required.'); end if;
  target_profile:=nullif(p_payload->>'profile_id','')::uuid; target_team:=nullif(p_payload->>'team_id','')::uuid;
  if (target_profile is null)=(target_team is null) then return public.incident_result_error('VALIDATION_ERROR','Select one Technician or maintenance team.'); end if;
  if target_profile is not null and not exists(select 1 from public.profiles where id=target_profile and role='technician' and is_active and deleted_at is null) then return public.incident_result_error('INVALID_ASSIGNMENT','Select an active Technician.'); end if;
  if target_team is not null and not exists(select 1 from public.maintenance_teams where id=target_team and is_active and deleted_at is null) then return public.incident_result_error('INVALID_ASSIGNMENT','Select an active maintenance team.'); end if;
  start_at:=nullif(p_payload->>'active_from','')::timestamptz; end_at:=nullif(p_payload->>'active_to','')::timestamptz;
  if start_at is not null and end_at is not null and end_at<=start_at then return public.incident_result_error('VALIDATION_ERROR','Effective end must be after effective start.'); end if;
  incident_category:=nullif(pg_catalog.lower(p_payload->>'incident_type'),'');
  if incident_category is not null and incident_category not in ('lift_entrapment','fire','flood','major_water_leak','electrical_failure','gas_leak','chemical_spill','medical_emergency','security','other') then return public.incident_result_error('VALIDATION_ERROR','Incident type is invalid.'); end if;
  ranking:=coalesce((p_payload->>'escalation_order')::integer,100); if ranking<0 then return public.incident_result_error('VALIDATION_ERROR','Escalation order must not be negative.'); end if;
  if coalesce((p_payload->>'active')::boolean,true) and exists(select 1 from public.emergency_response_roster r where r.id is distinct from p_roster_id and r.active and r.escalation_order=ranking and r.incident_type is not distinct from incident_category and r.profile_id is not distinct from target_profile and r.team_id is not distinct from target_team and tstzrange(coalesce(r.active_from,'-infinity'),coalesce(r.active_to,'infinity'),'[)') && tstzrange(coalesce(start_at,'-infinity'),coalesce(end_at,'infinity'),'[)')) then return public.incident_result_error('DUPLICATE_ROSTER','An overlapping active roster entry already exists for this target and ranking.'); end if;
  if p_roster_id is null then
    insert into public.emergency_response_roster(profile_id,team_id,receive_emergency_alerts,sms_enabled,whatsapp_enabled,email_enabled,escalation_order,active_from,active_to,incident_type,active,created_by)
    values(target_profile,target_team,coalesce((p_payload->>'receive_emergency_alerts')::boolean,true),coalesce((p_payload->>'sms_enabled')::boolean,true),coalesce((p_payload->>'whatsapp_enabled')::boolean,true),false,ranking,start_at,end_at,incident_category,coalesce((p_payload->>'active')::boolean,true),auth.uid()) returning * into result;
  else
    update public.emergency_response_roster set profile_id=target_profile,team_id=target_team,receive_emergency_alerts=coalesce((p_payload->>'receive_emergency_alerts')::boolean,true),sms_enabled=coalesce((p_payload->>'sms_enabled')::boolean,true),whatsapp_enabled=coalesce((p_payload->>'whatsapp_enabled')::boolean,true),email_enabled=false,escalation_order=ranking,active_from=start_at,active_to=end_at,incident_type=incident_category,active=coalesce((p_payload->>'active')::boolean,true)
    where id=p_roster_id returning * into result;
    if result.id is null then return public.incident_result_error('NOT_FOUND','Roster entry was not found.'); end if;
  end if;
  return pg_catalog.jsonb_build_object('ok',true,'roster',pg_catalog.to_jsonb(result));
exception when invalid_text_representation or datetime_field_overflow then return public.incident_result_error('VALIDATION_ERROR','Roster values are invalid.');
when others then return public.incident_result_error('INTERNAL_ERROR','The roster entry could not be saved.'); end;
$function$
;
CREATE OR REPLACE FUNCTION public.set_emergency_roster_active(p_roster_id uuid, p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare result public.emergency_response_roster;
begin
  if auth.uid() is null then return public.incident_result_error('AUTHENTICATION_REQUIRED','Authentication is required.'); end if;
  if public.current_user_role() not in ('supervisor','administrator') then return public.incident_result_error('ACCESS_DENIED','Roster management permission is required.'); end if;
  update public.emergency_response_roster set active=p_active where id=p_roster_id returning * into result;
  if result.id is null then return public.incident_result_error('NOT_FOUND','Roster entry was not found.'); end if;
  return pg_catalog.jsonb_build_object('ok',true,'roster',pg_catalog.to_jsonb(result));
exception when others then return public.incident_result_error('INTERNAL_ERROR','The roster entry could not be updated.'); end;
$function$
;
CREATE OR REPLACE FUNCTION public.register_evidence_item(p_parent_type text, p_parent_id uuid, p_original_filename text, p_content_type text, p_byte_size bigint, p_category text, p_description text, p_storage_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor_id uuid:=auth.uid(); actor_name text; actor_role text; result public.evidence_items;
begin
  if actor_id is null then return pg_catalog.jsonb_build_object('ok',false,'code','AUTHENTICATION_REQUIRED'); end if;
  if not public.pilot_account_ready(actor_id) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  select display_name,role into actor_name,actor_role from public.profiles where id=actor_id;
  if p_parent_type='work_order' then
    if actor_role='technician' then
      if not exists(select 1 from public.work_orders w where w.id=p_parent_id and w.assigned_technician_id=actor_id and (w.status in ('assigned','in_progress') or (w.status in ('completed','reviewed','closed') and exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))) and exists(select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id where fm.profile_id=actor_id and fm.facility_id=w.facility_id and fm.membership_role='technician' and fm.active and fm.effective_from<=pg_catalog.now() and (fm.effective_to is null or fm.effective_to>pg_catalog.now()) and s.is_active)) then return pg_catalog.jsonb_build_object('ok',false,'code','EVIDENCE_READ_ONLY'); end if;
    elsif not exists(select 1 from public.work_orders w where w.id=p_parent_id and (actor_role in ('approver','supervisor','administrator') or w.user_id=actor_id or w.requested_by=actor_id)) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  elsif p_parent_type='incident' then
    if not exists(select 1 from public.incidents i where i.id=p_parent_id and (actor_role in ('approver','supervisor','administrator') or i.reported_by=actor_id or i.assigned_technician_id=actor_id or (i.assigned_team_id is not null and exists(select 1 from public.maintenance_team_members m where m.team_id=i.assigned_team_id and m.profile_id=actor_id and m.is_active)))) then return pg_catalog.jsonb_build_object('ok',false,'code','ACCESS_DENIED'); end if;
  else return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_category not in ('before','after') or p_storage_path not like 'evidence/'||pg_catalog.replace(p_parent_type,'_','-')||'/'||p_parent_id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return pg_catalog.jsonb_build_object('ok',false,'code','INVALID_STORAGE_OBJECT'); end if;
  insert into public.evidence_items(parent_type,work_order_id,incident_id,uploaded_by,original_filename,content_type,byte_size,category,description,storage_path) values(p_parent_type,case when p_parent_type='work_order' then p_parent_id end,case when p_parent_type='incident' then p_parent_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_category,nullif(pg_catalog.btrim(p_description),''),p_storage_path) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,incident_id,action,actor,note) values(actor_id,result.work_order_id,result.incident_id,'evidence_uploaded',actor_name,pg_catalog.jsonb_build_object('evidence_id',result.id,'category',result.category,'parent_type',result.parent_type,'document_correction',exists(select 1 from public.work_order_document_corrections c where c.work_order_id=result.work_order_id and c.status='open'))::text);
  return pg_catalog.jsonb_build_object('ok',true,'evidence',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or invalid_text_representation then return pg_catalog.jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); when unique_violation then return pg_catalog.jsonb_build_object('ok',false,'code','DUPLICATE_EVIDENCE'); when others then return pg_catalog.jsonb_build_object('ok',false,'code','INTERNAL_ERROR'); end;$function$
;
CREATE OR REPLACE FUNCTION public.validate_new_asset_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if new.asset_id is not null and (tg_op='INSERT' or old.asset_id is distinct from new.asset_id)
    and not exists(select 1 from public.assets a where a.id=new.asset_id and a.lifecycle_status<>'decommissioned') then
    raise foreign_key_violation using message='Selected Asset is unavailable.';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.asset_result_error(code text, message text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select pg_catalog.jsonb_build_object('ok',false,'code',code,'message',message)
$function$
;
CREATE OR REPLACE FUNCTION public.create_asset_system(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.update_asset_system(p_system_id uuid, p_payload jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.create_asset(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.update_asset_details(p_asset_id uuid, p_payload jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.change_asset_criticality(p_asset_id uuid, p_criticality text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.change_asset_tag(p_asset_id uuid, p_asset_tag text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.change_asset_status(p_asset_id uuid, p_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.set_work_order_asset(p_work_order_id uuid, p_asset_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.set_incident_asset(p_incident_id uuid, p_asset_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.create_incident_with_asset(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.protect_pm_revision()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin raise exception using errcode='55000',message='Maintenance Requirement revisions are immutable.'; end;
$function$
;
CREATE OR REPLACE FUNCTION public.pm_result_error(p_code text, p_message text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select pg_catalog.jsonb_build_object('ok',false,'code',p_code,'message',p_message)
$function$
;
CREATE OR REPLACE FUNCTION public.pm_business_date()
 RETURNS date
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select (pg_catalog.now() at time zone 'Asia/Singapore')::date
$function$
;
CREATE OR REPLACE FUNCTION public.next_maintenance_requirement_number(p_reference timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare y integer:=extract(year from p_reference at time zone 'Asia/Singapore'); n integer;
begin
  insert into public.maintenance_requirement_number_counters(reference_year,last_value) values(y,1)
  on conflict(reference_year) do update set last_value=public.maintenance_requirement_number_counters.last_value+1
  returning last_value into n;
  return 'PM-'||y::text||'-'||pg_catalog.lpad(n::text,6,'0');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.calculate_pm_due_date(p_revision_id uuid, p_occurrence_number integer)
 RETURNS date
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare r public.maintenance_requirement_revisions; offset_value integer; target_month date; last_day integer;
begin
  if p_occurrence_number<1 then raise exception 'Occurrence number must be positive'; end if;
  select * into r from public.maintenance_requirement_revisions where id=p_revision_id;
  if not found then raise exception 'Maintenance Requirement revision not found'; end if;
  offset_value:=(p_occurrence_number-1)*r.interval_value;
  if r.interval_unit='day' then return r.first_due_date+offset_value;
  elsif r.interval_unit='week' then return r.first_due_date+(offset_value*7);
  else
    if r.interval_unit='year' then offset_value:=offset_value*12; end if;
    target_month:=(pg_catalog.date_trunc('month',r.first_due_date)::date+pg_catalog.make_interval(months=>offset_value))::date;
    last_day:=extract(day from (target_month+pg_catalog.make_interval(months=>1)-pg_catalog.make_interval(days=>1))::date);
    return target_month+(least(extract(day from r.first_due_date)::integer,last_day)-1);
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_pm_requirement(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; req public.maintenance_requirements; rev public.maintenance_requirement_revisions;
  asset_state text; effective date:=coalesce(nullif(p_payload->>'effective_date','')::date,public.pm_business_date()); first_due date:=nullif(p_payload->>'first_due_date','')::date;
  department_value uuid:=nullif(p_payload->>'department_id','')::uuid; team_value uuid:=nullif(p_payload->>'responsible_team_id','')::uuid;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select lifecycle_status into asset_state from public.assets where id=nullif(p_payload->>'asset_id','')::uuid;
  if asset_state is null or asset_state='decommissioned' then return public.pm_result_error('INVALID_ASSET','Selected Asset is unavailable for PM.'); end if;
  if pg_catalog.btrim(coalesce(p_payload->>'title',''))='' or pg_catalog.btrim(coalesce(p_payload->>'scope',''))=''
    or pg_catalog.lower(coalesce(p_payload->>'maintenance_type','')) not in ('preventive','inspection')
    or pg_catalog.lower(coalesce(p_payload->>'interval_unit','')) not in ('day','week','month','year')
    or coalesce((p_payload->>'interval_value')::integer,0) not between 1 and 365
    or first_due is null or effective>public.pm_business_date() or first_due<effective
    or pg_catalog.lower(coalesce(p_payload->>'default_priority','medium')) not in ('low','medium','high','critical') then
    return public.pm_result_error('VALIDATION_ERROR','Maintenance Requirement values are invalid.'); end if;
  if department_value is not null and not exists(select 1 from public.departments d where d.id=department_value and d.is_active and d.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Department is unavailable.'); end if;
  if team_value is not null and not exists(select 1 from public.maintenance_teams t where t.id=team_value and t.is_active and t.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Responsible team is unavailable.'); end if;
  insert into public.maintenance_requirements(requirement_number,asset_id,created_by,updated_by)
  values(public.next_maintenance_requirement_number(),(p_payload->>'asset_id')::uuid,actor_id,actor_id) returning * into req;
  insert into public.maintenance_requirement_revisions(requirement_id,revision_number,title,scope,maintenance_type,interval_value,interval_unit,first_due_date,lead_time_days,department_id,responsible_team_id,default_priority,estimated_hours,evidence_guidance,instructions,procedure_reference,effective_date,created_by)
  values(req.id,1,pg_catalog.btrim(p_payload->>'title'),pg_catalog.btrim(p_payload->>'scope'),pg_catalog.lower(p_payload->>'maintenance_type'),(p_payload->>'interval_value')::integer,pg_catalog.lower(p_payload->>'interval_unit'),first_due,coalesce(nullif(p_payload->>'lead_time_days','')::integer,0),department_value,team_value,pg_catalog.lower(coalesce(p_payload->>'default_priority','medium')),nullif(p_payload->>'estimated_hours','')::numeric,nullif(pg_catalog.btrim(coalesce(p_payload->>'evidence_guidance','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'instructions','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'procedure_reference','')),''),effective,actor_id) returning * into rev;
  update public.maintenance_requirements set current_revision_id=rev.id where id=req.id returning * into req;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note)
  values(actor_id,req.asset_id,req.id,'pm_requirement_created',actor->>'name',pg_catalog.jsonb_build_object('requirement_number',req.requirement_number,'revision',1,'state','draft')::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req),'revision',pg_catalog.to_jsonb(rev));
exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return public.pm_result_error('VALIDATION_ERROR','Maintenance Requirement values are invalid.');
when others then return public.pm_result_error('INTERNAL_ERROR','Maintenance Requirement creation failed.'); end;
$function$
;
CREATE OR REPLACE FUNCTION public.revise_pm_requirement(p_requirement_id uuid, p_payload jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); req public.maintenance_requirements; previous public.maintenance_requirement_revisions; rev public.maintenance_requirement_revisions;
  actor_id uuid; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); effective date:=coalesce(nullif(p_payload->>'effective_date','')::date,public.pm_business_date()); first_due date:=nullif(p_payload->>'first_due_date','')::date;
  department_value uuid:=nullif(p_payload->>'department_id','')::uuid; team_value uuid:=nullif(p_payload->>'responsible_team_id','')::uuid;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A revision reason is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into req from public.maintenance_requirements where id=p_requirement_id for update;
  if not found then return public.pm_result_error('NOT_FOUND','Maintenance Requirement not found.'); end if;
  if exists(select 1 from public.assets a where a.id=req.asset_id and a.lifecycle_status='decommissioned') then return public.pm_result_error('INVALID_ASSET','A decommissioned Asset cannot receive a new PM revision.'); end if;
  select * into previous from public.maintenance_requirement_revisions where id=req.current_revision_id;
  if pg_catalog.btrim(coalesce(p_payload->>'title',''))='' or pg_catalog.btrim(coalesce(p_payload->>'scope',''))=''
    or pg_catalog.lower(coalesce(p_payload->>'maintenance_type','')) not in ('preventive','inspection')
    or pg_catalog.lower(coalesce(p_payload->>'interval_unit','')) not in ('day','week','month','year')
    or coalesce((p_payload->>'interval_value')::integer,0) not between 1 and 365
    or first_due is null or effective>public.pm_business_date() or effective<previous.effective_date or first_due<effective then return public.pm_result_error('VALIDATION_ERROR','Revision values are invalid.'); end if;
  if department_value is not null and not exists(select 1 from public.departments d where d.id=department_value and d.is_active and d.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Department is unavailable.'); end if;
  if team_value is not null and not exists(select 1 from public.maintenance_teams t where t.id=team_value and t.is_active and t.deleted_at is null) then return public.pm_result_error('INVALID_REFERENCE','Responsible team is unavailable.'); end if;
  insert into public.maintenance_requirement_revisions(requirement_id,revision_number,title,scope,maintenance_type,interval_value,interval_unit,first_due_date,lead_time_days,department_id,responsible_team_id,default_priority,estimated_hours,evidence_guidance,instructions,procedure_reference,effective_date,created_by)
  values(req.id,previous.revision_number+1,pg_catalog.btrim(p_payload->>'title'),pg_catalog.btrim(p_payload->>'scope'),pg_catalog.lower(p_payload->>'maintenance_type'),(p_payload->>'interval_value')::integer,pg_catalog.lower(p_payload->>'interval_unit'),first_due,coalesce(nullif(p_payload->>'lead_time_days','')::integer,0),department_value,team_value,pg_catalog.lower(coalesce(p_payload->>'default_priority','medium')),nullif(p_payload->>'estimated_hours','')::numeric,nullif(pg_catalog.btrim(coalesce(p_payload->>'evidence_guidance','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'instructions','')),''),nullif(pg_catalog.btrim(coalesce(p_payload->>'procedure_reference','')),''),effective,(actor->>'id')::uuid) returning * into rev;
  update public.maintenance_requirements set current_revision_id=rev.id,updated_by=actor_id,updated_at=pg_catalog.now() where id=req.id returning * into req;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note) values(actor_id,req.asset_id,req.id,'pm_requirement_revised',actor->>'name',pg_catalog.jsonb_build_object('before_revision',previous.revision_number,'after_revision',rev.revision_number,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req),'revision',pg_catalog.to_jsonb(rev));
exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return public.pm_result_error('VALIDATION_ERROR','Revision values are invalid.');
when others then return public.pm_result_error('INTERNAL_ERROR','Maintenance Requirement revision failed.'); end;
$function$
;
CREATE OR REPLACE FUNCTION public.activate_pm_requirement(p_requirement_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); req public.maintenance_requirements;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  select * into req from public.maintenance_requirements where id=p_requirement_id for update; if not found then return public.pm_result_error('NOT_FOUND','Maintenance Requirement not found.'); end if;
  if req.state='active' then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','requirement',pg_catalog.to_jsonb(req)); end if;
  if not exists(select 1 from public.assets a where a.id=req.asset_id and a.lifecycle_status<>'decommissioned') then return public.pm_result_error('INVALID_ASSET','Selected Asset is unavailable for PM.'); end if;
  update public.maintenance_requirements set state='active',updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=req.id returning * into req;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note) values((actor->>'id')::uuid,req.asset_id,req.id,'pm_requirement_activated',actor->>'name',pg_catalog.jsonb_build_object('reason',nullif(pg_catalog.btrim(coalesce(p_reason,'')),''))::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.deactivate_pm_requirement(p_requirement_id uuid, p_reason text, p_cancel_future boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); req public.maintenance_requirements; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); cancelled_count integer:=0;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A deactivation reason is required.'); end if;
  select * into req from public.maintenance_requirements where id=p_requirement_id for update; if not found then return public.pm_result_error('NOT_FOUND','Maintenance Requirement not found.'); end if;
  if req.state='inactive' and not p_cancel_future then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','requirement',pg_catalog.to_jsonb(req)); end if;
  update public.maintenance_requirements set state='inactive',updated_by=(actor->>'id')::uuid,updated_at=pg_catalog.now() where id=req.id returning * into req;
  if p_cancel_future then
    with changed as (
      update public.pm_occurrences set generation_status='cancelled',cancelled_by=(actor->>'id')::uuid,cancellation_reason=reason,cancelled_at=pg_catalog.now()
      where requirement_id=req.id and generation_status in ('pending','generation_failed') and current_due_date>public.pm_business_date() returning id,asset_id
    ), logged as (
      insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
      select (actor->>'id')::uuid,c.asset_id,req.id,c.id,'pm_occurrence_cancelled',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'source','requirement_deactivation')::text from changed c returning 1
    ) select count(*) into cancelled_count from logged;
  end if;
  insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,action,actor,note) values((actor->>'id')::uuid,req.asset_id,req.id,'pm_requirement_deactivated',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'future_occurrences_cancelled',cancelled_count)::text);
  return pg_catalog.jsonb_build_object('ok',true,'requirement',pg_catalog.to_jsonb(req),'cancelled_occurrences',cancelled_count);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.materialize_pm_occurrences(p_through_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); req record; n integer; due_value date; inserted public.pm_occurrences; created_count integer:=0; today date:=public.pm_business_date();
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if p_through_date is null or p_through_date<today or p_through_date>today+366 then return public.pm_result_error('INVALID_HORIZON','Materialization horizon must be within 366 days.'); end if;
  for req in select r.id requirement_id,r.asset_id,r.current_revision_id from public.maintenance_requirements r join public.assets a on a.id=r.asset_id where r.state='active' and a.lifecycle_status<>'decommissioned' order by r.id loop
    n:=1;
    loop
      if n>10000 then raise exception 'PM recurrence safety bound exceeded'; end if;
      due_value:=public.calculate_pm_due_date(req.current_revision_id,n);
      exit when due_value>p_through_date;
      inserted:=null;
      insert into public.pm_occurrences(requirement_id,requirement_revision_id,asset_id,occurrence_number,original_due_date,current_due_date)
      values(req.requirement_id,req.current_revision_id,req.asset_id,n,due_value,due_value)
      on conflict do nothing returning * into inserted;
      if inserted.id is not null then
        created_count:=created_count+1;
        insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
        values((actor->>'id')::uuid,inserted.asset_id,inserted.requirement_id,inserted.id,'pm_occurrence_created',actor->>'name',pg_catalog.jsonb_build_object('original_due_date',inserted.original_due_date,'occurrence_number',inserted.occurrence_number)::text);
      end if;
      n:=n+1;
    end loop;
  end loop;
  return pg_catalog.jsonb_build_object('ok',true,'created_occurrences',created_count,'through_date',p_through_date);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.generate_pm_work_order(p_occurrence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); occurrence public.pm_occurrences; req public.maintenance_requirements; rev public.maintenance_requirement_revisions; asset public.assets; work public.work_orders; attempt integer; error_code text; previous_error_code text;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  select * into occurrence from public.pm_occurrences where id=p_occurrence_id for update; if not found then return public.pm_result_error('NOT_FOUND','PM Occurrence not found.'); end if;
  select * into work from public.work_orders where pm_occurrence_id=occurrence.id;
  if found then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(work),'occurrence',pg_catalog.to_jsonb(occurrence)); end if;
  if occurrence.generation_status='cancelled' then return public.pm_result_error('OCCURRENCE_CANCELLED','Cancelled PM Occurrences cannot generate work.'); end if;
  select * into req from public.maintenance_requirements where id=occurrence.requirement_id;
  select * into rev from public.maintenance_requirement_revisions where id=occurrence.requirement_revision_id;
  select * into asset from public.assets where id=occurrence.asset_id;
  attempt:=occurrence.generation_attempts+1;
  previous_error_code:=occurrence.last_generation_error_code;
  if req.state<>'active' then error_code:='REQUIREMENT_INACTIVE';
  elsif asset.lifecycle_status='decommissioned' then error_code:='ASSET_DECOMMISSIONED';
  elsif rev.requirement_id<>req.id or req.asset_id<>asset.id then error_code:='PM_REFERENCE_MISMATCH'; end if;
  if error_code is not null then
    update public.pm_occurrences set generation_status='generation_failed',generation_attempts=attempt,last_generation_error_code=error_code where id=occurrence.id returning * into occurrence;
    if previous_error_code is distinct from error_code then
      insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note) values((actor->>'id')::uuid,asset.id,req.id,occurrence.id,'pm_generation_failed',actor->>'name',pg_catalog.jsonb_build_object('code',error_code,'attempt',attempt)::text);
      insert into public.notification_outbox(pm_occurrence_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select occurrence.id,'pm_generation_failed','pm-occurrence:'||occurrence.id::text||':generation-failed:'||error_code,p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('pm_occurrence_id',occurrence.id,'code',error_code,'status','queued'),'pending'
      from public.profiles p where p.is_active and p.deleted_at is null and p.role in ('supervisor','administrator') on conflict do nothing;
    end if;
    return public.pm_result_error(error_code,'PM Work Order generation is blocked.');
  end if;
  begin
    insert into public.work_orders(user_id,requested_by,title,description,location,site,priority,status,source,source_reference,asset_id,department_id,due_date,estimated_hours,internal_notes,submitted_by,submitted_at,pm_occurrence_id)
    values((actor->>'id')::uuid,(actor->>'id')::uuid,rev.title,rev.scope,asset.location,asset.site,rev.default_priority,'submitted',rev.maintenance_type,req.requirement_number,asset.id,rev.department_id,occurrence.current_due_date,rev.estimated_hours,
      nullif(pg_catalog.concat_ws(E'\n\n',case when rev.instructions is not null then 'Instructions: '||rev.instructions end,case when rev.evidence_guidance is not null then 'Evidence guidance: '||rev.evidence_guidance end,case when rev.procedure_reference is not null then 'Procedure: '||rev.procedure_reference end),''),actor->>'name',pg_catalog.now(),occurrence.id) returning * into work;
    insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,from_status,to_status,actor,note)
    values((actor->>'id')::uuid,work.id,asset.id,req.id,occurrence.id,'work_order_created',null,'submitted',actor->>'name',pg_catalog.jsonb_build_object('source',work.source,'pm_requirement',req.requirement_number)::text);
    insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
    values((actor->>'id')::uuid,work.id,asset.id,req.id,occurrence.id,'pm_work_order_generated',actor->>'name',pg_catalog.jsonb_build_object('original_due_date',occurrence.original_due_date,'current_due_date',occurrence.current_due_date,'attempt',attempt)::text);
    update public.pm_occurrences set generation_status='generated',generated_at=pg_catalog.now(),generation_attempts=attempt,last_generation_error_code=null where id=occurrence.id returning * into occurrence;
    return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(work),'occurrence',pg_catalog.to_jsonb(occurrence));
  exception when others then
    error_code:='WORK_ORDER_GENERATION_FAILED';
    update public.pm_occurrences set generation_status='generation_failed',generation_attempts=attempt,last_generation_error_code=error_code where id=occurrence.id returning * into occurrence;
    if previous_error_code is distinct from error_code then
      insert into public.activity_logs(user_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note) values((actor->>'id')::uuid,asset.id,req.id,occurrence.id,'pm_generation_failed',actor->>'name',pg_catalog.jsonb_build_object('code',error_code,'attempt',attempt)::text);
      insert into public.notification_outbox(pm_occurrence_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
      select occurrence.id,'pm_generation_failed','pm-occurrence:'||occurrence.id::text||':generation-failed:'||error_code,p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('pm_occurrence_id',occurrence.id,'code',error_code,'status','queued'),'pending'
      from public.profiles p where p.is_active and p.deleted_at is null and p.role in ('supervisor','administrator') on conflict do nothing;
    end if;
    return public.pm_result_error(error_code,'PM Work Order generation failed.');
  end;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.process_due_pm_work(p_through_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); materialized jsonb; row record; result jsonb; generated integer:=0; failed integer:=0;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  materialized:=public.materialize_pm_occurrences(p_through_date); if coalesce((materialized->>'ok')::boolean,false) is not true then return materialized; end if;
  for row in select id from public.pm_occurrences where current_due_date<=p_through_date and generation_status in ('pending','generation_failed') order by current_due_date,id loop
    result:=public.generate_pm_work_order(row.id);
    if coalesce((result->>'ok')::boolean,false) then generated:=generated+1; else failed:=failed+1; end if;
  end loop;
  return pg_catalog.jsonb_build_object('ok',true,'materialized',coalesce((materialized->>'created_occurrences')::integer,0),'generated',generated,'failed',failed,'through_date',p_through_date);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.defer_pm_occurrence(p_occurrence_id uuid, p_revised_due_date date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); occurrence public.pm_occurrences; deferral public.pm_occurrence_deferrals; work public.work_orders; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); sequence integer;
begin
  if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.pm_result_error('ACCESS_DENIED','Supervisor or Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A deferral reason is required.'); end if;
  select * into occurrence from public.pm_occurrences where id=p_occurrence_id for update; if not found then return public.pm_result_error('NOT_FOUND','PM Occurrence not found.'); end if;
  if occurrence.generation_status='cancelled' then return public.pm_result_error('OCCURRENCE_CANCELLED','Cancelled PM Occurrences cannot be deferred.'); end if;
  if p_revised_due_date is null or p_revised_due_date<=occurrence.current_due_date then return public.pm_result_error('VALIDATION_ERROR','Revised due date must be later than the current due date.'); end if;
  select * into work from public.work_orders where pm_occurrence_id=occurrence.id for update;
  if found and work.status in ('in_progress','completed','reviewed','closed','cancelled') then return public.pm_result_error('WORK_ALREADY_STARTED','PM cannot be deferred after work has started or terminated.'); end if;
  select coalesce(pg_catalog.max(d.sequence_number),0)+1 into sequence from public.pm_occurrence_deferrals d where d.occurrence_id=occurrence.id;
  insert into public.pm_occurrence_deferrals(occurrence_id,sequence_number,previous_due_date,revised_due_date,reason,deferred_by)
  values(occurrence.id,sequence,occurrence.current_due_date,p_revised_due_date,reason,(actor->>'id')::uuid) returning * into deferral;
  update public.pm_occurrences set current_due_date=p_revised_due_date where id=occurrence.id returning * into occurrence;
  if work.id is not null then update public.work_orders set due_date=p_revised_due_date,updated_at=pg_catalog.now() where id=work.id returning * into work; end if;
  insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
  values((actor->>'id')::uuid,work.id,occurrence.asset_id,occurrence.requirement_id,occurrence.id,'pm_occurrence_deferred',actor->>'name',pg_catalog.jsonb_build_object('sequence',sequence,'previous_due_date',deferral.previous_due_date,'revised_due_date',deferral.revised_due_date,'reason',reason)::text);
  return pg_catalog.jsonb_build_object('ok',true,'occurrence',pg_catalog.to_jsonb(occurrence),'deferral',pg_catalog.to_jsonb(deferral),'work_order',case when work.id is null then null else pg_catalog.to_jsonb(work) end);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_pm_occurrence(p_occurrence_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); occurrence public.pm_occurrences; work public.work_orders; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null or actor->>'role'<>'administrator' then return public.pm_result_error('ACCESS_DENIED','Administrator authority is required.'); end if;
  if reason is null then return public.pm_result_error('REASON_REQUIRED','A cancellation reason is required.'); end if;
  select * into occurrence from public.pm_occurrences where id=p_occurrence_id for update; if not found then return public.pm_result_error('NOT_FOUND','PM Occurrence not found.'); end if;
  if occurrence.generation_status='cancelled' then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','occurrence',pg_catalog.to_jsonb(occurrence)); end if;
  select * into work from public.work_orders where pm_occurrence_id=occurrence.id for update;
  if found and work.status<>'cancelled' then return public.pm_result_error('WORK_ORDER_CANCELLATION_REQUIRED','Cancel the linked Work Order through its existing lifecycle first.'); end if;
  update public.pm_occurrences set generation_status='cancelled',generated_at=null,cancelled_by=(actor->>'id')::uuid,cancellation_reason=reason,cancelled_at=pg_catalog.now() where id=occurrence.id returning * into occurrence;
  insert into public.activity_logs(user_id,work_order_id,asset_id,maintenance_requirement_id,pm_occurrence_id,action,actor,note)
  values((actor->>'id')::uuid,work.id,occurrence.asset_id,occurrence.requirement_id,occurrence.id,'pm_occurrence_cancelled',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'linked_work_order',work.id)::text);
  return pg_catalog.jsonb_build_object('ok',true,'occurrence',pg_catalog.to_jsonb(occurrence));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.pilot_account_ready(p_user_id uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select exists (
    select 1 from public.profiles profile
    where profile.id=p_user_id
      and profile.is_active=true
      and profile.deleted_at is null
      and profile.password_change_required=false
      and profile.role in ('reviewer','initiator','approver','technician','supervisor','facility_manager','administrator')
  )
$function$
;
CREATE OR REPLACE FUNCTION public.protect_profile_authorization_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  admin_rpc boolean := coalesce(
    pg_catalog.current_setting('fmworks.profile_admin_rpc', true),
    ''
  ) = 'on';
  password_rpc boolean := coalesce(
    pg_catalog.current_setting('fmworks.password_change_completion', true),
    ''
  ) = 'on';
  active_administrator_count integer;
begin
  if new.password_change_required is distinct from old.password_change_required
    and not admin_rpc
    and not password_rpc
  then
    raise exception 'Password readiness can only be changed by a trusted server operation';
  end if;

  if (
      new.role is distinct from old.role
      or new.is_active is distinct from old.is_active
      or new.deleted_at is distinct from old.deleted_at
    ) and not admin_rpc
  then
    raise exception 'Role, activation and archive changes require the audited Administrator operation';
  end if;

  if auth.uid() is distinct from old.id
    and not admin_rpc
    and not (
      password_rpc
      and new.password_change_required is distinct from old.password_change_required
      and new.display_name is not distinct from old.display_name
      and new.email is not distinct from old.email
      and new.department is not distinct from old.department
      and new.department_id is not distinct from old.department_id
      and new.trade_discipline is not distinct from old.trade_discipline
      and new.contact_number is not distinct from old.contact_number
      and new.role is not distinct from old.role
      and new.is_active is not distinct from old.is_active
      and new.deleted_at is not distinct from old.deleted_at
      and new.last_active_at is not distinct from old.last_active_at
      and new.last_seen_route is not distinct from old.last_seen_route
    )
  then
    raise exception 'Another user profile can only be changed by the audited Administrator operation';
  end if;

  if admin_rpc and auth.uid() = old.id and (
    new.role <> 'administrator'
    or new.is_active = false
    or new.deleted_at is not null
  ) then
    raise exception 'Administrators cannot demote, deactivate or archive their own account';
  end if;

  if old.role = 'administrator'
    and old.is_active = true
    and old.deleted_at is null
    and old.password_change_required = false
    and (
      new.role <> 'administrator'
      or new.is_active = false
      or new.deleted_at is not null
    )
  then
    perform pg_catalog.pg_advisory_xact_lock(6042026);
    select pg_catalog.count(*)
    into active_administrator_count
    from public.profiles as profile
    where profile.role = 'administrator'
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false;

    if active_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be changed';
    end if;
  end if;

  new.updated_at := pg_catalog.now();
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_update_profile(p_target_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  previous_profile public.profiles%rowtype;
  result public.profiles%rowtype;
  next_role text;
  next_display_name text;
  next_trade text;
  next_active boolean;
  next_department_id uuid;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then
    raise exception 'Administrator authorization required';
  end if;

  select * into previous_profile from public.profiles
  where id = p_target_id and deleted_at is null for update;
  if previous_profile.id is null then raise exception 'Profile not found'; end if;

  next_role := lower(trim(coalesce(p_payload ->> 'role', previous_profile.role)));
  next_display_name := trim(coalesce(p_payload ->> 'display_name', previous_profile.display_name));
  next_trade := nullif(trim(case when p_payload ? 'trade_discipline'
    then coalesce(p_payload ->> 'trade_discipline', '')
    else coalesce(previous_profile.trade_discipline, '') end), '');
  next_active := case when p_payload ? 'is_active'
    then (p_payload ->> 'is_active')::boolean else previous_profile.is_active end;
  next_department_id := case when p_payload ? 'department_id'
    then nullif(p_payload ->> 'department_id', '')::uuid
    else previous_profile.department_id end;

  if next_role not in ('reviewer','initiator','approver','technician','supervisor','administrator')
    or next_display_name = ''
  then raise exception 'Invalid profile values'; end if;
  if next_role = 'technician' and next_trade is null then
    raise exception 'Technicians require a trade or discipline';
  end if;
  if next_department_id is not null and not exists (
    select 1 from public.departments where id = next_department_id and deleted_at is null
  ) then raise exception 'Department is unavailable'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    display_name = next_display_name,
    department_id = next_department_id,
    trade_discipline = case when next_role = 'technician' then next_trade else null end,
    contact_number = case when p_payload ? 'contact_number'
      then nullif(trim(coalesce(p_payload ->> 'contact_number', '')), '')
      else contact_number end,
    role = next_role,
    is_active = next_active
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_profile_updated',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', result.id,
      'previous_role', previous_profile.role,
      'role', result.role,
      'previous_active', previous_profile.is_active,
      'is_active', result.is_active
    )::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_finalize_provisioned_profile(p_target_id uuid, p_payload jsonb, p_event text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  result public.profiles%rowtype;
  target_role text := lower(trim(coalesce(p_payload ->> 'role', '')));
  target_name text := trim(coalesce(p_payload ->> 'display_name', ''));
  target_trade text := nullif(trim(coalesce(p_payload ->> 'trade_discipline', '')), '');
  target_department_id uuid := nullif(p_payload ->> 'department_id', '')::uuid;
  target_active boolean := coalesce((p_payload ->> 'is_active')::boolean, true);
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;
  if p_event not in ('user_admin_invited','user_admin_direct_created','user_admin_pending_activated')
  then raise exception 'Unsupported provisioning event'; end if;

  select * into target_profile from public.profiles where id = p_target_id for update;
  if target_profile.id is null then raise exception 'Quarantine profile was not created'; end if;
  if target_role not in ('reviewer','initiator','approver','technician','supervisor','administrator')
    or target_name = ''
  then raise exception 'Invalid profile values'; end if;
  if target_role = 'technician' and target_trade is null then
    raise exception 'Technicians require a trade or discipline';
  end if;
  if target_department_id is not null and not exists (
    select 1 from public.departments where id = target_department_id and deleted_at is null
  ) then raise exception 'Department is unavailable'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    display_name = target_name,
    department_id = target_department_id,
    trade_discipline = case when target_role = 'technician' then target_trade else null end,
    contact_number = nullif(trim(coalesce(p_payload ->> 'contact_number', '')), ''),
    role = target_role,
    is_active = target_active,
    deleted_at = null,
    password_change_required = true
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    p_event,
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', result.id,
      'role', result.role,
      'is_active', result.is_active,
      'password_change_required', true
    )::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_archive_profile(p_target_id uuid, p_confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  result public.profiles%rowtype;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;

  select * into target_profile from public.profiles
  where id = p_target_id and deleted_at is null for update;
  if target_profile.id is null then raise exception 'Profile not found'; end if;
  if target_profile.id = actor_profile.id then raise exception 'Administrators cannot archive their own account'; end if;
  if lower(trim(coalesce(p_confirmation, ''))) not in (
    lower(trim(target_profile.display_name)), lower(trim(coalesce(target_profile.email, '')))
  ) then raise exception 'Archive confirmation does not match'; end if;
  if exists (
    select 1 from public.work_orders
    where assigned_technician_id = p_target_id
      and status not in ('done','completed','closed','rejected','cancelled')
  ) then raise exception 'Active work assignments must be reassigned before archive'; end if;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);
  update public.profiles set
    is_active = false,
    deleted_at = pg_catalog.now(),
    password_change_required = false
  where id = p_target_id
  returning * into result;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_archived',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object('target_profile_id', result.id, 'role', result.role)::text
  );

  return pg_catalog.to_jsonb(result);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_prepare_permanent_profile_deletion(p_target_id uuid, p_confirmation text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  target_profile public.profiles%rowtype;
  ready_administrator_count integer;
begin
  select * into actor_profile from public.profiles where id = auth.uid();
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or not public.pilot_account_ready(actor_profile.id)
  then raise exception 'Administrator authorization required'; end if;

  select * into target_profile from public.profiles where id = p_target_id for update;
  if target_profile.id is null then raise exception 'Profile not found'; end if;
  if target_profile.id = actor_profile.id then
    raise exception 'Administrators cannot permanently delete their own account';
  end if;
  if lower(trim(coalesce(p_confirmation, ''))) not in (
    lower(trim(target_profile.display_name)), lower(trim(coalesce(target_profile.email, '')))
  ) then raise exception 'Permanent deletion confirmation does not match'; end if;
  if exists (
    select 1 from public.work_orders
    where assigned_technician_id = p_target_id
      and status not in ('closed','cancelled')
  ) then raise exception 'Active work assignments must be reassigned before permanent deletion'; end if;

  if target_profile.role = 'administrator'
    and target_profile.is_active = true
    and target_profile.deleted_at is null
    and target_profile.password_change_required = false
  then
    select count(*) into ready_administrator_count
    from public.profiles
    where role = 'administrator'
      and is_active = true
      and deleted_at is null
      and password_change_required = false;
    if ready_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be permanently deleted';
    end if;
  end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    'user_admin_permanent_deletion_requested',
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', target_profile.id,
      'target_email', target_profile.email,
      'target_display_name', target_profile.display_name,
      'target_role', target_profile.role,
      'external_auth_status', 'pending'
    )::text
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'target_profile_id', target_profile.id,
    'target_display_name', target_profile.display_name
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_record_permanent_delete_result(p_actor_id uuid, p_target_id uuid, p_succeeded boolean, p_error_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  actor_profile public.profiles%rowtype;
  safe_error_code text := nullif(pg_catalog.left(trim(coalesce(p_error_code, '')), 100), '');
begin
  select * into actor_profile from public.profiles where id = p_actor_id;
  if actor_profile.id is null or actor_profile.role <> 'administrator'
    or actor_profile.is_active is not true or actor_profile.deleted_at is not null
  then raise exception 'Administrator reconciliation actor is unavailable'; end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    actor_profile.id,
    case when p_succeeded
      then 'user_admin_permanent_deletion_completed'
      else 'user_admin_permanent_deletion_failed' end,
    actor_profile.display_name,
    pg_catalog.jsonb_build_object(
      'target_profile_id', p_target_id,
      'external_auth_status', case when p_succeeded then 'deleted' else 'failed' end,
      'error_code', case when p_succeeded then null else safe_error_code end
    )::text
  );

  return pg_catalog.jsonb_build_object('ok', true, 'recorded', true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.complete_password_change_trusted(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  target_profile public.profiles%rowtype;
  was_required boolean;
begin
  select profile.*
  into target_profile
  from public.profiles as profile
  where profile.id = p_user_id
    and profile.is_active = true
    and profile.deleted_at is null
  for update;

  if target_profile.id is null then
    raise exception 'Active profile not found';
  end if;

  was_required := target_profile.password_change_required;

  if was_required then
    perform pg_catalog.set_config(
      'fmworks.password_change_completion',
      'on',
      true
    );
    update public.profiles as profile
    set password_change_required = false
    where profile.id = p_user_id;
  end if;

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    p_user_id,
    case
      when was_required then 'user_first_password_changed'
      else 'user_password_changed'
    end,
    target_profile.display_name,
    'Password value and recovery token are intentionally not recorded.'
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'was_required', was_required
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.record_user_presence(presence_route text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor_id uuid := auth.uid();
  safe_route text;
begin
  if actor_id is null or not public.pilot_account_ready(actor_id) then
    return false;
  end if;

  safe_route := case
    when pg_catalog.left(pg_catalog.btrim(coalesce(presence_route, '')), 1) = '/'
      then pg_catalog.left(
        pg_catalog.split_part(pg_catalog.btrim(presence_route), '?', 1),
        200
      )
    else null
  end;

  update public.profiles as profile
  set
    last_active_at = pg_catalog.now(),
    last_seen_route = coalesce(safe_route, profile.last_seen_route)
  where profile.id = actor_id
    and public.pilot_account_ready(profile.id)
    and (
      profile.last_active_at is null
      or profile.last_active_at < pg_catalog.now() - interval '90 seconds'
      or (
        safe_route is not null
        and profile.last_seen_route is distinct from safe_route
      )
    );

  return found;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.enforce_pilot_actor_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is not null and not public.pilot_account_ready(auth.uid()) then
    raise insufficient_privilege using message = 'Operational account readiness is required';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.protect_profile_deletion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  ready_administrator_count integer;
begin
  if exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = old.id
  ) then
    raise insufficient_privilege using
      message = 'Profiles can only be permanently deleted through the trusted Auth deletion workflow';
  end if;

  if old.role = 'administrator'
    and old.is_active = true
    and old.deleted_at is null
    and old.password_change_required = false
  then
    perform pg_catalog.pg_advisory_xact_lock(6042026);
    select pg_catalog.count(*)
    into ready_administrator_count
    from public.profiles as profile
    where profile.role = 'administrator'
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false;

    if ready_administrator_count <= 1 then
      raise exception 'The final ready Administrator cannot be permanently deleted';
    end if;
  end if;

  if exists (
    select 1
    from public.work_orders as work_order
    where work_order.assigned_technician_id = old.id
      and work_order.status not in ('closed', 'cancelled')
  ) then
    raise exception 'Active work assignments must be reassigned before permanent deletion';
  end if;

  return old;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.bootstrap_first_administrator(p_target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  target_profile public.profiles%rowtype;
begin
  if p_target_user_id is null then
    raise exception using
      errcode = '22004',
      message = 'First Administrator bootstrap requires an explicit target Auth UUID';
  end if;

  -- Shared with the final-ready-Administrator protections. This serializes the
  -- zero-ready check, target promotion, and one-time audit marker.
  perform pg_catalog.pg_advisory_xact_lock(6042026);

  if exists (
    select 1
    from public.activity_logs as activity
    where activity.action = 'first_administrator_bootstrapped'
  ) then
    raise exception using
      errcode = '55000',
      message = 'First Administrator bootstrap has already been completed';
  end if;

  if exists (
    select 1
    from public.profiles as profile
    where profile.role = 'administrator'
      and profile.is_active = true
      and profile.deleted_at is null
      and profile.password_change_required = false
  ) then
    raise exception using
      errcode = '55000',
      message = 'First Administrator bootstrap refused: a ready Administrator already exists';
  end if;

  if not exists (
    select 1
    from auth.users as auth_user
    where auth_user.id = p_target_user_id
  ) then
    raise exception using
      errcode = 'P0002',
      message = 'First Administrator bootstrap target Auth user does not exist';
  end if;

  select profile.*
  into target_profile
  from public.profiles as profile
  where profile.id = p_target_user_id
  for update;

  if target_profile.id is null then
    raise exception using
      errcode = 'P0002',
      message = 'First Administrator bootstrap target profile does not exist';
  end if;

  if target_profile.role <> 'reviewer'
    or target_profile.is_active <> false
    or target_profile.deleted_at is not null
    or target_profile.password_change_required <> true
  then
    raise exception using
      errcode = '55000',
      message = 'First Administrator bootstrap target is not in the required quarantine state';
  end if;

  -- Cooperate with, rather than disable, the authorization-field trigger. The
  -- transaction-local capability is the same narrow mechanism used by audited
  -- Administrator RPCs and cannot survive this transaction.
  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'on', true);

  update public.profiles as profile
  set
    role = 'administrator',
    is_active = true,
    deleted_at = null
  where profile.id = p_target_user_id;

  perform pg_catalog.set_config('fmworks.profile_admin_rpc', 'off', true);

  insert into public.activity_logs(user_id, action, actor, note)
  values (
    p_target_user_id,
    'first_administrator_bootstrapped',
    'trusted database bootstrap',
    pg_catalog.jsonb_build_object(
      'event', 'first_administrator_bootstrap',
      'target_profile_id', p_target_user_id,
      'resulting_role', 'administrator',
      'is_active', true,
      'password_change_required', true
    )::text
  );

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'target_profile_id', p_target_user_id,
    'role', 'administrator',
    'is_active', true,
    'password_change_required', true
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.default_work_order_sla_category()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
begin
 if new.sla_service_category_id is null then select id into new.sla_service_category_id from public.service_categories where code='GENERAL'; end if;
 return new;
end;$function$
;
CREATE OR REPLACE FUNCTION public.attach_approved_sla_clock()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
declare selected_rule public.sla_rules; start_time timestamptz:=coalesce(new.submitted_at,new.created_at,now());
begin
 select r.* into selected_rule from public.sla_rules r join public.sla_agreement_versions v on v.id=r.version_id
 join public.sla_agreements a on a.id=v.agreement_id
 where r.service_category_id=new.sla_service_category_id and r.work_order_priority=new.priority and r.is_active and a.is_active
   and v.approval_status='approved' and v.effective_from<=start_time::date and (v.effective_to is null or v.effective_to>=start_time::date)
 order by v.effective_from desc,v.version_number desc limit 1;
 if found then
  insert into public.work_order_sla_clocks(work_order_id,sla_rule_id,started_at,acknowledgement_deadline,response_deadline,attendance_deadline,make_safe_deadline,rectification_deadline)
  values(new.id,selected_rule.id,start_time,
   case when selected_rule.acknowledgement_minutes is not null then start_time+make_interval(mins=>selected_rule.acknowledgement_minutes) end,
   case when selected_rule.response_minutes is not null then start_time+make_interval(mins=>selected_rule.response_minutes) end,
   case when selected_rule.attendance_minutes is not null then start_time+make_interval(mins=>selected_rule.attendance_minutes) end,
   case when selected_rule.make_safe_minutes is not null then start_time+make_interval(mins=>selected_rule.make_safe_minutes) end,
   start_time+make_interval(mins=>selected_rule.rectification_minutes)) on conflict(work_order_id) do nothing;
 end if;
 return new;
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_sla_version(p_version_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); result public.sla_agreement_versions;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Facility Manager or Administrator approval is required.'); end if;
 if not exists(select 1 from public.sla_rules r where r.version_id=p_version_id and r.is_active) then return public.work_order_result_error('VALIDATION_ERROR','At least one active SLA rule is required.'); end if;
 update public.sla_agreement_versions set approval_status='approved',approved_by=(actor->>'id')::uuid,approved_at=now(),approval_note=nullif(btrim(coalesce(p_note,'')),'') where id=p_version_id and approval_status in ('draft','pending_approval') returning * into result;
 if not found then return public.work_order_result_error('INVALID_STATE','Only a draft or pending version can be approved.'); end if;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_version_approved',actor->>'name',jsonb_build_object('version_id',result.id,'note',p_note)::text);
 return jsonb_build_object('ok',true,'version',to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.refresh_work_order_sla(p_work_order_id uuid, p_as_of timestamp with time zone DEFAULT now())
 RETURNS work_order_sla_clocks
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare c public.work_order_sla_clocks; elapsed numeric; total numeric;
begin
 select * into c from public.work_order_sla_clocks where work_order_id=p_work_order_id for update;
 if not found then return null; end if;
 total:=greatest(extract(epoch from(c.rectification_deadline-c.started_at)),1);
 elapsed:=greatest(extract(epoch from(coalesce(c.rectified_at,p_as_of)-c.started_at)),0);
 update public.work_order_sla_clocks set consumed_percent=least(999.99,round(elapsed/total*100,2)),
  risk_state=case when rectified_at is not null and rectified_at<=rectification_deadline then 'met' when coalesce(rectified_at,p_as_of)>rectification_deadline then 'breached' when elapsed/total>=.75 then 'at_risk' else 'on_track' end,
  last_evaluated_at=p_as_of where work_order_id=p_work_order_id returning * into c;
 return c;
end;$function$
;
CREATE OR REPLACE FUNCTION public.process_sla_escalations(p_as_of timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); inserted_count integer;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then raise exception 'ACCESS_DENIED'; end if;
 perform public.refresh_work_order_sla(c.work_order_id,p_as_of) from public.work_order_sla_clocks c;
 insert into public.sla_escalation_events(work_order_id,matrix_step_id,threshold_percent,escalation_level,reason,triggered_at)
 select c.work_order_id,s.id,s.threshold_percent,s.escalation_level,
  case when s.is_immediate_for_critical_safety and w.priority='critical' then 'Critical safety immediate escalation' else 'SLA threshold reached' end,p_as_of
 from public.work_order_sla_clocks c join public.sla_rules r on r.id=c.sla_rule_id
 join public.sla_agreement_versions v on v.id=r.version_id join public.escalation_matrix_steps s on s.version_id=v.id
 join public.work_orders w on w.id=c.work_order_id
 where c.risk_state<>'met' and (c.consumed_percent>=s.threshold_percent or (s.is_immediate_for_critical_safety and w.priority='critical'))
 on conflict(work_order_id,matrix_step_id) do nothing;
 get diagnostics inserted_count=row_count;
 insert into public.activity_logs(user_id,work_order_id,action,actor,note)
 select (actor->>'id')::uuid,e.work_order_id,'sla_escalated',actor->>'name',jsonb_build_object('level',e.escalation_level,'threshold_percent',e.threshold_percent,'reason',e.reason)::text
 from public.sla_escalation_events e where e.triggered_at=p_as_of;
 return inserted_count;
end;$function$
;
CREATE OR REPLACE FUNCTION public.create_report_schedule(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); result public.report_schedules; cadence_value text:=lower(coalesce(p_payload->>'cadence',''));
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management reporting authority is required.'); end if;
 if cadence_value not in ('daily','weekly','monthly') or length(btrim(coalesce(p_payload->>'name','')))<3 then return public.work_order_result_error('VALIDATION_ERROR','A valid name and cadence are required.'); end if;
 insert into public.report_schedules(name,cadence,report_scope,recipient_roles,recipient_emails,next_run_at,created_by)
 values(btrim(p_payload->>'name'),cadence_value,coalesce(p_payload->'scope','{}'::jsonb),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'recipient_roles','[]'::jsonb))),'{}'),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'recipient_emails','[]'::jsonb))),'{}'),coalesce(nullif(p_payload->>'next_run_at','')::timestamptz,now()),(actor->>'id')::uuid) returning * into result;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'report_schedule_created',actor->>'name',jsonb_build_object('schedule_id',result.id,'cadence',result.cadence,'delivery_status','NOT_CONFIGURED')::text);
 return jsonb_build_object('ok',true,'schedule',to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.acknowledge_sla_escalation(p_event_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); event public.sla_escalation_events;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management acknowledgement authority is required.'); end if;
 update public.sla_escalation_events set acknowledged_by=(actor->>'id')::uuid,acknowledged_at=now(),acknowledgement_note=nullif(btrim(coalesce(p_note,'')),'') where id=p_event_id and acknowledged_at is null returning * into event;
 if not found then return public.work_order_result_error('INVALID_STATE','Escalation is unavailable or already acknowledged.'); end if;
 insert into public.activity_logs(user_id,work_order_id,action,actor,note)values((actor->>'id')::uuid,event.work_order_id,'sla_escalation_acknowledged',actor->>'name',jsonb_build_object('event_id',event.id,'note',p_note)::text);
 return jsonb_build_object('ok',true,'event',to_jsonb(event));
end;$function$
;
CREATE OR REPLACE FUNCTION public.create_sla_document(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); result public.sla_documents;
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management document authority is required.'); end if;
 if length(btrim(coalesce(p_payload->>'title','')))<3 or coalesce(p_payload->>'maintenance_model','') not in ('IN_HOUSE','OUTSOURCED','HYBRID') then return public.work_order_result_error('VALIDATION_ERROR','Valid title and maintenance model are required.'); end if;
 insert into public.sla_documents(agreement_id,title,client_owner,service_provider,maintenance_model,agreement_reference,version_label,effective_date,expiry_date,original_filename,media_type,byte_size,content_sha256,storage_key,extracted_text,notes,uploaded_by)
 values(nullif(p_payload->>'agreement_id','')::uuid,btrim(p_payload->>'title'),nullif(btrim(coalesce(p_payload->>'client_owner','')),''),nullif(btrim(coalesce(p_payload->>'service_provider','')),''),p_payload->>'maintenance_model',btrim(p_payload->>'agreement_reference'),btrim(p_payload->>'version_label'),nullif(p_payload->>'effective_date','')::date,nullif(p_payload->>'expiry_date','')::date,p_payload->>'original_filename',p_payload->>'media_type',(p_payload->>'byte_size')::integer,p_payload->>'content_sha256',p_payload->>'storage_key',nullif(p_payload->>'extracted_text',''),nullif(p_payload->>'notes',''),(actor->>'id')::uuid) returning * into result;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_document_ingested',actor->>'name',jsonb_build_object('document_id',result.id,'reference',result.agreement_reference,'version',result.version_label,'sha256',result.content_sha256)::text);
 return jsonb_build_object('ok',true,'document',to_jsonb(result)-'extracted_text');
exception when check_violation or unique_violation or invalid_text_representation then return public.work_order_result_error('VALIDATION_ERROR','Document metadata is invalid or this version already exists.'); end $function$
;
CREATE OR REPLACE FUNCTION public.record_sla_extraction(p_document_id uuid, p_provider_key text, p_provider_model text, p_candidates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); candidate jsonb; proposal public.sla_extraction_proposals; ids jsonb:='[]'::jsonb;
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management extraction authority is required.'); end if;
 if p_provider_key not in ('mock','disabled') or jsonb_typeof(p_candidates)<>'array' then return public.work_order_result_error('VALIDATION_ERROR','Provider or candidate output is invalid.'); end if;
 if not exists(select 1 from public.sla_documents where id=p_document_id and superseded_at is null) then return public.work_order_result_error('NOT_FOUND','SLA document is unavailable.'); end if;
 for candidate in select value from jsonb_array_elements(p_candidates) loop
  if coalesce(candidate->>'sourceClause','')='' or coalesce(candidate->>'extractedObligation','')='' or jsonb_typeof(candidate->'proposedRule')<>'object' or coalesce((candidate->>'confidence')::numeric,-1) not between 0 and 1 then return public.work_order_result_error('MALFORMED_AI_OUTPUT','Every candidate requires source, obligation, rule and confidence.'); end if;
  insert into public.sla_extraction_proposals(document_id,source_page,source_section,source_clause,source_excerpt,extracted_obligation,proposed_rule,confidence,ambiguity_warning,provider_key,provider_model,extraction_payload,extraction_warnings,created_by)
  values(p_document_id,candidate->>'sourcePage',candidate->>'sourceSection',candidate->>'sourceClause',candidate->>'sourceExcerpt',candidate->>'extractedObligation',candidate->'proposedRule',(candidate->>'confidence')::numeric,candidate->>'ambiguityWarning',p_provider_key,p_provider_model,candidate,coalesce(array(select jsonb_array_elements_text(coalesce(candidate->'warnings','[]'::jsonb))),'{}'),(actor->>'id')::uuid) returning * into proposal;
  ids:=ids||to_jsonb(proposal.id);
 end loop;
 update public.sla_documents set review_status='EXTRACTED' where id=p_document_id;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_document_extracted',actor->>'name',jsonb_build_object('document_id',p_document_id,'provider',p_provider_key,'model',p_provider_model,'candidate_count',jsonb_array_length(ids))::text);
 return jsonb_build_object('ok',true,'proposal_ids',ids,'human_approval_required',true);
end $function$
;
CREATE OR REPLACE FUNCTION public.review_sla_extraction(p_proposal_id uuid, p_decision text, p_changes jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); result public.sla_extraction_proposals;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Facility Manager or Administrator review is required.'); end if;
 if p_decision not in ('approved_for_draft','rejected') then return public.work_order_result_error('VALIDATION_ERROR','Review decision is invalid.'); end if;
 update public.sla_extraction_proposals set proposed_rule=case when p_decision='approved_for_draft' then proposed_rule||coalesce(p_changes,'{}'::jsonb) else proposed_rule end,human_approval_state=p_decision,reviewed_by=(actor->>'id')::uuid,reviewed_at=now(),modifications=modifications||jsonb_build_array(jsonb_build_object('at',now(),'by',actor->>'id','changes',coalesce(p_changes,'{}'::jsonb))) where id=p_proposal_id and human_approval_state='pending' returning * into result;
 if not found then return public.work_order_result_error('INVALID_STATE','Only pending proposals can be reviewed.'); end if;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_extraction_reviewed',actor->>'name',jsonb_build_object('proposal_id',result.id,'decision',p_decision,'changes',p_changes)::text);
 return jsonb_build_object('ok',true,'proposal',to_jsonb(result));
end $function$
;
CREATE OR REPLACE FUNCTION public.approve_reviewed_sla_clause(p_proposal_id uuid, p_version_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); p public.sla_extraction_proposals; rule public.sla_rules; category_id uuid; payload jsonb;
begin
 if actor is null or actor->>'role' not in ('supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Facility Manager or Administrator approval is required.'); end if;
 select * into p from public.sla_extraction_proposals where id=p_proposal_id and human_approval_state='approved_for_draft' and approved_rule_id is null for update;
 if not found then return public.work_order_result_error('INVALID_STATE','A reviewed, unapproved proposal is required.'); end if; payload:=p.proposed_rule;
 select id into category_id from public.service_categories where code=coalesce(payload->>'serviceCategoryCode','GENERAL') and is_active; if category_id is null then return public.work_order_result_error('VALIDATION_ERROR','Service category is unavailable.'); end if;
 insert into public.sla_rules(version_id,service_category_id,priority_class,work_order_priority,acknowledgement_minutes,response_minutes,attendance_minutes,make_safe_minutes,rectification_minutes,kpi_target_percent,source_clause)
 values(p_version_id,category_id,payload->>'priorityClass',payload->>'workOrderPriority',nullif(payload->>'acknowledgementMinutes','')::integer,nullif(payload->>'responseMinutes','')::integer,nullif(payload->>'attendanceMinutes','')::integer,nullif(payload->>'makeSafeMinutes','')::integer,(payload->>'rectificationMinutes')::integer,(payload->>'kpiTargetPercent')::numeric,p.source_clause) returning * into rule;
 update public.sla_extraction_proposals set approved_rule_id=rule.id,approved_by=(actor->>'id')::uuid,approved_at=now() where id=p.id;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'sla_clause_approved',actor->>'name',jsonb_build_object('proposal_id',p.id,'rule_id',rule.id,'document_id',p.document_id,'source_clause',p.source_clause)::text);
 return jsonb_build_object('ok',true,'rule',to_jsonb(rule),'lineage',jsonb_build_object('document_id',p.document_id,'proposal_id',p.id,'source_clause',p.source_clause));
exception when check_violation or unique_violation or invalid_text_representation then return public.work_order_result_error('VALIDATION_ERROR','Reviewed structured rule is incomplete or conflicts with this version.'); end $function$
;
CREATE OR REPLACE FUNCTION public.create_staffing_assessment(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); result public.staffing_assessments;
begin
 if actor is null or actor->>'role' not in ('approver','supervisor','administrator') then return public.work_order_result_error('ACCESS_DENIED','Management staffing authority is required.'); end if;
 if coalesce(p_payload->>'operating_model','') not in ('IN_HOUSE','OUTSOURCED','HYBRID') then return public.work_order_result_error('VALIDATION_ERROR','Operating model is invalid.'); end if;
 insert into public.staffing_assessments(name,operating_model,scope,facility_inputs,asset_inputs,service_inputs,workforce_inputs,proposed_organization,created_by)
 values(btrim(p_payload->>'name'),p_payload->>'operating_model',coalesce(p_payload->'scope','{}'),coalesce(p_payload->'facility_inputs','{}'),coalesce(p_payload->'asset_inputs','{}'),coalesce(p_payload->'service_inputs','{}'),coalesce(p_payload->'workforce_inputs','{}'),coalesce(p_payload->'proposed_organization','[]'),(actor->>'id')::uuid) returning * into result;
 insert into public.activity_logs(user_id,action,actor,note) values((actor->>'id')::uuid,'staffing_assessment_created',actor->>'name',jsonb_build_object('assessment_id',result.id,'operating_model',result.operating_model)::text);
 return jsonb_build_object('ok',true,'assessment',to_jsonb(result));
end $function$
;
CREATE OR REPLACE FUNCTION public.set_sla_document_parser_result(p_document_id uuid, p_status text, p_metadata jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ declare actor jsonb:=public.work_order_actor();begin if actor is null or actor->>'role' not in('approver','supervisor','administrator')then return public.work_order_result_error('ACCESS_DENIED','Management document authority is required.');end if;update public.sla_documents set parser_status=p_status,parser_metadata=coalesce(p_metadata,'{}')where id=p_document_id and uploaded_by=(actor->>'id')::uuid;if not found then return public.work_order_result_error('NOT_FOUND','Document is unavailable.');end if;return jsonb_build_object('ok',true,'parser_status',p_status);exception when check_violation then return public.work_order_result_error('VALIDATION_ERROR','Parser result is invalid.');end $function$
;
CREATE OR REPLACE FUNCTION public.record_ai_operation(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ declare actor jsonb:=public.work_order_actor();r public.ai_operation_audit;begin if actor is null or actor->>'role' not in('approver','supervisor','administrator')then return public.work_order_result_error('ACCESS_DENIED','Management AI authority is required.');end if;insert into public.ai_operation_audit(operation_type,provider,model_identifier,prompt_version,document_id,requesting_user,completed_at,latency_ms,status,retry_count,input_size,confidence,validation_result,human_review_required,error_category,safe_diagnostic)values(left(p_payload->>'operation_type',60),left(p_payload->>'provider',80),left(p_payload->>'model_identifier',120),left(p_payload->>'prompt_version',80),nullif(p_payload->>'document_id','')::uuid,(actor->>'id')::uuid,now(),coalesce((p_payload->>'latency_ms')::int,0),left(p_payload->>'status',40),coalesce((p_payload->>'retry_count')::int,0),coalesce((p_payload->>'input_size')::int,0),nullif(p_payload->>'confidence','')::numeric,left(p_payload->>'validation_result',60),coalesce((p_payload->>'human_review_required')::boolean,true),left(p_payload->>'error_category',60),left(p_payload->>'safe_diagnostic',300))returning*into r;return jsonb_build_object('ok',true,'request_id',r.request_id);exception when others then return public.work_order_result_error('VALIDATION_ERROR','Safe AI audit metadata is invalid.');end $function$
;
CREATE OR REPLACE FUNCTION public.test_ai_configuration()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$ declare actor jsonb:=public.work_order_actor();c public.ai_provider_configurations;result text;begin if actor is null or actor->>'role' not in('supervisor','administrator')then return public.work_order_result_error('ACCESS_DENIED','AI administration authority is required.');end if;select*into c from public.ai_provider_configurations where enabled order by created_at desc limit 1;result:=case when c.id is null then'NOT_CONFIGURED' when c.provider_type='DISABLED'then'DISABLED' when c.provider_type='MOCK'then'READY' when not c.external_processing_approved then'EXTERNAL_AI_NOT_APPROVED' else'NOT_CONFIGURED'end;update public.ai_provider_configurations set last_connectivity_test=now(),configuration_status=result where id=c.id;insert into public.ai_operation_audit(operation_type,provider,model_identifier,requesting_user,completed_at,latency_ms,status,input_size,human_review_required,safe_diagnostic)values('HEALTH_CHECK',coalesce(c.provider_type,'DISABLED'),c.model_identifier,(actor->>'id')::uuid,now(),0,result,0,false,'Safe configuration metadata check; no document or credential transmitted.');return jsonb_build_object('ok',true,'status',result,'latency_ms',0,'credential_exposed',false);end $function$
;
CREATE OR REPLACE FUNCTION public.verify_completed_work_0037_core(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  completion_activity_id uuid;
  completion_actor_id uuid;
  cycle_number integer;
  administrator_self_verification boolean := false;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;

  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous
  from public.work_orders
  where id = p_work_order_id
  for update;

  if not found then
    return public.work_order_result_error('NOT_FOUND', 'Work order not found.');
  end if;

  if previous.status = 'reviewed' then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order', pg_catalog.to_jsonb(previous));
  end if;

  if previous.status <> 'completed' then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only Completed Work awaiting verification can be verified.');
  end if;

  if actor_role not in ('supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Supervisor, Facility Manager or Administrator authority is required.');
  end if;

  select l.id, l.user_id
    into completion_activity_id, completion_actor_id
  from public.activity_logs l
  where l.work_order_id = previous.id
    and l.action = 'work_order_complete'
  order by l.created_at desc, l.id desc
  limit 1;

  if completion_activity_id is null then
    return public.work_order_result_error('COMPLETION_AUDIT_REQUIRED', 'The latest Completed Work audit record could not be found.');
  end if;

  if actor_id = completion_actor_id then
    if actor_role <> 'administrator' then
      return public.work_order_result_error('SELF_REVIEW_DENIED', 'Technician, Supervisor and Facility Manager Completed Work must be verified by another authorised person.');
    end if;
    if reason is null then
      return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-verification requires an override reason.');
    end if;
    administrator_self_verification := true;
  end if;

  select count(*) + 1 into cycle_number
  from public.activity_logs l
  where l.work_order_id = previous.id
    and l.action = 'work_order_returned_for_rework';

  update public.work_orders
  set status = 'reviewed',
      reviewed_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where id = previous.id
  returning * into result;

  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values(
    actor_id,
    result.id,
    'work_order_review',
    'completed',
    'reviewed',
    actor_name,
    pg_catalog.jsonb_build_object(
      'cycle', cycle_number,
      'decision', 'verified',
      'reason', reason,
      'completion_activity_id', completion_activity_id,
      'independent_review', not administrator_self_verification,
      'administrator_self_verification', administrator_self_verification,
      'verified_by', actor_id,
      'verified_at', pg_catalog.now()
    )::text
  );

  if result.assigned_technician_id is not null then
    insert into public.notification_outbox(
      work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status
    )
    select result.id,
      'work_order_completion_accepted',
      'work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',
      p.id,p.id,p.email,'email',
      pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),
      'pending'
    from public.profiles p
    where p.id = result.assigned_technician_id
      and p.is_active
      and p.deleted_at is null
    on conflict do nothing;
  end if;

  if result.assigned_vendor_id is not null then
    insert into public.contractor_payment_assessments(
      work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_due_at
    )
    values(
      result.id,
      result.assigned_vendor_id,
      'awaiting_approval',
      coalesce((select sum(amount) from public.work_order_cost_lines where work_order_id=result.id),0),
      pg_catalog.now(),
      pg_catalog.now() + interval '30 days'
    )
    on conflict(work_order_id) do update set
      status='awaiting_approval',
      assessed_amount=excluded.assessed_amount,
      completed_work_accepted_at=excluded.completed_work_accepted_at,
      payment_due_at=excluded.payment_due_at,
      updated_at=pg_catalog.now();
  end if;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'work_order', pg_catalog.to_jsonb(result),
    'cycle', cycle_number,
    'administrator_self_verification', administrator_self_verification,
    'notification_status', 'queued'
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Completed Work verification data is invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Completed Work verification failed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.record_work_order_execution(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
    and not (
      actor_role='technician'
      and previous.assigned_technician_id is not null
      and actor_id=previous.assigned_technician_id
    ) then
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
$function$
;
CREATE OR REPLACE FUNCTION public.transition_work_order_20260924_core(p_work_order_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_orders%rowtype;
  action text:=pg_catalog.lower(coalesce(p_action,'')); reason text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'reason','')),''); readiness jsonb; cost numeric; role text; actor_id uuid; actor_name text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  role:=actor->>'role'; actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if role='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if role='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if action not in ('approve','complete') then return public.transition_work_order_0034_core(p_work_order_id,p_action,p_payload); end if;
  if action='complete' then
    if role<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Use the assigned Technician physical-completion submission.'); end if;
    if reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED','Administrator exception completion requires an explicit audited reason.'); end if;
    readiness:=public.transition_work_order_0034_core(p_work_order_id,'complete',
      pg_catalog.jsonb_build_object('completion_notes',w.completion_notes,'actual_labour_hours',w.actual_labour_hours));
    if coalesce((readiness->>'ok')::boolean,false) then
      insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
      values(actor_id,w.id,'administrator_exception_completion_recorded',w.status,'completed',actor_name,
        pg_catalog.jsonb_build_object('reason',reason,'completion_actor_id',actor_id,'recorded_at',pg_catalog.now())::text);
    end if;
    return readiness;
  end if;
  if w.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only submitted work may be approved to proceed.'); end if;
  readiness:=public.work_order_approval_readiness(w.id);
  if not coalesce((readiness->>'ready')::boolean,false) then return public.work_order_result_error('APPROVAL_NOT_READY',coalesce(readiness->>'blocking_reason','Approval basis is incomplete.')); end if;
  cost:=(readiness->>'proposed_cost')::numeric;
  if (cost<=250000 and role not in ('supervisor','facility_manager','administrator'))
    or (cost>250000 and cost<=500000 and role not in ('facility_manager','administrator'))
    or (cost>500000 and role<>'administrator') then return public.work_order_result_error('APPROVAL_AUTHORITY_EXCEEDED','Your monetary approval authority is insufficient.'); end if;
  if actor_id=w.requested_by and role<>'administrator' then return public.work_order_result_error('SELF_APPROVAL_DENIED','A requester cannot approve their own proposed work.'); end if;
  if actor_id=w.requested_by and reason is null then return public.work_order_result_error('OVERRIDE_REASON_REQUIRED','Administrator self-approval requires an audited reason.'); end if;
  update public.work_orders set status='approved',approved_at=pg_catalog.now(),updated_at=pg_catalog.now() where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_approve','submitted','approved',actor_name,
    pg_catalog.jsonb_build_object('decision','approved_to_proceed','proposed_cost',cost,'required_authority',readiness->>'required_authority',
      'reason',reason,'administrator_override',actor_id=w.requested_by and role='administrator')::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'approval_readiness',readiness);
exception when invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Approval data is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Work Order approval failed.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.technician_facility_read_permitted(p_facility_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='technician'
    and exists (
      select 1
      from public.facility_memberships fm
      join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid()
        and fm.facility_id=p_facility_id
        and fm.membership_role='technician'
        and fm.active
        and fm.effective_from <= pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to > pg_catalog.now())
        and s.is_active
    )
$function$
;
CREATE OR REPLACE FUNCTION public.resolve_facility_for_write(p_actor_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  resolved uuid;
begin
  select pg_catalog.min(fm.facility_id::text)::uuid into resolved
  from public.facility_memberships fm
  join public.sites s on s.id=fm.facility_id and s.is_active
  where fm.profile_id=p_actor_id and fm.active
    and fm.effective_from <= pg_catalog.now()
    and (fm.effective_to is null or fm.effective_to > pg_catalog.now())
  having pg_catalog.count(distinct fm.facility_id)=1;

  if resolved is null then
    select pg_catalog.min(s.id::text)::uuid into resolved
    from public.sites s where s.is_active
    having pg_catalog.count(*)=1;
  end if;
  return resolved;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_work_order_facility()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare linked_asset_facility uuid; linked_area_facility uuid;
begin
  if new.asset_id is not null then
    select a.facility_id into linked_asset_facility from public.assets a where a.id=new.asset_id;
  end if;
  if new.facility_area_id is not null then
    select a.facility_id into linked_area_facility from public.facility_areas a where a.id=new.facility_area_id;
  end if;
  new.facility_id:=coalesce(new.facility_id,linked_asset_facility,linked_area_facility,public.resolve_facility_for_write(auth.uid()));
  if new.facility_id is null then raise exception using errcode='23514',message='FACILITY_REQUIRED'; end if;
  if not exists(select 1 from public.sites s where s.id=new.facility_id and s.is_active) then
    raise exception using errcode='23514',message='FACILITY_INVALID';
  end if;
  if linked_asset_facility is not null and linked_asset_facility<>new.facility_id then
    raise exception using errcode='23514',message='FACILITY_ASSET_MISMATCH';
  end if;
  if linked_area_facility is not null and linked_area_facility<>new.facility_id then
    raise exception using errcode='23514',message='FACILITY_AREA_MISMATCH';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_asset_facility()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.facility_id:=coalesce(new.facility_id,public.resolve_facility_for_write(auth.uid()));
  if new.facility_id is null then raise exception using errcode='23514',message='FACILITY_REQUIRED'; end if;
  if not exists(select 1 from public.sites s where s.id=new.facility_id and s.is_active) then
    raise exception using errcode='23514',message='FACILITY_INVALID';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.assign_facility_area_facility()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  new.facility_id:=coalesce(new.facility_id,public.resolve_facility_for_write(auth.uid()));
  if new.facility_id is null then raise exception using errcode='23514',message='FACILITY_REQUIRED'; end if;
  if not exists(select 1 from public.sites s where s.id=new.facility_id and s.is_active) then
    raise exception using errcode='23514',message='FACILITY_INVALID';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.facility_manager_facility_permitted(p_facility_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='facility_manager'
    and exists (
      select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid() and fm.facility_id=p_facility_id
        and fm.membership_role='facility_manager' and fm.active
        and fm.effective_from<=pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
        and s.is_active
    )
$function$
;
CREATE OR REPLACE FUNCTION public.supervisor_facility_permitted(p_facility_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select public.pilot_account_ready(auth.uid())
    and public.current_user_role()='supervisor'
    and exists (
      select 1 from public.facility_memberships fm join public.sites s on s.id=fm.facility_id
      where fm.profile_id=auth.uid() and fm.facility_id=p_facility_id
        and fm.membership_role='supervisor' and fm.active
        and fm.effective_from<=pg_catalog.now()
        and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
        and s.is_active
    )
$function$
;
CREATE OR REPLACE FUNCTION public.set_work_order_approval_basis(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; actor_role text; actor_name text; w public.work_orders%rowtype;
  proposed numeric; cost_basis text; arrangement text; safety text; board_ref text; board_date date; board_document text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_role:=actor->>'role'; actor_name:=coalesce(actor->>'name','Unknown user');
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('draft','submitted') then return public.work_order_result_error('INVALID_TRANSITION','Approval basis may be changed only before approval.'); end if;
  if actor_role='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if actor_role='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor_role<>'administrator' and not (actor_id=w.requested_by and actor_role in ('reviewer','initiator','approver','supervisor','facility_manager'))
    and actor_role not in ('supervisor','facility_manager') then return public.work_order_result_error('ACCESS_DENIED','You cannot prepare this approval basis.'); end if;
  begin proposed:=(p_payload->>'proposed_cost')::numeric; exception when others then proposed:=null; end;
  cost_basis:=nullif(pg_catalog.btrim(coalesce(p_payload->>'cost_basis','')),'');
  arrangement:=nullif(pg_catalog.btrim(coalesce(p_payload->>'execution_arrangement','')),'');
  safety:=nullif(pg_catalog.btrim(coalesce(p_payload->>'safety_isolation_information','')),'');
  board_ref:=nullif(pg_catalog.btrim(coalesce(p_payload->>'board_approval_reference','')),'');
  board_document:=nullif(pg_catalog.btrim(coalesce(p_payload->>'board_supporting_document_reference','')),'');
  begin board_date:=nullif(p_payload->>'board_approval_date','')::date; exception when others then board_date:=null; end;
  if proposed is null or proposed<0 or cost_basis is null or arrangement is null or safety is null then
    return public.work_order_result_error('VALIDATION_ERROR','Structured proposed cost, cost basis, execution arrangement and safety/isolation information are required.');
  end if;
  if proposed>1000000 and (board_ref is null or board_date is null or board_document is null) then
    return public.work_order_result_error('BOARD_APPROVAL_REQUIRED','Board approval reference, date and supporting document reference are required above S$1,000,000.');
  end if;
  if exists(select 1 from public.work_order_cost_lines c where c.work_order_id=w.id and (c.technician_certified_at is not null or c.approved_at is not null)) then
    return public.work_order_result_error('COST_BASIS_LOCKED','Certified or approved cost lines cannot be replaced through pre-work approval preparation.');
  end if;
  delete from public.work_order_cost_lines c where c.work_order_id=w.id;
  insert into public.work_order_cost_lines(work_order_id,cost_type,description,quantity,unit,unit_rate,entered_by)
  values(w.id,'service','Pre-work proposed cost',1,'lump_sum',proposed,actor_id);
  insert into public.work_order_approval_basis(work_order_id,cost_basis,execution_arrangement,safety_isolation_information,
    board_approval_reference,board_approval_date,board_supporting_document_reference,updated_by)
  values(w.id,cost_basis,arrangement,safety,board_ref,board_date,board_document,actor_id)
  on conflict(work_order_id) do update set cost_basis=excluded.cost_basis,execution_arrangement=excluded.execution_arrangement,
    safety_isolation_information=excluded.safety_isolation_information,board_approval_reference=excluded.board_approval_reference,
    board_approval_date=excluded.board_approval_date,board_supporting_document_reference=excluded.board_supporting_document_reference,
    updated_by=excluded.updated_by,updated_at=pg_catalog.now();
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_approval_basis_recorded',w.status,w.status,actor_name,
    pg_catalog.jsonb_build_object('proposed_cost',proposed,'board_approval_recorded',proposed>1000000,'status_unchanged',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'data',public.work_order_approval_readiness(w.id));
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Approval basis is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Approval basis could not be saved.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_approval_readiness(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; basis public.work_order_approval_basis%rowtype;
  proposed numeric; line_count integer; missing jsonb:='[]'::jsonb; authority text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if not (public.current_user_role() in ('approver','administrator')
    or public.supervisor_facility_permitted(w.facility_id)
    or public.facility_manager_facility_permitted(w.facility_id)
    or w.requested_by=auth.uid() or w.assigned_technician_id=auth.uid()
    or public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','This Work Order is outside your permitted scope.');
  end if;
  select pg_catalog.count(*),coalesce(pg_catalog.sum(c.amount),0) into line_count,proposed
  from public.work_order_cost_lines c where c.work_order_id=w.id;
  select * into basis from public.work_order_approval_basis b where b.work_order_id=w.id;
  if w.facility_id is null then missing:=missing||'"facility"'::jsonb; end if;
  if w.asset_id is null and w.facility_area_id is null and nullif(pg_catalog.btrim(coalesce(w.location,'')),'') is null then missing:=missing||'"asset_or_location"'::jsonb; end if;
  if nullif(pg_catalog.btrim(coalesce(w.description,'')),'') is null then missing:=missing||'"requested_work_scope"'::jsonb; end if;
  if w.priority is null then missing:=missing||'"priority_operational_risk"'::jsonb; end if;
  if line_count=0 then missing:=missing||'"structured_proposed_cost"'::jsonb; end if;
  if basis.work_order_id is null or nullif(pg_catalog.btrim(coalesce(basis.cost_basis,'')),'') is null then missing:=missing||'"cost_basis"'::jsonb; end if;
  if basis.work_order_id is null or nullif(pg_catalog.btrim(coalesce(basis.execution_arrangement,'')),'') is null then missing:=missing||'"execution_arrangement"'::jsonb; end if;
  if basis.work_order_id is null or nullif(pg_catalog.btrim(coalesce(basis.safety_isolation_information,'')),'') is null then missing:=missing||'"safety_isolation_information"'::jsonb; end if;
  authority:=case when proposed<=250000 then 'supervisor' when proposed<=500000 then 'facility_manager'
    when proposed<=1000000 then 'administrator' else 'company_board_then_administrator_release' end;
  if proposed>1000000 and (basis.board_approval_reference is null or basis.board_approval_date is null or basis.board_supporting_document_reference is null) then
    missing:=missing||'"board_approval_reference_date_and_supporting_document"'::jsonb;
  end if;
  return pg_catalog.jsonb_build_object('ok',true,'ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'required_authority',authority,'proposed_cost',proposed,
    'approval_reason',case when pg_catalog.jsonb_array_length(missing)=0 then 'Structured pre-work approval basis is complete.' end,
    'blocking_reason',case when pg_catalog.jsonb_array_length(missing)>0 then 'Required structured pre-work approval information is incomplete.' end);
end;$function$
;
CREATE OR REPLACE FUNCTION public.accept_work_responsibility(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  w public.work_orders%rowtype;
  result public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  actor_name:=coalesce(actor->>'display_name',actor->>'name','Unknown user');
  actor_role:=actor->>'role';
  if actor_role not in ('technician','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Field execution authority is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('approved','assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Responsibility may be accepted only for approved or active work.'); end if;
  if not public.field_work_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Active facility authority is required for this work order.'); end if;
  if w.assigned_technician_id is not null and w.assigned_technician_id<>actor_id then return public.work_order_result_error('ASSIGNMENT_CONFLICT','Another field-responsible person already owns this work order.'); end if;
  if w.assigned_technician_id=actor_id then return pg_catalog.jsonb_build_object('ok',true,'code','NO_CHANGE','work_order',pg_catalog.to_jsonb(w)); end if;

  update public.work_orders
  set assigned_technician_id=actor_id,
      assigned_to=actor_name,
      assigned_at=coalesce(assigned_at,pg_catalog.now()),
      accepted_at=pg_catalog.now(),
      status=case when status='approved' then 'assigned' else status end,
      updated_at=pg_catalog.now()
  where id=w.id
  returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_responsibility_accepted',w.status,result.status,actor_name,
    pg_catalog.jsonb_build_object(
      'responsible_field_profile_id',actor_id,
      'responsible_field_role',actor_role,
      'facility_id',w.facility_id,
      'assigned_vendor_id',w.assigned_vendor_id,
      'accepted_at',pg_catalog.now()
    )::text);

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result));
exception
  when check_violation or foreign_key_violation then return public.work_order_result_error('VALIDATION_ERROR','Responsibility could not be accepted.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Responsibility acceptance failed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.submit_physical_completion_20260921_core(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; w public.work_orders%rowtype; result public.work_orders%rowtype;
  statement text; hours numeric; evidence_ids jsonb; cycle integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  if actor->>'role'<>'technician' then return public.work_order_result_error('ACCESS_DENIED','Assigned Technician authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Only active assigned work may be submitted as physically complete.'); end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility assigned Technician responsibility is required.');
  end if;
  statement:=nullif(pg_catalog.btrim(coalesce(p_payload->>'completion_notes',w.completion_notes,'')),'');
  begin hours:=coalesce(nullif(p_payload->>'actual_labour_hours','')::numeric,w.actual_labour_hours); exception when others then hours:=null; end;
  if statement is null then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED','A work-performed statement is required.'); end if;
  if hours is null or hours<0 then return public.work_order_result_error('COMPLETION_DETAILS_REQUIRED','Cumulative non-negative labour hours are required.'); end if;
  if w.actual_labour_hours is not null and hours<w.actual_labour_hours then return public.work_order_result_error('CUMULATIVE_LABOUR_REQUIRED','Cumulative labour hours cannot decrease.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_costs_confirmed_by<>actor_id then
    return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Confirm that actual costing is complete, including a genuine zero-cost outcome, before physical completion.');
  end if;
  select coalesce(pg_catalog.jsonb_agg(e.id order by e.uploaded_at,e.id),'[]'::jsonb) into evidence_ids
  from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null;
  if pg_catalog.jsonb_array_length(evidence_ids)=0 then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','At least one active After evidence item is required.'); end if;
  select pg_catalog.count(*)+1 into cycle from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_returned_for_rework';
  update public.work_orders set status='completed',completion_notes=statement,actual_labour_hours=hours,
    started_at=coalesce(started_at,pg_catalog.now()),completed_at=pg_catalog.now(),updated_at=pg_catalog.now()
  where id=w.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_complete',w.status,'completed',actor_name,
    pg_catalog.jsonb_build_object('cycle',cycle,'completion_notes',statement,'cumulative_labour_hours',hours,
      'completed_at',result.completed_at,'evidence_ids',evidence_ids,'submitted_by',actor_id,'submitted_at',pg_catalog.now(),
      'actual_costs_confirmed_at',w.actual_costs_confirmed_at,'submission_type','technician_physical_completion')::text);
  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle);
exception when check_violation or invalid_text_representation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Physical completion data is invalid.');
when others then return public.work_order_result_error('INTERNAL_ERROR','Physical completion submission failed.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_verification_readiness(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; event_id uuid; event_actor uuid; missing jsonb:='[]'::jsonb; same_actor boolean;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role' not in ('supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Completed Work verification authority is required.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Supervisor membership is required.');
  end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility Facility Manager membership is required.');
  end if;
  if w.status<>'completed' then missing:=missing||'"completed_awaiting_verification_status"'::jsonb; end if;
  select l.id,l.user_id into event_id,event_actor from public.activity_logs l where l.work_order_id=w.id and l.action='work_order_complete' order by l.created_at desc,l.id desc limit 1;
  if event_id is null then missing:=missing||'"authoritative_completion_submission_event"'::jsonb; end if;
  same_actor:=event_actor=(actor->>'id')::uuid;
  if same_actor and actor->>'role'<>'administrator' then missing:=missing||'"independent_authorised_verifier"'::jsonb; end if;
  return pg_catalog.jsonb_build_object('ok',true,'verification_ready',pg_catalog.jsonb_array_length(missing)=0,
    'missing_requirements',missing,'completion_event_found',event_id is not null,'completion_event_id',event_id,
    'legacy_completion_record',w.status='completed' and event_id is null,
    'self_verification_reason_required',same_actor and actor->>'role'='administrator');
end;$function$
;
CREATE OR REPLACE FUNCTION public.verify_completed_work(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  actor_id uuid;
  actor_name text;
  actor_role text;
  previous public.work_orders%rowtype;
  result public.work_orders%rowtype;
  reason text := nullif(pg_catalog.btrim(coalesce(p_payload ->> 'reason', p_payload ->> 'note', '')), '');
  completion_activity_id uuid;
  completion_actor_id uuid;
  cycle_number integer;
  actual_total numeric(14,2);
  administrator_self_verification boolean := false;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;

  actor_id := (actor ->> 'id')::uuid;
  actor_name := coalesce(actor ->> 'name', actor ->> 'display_name', 'Unknown user');
  actor_role := actor ->> 'role';

  select * into previous from public.work_orders where id = p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND', 'Work order not found.'); end if;
  if previous.status = 'reviewed' then
    return pg_catalog.jsonb_build_object('ok', true, 'code', 'NO_CHANGE', 'work_order', pg_catalog.to_jsonb(previous));
  end if;
  if previous.status <> 'completed' then
    return public.work_order_result_error('INVALID_TRANSITION', 'Only Completed Work awaiting verification can be verified.');
  end if;
  if actor_role not in ('supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Supervisor, Facility Manager or Administrator authority is required.');
  end if;

  select l.id, l.user_id into completion_activity_id, completion_actor_id
  from public.activity_logs l
  where l.work_order_id = previous.id and l.action = 'work_order_complete'
  order by l.created_at desc, l.id desc limit 1;
  if completion_activity_id is null then
    return public.work_order_result_error('COMPLETION_AUDIT_REQUIRED', 'The latest Completed Work audit record could not be found.');
  end if;

  if actor_id = completion_actor_id then
    if actor_role <> 'administrator' then
      return public.work_order_result_error('SELF_REVIEW_DENIED', 'Technician, Supervisor and Facility Manager Completed Work must be verified by another authorised person.');
    end if;
    if reason is null then
      return public.work_order_result_error('OVERRIDE_REASON_REQUIRED', 'Administrator self-verification requires an override reason.');
    end if;
    administrator_self_verification := true;
  end if;

  select count(*) + 1 into cycle_number from public.activity_logs l
  where l.work_order_id = previous.id and l.action = 'work_order_returned_for_rework';

  update public.work_orders set status='reviewed', reviewed_at=pg_catalog.now(), updated_at=pg_catalog.now()
  where id=previous.id returning * into result;

  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,result.id,'work_order_review','completed','reviewed',actor_name,
    pg_catalog.jsonb_build_object('cycle',cycle_number,'decision','verified','reason',reason,
      'completion_activity_id',completion_activity_id,'independent_review',not administrator_self_verification,
      'administrator_self_verification',administrator_self_verification,'verified_by',actor_id,
      'verified_at',pg_catalog.now())::text);

  if result.assigned_technician_id is not null then
    insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
    select result.id,'work_order_completion_accepted','work_order:'||result.id::text||':completion:'||cycle_number::text||':accepted',
      p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',result.id,'cycle',cycle_number,'status','queued'),'pending'
    from public.profiles p
    where p.id=result.assigned_technician_id and p.is_active and p.deleted_at is null
    on conflict do nothing;
  end if;

  if result.assigned_vendor_id is not null then
    select coalesce(pg_catalog.sum(c.amount),0) into actual_total
    from public.work_order_cost_lines c
    where c.work_order_id=result.id and c.cost_phase='actual';

    insert into public.contractor_payment_assessments(
      work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,payment_term_started_at,payment_due_at
    ) values(result.id,result.assigned_vendor_id,'draft',actual_total,result.reviewed_at,result.reviewed_at,result.reviewed_at+interval '30 days')
    on conflict(work_order_id) do update set
      vendor_id=excluded.vendor_id,status='draft',assessed_amount=excluded.assessed_amount,
      completed_work_accepted_at=excluded.completed_work_accepted_at,
      payment_term_started_at=excluded.payment_term_started_at,payment_due_at=excluded.payment_due_at,
      recommended_by=null,recommended_at=null,approved_by=null,approved_at=null,approval_note=null,
      completion_notified_at=null,paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,
      updated_at=pg_catalog.now();
  end if;

  return pg_catalog.jsonb_build_object('ok',true,'work_order',pg_catalog.to_jsonb(result),'cycle',cycle_number,
    'administrator_self_verification',administrator_self_verification,'notification_status','queued');
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    return public.work_order_result_error('VALIDATION_ERROR', 'Completed Work verification data is invalid.');
  when others then
    return public.work_order_result_error('INTERNAL_ERROR', 'Completed Work verification failed.');
end;
$function$
;
CREATE OR REPLACE FUNCTION public.field_work_facility_permitted(p_facility_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
  select public.pilot_account_ready(auth.uid())
    and exists (
      select 1 from public.sites s where s.id=p_facility_id and s.is_active
    )
    and (
      public.current_user_role()='administrator'
      or exists (
        select 1
        from public.facility_memberships fm
        where fm.profile_id=auth.uid()
          and fm.facility_id=p_facility_id
          and fm.membership_role=public.current_user_role()
          and fm.membership_role in ('technician','supervisor','facility_manager')
          and fm.active
          and fm.effective_from<=pg_catalog.now()
          and (fm.effective_to is null or fm.effective_to>pg_catalog.now())
      )
    )
$function$
;
CREATE OR REPLACE FUNCTION public.record_contractor_quotation(p_work_order_id uuid, p_quotation_ref text, p_quotation_date date, p_lines jsonb, p_source_filename text DEFAULT NULL::text, p_source_sha256 text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  line jsonb; item public.contractor_rate_items%rowtype; qty numeric; quoted numeric; agreed numeric; line_number integer:=0; total numeric:=0; next_version integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor before recording a quotation.'); end if;
  if w.status not in ('draft','submitted','approved','assigned','in_progress') then return public.work_order_result_error('QUOTATION_READ_ONLY','Quotations are read-only outside planning and active execution.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress') or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may record this quotation.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Quotation recording authority is required.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_quotation_ref,'')),'') is null or p_quotation_date is null or p_lines is null or pg_catalog.jsonb_typeof(p_lines)<>'array' or pg_catalog.jsonb_array_length(p_lines)=0 then return public.work_order_result_error('VALIDATION_ERROR','Quotation reference, date and at least one line are required.'); end if;
  select coalesce(pg_catalog.max(version_no),0)+1 into next_version from public.contractor_quotations where work_order_id=w.id and quotation_ref=pg_catalog.btrim(p_quotation_ref);
  update public.contractor_quotations set status='superseded',updated_at=pg_catalog.now() where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status='submitted';
  insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,source_filename,source_sha256,submitted_by)
  values(w.id,w.assigned_vendor_id,pg_catalog.btrim(p_quotation_ref),p_quotation_date,next_version,'submitted','SGD',nullif(pg_catalog.btrim(coalesce(p_source_filename,'')),''),nullif(pg_catalog.btrim(coalesce(p_source_sha256,'')),''),actor_id) returning * into q;
  for line in select value from pg_catalog.jsonb_array_elements(p_lines) loop
    line_number:=line_number+1;
    begin qty:=(line->>'quantity')::numeric; quoted:=(line->>'quoted_unit_rate')::numeric; exception when others then qty:=null; quoted:=null; end;
    select * into item from public.contractor_rate_items where id=(line->>'rate_item_id')::uuid and vendor_id=w.assigned_vendor_id and active and effective_from<=p_quotation_date and (effective_to is null or effective_to>=p_quotation_date);
    if item.id is null or qty is null or qty<=0 or quoted is null or quoted<0 then raise exception using errcode='22023',message='Quotation line is invalid.'; end if;
    agreed:=case when w.emergency_work and item.emergency_unit_rate is not null then item.emergency_unit_rate else item.normal_unit_rate end;
    if quoted<>agreed and nullif(pg_catalog.btrim(coalesce(line->>'exception_reason','')),'') is null then raise exception using errcode='22023',message='A rate exception reason is required.'; end if;
    insert into public.contractor_quotation_lines(quotation_id,line_no,rate_item_id,cost_type,item_code,description,unit,quantity,agreed_unit_rate,quoted_unit_rate,rate_exception,exception_reason,worker_name,remarks)
    values(q.id,line_number,item.id,item.cost_type,item.item_code,item.description,item.unit,qty,agreed,quoted,quoted<>agreed,case when quoted<>agreed then pg_catalog.btrim(line->>'exception_reason') end,nullif(pg_catalog.btrim(coalesce(line->>'worker_name','')),''),nullif(pg_catalog.btrim(coalesce(line->>'remarks','')),''));
    total:=total+pg_catalog.round(qty*quoted,2);
  end loop;
  update public.contractor_quotations set total_amount=total,updated_at=pg_catalog.now() where id=q.id returning * into q;
  update public.work_order_financial_controls set quoted_cost=total,cost_status='quotation_recorded',recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_quotation_recorded',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'quotation_ref',q.quotation_ref,'total_amount',total,'recorded_by_role',actor->>'role')::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'line_count',line_number);
exception when invalid_text_representation or check_violation or foreign_key_violation or numeric_value_out_of_range or sqlstate '22023' then return public.work_order_result_error('VALIDATION_ERROR',sqlerrm); when unique_violation then return public.work_order_result_error('DUPLICATE_QUOTATION','That quotation version already exists.'); when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor quotation could not be recorded.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_contractor_quotations(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); facility uuid; result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select facility_id into facility from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if not public.field_work_facility_permitted(facility) and actor->>'role' not in ('approver','administrator') then return public.work_order_result_error('ACCESS_DENIED','Work Order quotation access is denied.'); end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id',q.id,'quotation_ref',q.quotation_ref,'quotation_date',q.quotation_date,'version_no',q.version_no,'status',q.status,'currency',q.currency,'total_amount',q.total_amount,'vendor_id',q.vendor_id,'source_filename',q.source_filename,'prepared_by',q.prepared_by,'prepared_at',q.prepared_at,'draft_saved_at',q.draft_saved_at,'scope_summary',q.scope_summary,'contractor_legal_name',q.contractor_legal_name,'gst_treatment',q.gst_treatment,'itemization_note',q.itemization_note,'submitted_by',q.submitted_by,'submitted_at',q.submitted_at,'approved_by',q.approved_by,'approved_at',q.approved_at,'approval_note',q.approval_note,'lines',(select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(l)-'quotation_id' order by l.line_no),'[]'::jsonb) from public.contractor_quotation_lines l where l.quotation_id=q.id)) order by q.created_at desc,q.version_no desc),'[]'::jsonb) into result from public.contractor_quotations q where q.work_order_id=p_work_order_id;
  return pg_catalog.jsonb_build_object('ok',true,'quotations',result);
end;$function$
;
CREATE OR REPLACE FUNCTION public.preview_contractor_actual_import(p_work_order_id uuid, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; line jsonb; item public.contractor_rate_items%rowtype; qty numeric; agreed numeric; actual numeric; line_date date; exception_reason text; is_exception boolean; normalized jsonb:='[]'::jsonb; total numeric:=0; exceptions integer:=0; line_no integer:=0; q public.contractor_quotations%rowtype; quoted_total numeric:=0;
begin
if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
actor_id:=(actor->>'id')::uuid;
select * into w from public.work_orders where id=p_work_order_id;
if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor before importing contractor actuals.'); end if;
if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Contractor actuals may be imported only while field work is active.'); end if;
if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id or not public.field_work_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','The responsible same-facility field actor is required to import contractor actuals.'); end if;
if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then return public.work_order_result_error('VALIDATION_ERROR','At least one actual-cost row is required.'); end if;
select * into q from public.contractor_quotations where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status in ('approved','submitted') order by case when status='approved' then 0 else 1 end, quotation_date desc, version_no desc limit 1;
if found then quoted_total:=q.total_amount; end if;
for line in select value from jsonb_array_elements(p_lines) loop
line_no:=line_no+1;
begin qty:=(line->>'quantity')::numeric; exception when others then qty:=null; end;
if qty is null or qty<=0 then raise exception using errcode='22023',message='Actual quantity/hours must be greater than zero.'; end if;
begin line_date:=coalesce(nullif(line->>'work_date','')::date,current_date); exception when others then line_date:=null; end;
if line_date is null then raise exception using errcode='22023',message='Work date is invalid.'; end if;
select * into item from public.contractor_rate_items where id=(line->>'rate_item_id')::uuid and vendor_id=w.assigned_vendor_id and active and effective_from<=line_date and (effective_to is null or effective_to>=line_date);
if not found then raise exception using errcode='22023',message='Actual-cost row does not match an effective agreed contractor rate item.'; end if;
agreed:=case when w.emergency_work and item.emergency_unit_rate is not null then item.emergency_unit_rate else item.normal_unit_rate end;
begin actual:=coalesce(nullif(line->>'actual_unit_rate','')::numeric,agreed); exception when others then actual:=null; end;
if actual is null or actual<0 then raise exception using errcode='22023',message='Actual unit rate is invalid.'; end if;
is_exception:=actual<>agreed; exception_reason:=nullif(btrim(coalesce(line->>'exception_reason','')),'');
if is_exception and exception_reason is null then raise exception using errcode='22023',message='A rate exception reason is required when actual rate differs from agreed rate.'; end if;
if item.cost_type='labour' and nullif(btrim(coalesce(line->>'worker_name','')),'') is null then raise exception using errcode='22023',message='Personnel name is required for labour rows.'; end if;
normalized:=normalized||jsonb_build_array(jsonb_build_object('line_no',line_no,'rate_item_id',item.id,'cost_type',item.cost_type,'item_code',item.item_code,'description',item.description,'unit',item.unit,'worker_name',nullif(btrim(coalesce(line->>'worker_name','')),''),'worker_id',nullif(btrim(coalesce(line->>'worker_id','')),''),'work_date',line_date,'quantity',qty,'agreed_unit_rate',agreed,'actual_unit_rate',actual,'amount',round(qty*actual,2),'rate_exception',is_exception,'exception_reason',case when is_exception then exception_reason end,'remarks',nullif(btrim(coalesce(line->>'remarks','')),'')));
total:=total+round(qty*actual,2); if is_exception then exceptions:=exceptions+1; end if;
end loop;
return jsonb_build_object('ok',true,'work_order_id',w.id,'vendor_id',w.assigned_vendor_id,'quotation_id',case when q.id is null then null else q.id end,'quotation_status',case when q.id is null then null else q.status end,'quoted_total',quoted_total,'actual_total',total,'variance_amount',round(total-quoted_total,2),'variance_percent',case when quoted_total=0 then null else round(((total-quoted_total)/quoted_total)*100,2) end,'exception_count',exceptions,'lines',normalized);
exception when invalid_text_representation or check_violation or numeric_value_out_of_range or sqlstate '22023' then return public.work_order_result_error('VALIDATION_ERROR',sqlerrm); when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor actual-cost preview failed.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.confirm_contractor_actual_import(p_work_order_id uuid, p_import_kind text, p_source_filename text, p_source_sha256 text, p_lines jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; preview jsonb; w public.work_orders%rowtype; imp public.contractor_actual_imports%rowtype; line jsonb; line_count integer:=0;
begin
if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'display_name',actor->>'name','Recorded user');
if p_import_kind not in ('personnel','materials','equipment_services','mixed') then return public.work_order_result_error('VALIDATION_ERROR','Actual-cost import kind is invalid.'); end if;
if nullif(btrim(coalesce(p_source_filename,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','Source CSV filename is required.'); end if;
select * into w from public.work_orders where id=p_work_order_id for update; if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
preview:=public.preview_contractor_actual_import(p_work_order_id,p_lines); if not coalesce((preview->>'ok')::boolean,false) then return preview; end if;
insert into public.contractor_actual_imports(work_order_id,vendor_id,quotation_id,source_filename,source_sha256,import_kind,currency,total_amount,exception_count,confirmed_by) values(w.id,w.assigned_vendor_id,nullif(preview->>'quotation_id','')::uuid,btrim(p_source_filename),nullif(btrim(coalesce(p_source_sha256,'')),''),p_import_kind,'SGD',(preview->>'actual_total')::numeric,(preview->>'exception_count')::integer,actor_id) returning * into imp;
for line in select value from jsonb_array_elements(preview->'lines') loop line_count:=line_count+1; insert into public.contractor_actual_import_lines(import_id,line_no,rate_item_id,cost_type,item_code,description,unit,worker_name,worker_id,work_date,quantity,agreed_unit_rate,actual_unit_rate,rate_exception,exception_reason,remarks) values(imp.id,(line->>'line_no')::integer,(line->>'rate_item_id')::uuid,line->>'cost_type',line->>'item_code',line->>'description',line->>'unit',line->>'worker_name',line->>'worker_id',(line->>'work_date')::date,(line->>'quantity')::numeric,(line->>'agreed_unit_rate')::numeric,(line->>'actual_unit_rate')::numeric,(line->>'rate_exception')::boolean,line->>'exception_reason',line->>'remarks'); end loop;
insert into public.activity_logs(user_id,work_order_id,action,actor,note) values(actor_id,w.id,'contractor_actual_cost_import_confirmed',actor_name,jsonb_build_object('import_id',imp.id,'import_kind',imp.import_kind,'source_filename',imp.source_filename,'total_amount',imp.total_amount,'exception_count',imp.exception_count,'line_count',line_count,'quotation_id',imp.quotation_id,'variance_amount',preview->'variance_amount','variance_percent',preview->'variance_percent')::text);
return jsonb_build_object('ok',true,'import',to_jsonb(imp),'line_count',line_count,'quoted_total',preview->'quoted_total','actual_total',preview->'actual_total','variance_amount',preview->'variance_amount','variance_percent',preview->'variance_percent');
exception when unique_violation then return public.work_order_result_error('DUPLICATE_IMPORT','This CSV file has already been confirmed for the Work Order.'); when invalid_text_representation or check_violation or foreign_key_violation or numeric_value_out_of_range then return public.work_order_result_error('VALIDATION_ERROR','Contractor actual-cost import is invalid.'); when others then return public.work_order_result_error('INTERNAL_ERROR','Contractor actual-cost import could not be confirmed.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_contractor_cost_variance(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; q public.contractor_quotations%rowtype; actual numeric:=0; exceptions integer:=0;
begin
if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; select * into w from public.work_orders where id=p_work_order_id; if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
if not public.field_work_facility_permitted(w.facility_id) and actor->>'role' not in ('approver','administrator') then return public.work_order_result_error('ACCESS_DENIED','Work order contractor-cost access is denied.'); end if;
select * into q from public.contractor_quotations where work_order_id=w.id and vendor_id=w.assigned_vendor_id and status in ('approved','submitted') order by case when status='approved' then 0 else 1 end,quotation_date desc,version_no desc limit 1;
select coalesce(sum(total_amount),0),coalesce(sum(exception_count),0) into actual,exceptions from public.contractor_actual_imports where work_order_id=w.id and vendor_id=w.assigned_vendor_id;
return jsonb_build_object('ok',true,'work_order_id',w.id,'vendor_id',w.assigned_vendor_id,'quotation_id',case when q.id is null then null else q.id end,'quotation_status',case when q.id is null then null else q.status end,'quoted_total',coalesce(q.total_amount,0),'actual_total',actual,'variance_amount',round(actual-coalesce(q.total_amount,0),2),'variance_percent',case when coalesce(q.total_amount,0)=0 then null else round(((actual-q.total_amount)/q.total_amount)*100,2) end,'exception_count',exceptions); end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_contractor_rate_items(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result jsonb;
begin
if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
select * into w from public.work_orders where id=p_work_order_id;
if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','Assign a contractor first.'); end if;
if not public.field_work_facility_permitted(w.facility_id) and actor->>'role' not in ('approver','administrator') then return public.work_order_result_error('ACCESS_DENIED','Contractor rate access is denied.'); end if;
select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'item_code',r.item_code,'cost_type',r.cost_type,'description',r.description,'unit',r.unit,'normal_unit_rate',r.normal_unit_rate,'emergency_unit_rate',r.emergency_unit_rate,'currency',r.currency,'effective_from',r.effective_from,'effective_to',r.effective_to) order by r.cost_type,r.item_code,r.description),'[]'::jsonb) into result from public.contractor_rate_items r where r.vendor_id=w.assigned_vendor_id and r.active and r.effective_from<=current_date and (r.effective_to is null or r.effective_to>=current_date);
return jsonb_build_object('ok',true,'vendor_id',w.assigned_vendor_id,'rates',result);
end;$function$
;
CREATE OR REPLACE FUNCTION public.manage_work_order_actual_cost(p_work_order_id uuid, p_cost_line_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb:=public.work_order_actor(); actor_id uuid; actor_name text; w public.work_orders%rowtype;
  operation text:=pg_catalog.lower(coalesce(p_payload->>'operation','upsert'));
  kind text; detail text; measure text; worker text; quantity_value numeric; rate_value numeric;
  existing public.work_order_cost_lines%rowtype; result public.work_order_cost_lines%rowtype;
  previous_value jsonb; actual_count bigint; actual_total numeric;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; actor_name:=coalesce(actor->>'name','Unknown user');
  if actor->>'role'<>'technician' then return public.work_order_result_error('ACCESS_DENIED','Assigned Technician authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('ACTUAL_COST_READ_ONLY','Actual execution costs are read-only outside active assigned work.'); end if;
  if w.assigned_technician_id is null or w.assigned_technician_id<>actor_id
    or not public.technician_facility_read_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED','Active same-facility assigned Technician responsibility is required.');
  end if;

  if operation='confirm' then
    if p_cost_line_id is not null then return public.work_order_result_error('VALIDATION_ERROR','Cost-line identity is not accepted when confirming actual costing.'); end if;
    update public.work_orders set actual_costs_confirmed_at=pg_catalog.now(),actual_costs_confirmed_by=actor_id,updated_at=pg_catalog.now()
      where id=w.id;
    select pg_catalog.count(*),coalesce(pg_catalog.sum(c.amount),0) into actual_count,actual_total
      from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
    insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
    values(actor_id,w.id,'work_order_actual_costing_confirmed',w.status,w.status,actor_name,
      pg_catalog.jsonb_build_object('facility_id',w.facility_id,'actual_line_count',actual_count,'actual_total',actual_total,
        'confirmed_at',pg_catalog.now())::text);
    return pg_catalog.jsonb_build_object('ok',true,'confirmed',true,'actual_line_count',actual_count,'actual_total',actual_total);
  end if;
  if operation<>'upsert' then return public.work_order_result_error('VALIDATION_ERROR','Actual-cost operation is invalid.'); end if;

  kind:=pg_catalog.lower(coalesce(p_payload->>'cost_type',''));
  detail:=nullif(pg_catalog.btrim(coalesce(p_payload->>'description','')),'');
  measure:=nullif(pg_catalog.btrim(coalesce(p_payload->>'unit','')),'');
  worker:=nullif(pg_catalog.btrim(coalesce(p_payload->>'worker_name','')),'');
  begin quantity_value:=(p_payload->>'quantity')::numeric; exception when others then quantity_value:=null; end;
  begin rate_value:=(p_payload->>'unit_rate')::numeric; exception when others then rate_value:=null; end;
  if kind not in ('labour','material','equipment','service','callout') or detail is null or measure is null
    or quantity_value is null or quantity_value<0 or rate_value is null or rate_value<0 then
    return public.work_order_result_error('VALIDATION_ERROR','Cost type, description, non-negative quantity, unit and non-negative unit rate are required.');
  end if;
  if pg_catalog.length(detail)>1000 or pg_catalog.length(measure)>100 or pg_catalog.length(coalesce(worker,''))>200 then
    return public.work_order_result_error('VALIDATION_ERROR','Actual-cost text exceeds the permitted length.');
  end if;

  if p_cost_line_id is null then
    insert into public.work_order_cost_lines(work_order_id,vendor_id,worker_name,cost_type,description,quantity,unit,unit_rate,entered_by,cost_phase)
    values(w.id,case when kind in ('service','callout') then w.assigned_vendor_id end,worker,kind,detail,quantity_value,measure,rate_value,actor_id,'actual')
    returning * into result;
  else
    select * into existing from public.work_order_cost_lines c where c.id=p_cost_line_id and c.work_order_id=w.id for update;
    if not found then return public.work_order_result_error('NOT_FOUND','Actual cost line not found.'); end if;
    if existing.cost_phase is distinct from 'actual' then return public.work_order_result_error('PROPOSED_COST_PROTECTED','Proposed or legacy cost lines cannot be changed through actual-cost recording.'); end if;
    if existing.entered_by<>actor_id then return public.work_order_result_error('ACCESS_DENIED','A Technician may update only their own active actual-cost line.'); end if;
    if existing.technician_certified_at is not null or existing.approved_at is not null then
      return public.work_order_result_error('ACTUAL_COST_LOCKED','Certified or approved actual-cost lines are read-only.');
    end if;
    previous_value:=pg_catalog.to_jsonb(existing);
    update public.work_order_cost_lines set
      vendor_id=case when kind in ('service','callout') then w.assigned_vendor_id end,
      worker_name=worker,cost_type=kind,description=detail,quantity=quantity_value,unit=measure,unit_rate=rate_value
    where id=existing.id returning * into result;
  end if;

  update public.work_orders set actual_costs_confirmed_at=null,actual_costs_confirmed_by=null,updated_at=pg_catalog.now() where id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,case when p_cost_line_id is null then 'work_order_actual_cost_created' else 'work_order_actual_cost_updated' end,
    w.status,w.status,actor_name,pg_catalog.jsonb_build_object('facility_id',w.facility_id,'cost_line_id',result.id,
      'previous',previous_value,'new',pg_catalog.to_jsonb(result),'recorded_at',pg_catalog.now())::text);
  return pg_catalog.jsonb_build_object('ok',true,'cost_line',pg_catalog.to_jsonb(result),'actual_costing_confirmed',false);
exception
  when check_violation or foreign_key_violation or invalid_text_representation or numeric_value_out_of_range then
    return public.work_order_result_error('VALIDATION_ERROR','Actual cost data is invalid.');
  when others then return public.work_order_result_error('INTERNAL_ERROR','Actual cost could not be recorded.');
end;$function$
;
CREATE OR REPLACE FUNCTION public.record_work_order_markup(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_order_markups%rowtype;
  source_kind text:=pg_catalog.lower(coalesce(p_payload->>'source_type','drawing'));
  source_ref text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'source_reference','')),'');
  revision text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'drawing_revision','')),'');
  annotation text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'note','')),'');
  kind text:=pg_catalog.lower(coalesce(p_payload->>'annotation_type',''));
  shape jsonb:=p_payload->'geometry'; first_point jsonb; x numeric; y numeric; page integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('MARKUP_READ_ONLY','Markup is editable only during active assigned work.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may add field markup.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.'); end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  if shape is null or pg_catalog.jsonb_typeof(shape)<>'object' or pg_catalog.jsonb_typeof(shape->'points')<>'array' or pg_catalog.jsonb_array_length(shape->'points')=0 or pg_catalog.octet_length(shape::text)>20000 then return public.work_order_result_error('VALIDATION_ERROR','Markup geometry is invalid.'); end if;
  first_point:=shape->'points'->0;
  begin x:=(first_point->>'x')::numeric; y:=(first_point->>'y')::numeric; page:=nullif(p_payload->>'page_number','')::integer; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Markup coordinates or page are invalid.'); end;
  if source_kind not in ('drawing','pdf') or source_ref is null or revision is null or annotation is null or kind not in ('marker','arrow','circle','rectangle','freehand','text') or x not between 0 and 100 or y not between 0 and 100 then return public.work_order_result_error('VALIDATION_ERROR','Drawing revision, annotation, note and calibrated geometry are required.'); end if;
  insert into public.work_order_markups(work_order_id,source_type,source_reference,drawing_revision,page_number,x_percent,y_percent,annotation_type,geometry,note,created_by)
  values(w.id,source_kind,source_ref,revision,page,x,y,kind,shape,annotation,(actor->>'id')::uuid) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_recorded',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('markup_id',result.id,'drawing',source_ref,'revision',revision,'annotation_type',kind)::text);
  return pg_catalog.jsonb_build_object('ok',true,'markup',pg_catalog.to_jsonb(result));
exception when others then return public.work_order_result_error('INTERNAL_ERROR','Markup could not be recorded.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.record_work_order_procurement(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result public.work_order_procurement_commitments%rowtype;
  reference text:=nullif(btrim(coalesce(p_payload->>'purchase_reference','')),''); detail text:=nullif(btrim(coalesce(p_payload->>'description','')),''); amount numeric; state text:=lower(coalesce(p_payload->>'status','proposed'));
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role'='supervisor' and not public.supervisor_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Supervisor authority is required.'); end if;
  if actor->>'role'='facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Same-facility Facility Manager authority is required.'); end if;
  if actor->>'role' not in ('supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Procurement authority is required.'); end if;
  begin amount:=(p_payload->>'committed_amount')::numeric; exception when others then amount:=null; end;
  if reference is null or detail is null or amount is null or amount<0 or state not in ('proposed','approved','ordered','received','cancelled') then return public.work_order_result_error('VALIDATION_ERROR','Purchase reference, description, non-negative amount and valid status are required.'); end if;
  insert into public.work_order_procurement_commitments(work_order_id,vendor_id,purchase_reference,description,committed_amount,status,created_by,approved_by,approved_at)
  values(w.id,w.assigned_vendor_id,reference,detail,amount,state,(actor->>'id')::uuid,case when state in ('approved','ordered','received') then (actor->>'id')::uuid end,case when state in ('approved','ordered','received') then now() end)
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_procurement_recorded',w.status,w.status,actor->>'name',jsonb_build_object('commitment_id',result.id,'purchase_reference',reference,'committed_amount',amount,'currency','SGD','status',state)::text);
  return jsonb_build_object('ok',true,'commitment',to_jsonb(result));
exception when unique_violation then return public.work_order_result_error('VALIDATION_ERROR','Purchase reference already exists for this Work Order.'); when others then return public.work_order_result_error('INTERNAL_ERROR','Procurement commitment could not be recorded.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.delete_work_order_markup(p_work_order_id uuid, p_markup_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; m public.work_order_markups%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into m from public.work_order_markups where id=p_markup_id and work_order_id=p_work_order_id and deleted_at is null;
  if w.id is null or m.id is null then return public.work_order_result_error('NOT_FOUND','Markup not found.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('MARKUP_READ_ONLY','Markup is editable only during active assigned work.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or m.created_by is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Technicians may delete only their own active-assignment markup.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational markup authority is required.'); end if;
  update public.work_order_markups set deleted_at=pg_catalog.now(),deleted_by=(actor->>'id')::uuid where id=m.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_markup_deleted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('markup_id',m.id,'drawing',m.source_reference,'revision',m.drawing_revision)::text);
  return pg_catalog.jsonb_build_object('ok',true,'markup_id',m.id);
end;$function$
;
CREATE OR REPLACE FUNCTION public.recommend_work_order_cost(p_work_order_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; control public.work_order_financial_controls%rowtype; quote_total numeric; quote_count integer; required_count integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or w.status not in ('assigned','in_progress') or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may recommend this cost.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Cost recommendation authority is required.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  if not found then return public.work_order_result_error('FINANCIAL_CONTROL_REQUIRED','Financial control is not configured.'); end if;
  select coalesce(count(*),0),coalesce(max(total_amount),0) into quote_count,quote_total from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  if quote_count<coalesce(required_count,1) then return public.work_order_result_error('QUOTATION_COUNT_REQUIRED','The configured quotation requirement has not been met.'); end if;
  update public.work_order_financial_controls set quoted_cost=quote_total,cost_status='recommended',recommended_by=(actor->>'id')::uuid,recommended_at=pg_catalog.now(),recommendation_note=nullif(pg_catalog.btrim(p_note),''),financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id returning * into control;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values((actor->>'id')::uuid,w.id,'work_order_cost_recommended',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quoted_cost',quote_total,'quotation_count',quote_count,'required_quotations',required_count)::text);
  return pg_catalog.jsonb_build_object('ok',true,'financial',pg_catalog.to_jsonb(control),'quotation_count',quote_count,'required_quotations',required_count);
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_work_order_financial(p_work_order_id uuid, p_approved_budget numeric, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb := public.work_order_actor();
  w public.work_orders%rowtype;
  control public.work_order_financial_controls%rowtype;
begin
  if actor is null then
    return public.work_order_result_error('ACCESS_DENIED', 'An active authenticated profile is required.');
  end if;
  select * into w from public.work_orders where id = p_work_order_id;
  select * into control from public.work_order_financial_controls where work_order_id = p_work_order_id for update;
  if w.id is null or control.work_order_id is null then
    return public.work_order_result_error('NOT_FOUND', 'Financial control not found.');
  end if;
  if actor ->> 'role' = 'technician' then
    return public.work_order_result_error('SELF_APPROVAL_DENIED', 'Technicians cannot approve expenditure.');
  end if;
  if actor ->> 'role' = 'supervisor' and not public.supervisor_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Same-facility Supervisor authority is required.');
  end if;
  if actor ->> 'role' = 'facility_manager' and not public.facility_manager_facility_permitted(w.facility_id) then
    return public.work_order_result_error('ACCESS_DENIED', 'Same-facility Facility Manager authority is required.');
  end if;
  if actor ->> 'role' not in ('approver', 'supervisor', 'facility_manager', 'administrator') then
    return public.work_order_result_error('ACCESS_DENIED', 'Independent financial approval authority is required.');
  end if;
  if control.cost_status <> 'recommended' or control.recommended_by is null then
    return public.work_order_result_error('COST_RECOMMENDATION_REQUIRED', 'A cost recommendation is required first.');
  end if;
  if control.recommended_by = (actor ->> 'id')::uuid then
    return public.work_order_result_error('SELF_APPROVAL_DENIED', 'The recommender cannot approve the same expenditure.');
  end if;
  if p_approved_budget is null or p_approved_budget < 0 or nullif(pg_catalog.btrim(coalesce(p_note, '')), '') is null then
    return public.work_order_result_error('VALIDATION_ERROR', 'Approved budget and approval note are required.');
  end if;
  update public.work_order_financial_controls
  set approved_budget = p_approved_budget,
      cost_status = 'approved',
      financial_approved_by = (actor ->> 'id')::uuid,
      financial_approved_at = pg_catalog.now(),
      financial_approval_note = pg_catalog.btrim(p_note),
      updated_at = pg_catalog.now()
  where work_order_id = w.id
  returning * into control;
  insert into public.activity_logs(user_id, work_order_id, action, from_status, to_status, actor, note)
  values (
    (actor ->> 'id')::uuid,
    w.id,
    'work_order_financial_approved',
    w.status,
    w.status,
    actor ->> 'name',
    pg_catalog.jsonb_build_object('approved_budget', p_approved_budget, 'recommended_by', control.recommended_by)::text
  );
  return pg_catalog.jsonb_build_object('ok', true, 'financial', pg_catalog.to_jsonb(control));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_work_order_proposal_20260924_core(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; amount numeric; scope_text text; quote_ref text; quote_date date; legal_name text; gst text; itemization text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare this proposal.'); end if;
  select * into q from public.contractor_quotations where work_order_id=w.id and status in ('draft','returned') order by updated_at desc limit 1 for update;
  if q.id is null then return public.work_order_result_error('PROPOSAL_REQUIRED','Prepare a governed contractor proposal first.'); end if;
  begin amount:=(p_payload->>'proposed_amount')::numeric; quote_date:=nullif(p_payload->>'quotation_date','')::date; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Proposed amount or quotation date is invalid.'); end;
  scope_text:=nullif(btrim(coalesce(p_payload->>'scope_summary','')),''); quote_ref:=nullif(btrim(coalesce(p_payload->>'quotation_ref','')),''); legal_name:=nullif(btrim(coalesce(p_payload->>'contractor_legal_name','')),''); gst:=nullif(btrim(coalesce(p_payload->>'gst_treatment','')),''); itemization:=nullif(btrim(coalesce(p_payload->>'itemization_note','')),'');
  if amount is null or amount<0 or scope_text is null then return public.work_order_result_error('VALIDATION_ERROR','A valid proposal amount and repair scope are required.'); end if;
  update public.contractor_quotations set quotation_ref=quote_ref,quotation_date=quote_date,total_amount=amount,status='draft',prepared_by=actor_id,prepared_at=coalesce(prepared_at,now()),draft_saved_at=now(),scope_summary=scope_text,contractor_legal_name=legal_name,gst_treatment=gst,itemization_note=itemization,submitted_by=null,submitted_at=null,approved_by=null,approved_at=null,approval_note=null,updated_at=now() where id=q.id returning * into q;
  update public.work_order_financial_controls set estimated_cost=amount,updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_draft_saved',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'proposed_amount',amount)::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$
;
CREATE OR REPLACE FUNCTION public.submit_work_order_proposal(p_work_order_id uuid, p_quotation_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype;
  required_count integer; collected_count integer; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Draft proposal was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or q.prepared_by is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician who prepared the draft may submit it.'); end if;
  if q.status not in ('draft','returned') then return public.work_order_result_error('INVALID_TRANSITION','Only a draft or returned proposal may be submitted.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.quotation_id=q.id and d.document_type='quotation' and d.deleted_at is null) then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','Attach the authentic contractor quotation before submission.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  update public.contractor_quotations set status='submitted',submitted_by=actor_id,submitted_at=pg_catalog.now(),submission_note=nullif(pg_catalog.btrim(coalesce(p_note,'')),''),updated_at=pg_catalog.now() where id=q.id returning * into q;
  select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  note_text:=coalesce(nullif(pg_catalog.btrim(coalesce(p_note,'')),''),'Authentic quotation submitted for governed comparison.');
  if coalesce(required_count,1)=1 then
    update public.work_orders set recommended_vendor_id=q.vendor_id,updated_at=pg_catalog.now() where id=w.id;
    update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=note_text,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,approved_budget=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  else
    update public.work_order_financial_controls set cost_status='quotation_recorded',quoted_cost=null,recommended_by=null,recommended_at=null,recommendation_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'vendor_id',q.vendor_id,'quoted_amount',q.total_amount,'required_quotations',required_count,'distinct_quotations_collected',collected_count,'ready_for_selection',collected_count>=coalesce(required_count,1))::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'required_quotations',required_count,'collected_quotations',collected_count,'ready_for_selection',collected_count>=coalesce(required_count,1));
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_work_order_proposal_20260924_core(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Submitted proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent financial approval authority is required.'); end if;
  if q.submitted_by=actor_id or q.prepared_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','A proposal preparer cannot approve the same expenditure.'); end if;
  if q.status<>'submitted' then return public.work_order_result_error('INVALID_TRANSITION','Only a submitted proposal may be approved.'); end if;
  if nullif(btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','An independent approval note is required.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.quotation_id=q.id and d.document_type='quotation' and d.deleted_at is null) then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','The supporting quotation document is required for approval.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e where e.vendor_id=q.vendor_id and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','The recommended contractor is no longer eligible.'); end if;
  update public.contractor_quotations set status='superseded',updated_at=now() where work_order_id=w.id and id<>q.id and status='approved';
  update public.contractor_quotations set status='approved',approved_by=actor_id,approved_at=now(),approval_note=btrim(p_note),updated_at=now() where id=q.id returning * into q;
  update public.work_orders set assigned_vendor_id=q.vendor_id,recommended_vendor_id=q.vendor_id,updated_at=now() where id=w.id;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,approved_budget=q.total_amount,cost_status='approved',financial_approved_by=actor_id,financial_approved_at=now(),financial_approval_note=btrim(p_note),updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_independently_approved',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'version_no',q.version_no,'approved_amount',q.total_amount,'selected_vendor_id',q.vendor_id,'supporting_document_locked',true,'prepared_by',q.prepared_by,'approved_by',actor_id,'self_approval',false)::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$
;
CREATE OR REPLACE FUNCTION public.save_work_order_payment_proposal(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; final_cost public.work_order_final_cost_submissions%rowtype;
  result public.contractor_payment_assessments%rowtype; note_text text; invoice_ref text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into final_cost from public.work_order_final_cost_submissions where work_order_id=p_work_order_id;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.assigned_vendor_id is null then return public.work_order_result_error('CONTRACTOR_REQUIRED','An assigned contractor record is required.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare the final account.'); end if;
  if w.status not in ('reviewed','closed') or w.reviewed_at is null then return public.work_order_result_error('APPROVAL_NOT_READY','Verified completion is required before preparing the final account.'); end if;
  if final_cost.id is null or final_cost.status not in ('confirmed','variance_approved') then return public.work_order_result_error('FINAL_COST_REQUIRED','A reconciled final cost and any required variance approval are required.'); end if;
  if exists(select 1 from public.work_order_financial_dispositions d where d.work_order_id=w.id and d.status in ('proposed','approved')) then return public.work_order_result_error('FINANCIAL_DISPOSITION_REQUIRED','Return or reject the no-payment disposition before preparing a payment proposal.'); end if;
  note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'recommendation_note','')),''); invoice_ref:=nullif(pg_catalog.btrim(coalesce(p_payload->>'invoice_reference','')),'');
  if note_text is null or length(note_text)>1000 or coalesce(length(invoice_ref),0)>120 then return public.work_order_result_error('VALIDATION_ERROR','A bounded payment recommendation note is required.'); end if;
  insert into public.contractor_payment_assessments(work_order_id,vendor_id,status,assessed_amount,completed_work_accepted_at,invoice_reference,recommendation_note,payment_term_started_at,payment_due_at)
  values(w.id,w.assigned_vendor_id,'draft',final_cost.confirmed_actual_cost,w.reviewed_at,invoice_ref,note_text,w.reviewed_at,w.reviewed_at+interval '30 days')
  on conflict(work_order_id) do update set status='draft',vendor_id=excluded.vendor_id,assessed_amount=excluded.assessed_amount,completed_work_accepted_at=excluded.completed_work_accepted_at,invoice_reference=excluded.invoice_reference,recommendation_note=excluded.recommendation_note,payment_term_started_at=excluded.payment_term_started_at,payment_due_at=excluded.payment_due_at,recommended_by=null,recommended_at=null,approved_by=null,approved_at=null,approval_note=null,completion_notified_at=null,paid_at=null,paid_amount=null,payment_reference=null,paid_by=null,payment_note=null,updated_at=pg_catalog.now() returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_final_account_draft_saved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_quotation',(select approved_budget from public.work_order_financial_controls where work_order_id=w.id),'actual_repair_cost',final_cost.confirmed_actual_cost,'recommended_payment',result.assessed_amount,'quotation_excluded_from_payment_total',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.submit_work_order_payment_proposal(p_work_order_id uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Final account draft was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may submit the payment proposal.'); end if;
  if result.status not in ('draft','returned') then return public.work_order_result_error('INVALID_TRANSITION','Only a draft or returned payment proposal may be submitted.'); end if;
  if not exists(select 1 from public.work_order_commercial_documents d where d.work_order_id=w.id and d.payment_assessment_id=result.id and d.document_type='invoice' and d.deleted_at is null) then return public.work_order_result_error('INVOICE_REQUIRED','Attach the contractor invoice before submitting the payment proposal.'); end if;
  update public.contractor_payment_assessments set status='awaiting_approval',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=coalesce(nullif(pg_catalog.btrim(coalesce(p_note,'')),''),recommendation_note),completion_notified_at=pg_catalog.now(),updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,'contractor_final_account_submitted','work_order:'||w.id::text||':payment-proposal:'||result.id::text||':submitted',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',w.id,'payment_assessment_id',result.id,'recommended_payment',result.assessed_amount,'payment_due_at',result.payment_due_at),'pending'
  from public.profiles p where p.is_active and p.deleted_at is null and p.role in ('approver','administrator') and p.id<>actor_id on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_final_account_submitted',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'recommended_payment',result.assessed_amount,'invoice_attached',true,'completion_notification_queued',true,'payment_term_started_at',result.payment_term_started_at,'payment_due_at',result.payment_due_at)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_work_order_payment(p_work_order_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Submitted payment proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent payment approval authority is required.'); end if;
  if result.recommended_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment recommender cannot approve the same payment.'); end if;
  if result.status<>'awaiting_approval' then return public.work_order_result_error('INVALID_TRANSITION','Only a submitted payment proposal may be approved.'); end if;
  if nullif(pg_catalog.btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('VALIDATION_ERROR','An independent payment approval note is required.'); end if;
  update public.contractor_payment_assessments set status='approved_for_payment',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=pg_catalog.btrim(p_note),updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.notification_outbox(work_order_id,event_type,event_key,recipient_user_id,recipient_profile_id,recipient_email,channel,payload,delivery_status)
  select w.id,'contractor_payment_approved','work_order:'||w.id::text||':payment-proposal:'||result.id::text||':approved',p.id,p.id,p.email,'email',pg_catalog.jsonb_build_object('work_order_id',w.id,'approved_payment',result.assessed_amount,'payment_due_at',result.payment_due_at),'pending'
  from public.profiles p where p.id=w.assigned_technician_id and p.is_active and p.deleted_at is null on conflict do nothing;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_payment_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'recommended_by',result.recommended_by,'approved_by',actor_id,'self_approval',false,'finance_payment_recorded',false)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.record_work_order_finance_payment(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype; amount numeric; reference text; note_text text; paid_time timestamptz;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  if actor->>'role'<>'administrator' then return public.work_order_result_error('ACCESS_DENIED','Finance payment recording is restricted to an Administrator.'); end if;
  select * into w from public.work_orders where id=p_work_order_id; select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Approved payment proposal was not found.'); end if;
  if result.status<>'approved_for_payment' then return public.work_order_result_error('INVALID_TRANSITION','Independent payment approval is required before Finance records payment.'); end if;
  if result.approved_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment approver cannot also record the Finance payment.'); end if;
  begin amount:=(p_payload->>'paid_amount')::numeric; paid_time:=coalesce(nullif(p_payload->>'paid_at','')::timestamptz,pg_catalog.now()); exception when others then return public.work_order_result_error('VALIDATION_ERROR','Paid amount or payment date is invalid.'); end;
  reference:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_reference','')),''); note_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'payment_note','')),'');
  if amount is null or amount<>result.assessed_amount or reference is null or note_text is null then return public.work_order_result_error('PAYMENT_RECONCILIATION_REQUIRED','Recorded payment must equal the independently approved payment proposal and include a reference and Finance note.'); end if;
  update public.contractor_payment_assessments set status='paid',paid_amount=amount,payment_reference=reference,paid_by=actor_id,paid_at=paid_time,payment_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_payment_recorded_by_finance',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'approved_payment',result.assessed_amount,'paid_amount',result.paid_amount,'payment_reference',result.payment_reference,'paid_at',result.paid_at,'reconciled',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.register_work_order_commercial_document(p_work_order_id uuid, p_document_type text, p_record_id uuid, p_original_filename text, p_content_type text, p_byte_size bigint, p_storage_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_commercial_documents%rowtype; replaced_ids uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may attach commercial documents.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Commercial document authority is required.'); end if;
  if p_document_type='quotation' and not exists(select 1 from public.contractor_quotations q where q.id=p_record_id and q.work_order_id=w.id and q.status in ('draft','returned')) then return public.work_order_result_error('APPROVED_DOCUMENT_IMMUTABLE','Only a draft or returned quotation revision can receive a replacement document.'); end if;
  if p_document_type='invoice' and not exists(select 1 from public.contractor_payment_assessments p where p.id=p_record_id and p.work_order_id=w.id and p.status in ('draft','awaiting_approval','approved_for_payment','returned')) then return public.work_order_result_error('NOT_FOUND','Final account record was not found.'); end if;
  if p_document_type not in ('quotation','invoice') or p_storage_path not like 'commercial/work-order/'||w.id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return public.work_order_result_error('INVALID_STORAGE_OBJECT','Commercial document storage could not be verified.'); end if;
  if p_document_type='quotation' then select pg_catalog.array_agg(id) into replaced_ids from public.work_order_commercial_documents where quotation_id=p_record_id and deleted_at is null; end if;
  insert into public.work_order_commercial_documents(work_order_id,document_type,quotation_id,payment_assessment_id,uploaded_by,original_filename,content_type,byte_size,storage_path) values(w.id,p_document_type,case when p_document_type='quotation' then p_record_id end,case when p_document_type='invoice' then p_record_id end,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into result;
  if p_document_type='quotation' and replaced_ids is not null then update public.work_order_commercial_documents set deleted_at=pg_catalog.now(),superseded_at=pg_catalog.now(),superseded_by=result.id,superseded_by_user=actor_id where id=any(replaced_ids); end if;
  if p_document_type='invoice' then update public.contractor_payment_assessments set invoice_received_at=coalesce(invoice_received_at,pg_catalog.now()),updated_at=pg_catalog.now() where id=p_record_id; end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,case when replaced_ids is null then 'work_order_commercial_document_attached' else 'draft_quotation_document_replaced' end,w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'document_type',result.document_type,'record_id',p_record_id,'filename',result.original_filename,'replaced_document_ids',coalesce(pg_catalog.to_jsonb(replaced_ids),'[]'::jsonb))::text);
  return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
exception when check_violation or foreign_key_violation or unique_violation then return public.work_order_result_error('VALIDATION_ERROR','Commercial document metadata is invalid.'); end;$function$
;
CREATE OR REPLACE FUNCTION public.open_work_order_document_correction(p_work_order_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_document_corrections%rowtype; reason_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; reason_text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Authorized management approval is required to open a document correction.'); end if;
  if w.status not in ('completed','reviewed','closed') then return public.work_order_result_error('INVALID_TRANSITION','Document correction is only available after physical completion.'); end if;
  if w.assigned_technician_id is null then return public.work_order_result_error('INVALID_ASSIGNMENT','An assigned Technician is required.'); end if;
  if reason_text is null or length(reason_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A correction reason is required.'); end if;
  if exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_ALREADY_OPEN','A supporting-document correction is already open.'); end if;
  insert into public.work_order_document_corrections(work_order_id,original_status,reason,opened_by) values(w.id,w.status,reason_text,actor_id) returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'supporting_document_correction_opened',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('correction_id',result.id,'reason',reason_text,'work_order_status_preserved',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'correction',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.start_work_order_quotation_revision(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; prior public.contractor_quotations%rowtype; result public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a quotation revision.'); end if;
  if w.status in ('completed','reviewed','closed') and not exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_REQUIRED','Authorized management must open a supporting-document correction first.'); end if;
  if exists(select 1 from public.contractor_quotations q where q.work_order_id=w.id and q.status in ('draft','returned','submitted')) then return public.work_order_result_error('REVISION_ALREADY_ACTIVE','A quotation revision is already active.'); end if;
  select * into prior from public.contractor_quotations where work_order_id=w.id and status in ('approved','superseded') order by version_no desc limit 1;
  if prior.id is null then return public.work_order_result_error('NOT_FOUND','An approved quotation was not found.'); end if;
  insert into public.contractor_quotations(work_order_id,vendor_id,quotation_ref,quotation_date,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary,contractor_legal_name,gst_treatment,itemization_note)
  values(w.id,w.assigned_vendor_id,prior.quotation_ref,prior.quotation_date,prior.version_no+1,'draft',prior.currency,prior.total_amount,actor_id,pg_catalog.now(),pg_catalog.now(),prior.scope_summary,prior.contractor_legal_name,prior.gst_treatment,prior.itemization_note) returning * into result;
  update public.work_order_financial_controls set cost_status='draft',recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_revision_started',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('prior_quotation_id',prior.id,'revision_quotation_id',result.id,'version_no',result.version_no,'prior_approved_document_preserved',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.close_work_order_document_correction(p_work_order_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; correction public.work_order_document_corrections%rowtype; note_text text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; note_text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),''); select * into w from public.work_orders where id=p_work_order_id;
  select * into correction from public.work_order_document_corrections where work_order_id=p_work_order_id and status='open' for update;
  if w.id is null or correction.id is null then return public.work_order_result_error('NOT_FOUND','An open supporting-document correction was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Authorized management verification is required to close a document correction.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A correction verification note is required.'); end if;
  if not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='before' and e.deleted_at is null) then return public.work_order_result_error('BEFORE_EVIDENCE_REQUIRED','Active Before evidence is required.'); end if;
  if not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null) then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Active After evidence is required.'); end if;
  if exists(select 1 from public.contractor_quotations q where q.work_order_id=w.id and q.status in ('draft','returned','submitted')) then return public.work_order_result_error('QUOTATION_APPROVAL_REQUIRED','The active quotation revision must be independently approved.'); end if;
  if not exists(select 1 from public.contractor_quotations q join public.work_order_commercial_documents d on d.quotation_id=q.id and d.deleted_at is null where q.work_order_id=w.id and q.status='approved') then return public.work_order_result_error('QUOTATION_DOCUMENT_REQUIRED','An approved quotation supporting document is required.'); end if;
  update public.work_order_document_corrections set status='closed',closed_by=actor_id,closed_at=pg_catalog.now(),closure_note=note_text where id=correction.id returning * into correction;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'supporting_document_correction_verified',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('correction_id',correction.id,'before_evidence_present',true,'after_evidence_present',true,'approved_quotation_document_present',true,'note',note_text,'original_history_preserved',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'correction',pg_catalog.to_jsonb(correction));
end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_eligible_contractors(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; result jsonb;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from (actor->>'id')::uuid or not public.technician_facility_read_permitted(w.facility_id)) then
    return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may review eligible contractors.');
  end if;
  if actor->>'role' not in ('technician','approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Commercial access is required.'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'trade',v.trade,'payment_terms_days',v.payment_terms_days) order by v.name),'[]'::jsonb)
  into result from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id
  where e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null;
  return jsonb_build_object('ok',true,'contractors',result);
end;$function$
;
CREATE OR REPLACE FUNCTION public.prepare_work_order_proposal(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
  control public.work_order_financial_controls%rowtype; vendor uuid; amount numeric; governed_estimate numeric; scope_text text; rule uuid;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid; select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may prepare a proposal.'); end if;
  if w.status not in ('assigned','in_progress') then return public.work_order_result_error('INVALID_TRANSITION','Proposal preparation requires active assigned work.'); end if;
  begin vendor:=(p_payload->>'vendor_id')::uuid; amount:=(p_payload->>'proposed_amount')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Eligible contractor and proposed amount are required.'); end;
  scope_text:=nullif(pg_catalog.btrim(coalesce(p_payload->>'scope_summary','')),'');
  if amount is null or amount<0 or scope_text is null or length(scope_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','Repair scope and non-negative proposed amount are required.'); end if;
  if not exists(select 1 from public.vendor_facility_eligibility e join public.vendors v on v.id=e.vendor_id where e.vendor_id=vendor and e.facility_id=w.facility_id and e.active and e.procurement_prequalified and e.facility_confirmed and v.active and v.deleted_at is null) then return public.work_order_result_error('CONTRACTOR_INELIGIBLE','Select a Procurement-prequalified, Facility-confirmed contractor.'); end if;
  if exists(select 1 from public.contractor_quotations x where x.work_order_id=w.id and x.vendor_id=vendor and x.status in ('draft','submitted','approved')) then return public.work_order_result_error('DUPLICATE_CONTRACTOR_QUOTATION','A current quotation for this contractor already exists.'); end if;
  select * into control from public.work_order_financial_controls where work_order_id=w.id for update;
  governed_estimate:=greatest(coalesce(control.estimated_cost,0),amount);
  select id into rule from public.commercial_approval_rules where active and governed_estimate>=minimum_amount and (maximum_amount is null or governed_estimate<maximum_amount) order by minimum_amount desc limit 1;
  if rule is null then return public.work_order_result_error('COMMERCIAL_RULE_REQUIRED','No commercial approval rule covers this amount.'); end if;
  insert into public.work_order_financial_controls(work_order_id,estimated_cost,rule_id,cost_status)
  values(w.id,governed_estimate,rule,'draft') on conflict(work_order_id) do update set estimated_cost=governed_estimate,rule_id=rule,cost_status='draft',quoted_cost=null,approved_budget=null,recommended_by=null,recommended_at=null,recommendation_note=null,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,updated_at=pg_catalog.now();
  insert into public.contractor_quotations(work_order_id,vendor_id,version_no,status,currency,total_amount,prepared_by,prepared_at,draft_saved_at,scope_summary)
  values(w.id,vendor,coalesce((select max(version_no)+1 from public.contractor_quotations where work_order_id=w.id),1),'draft','SGD',amount,actor_id,pg_catalog.now(),pg_catalog.now(),scope_text) returning * into q;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_competing_quotation_prepared',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('vendor_id',vendor,'quotation_id',q.id,'quoted_amount',amount,'governed_estimate',governed_estimate,'decision_pending',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q));
end;$function$
;
CREATE OR REPLACE FUNCTION public.return_work_order_proposal(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null then return public.work_order_result_error('NOT_FOUND','Submitted proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent approval authority is required.'); end if;
  if q.status<>'submitted' or nullif(btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('INVALID_TRANSITION','A submitted proposal and return reason are required.'); end if;
  update public.contractor_quotations set status='returned',approval_note=btrim(p_note),updated_at=now() where id=q.id returning * into q;
  update public.work_order_financial_controls set cost_status='returned',financial_approved_by=null,financial_approved_at=null,financial_approval_note=btrim(p_note),updated_at=now() where work_order_id=w.id;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_proposal_returned',w.status,w.status,actor->>'name',jsonb_build_object('quotation_id',q.id,'reason',btrim(p_note))::text);
  return jsonb_build_object('ok',true,'quotation',to_jsonb(q));
end;$function$
;
CREATE OR REPLACE FUNCTION public.return_work_order_payment(p_work_order_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.contractor_payment_assessments%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Payment proposal was not found.'); end if;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent payment authority is required.'); end if;
  if result.status<>'awaiting_approval' or nullif(btrim(coalesce(p_note,'')),'') is null then return public.work_order_result_error('INVALID_TRANSITION','An awaiting-approval payment proposal and return reason are required.'); end if;
  update public.contractor_payment_assessments set status='returned',approval_note=btrim(p_note),updated_at=now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'contractor_payment_proposal_returned',w.status,w.status,actor->>'name',jsonb_build_object('payment_assessment_id',result.id,'reason',btrim(p_note))::text);
  return jsonb_build_object('ok',true,'payment',to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.reopen_work_order_payment_for_correction(p_work_order_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  actor jsonb:=public.work_order_actor();
  actor_id uuid;
  w public.work_orders%rowtype;
  result public.contractor_payment_assessments%rowtype;
  actual_total numeric(14,2);
  reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then
    return public.work_order_result_error('ACCESS_DENIED','Independent payment correction authority is required.');
  end if;
  if reason is null or pg_catalog.length(reason)>1000 then
    return public.work_order_result_error('VALIDATION_ERROR','A bounded payment correction reason is required.');
  end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  select * into result from public.contractor_payment_assessments where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Payment assessment was not found.'); end if;
  if result.status<>'approved_for_payment' or result.paid_at is not null then
    return public.work_order_result_error('INVALID_TRANSITION','Only an approved, unpaid assessment may be reopened for correction.');
  end if;
  if result.recommended_by=actor_id then
    return public.work_order_result_error('SELF_APPROVAL_DENIED','The payment recommender cannot reopen their own assessment approval.');
  end if;
  select coalesce(pg_catalog.sum(c.amount),0) into actual_total
  from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
  update public.contractor_payment_assessments set
    status='returned',assessed_amount=actual_total,completed_work_accepted_at=w.reviewed_at,
    payment_term_started_at=w.reviewed_at,payment_due_at=w.reviewed_at+interval '30 days',
    approval_note=null,approved_by=null,approved_at=null,completion_notified_at=null,updated_at=pg_catalog.now()
  where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'contractor_payment_reopened_for_correction',w.status,w.status,actor->>'name',
    pg_catalog.jsonb_build_object('payment_assessment_id',result.id,'reason',reason,
      'corrected_assessed_amount',actual_total,'basis','confirmed_actual_cost_only',
      'prior_approval_preserved_in_activity_history',true)::text);
  return pg_catalog.jsonb_build_object('ok',true,'payment',pg_catalog.to_jsonb(result));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_work_order_final_cost(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype;
  contractor numeric; derived_actual numeric; claimed_actual numeric; approved numeric; note text; next_status text; payment_status text;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or w.status not in ('assigned','in_progress','completed','reviewed') or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may reconcile final costs before closure.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_labour_hours is null then return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Physical labour and the execution cost ledger must be confirmed before final reconciliation.'); end if;
  select p.status into payment_status from public.contractor_payment_assessments p where p.work_order_id=w.id;
  if payment_status in ('awaiting_approval','approved_for_payment','paid') then return public.work_order_result_error('FINANCIAL_RECORD_IMMUTABLE','Final cost cannot change after the payment proposal is submitted.'); end if;
  begin contractor:=(p_payload->>'final_contractor_amount')::numeric; claimed_actual:=nullif(p_payload->>'confirmed_actual_cost','')::numeric; exception when others then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount or claimed actual cost is invalid.'); end;
  select coalesce(pg_catalog.sum(c.amount),0) into derived_actual from public.work_order_cost_lines c where c.work_order_id=w.id and c.cost_phase='actual';
  note:=nullif(pg_catalog.btrim(coalesce(p_payload->>'comments','')),'');
  if contractor is null or contractor<0 or note is null or length(note)>2000 then return public.work_order_result_error('VALIDATION_ERROR','Final contractor amount and comments are required.'); end if;
  if claimed_actual is not null and claimed_actual<>derived_actual then return public.work_order_result_error('ACTUAL_COST_MISMATCH','Confirmed actual cost must equal the execution cost ledger total.'); end if;
  select approved_budget into approved from public.work_order_financial_controls where work_order_id=w.id;
  next_status:=case when derived_actual>coalesce(approved,0) then 'variance_pending' else 'confirmed' end;
  insert into public.work_order_final_cost_submissions(work_order_id,status,actual_labour_hours,final_contractor_amount,confirmed_actual_cost,comments,submitted_by,submitted_at)
  values(w.id,next_status,w.actual_labour_hours,contractor,derived_actual,note,actor_id,pg_catalog.now())
  on conflict(work_order_id) do update set status=excluded.status,actual_labour_hours=excluded.actual_labour_hours,final_contractor_amount=excluded.final_contractor_amount,confirmed_actual_cost=excluded.confirmed_actual_cost,comments=excluded.comments,submitted_by=excluded.submitted_by,submitted_at=excluded.submitted_at,variance_approved_by=null,variance_approved_at=null,variance_approval_note=null,updated_at=pg_catalog.now() returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_reconciled',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'approved_quotation',approved,'actual_contractor_charge',contractor,'actual_repair_cost',derived_actual,'actual_labour_hours',w.actual_labour_hours,'variance',derived_actual-coalesce(approved,0),'quotation_excluded_from_actual_total',true,'status',next_status)::text);
  return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result),'approved_quotation',approved,'actual_repair_cost',derived_actual,'variance',derived_actual-coalesce(approved,0));
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_work_order_final_cost_variance(p_work_order_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_final_cost_submissions%rowtype; note text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 if actor->>'role' not in ('approver','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent expenditure authority is required.'); end if;
 select * into w from public.work_orders where id=p_work_order_id; select * into result from public.work_order_final_cost_submissions where work_order_id=p_work_order_id for update;
 if result.id is null or result.status<>'variance_pending' then return public.work_order_result_error('INVALID_TRANSITION','A pending final-cost variance was not found.'); end if;
 if result.submitted_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The Technician cannot approve their own final-cost variance.'); end if;
 if note is null then return public.work_order_result_error('VALIDATION_ERROR','An approval note is required.'); end if;
 update public.work_order_final_cost_submissions set status='variance_approved',variance_approved_by=actor_id,variance_approved_at=pg_catalog.now(),variance_approval_note=note,updated_at=pg_catalog.now() where id=result.id returning * into result;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_cost_variance_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('submission_id',result.id,'confirmed_actual_cost',result.confirmed_actual_cost,'approval_note',note)::text);
 return pg_catalog.jsonb_build_object('ok',true,'final_cost',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.register_work_order_final_cost_document(p_work_order_id uuid, p_submission_id uuid, p_original_filename text, p_content_type text, p_byte_size bigint, p_storage_path text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; submission public.work_order_final_cost_submissions%rowtype; result public.work_order_final_cost_documents%rowtype; old_ids uuid[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into submission from public.work_order_final_cost_submissions where id=p_submission_id and work_order_id=p_work_order_id;
  if w.id is null or submission.id is null then return public.work_order_result_error('NOT_FOUND','Final-cost submission was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) or w.status not in ('assigned','in_progress','completed','reviewed') then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may attach a final invoice before closure.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status in ('awaiting_approval','approved_for_payment','paid')) then return public.work_order_result_error('FINANCIAL_RECORD_IMMUTABLE','Final-cost documents cannot change after the payment proposal is submitted.'); end if;
  if p_content_type not in ('image/jpeg','image/png','image/webp','application/pdf') or p_byte_size not between 1 and 10485760 or p_storage_path not like 'commercial/work-order/'||w.id::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='field-evidence' and o.name=p_storage_path) then return public.work_order_result_error('INVALID_STORAGE_OBJECT','Final invoice storage could not be verified.'); end if;
  select pg_catalog.array_agg(id) into old_ids from public.work_order_final_cost_documents where final_cost_submission_id=submission.id and deleted_at is null;
  insert into public.work_order_final_cost_documents(final_cost_submission_id,work_order_id,uploaded_by,original_filename,content_type,byte_size,storage_path) values(submission.id,w.id,actor_id,p_original_filename,p_content_type,p_byte_size,p_storage_path) returning * into result;
  if old_ids is not null then update public.work_order_final_cost_documents set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason='Replaced by a controlled financial-document revision',superseded_by=result.id where id=any(old_ids); end if;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_final_invoice_attached',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',result.id,'submission_id',submission.id,'filename',result.original_filename,'physical_completion_timestamp_unchanged',true,'replaced_document_ids',coalesce(pg_catalog.to_jsonb(old_ids),'[]'::jsonb))::text);
  return pg_catalog.jsonb_build_object('ok',true,'document',pg_catalog.to_jsonb(result)-'storage_path');
end;$function$
;
CREATE OR REPLACE FUNCTION public.void_work_order_evidence(p_evidence_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; item public.evidence_items%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into item from public.evidence_items where id=p_evidence_id and deleted_at is null for update; if item.id is null or item.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Active Work Order evidence was not found.'); end if;
 select * into w from public.work_orders where id=item.work_order_id for update;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) or not (w.status in ('assigned','in_progress') or exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open'))) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician may remove evidence while the record is editable.'); end if;
 if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Evidence removal authority is required.'); end if;
 if item.category='after' and w.status in ('completed','reviewed','closed') and not exists(select 1 from public.evidence_items e where e.work_order_id=w.id and e.category='after' and e.deleted_at is null and e.id<>item.id) then return public.work_order_result_error('AFTER_EVIDENCE_REQUIRED','Upload replacement After evidence before removing the last mandatory item.'); end if;
 update public.evidence_items set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=item.id;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'evidence_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('evidence_id',item.id,'filename',item.original_filename,'original_category',item.category,'reason',reason)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$
;
CREATE OR REPLACE FUNCTION public.withdraw_physical_completion(p_work_order_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into w from public.work_orders where id=p_work_order_id for update;
 if w.status<>'completed' then return public.work_order_result_error('INVALID_TRANSITION','Only an unverified completion submission may be withdrawn.'); end if;
 if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned Technician may withdraw their unverified completion submission.'); end if;
 if reason is null then return public.work_order_result_error('VALIDATION_ERROR','A withdrawal reason is required.'); end if;
 update public.work_orders set status='in_progress',completed_at=null,updated_at=pg_catalog.now() where id=w.id;
 update public.work_order_final_cost_submissions set status='draft',variance_approved_by=null,variance_approved_at=null,variance_approval_note=null,updated_at=pg_catalog.now() where work_order_id=w.id;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'physical_completion_withdrawn','completed','in_progress',actor->>'name',pg_catalog.jsonb_build_object('reason',reason,'prior_completed_at',w.completed_at,'physical_history_preserved',true)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$
;
CREATE OR REPLACE FUNCTION public.submit_physical_completion(p_work_order_id uuid, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if w.actual_costs_confirmed_at is null or w.actual_costs_confirmed_by is distinct from (actor->>'id')::uuid then
    return public.work_order_result_error('ACTUAL_COSTING_CONFIRMATION_REQUIRED','Confirm the execution cost ledger, including a genuine zero-cost result, before physical completion.');
  end if;
  return public.submit_physical_completion_20260921_core(p_work_order_id,p_payload);
end;$function$
;
CREATE OR REPLACE FUNCTION public.void_work_order_supporting_document(p_work_order_id uuid, p_document_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; commercial public.work_order_commercial_documents%rowtype;
  final_doc public.work_order_final_cost_documents%rowtype; reason text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),''); record_editable boolean:=false;
begin
 if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
 select * into w from public.work_orders where id=p_work_order_id for update;
 if w.id is null then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
 if reason is null or length(reason)>500 then return public.work_order_result_error('VALIDATION_ERROR','A bounded removal reason is required.'); end if;
 if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may remove editable supporting documents.'); end if;
 select * into commercial from public.work_order_commercial_documents where id=p_document_id and work_order_id=w.id and deleted_at is null for update;
 if commercial.id is not null then
   if commercial.document_type='quotation' then record_editable:=exists(select 1 from public.contractor_quotations q where q.id=commercial.quotation_id and q.status in ('draft','returned'));
   elsif commercial.document_type='invoice' then record_editable:=exists(select 1 from public.contractor_payment_assessments p where p.id=commercial.payment_assessment_id and p.status in ('draft','returned'));
   end if;
   if not record_editable then return public.work_order_result_error('APPROVED_DOCUMENT_IMMUTABLE','Submitted or approved supporting documents require a controlled revision.'); end if;
   update public.work_order_commercial_documents set deleted_at=pg_catalog.now(),superseded_by_user=actor_id where id=commercial.id;
 else
   select * into final_doc from public.work_order_final_cost_documents where id=p_document_id and work_order_id=w.id and deleted_at is null for update;
   if final_doc.id is null then return public.work_order_result_error('NOT_FOUND','Supporting document was not found.'); end if;
   if w.status not in ('assigned','in_progress') and not exists(select 1 from public.work_order_document_corrections c where c.work_order_id=w.id and c.status='open') then return public.work_order_result_error('CORRECTION_REQUIRED','Authorized document correction is required.'); end if;
   update public.work_order_final_cost_documents set deleted_at=pg_catalog.now(),deleted_by=actor_id,deletion_reason=reason where id=final_doc.id;
 end if;
 insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_supporting_document_voided',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('document_id',p_document_id,'reason',reason,'soft_deleted',true)::text);
 return pg_catalog.jsonb_build_object('ok',true);
end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_financial_documentation_readiness(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; final_cost public.work_order_final_cost_submissions%rowtype;
  payment public.contractor_payment_assessments%rowtype; invoice_present boolean:=false; final_invoice_present boolean:=false;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  select * into final_cost from public.work_order_final_cost_submissions where work_order_id=w.id;
  select * into payment from public.contractor_payment_assessments where work_order_id=w.id;
  if final_cost.id is not null then
    select exists(select 1 from public.work_order_final_cost_documents d where d.final_cost_submission_id=final_cost.id and d.deleted_at is null) into final_invoice_present;
  end if;
  if payment.id is not null then
    select exists(select 1 from public.work_order_commercial_documents d where d.payment_assessment_id=payment.id and d.document_type='invoice' and d.deleted_at is null) into invoice_present;
  end if;
  return pg_catalog.jsonb_build_object(
    'ok',true,'physical_completion_status',w.status,
    'actual_costs_confirmed',w.actual_costs_confirmed_at is not null,
    'final_cost_status',final_cost.status,'final_invoice_present',final_invoice_present,
    'payment_status',payment.status,'payment_invoice_present',invoice_present,
    'payment_proposal_ready',w.status in ('reviewed','closed') and final_cost.status in ('confirmed','variance_approved') and invoice_present
  );
end;$function$
;
CREATE OR REPLACE FUNCTION public.work_order_closure_readiness(p_work_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; payment public.contractor_payment_assessments%rowtype;
  disposition public.work_order_financial_dispositions%rowtype; resolved boolean:=false; resolution text; missing text[]:=array[]::text[];
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  select * into payment from public.contractor_payment_assessments where work_order_id=w.id;
  select * into disposition from public.work_order_financial_dispositions where work_order_id=w.id;
  if payment.status='paid' and payment.paid_at is not null and payment.paid_amount=payment.assessed_amount then resolved:=true; resolution:='paid';
  elsif disposition.status='approved' and disposition.disposition_type='no_payment_required' then resolved:=true; resolution:='no_payment_required'; end if;
  if w.status<>'reviewed' then missing:=array_append(missing,'verified_completion'); end if;
  if not resolved then missing:=array_append(missing,'resolved_financial_disposition'); end if;
  return pg_catalog.jsonb_build_object('ok',true,'ready',w.status='reviewed' and resolved,'work_order_status',w.status,
    'resolution',resolution,'payment_status',payment.status,'no_payment_status',disposition.status,'missing_requirements',pg_catalog.to_jsonb(missing));
end;$function$
;
CREATE OR REPLACE FUNCTION public.propose_work_order_no_payment(p_work_order_id uuid, p_reason_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_financial_dispositions%rowtype;
  code text:=pg_catalog.lower(coalesce(p_reason_code,'')); reason_text text:=nullif(pg_catalog.btrim(coalesce(p_reason,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id for update;
  if not found then return public.work_order_result_error('NOT_FOUND','Work Order not found.'); end if;
  if actor->>'role'='technician' and (w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id)) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may propose no payment.'); end if;
  if actor->>'role' not in ('technician','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Operational financial disposition authority is required.'); end if;
  if w.status not in ('completed','reviewed') then return public.work_order_result_error('INVALID_TRANSITION','No-payment disposition is available after physical completion.'); end if;
  if code not in ('in_house','warranty','goodwill','zero_cost','other') or reason_text is null or length(reason_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A valid no-payment reason and bounded explanation are required.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status<>'returned') then return public.work_order_result_error('PAYMENT_ALREADY_RECORDED','An active or recorded payment process must be returned before no payment required can be proposed.'); end if;
  insert into public.work_order_financial_dispositions(work_order_id,disposition_type,reason_code,reason,status,proposed_by)
  values(w.id,'no_payment_required',code,reason_text,'proposed',actor_id)
  on conflict(work_order_id) do update set disposition_type='no_payment_required',reason_code=excluded.reason_code,reason=excluded.reason,status='proposed',proposed_by=actor_id,proposed_at=pg_catalog.now(),approved_by=null,approved_at=null,approval_note=null,updated_at=pg_catalog.now()
  returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_no_payment_proposed',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('disposition_id',result.id,'reason_code',code,'reason',reason_text,'proposed_by',actor_id)::text);
  return pg_catalog.jsonb_build_object('ok',true,'disposition',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_work_order_no_payment(p_work_order_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; result public.work_order_financial_dispositions%rowtype;
  note_text text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  actor_id:=(actor->>'id')::uuid;
  if actor->>'role' not in ('approver','supervisor','facility_manager','administrator') then return public.work_order_result_error('ACCESS_DENIED','Independent no-payment approval authority is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id for update;
  select * into result from public.work_order_financial_dispositions where work_order_id=p_work_order_id for update;
  if w.id is null or result.id is null then return public.work_order_result_error('NOT_FOUND','Proposed no-payment disposition was not found.'); end if;
  if result.status<>'proposed' then return public.work_order_result_error('INVALID_TRANSITION','Only a proposed no-payment disposition may be approved.'); end if;
  if result.proposed_by=actor_id then return public.work_order_result_error('SELF_APPROVAL_DENIED','The proposer cannot approve their own no-payment disposition.'); end if;
  if exists(select 1 from public.contractor_payment_assessments p where p.work_order_id=w.id and p.status<>'returned') then return public.work_order_result_error('PAYMENT_ALREADY_RECORDED','No payment required cannot be approved while a payment process is active or recorded.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A bounded independent approval note is required.'); end if;
  update public.work_order_financial_dispositions set status='approved',approved_by=actor_id,approved_at=pg_catalog.now(),approval_note=note_text,updated_at=pg_catalog.now() where id=result.id returning * into result;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note)
  values(actor_id,w.id,'work_order_no_payment_independently_approved',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('disposition_id',result.id,'reason_code',result.reason_code,'proposed_by',result.proposed_by,'approved_by',actor_id,'self_approval',false,'approval_note',note_text)::text);
  return pg_catalog.jsonb_build_object('ok',true,'disposition',pg_catalog.to_jsonb(result));
end;$function$
;
CREATE OR REPLACE FUNCTION public.transition_work_order(p_work_order_id uuid, p_action text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare action text:=pg_catalog.lower(coalesce(p_action,'')); readiness jsonb;
begin
  if action<>'close' then return public.transition_work_order_20260924_core(p_work_order_id,p_action,p_payload); end if;
  readiness:=public.work_order_closure_readiness(p_work_order_id);
  if not coalesce((readiness->>'ready')::boolean,false) then return public.work_order_result_error('FINANCIAL_DISPOSITION_REQUIRED','Payment must be recorded or an independent no-payment-required disposition must be approved before closure.'); end if;
  return public.transition_work_order_20260924_core(p_work_order_id,p_action,p_payload);
end;$function$
;
CREATE OR REPLACE FUNCTION public.recommend_work_order_quotation(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); actor_id uuid; w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer; note_text text:=nullif(pg_catalog.btrim(coalesce(p_note,'')),'');
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if; actor_id:=(actor->>'id')::uuid;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id and status='submitted'; select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id for update;
  if w.id is null or q.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Submitted quotation collection was not found.'); end if;
  if actor->>'role'<>'technician' or w.assigned_technician_id is distinct from actor_id or not public.technician_facility_read_permitted(w.facility_id) then return public.work_order_result_error('ACCESS_DENIED','Only the assigned same-facility Technician may recommend a quotation.'); end if;
  if note_text is null or length(note_text)>1000 then return public.work_order_result_error('VALIDATION_ERROR','A bounded selection rationale is required.'); end if;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active;
  select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  if collected_count<coalesce(required_count,1) then return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','Collect the required number of distinct eligible-contractor quotations before recommendation.'); end if;
  update public.work_orders set recommended_vendor_id=q.vendor_id,updated_at=pg_catalog.now() where id=w.id;
  update public.work_order_financial_controls set quoted_cost=q.total_amount,cost_status='recommended',recommended_by=actor_id,recommended_at=pg_catalog.now(),recommendation_note=note_text,financial_approved_by=null,financial_approved_at=null,financial_approval_note=null,approved_budget=null,updated_at=pg_catalog.now() where work_order_id=w.id returning * into control;
  insert into public.activity_logs(user_id,work_order_id,action,from_status,to_status,actor,note) values(actor_id,w.id,'work_order_quotation_recommended',w.status,w.status,actor->>'name',pg_catalog.jsonb_build_object('quotation_id',q.id,'vendor_id',q.vendor_id,'quoted_amount',q.total_amount,'governed_estimate',control.estimated_cost,'required_quotations',required_count,'collected_quotations',collected_count,'selection_rationale',note_text)::text);
  return pg_catalog.jsonb_build_object('ok',true,'quotation',pg_catalog.to_jsonb(q),'financial',pg_catalog.to_jsonb(control));
end;$function$
;
CREATE OR REPLACE FUNCTION public.approve_work_order_proposal(p_work_order_id uuid, p_quotation_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare actor jsonb:=public.work_order_actor(); w public.work_orders%rowtype; q public.contractor_quotations%rowtype; control public.work_order_financial_controls%rowtype; required_count integer; collected_count integer;
begin
  if actor is null then return public.work_order_result_error('ACCESS_DENIED','An active authenticated profile is required.'); end if;
  select * into w from public.work_orders where id=p_work_order_id; select * into q from public.contractor_quotations where id=p_quotation_id and work_order_id=p_work_order_id; select * into control from public.work_order_financial_controls where work_order_id=p_work_order_id;
  if w.id is null or q.id is null or control.work_order_id is null then return public.work_order_result_error('NOT_FOUND','Recommended quotation was not found.'); end if;
  select minimum_quotations into required_count from public.commercial_approval_rules where id=control.rule_id and active; select count(distinct vendor_id) into collected_count from public.contractor_quotations where work_order_id=w.id and status in ('submitted','approved');
  if control.cost_status<>'recommended' or w.recommended_vendor_id is distinct from q.vendor_id or control.quoted_cost is distinct from q.total_amount then return public.work_order_result_error('APPROVAL_NOT_READY','Select and justify the recommended quotation before approval.'); end if;
  if collected_count<coalesce(required_count,1) then return public.work_order_result_error('INSUFFICIENT_QUOTATIONS','The configured quotation count has not been met.'); end if;
  return public.approve_work_order_proposal_20260924_core(p_work_order_id,p_quotation_id,p_note);
end;$function$
;
CREATE OR REPLACE FUNCTION public.save_work_order_proposal(p_work_order_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  result jsonb;
  prior_estimate numeric;
  quotation_amount numeric;
  governed_estimate numeric;
  governed_rule_id uuid;
begin
  select estimated_cost
    into prior_estimate
    from public.work_order_financial_controls
   where work_order_id=p_work_order_id;

  result:=public.save_work_order_proposal_20260924_core(p_work_order_id,p_payload);
  if not coalesce((result->>'ok')::boolean,false) then
    return result;
  end if;

  quotation_amount:=(result->'quotation'->>'total_amount')::numeric;
  governed_estimate:=greatest(coalesce(prior_estimate,0),coalesce(quotation_amount,0));

  select id
    into governed_rule_id
    from public.commercial_approval_rules
   where active
     and governed_estimate>=minimum_amount
     and (maximum_amount is null or governed_estimate<maximum_amount)
   order by minimum_amount desc
   limit 1;

  update public.work_order_financial_controls
     set estimated_cost=governed_estimate,
         rule_id=governed_rule_id,
         updated_at=pg_catalog.now()
   where work_order_id=p_work_order_id;

  return result || pg_catalog.jsonb_build_object(
    'governed_estimate',governed_estimate,
    'commercial_rule_id',governed_rule_id
  );
end;
$function$
;
create view public.pm_occurrence_compliance with (security_invoker=true) as  SELECT o.id,
    o.requirement_id,
    o.requirement_revision_id,
    o.asset_id,
    o.original_due_date,
    o.current_due_date,
    o.generation_status,
    w.id AS work_order_id,
    w.status AS work_order_status,
    w.reviewed_at,
    count(d.id)::integer AS deferral_count,
    count(d.id) > 0 AS deferred,
    count(d.id) > 1 AS repeatedly_deferred,
        CASE
            WHEN o.generation_status = 'cancelled'::text THEN 'cancelled'::text
            WHEN o.generation_status = 'generation_failed'::text AND w.id IS NULL THEN 'generation_failed'::text
            WHEN w.reviewed_at IS NOT NULL AND (w.reviewed_at AT TIME ZONE 'Asia/Singapore'::text)::date <= o.current_due_date THEN 'completed_on_time'::text
            WHEN w.reviewed_at IS NOT NULL THEN 'completed_late'::text
            WHEN o.current_due_date < pm_business_date() THEN 'overdue'::text
            WHEN o.current_due_date = pm_business_date() THEN 'due'::text
            ELSE 'scheduled'::text
        END AS compliance_state
   FROM pm_occurrences o
     LEFT JOIN work_orders w ON w.pm_occurrence_id = o.id
     LEFT JOIN pm_occurrence_deferrals d ON d.occurrence_id = o.id
  GROUP BY o.id, w.id;;
alter table profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table account_invitations add constraint account_invitations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table work_orders add constraint work_orders_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
alter table work_orders add constraint work_orders_assigned_technician_id_fkey FOREIGN KEY (assigned_technician_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table activity_logs add constraint activity_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table activity_logs add constraint activity_logs_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table notification_outbox add constraint notification_outbox_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table notification_outbox add constraint notification_outbox_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table departments add constraint departments_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table departments add constraint departments_parent_department_id_fkey FOREIGN KEY (parent_department_id) REFERENCES departments(id) ON DELETE SET NULL;
alter table departments add constraint departments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table profiles add constraint profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL;
alter table maintenance_teams add constraint maintenance_teams_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE SET NULL;
alter table maintenance_team_members add constraint maintenance_team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES maintenance_teams(id) ON DELETE CASCADE;
alter table maintenance_team_members add constraint maintenance_team_members_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table work_orders add constraint work_orders_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_assigned_vendor_fkey FOREIGN KEY (assigned_vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_assigned_team_fkey FOREIGN KEY (assigned_team_id) REFERENCES maintenance_teams(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_assigned_by_user_fkey FOREIGN KEY (assigned_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table work_orders add constraint work_orders_duplicated_from_fkey FOREIGN KEY (duplicated_from_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table incidents add constraint incidents_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table incidents add constraint incidents_incident_commander_id_fkey FOREIGN KEY (incident_commander_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table incidents add constraint incidents_assigned_technician_id_fkey FOREIGN KEY (assigned_technician_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table incidents add constraint incidents_assigned_team_id_fkey FOREIGN KEY (assigned_team_id) REFERENCES maintenance_teams(id) ON DELETE RESTRICT;
alter table emergency_response_roster add constraint emergency_response_roster_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table emergency_response_roster add constraint emergency_response_roster_team_id_fkey FOREIGN KEY (team_id) REFERENCES maintenance_teams(id) ON DELETE CASCADE;
alter table emergency_response_roster add constraint emergency_response_roster_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE SET NULL;
alter table activity_logs add constraint activity_logs_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE;
alter table notification_outbox add constraint notification_outbox_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE;
alter table notification_outbox add constraint notification_outbox_recipient_profile_id_fkey FOREIGN KEY (recipient_profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table evidence_items add constraint evidence_items_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table evidence_items add constraint evidence_items_incident_id_fkey FOREIGN KEY (incident_id) REFERENCES incidents(id) ON DELETE CASCADE;
alter table evidence_items add constraint evidence_items_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table asset_systems add constraint asset_systems_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table asset_systems add constraint asset_systems_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table assets add constraint assets_system_id_fkey FOREIGN KEY (system_id) REFERENCES asset_systems(id) ON DELETE RESTRICT;
alter table assets add constraint assets_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
alter table assets add constraint assets_responsible_team_id_fkey FOREIGN KEY (responsible_team_id) REFERENCES maintenance_teams(id) ON DELETE RESTRICT;
alter table assets add constraint assets_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table assets add constraint assets_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE RESTRICT NOT VALID;
alter table incidents add constraint incidents_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE RESTRICT;
alter table activity_logs add constraint activity_logs_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE RESTRICT;
alter table maintenance_requirements add constraint maintenance_requirements_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE RESTRICT;
alter table maintenance_requirements add constraint maintenance_requirements_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table maintenance_requirements add constraint maintenance_requirements_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_requirement_id_fkey FOREIGN KEY (requirement_id) REFERENCES maintenance_requirements(id) ON DELETE RESTRICT;
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_department_id_fkey FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT;
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_responsible_team_id_fkey FOREIGN KEY (responsible_team_id) REFERENCES maintenance_teams(id) ON DELETE RESTRICT;
alter table maintenance_requirement_revisions add constraint maintenance_requirement_revisions_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table maintenance_requirements add constraint maintenance_requirements_current_revision_fkey FOREIGN KEY (current_revision_id) REFERENCES maintenance_requirement_revisions(id) ON DELETE RESTRICT;
alter table pm_occurrences add constraint pm_occurrences_requirement_id_fkey FOREIGN KEY (requirement_id) REFERENCES maintenance_requirements(id) ON DELETE RESTRICT;
alter table pm_occurrences add constraint pm_occurrences_requirement_revision_id_fkey FOREIGN KEY (requirement_revision_id) REFERENCES maintenance_requirement_revisions(id) ON DELETE RESTRICT;
alter table pm_occurrences add constraint pm_occurrences_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE RESTRICT;
alter table pm_occurrences add constraint pm_occurrences_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table pm_occurrence_deferrals add constraint pm_occurrence_deferrals_occurrence_id_fkey FOREIGN KEY (occurrence_id) REFERENCES pm_occurrences(id) ON DELETE RESTRICT;
alter table pm_occurrence_deferrals add constraint pm_occurrence_deferrals_deferred_by_fkey FOREIGN KEY (deferred_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_pm_occurrence_fkey FOREIGN KEY (pm_occurrence_id) REFERENCES pm_occurrences(id) ON DELETE RESTRICT;
alter table activity_logs add constraint activity_logs_maintenance_requirement_id_fkey FOREIGN KEY (maintenance_requirement_id) REFERENCES maintenance_requirements(id) ON DELETE RESTRICT;
alter table activity_logs add constraint activity_logs_pm_occurrence_id_fkey FOREIGN KEY (pm_occurrence_id) REFERENCES pm_occurrences(id) ON DELETE RESTRICT;
alter table notification_outbox add constraint notification_outbox_pm_occurrence_id_fkey FOREIGN KEY (pm_occurrence_id) REFERENCES pm_occurrences(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_sla_service_category_id_fkey FOREIGN KEY (sla_service_category_id) REFERENCES service_categories(id) ON DELETE RESTRICT;
alter table sla_agreements add constraint sla_agreements_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table sla_agreement_versions add constraint sla_agreement_versions_agreement_id_fkey FOREIGN KEY (agreement_id) REFERENCES sla_agreements(id) ON DELETE RESTRICT;
alter table sla_agreement_versions add constraint sla_agreement_versions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id);
alter table sla_agreement_versions add constraint sla_agreement_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table sla_rules add constraint sla_rules_version_id_fkey FOREIGN KEY (version_id) REFERENCES sla_agreement_versions(id) ON DELETE CASCADE;
alter table sla_rules add constraint sla_rules_service_category_id_fkey FOREIGN KEY (service_category_id) REFERENCES service_categories(id);
alter table sla_extraction_proposals add constraint sla_extraction_proposals_agreement_id_fkey FOREIGN KEY (agreement_id) REFERENCES sla_agreements(id);
alter table sla_extraction_proposals add constraint sla_extraction_proposals_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id);
alter table sla_extraction_proposals add constraint sla_extraction_proposals_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table work_order_sla_clocks add constraint work_order_sla_clocks_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table work_order_sla_clocks add constraint work_order_sla_clocks_sla_rule_id_fkey FOREIGN KEY (sla_rule_id) REFERENCES sla_rules(id) ON DELETE RESTRICT;
alter table escalation_matrix_steps add constraint escalation_matrix_steps_version_id_fkey FOREIGN KEY (version_id) REFERENCES sla_agreement_versions(id) ON DELETE CASCADE;
alter table sla_escalation_events add constraint sla_escalation_events_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table sla_escalation_events add constraint sla_escalation_events_matrix_step_id_fkey FOREIGN KEY (matrix_step_id) REFERENCES escalation_matrix_steps(id);
alter table sla_escalation_events add constraint sla_escalation_events_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES profiles(id);
alter table buildings add constraint buildings_site_id_fkey FOREIGN KEY (site_id) REFERENCES sites(id);
alter table location_levels add constraint location_levels_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id);
alter table location_zones add constraint location_zones_level_id_fkey FOREIGN KEY (level_id) REFERENCES location_levels(id);
alter table assets add constraint assets_location_zone_id_fkey FOREIGN KEY (location_zone_id) REFERENCES location_zones(id) ON DELETE SET NULL;
alter table report_schedules add constraint report_schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table report_runs add constraint report_runs_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES report_schedules(id);
alter table report_runs add constraint report_runs_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES profiles(id);
alter table sla_documents add constraint sla_documents_agreement_id_fkey FOREIGN KEY (agreement_id) REFERENCES sla_agreements(id);
alter table sla_documents add constraint sla_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id);
alter table sla_extraction_proposals add constraint sla_extraction_proposals_document_id_fkey FOREIGN KEY (document_id) REFERENCES sla_documents(id) ON DELETE RESTRICT;
alter table sla_extraction_proposals add constraint sla_extraction_proposals_approved_rule_id_fkey FOREIGN KEY (approved_rule_id) REFERENCES sla_rules(id);
alter table sla_extraction_proposals add constraint sla_extraction_proposals_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id);
alter table staffing_assessments add constraint staffing_assessments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
alter table staffing_recommendations add constraint staffing_recommendations_assessment_id_fkey FOREIGN KEY (assessment_id) REFERENCES staffing_assessments(id) ON DELETE CASCADE;
alter table staffing_recommendations add constraint staffing_recommendations_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES profiles(id);
alter table ai_provider_configurations add constraint ai_provider_configurations_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id);
alter table ai_prompt_versions add constraint ai_prompt_versions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id);
alter table ai_operation_audit add constraint ai_operation_audit_document_id_fkey FOREIGN KEY (document_id) REFERENCES sla_documents(id);
alter table ai_operation_audit add constraint ai_operation_audit_requesting_user_fkey FOREIGN KEY (requesting_user) REFERENCES profiles(id);
alter table contractor_services add constraint contractor_services_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE CASCADE;
alter table contractor_services add constraint contractor_services_service_category_id_fkey FOREIGN KEY (service_category_id) REFERENCES contractor_service_categories(id) ON DELETE RESTRICT;
alter table contractor_rate_items add constraint contractor_rate_items_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table contractor_rate_items add constraint contractor_rate_items_service_category_id_fkey FOREIGN KEY (service_category_id) REFERENCES contractor_service_categories(id) ON DELETE RESTRICT;
alter table work_order_cost_lines add constraint work_order_cost_lines_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table work_order_cost_lines add constraint work_order_cost_lines_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table work_order_cost_lines add constraint work_order_cost_lines_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES contractor_rate_items(id) ON DELETE RESTRICT;
alter table work_order_cost_lines add constraint work_order_cost_lines_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_cost_lines add constraint work_order_cost_lines_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_payment_assessments add constraint contractor_payment_assessments_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table contractor_payment_assessments add constraint contractor_payment_assessments_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table contractor_payment_assessments add constraint contractor_payment_assessments_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_facility_area_id_fkey FOREIGN KEY (facility_area_id) REFERENCES facility_areas(id) ON DELETE SET NULL;
alter table authorised_work_liaisons add constraint authorised_work_liaisons_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table evidence_items add constraint evidence_items_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES sites(id) ON DELETE RESTRICT;
alter table facility_areas add constraint facility_areas_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES sites(id) ON DELETE RESTRICT;
alter table assets add constraint assets_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES sites(id) ON DELETE RESTRICT;
alter table facility_memberships add constraint facility_memberships_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES sites(id) ON DELETE RESTRICT;
alter table facility_memberships add constraint facility_memberships_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table facility_memberships add constraint facility_memberships_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_approval_basis add constraint work_order_approval_basis_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_approval_basis add constraint work_order_approval_basis_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_quotations add constraint contractor_quotations_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table contractor_quotations add constraint contractor_quotations_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table contractor_quotations add constraint contractor_quotations_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_quotations add constraint contractor_quotations_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_quotation_lines add constraint contractor_quotation_lines_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES contractor_quotations(id) ON DELETE CASCADE;
alter table contractor_quotation_lines add constraint contractor_quotation_lines_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES contractor_rate_items(id) ON DELETE RESTRICT;
alter table contractor_actual_imports add constraint contractor_actual_imports_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table contractor_actual_imports add constraint contractor_actual_imports_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table contractor_actual_imports add constraint contractor_actual_imports_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES contractor_quotations(id) ON DELETE RESTRICT;
alter table contractor_actual_imports add constraint contractor_actual_imports_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_import_id_fkey FOREIGN KEY (import_id) REFERENCES contractor_actual_imports(id) ON DELETE CASCADE;
alter table contractor_actual_import_lines add constraint contractor_actual_import_lines_rate_item_id_fkey FOREIGN KEY (rate_item_id) REFERENCES contractor_rate_items(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_actual_costs_confirmed_by_fkey FOREIGN KEY (actual_costs_confirmed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_markups add constraint work_order_markups_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_markups add constraint work_order_markups_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES contractor_quotations(id) ON DELETE RESTRICT;
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_procurement_commitments add constraint work_order_procurement_commitments_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_markups add constraint work_order_markups_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_financial_controls add constraint work_order_financial_controls_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_financial_controls add constraint work_order_financial_controls_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES commercial_approval_rules(id) ON DELETE RESTRICT;
alter table work_order_financial_controls add constraint work_order_financial_controls_recommended_by_fkey FOREIGN KEY (recommended_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_financial_controls add constraint work_order_financial_controls_financial_approved_by_fkey FOREIGN KEY (financial_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_quotations add constraint contractor_quotations_prepared_by_fkey FOREIGN KEY (prepared_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_payment_assessments add constraint contractor_payment_assessments_recommended_by_fkey FOREIGN KEY (recommended_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table contractor_payment_assessments add constraint contractor_payment_assessments_paid_by_fkey FOREIGN KEY (paid_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_commercial_documents add constraint work_order_commercial_documents_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_commercial_documents add constraint work_order_commercial_documents_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES contractor_quotations(id) ON DELETE RESTRICT;
alter table work_order_commercial_documents add constraint work_order_commercial_documents_payment_assessment_id_fkey FOREIGN KEY (payment_assessment_id) REFERENCES contractor_payment_assessments(id) ON DELETE RESTRICT;
alter table work_order_commercial_documents add constraint work_order_commercial_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_document_corrections add constraint work_order_document_corrections_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_document_corrections add constraint work_order_document_corrections_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_document_corrections add constraint work_order_document_corrections_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_commercial_documents add constraint work_order_commercial_documents_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES work_order_commercial_documents(id) ON DELETE RESTRICT;
alter table work_order_commercial_documents add constraint work_order_commercial_documents_superseded_by_user_fkey FOREIGN KEY (superseded_by_user) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_orders add constraint work_orders_recommended_vendor_id_fkey FOREIGN KEY (recommended_vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table vendor_facility_eligibility add constraint vendor_facility_eligibility_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES vendors(id) ON DELETE RESTRICT;
alter table vendor_facility_eligibility add constraint vendor_facility_eligibility_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES sites(id) ON DELETE RESTRICT;
alter table vendor_facility_eligibility add constraint vendor_facility_eligibility_confirmed_by_fkey FOREIGN KEY (confirmed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_final_cost_submissions add constraint work_order_final_cost_submissions_variance_approved_by_fkey FOREIGN KEY (variance_approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_final_cost_submission_id_fkey FOREIGN KEY (final_cost_submission_id) REFERENCES work_order_final_cost_submissions(id) ON DELETE RESTRICT;
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_final_cost_documents add constraint work_order_final_cost_documents_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES work_order_final_cost_documents(id) ON DELETE RESTRICT;
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE RESTRICT;
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_proposed_by_fkey FOREIGN KEY (proposed_by) REFERENCES profiles(id) ON DELETE RESTRICT;
alter table work_order_financial_dispositions add constraint work_order_financial_dispositions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES profiles(id) ON DELETE RESTRICT;
CREATE INDEX profiles_role_active_idx ON public.profiles USING btree (role, is_active) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX profiles_email_lower_idx ON public.profiles USING btree (lower(email)) WHERE ((email IS NOT NULL) AND (deleted_at IS NULL));
CREATE UNIQUE INDEX account_invitations_open_email_idx ON public.account_invitations USING btree (lower(email)) WHERE ((used_at IS NULL) AND (is_active = true));
CREATE INDEX work_orders_assigned_technician_idx ON public.work_orders USING btree (assigned_technician_id) WHERE (assigned_technician_id IS NOT NULL);
CREATE INDEX notification_outbox_delivery_idx ON public.notification_outbox USING btree (delivery_status, available_at, created_at);
CREATE UNIQUE INDEX departments_code_active_unique_idx ON public.departments USING btree (lower(code)) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX departments_name_active_unique_idx ON public.departments USING btree (lower(name)) WHERE (deleted_at IS NULL);
CREATE INDEX departments_manager_idx ON public.departments USING btree (manager_id) WHERE (deleted_at IS NULL);
CREATE INDEX departments_parent_idx ON public.departments USING btree (parent_department_id) WHERE (deleted_at IS NULL);
CREATE INDEX profiles_department_id_idx ON public.profiles USING btree (department_id) WHERE (deleted_at IS NULL);
CREATE INDEX vendors_active_idx ON public.vendors USING btree (active) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX maintenance_teams_name_active_unique_idx ON public.maintenance_teams USING btree (lower(name)) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX work_orders_work_order_number_key ON public.work_orders USING btree (work_order_number);
CREATE INDEX work_orders_status_created_idx ON public.work_orders USING btree (status, created_at DESC);
CREATE INDEX work_orders_department_idx ON public.work_orders USING btree (department_id);
CREATE INDEX work_orders_source_idx ON public.work_orders USING btree (source);
CREATE INDEX work_orders_due_date_idx ON public.work_orders USING btree (due_date);
CREATE INDEX work_orders_requested_by_idx ON public.work_orders USING btree (requested_by);
CREATE INDEX work_orders_assigned_vendor_idx ON public.work_orders USING btree (assigned_vendor_id);
CREATE INDEX work_orders_assigned_team_idx ON public.work_orders USING btree (assigned_team_id);
CREATE UNIQUE INDEX notification_outbox_event_recipient_channel_idx ON public.notification_outbox USING btree (event_key, COALESCE(recipient_profile_id, recipient_user_id), COALESCE(recipient_email, ''::text), COALESCE(channel, ''::text));
CREATE INDEX incidents_active_priority_idx ON public.incidents USING btree (status, severity, reported_at DESC) WHERE (status <> ALL (ARRAY['closed'::text, 'cancelled'::text]));
CREATE INDEX incidents_ack_deadline_idx ON public.incidents USING btree (acknowledgement_deadline) WHERE ((acknowledged_at IS NULL) AND (status <> ALL (ARRAY['closed'::text, 'cancelled'::text])));
CREATE INDEX incidents_technician_idx ON public.incidents USING btree (assigned_technician_id, reported_at DESC);
CREATE INDEX incidents_team_idx ON public.incidents USING btree (assigned_team_id, reported_at DESC);
CREATE INDEX work_orders_incident_idx ON public.work_orders USING btree (incident_id) WHERE (incident_id IS NOT NULL);
CREATE INDEX activity_logs_incident_idx ON public.activity_logs USING btree (incident_id, created_at DESC) WHERE (incident_id IS NOT NULL);
CREATE INDEX emergency_roster_resolution_idx ON public.emergency_response_roster USING btree (active, incident_type, escalation_order);
CREATE INDEX notification_outbox_incident_idx ON public.notification_outbox USING btree (incident_id, channel, delivery_status, created_at DESC) WHERE (incident_id IS NOT NULL);
CREATE INDEX evidence_work_order_idx ON public.evidence_items USING btree (work_order_id, uploaded_at DESC) WHERE (work_order_id IS NOT NULL);
CREATE INDEX evidence_incident_idx ON public.evidence_items USING btree (incident_id, uploaded_at DESC) WHERE (incident_id IS NOT NULL);
CREATE INDEX activity_logs_work_order_action_idx ON public.activity_logs USING btree (work_order_id, action, created_at DESC, id DESC) WHERE (work_order_id IS NOT NULL);
CREATE UNIQUE INDEX asset_systems_code_unique_idx ON public.asset_systems USING btree (lower(system_code));
CREATE INDEX asset_systems_site_idx ON public.asset_systems USING btree (lower(site), is_active);
CREATE UNIQUE INDEX assets_tag_unique_idx ON public.assets USING btree (lower(asset_tag));
CREATE INDEX assets_name_idx ON public.assets USING btree (lower(name));
CREATE INDEX assets_system_idx ON public.assets USING btree (system_id) WHERE (system_id IS NOT NULL);
CREATE INDEX assets_status_criticality_idx ON public.assets USING btree (lifecycle_status, criticality);
CREATE INDEX assets_site_idx ON public.assets USING btree (lower(site));
CREATE INDEX assets_department_idx ON public.assets USING btree (department_id) WHERE (department_id IS NOT NULL);
CREATE INDEX assets_team_idx ON public.assets USING btree (responsible_team_id) WHERE (responsible_team_id IS NOT NULL);
CREATE INDEX work_orders_asset_idx ON public.work_orders USING btree (asset_id) WHERE (asset_id IS NOT NULL);
CREATE INDEX incidents_asset_idx ON public.incidents USING btree (asset_id) WHERE (asset_id IS NOT NULL);
CREATE INDEX activity_logs_asset_idx ON public.activity_logs USING btree (asset_id, created_at DESC) WHERE (asset_id IS NOT NULL);
CREATE INDEX maintenance_requirements_asset_state_idx ON public.maintenance_requirements USING btree (asset_id, state);
CREATE INDEX maintenance_revisions_effective_idx ON public.maintenance_requirement_revisions USING btree (requirement_id, effective_date DESC, revision_number DESC);
CREATE INDEX pm_occurrences_due_status_idx ON public.pm_occurrences USING btree (current_due_date, generation_status);
CREATE INDEX pm_occurrences_asset_due_idx ON public.pm_occurrences USING btree (asset_id, current_due_date DESC);
CREATE INDEX pm_occurrences_failed_idx ON public.pm_occurrences USING btree (current_due_date) WHERE (generation_status = 'generation_failed'::text);
CREATE INDEX pm_deferrals_occurrence_idx ON public.pm_occurrence_deferrals USING btree (occurrence_id, deferred_at DESC);
CREATE UNIQUE INDEX work_orders_pm_occurrence_unique_idx ON public.work_orders USING btree (pm_occurrence_id) WHERE (pm_occurrence_id IS NOT NULL);
CREATE INDEX activity_logs_pm_requirement_idx ON public.activity_logs USING btree (maintenance_requirement_id, created_at DESC) WHERE (maintenance_requirement_id IS NOT NULL);
CREATE INDEX activity_logs_pm_occurrence_idx ON public.activity_logs USING btree (pm_occurrence_id, created_at DESC) WHERE (pm_occurrence_id IS NOT NULL);
CREATE INDEX notification_outbox_pm_occurrence_idx ON public.notification_outbox USING btree (pm_occurrence_id, delivery_status, created_at DESC) WHERE (pm_occurrence_id IS NOT NULL);
CREATE INDEX profiles_account_readiness_idx ON public.profiles USING btree (is_active, password_change_required, role) WHERE (deleted_at IS NULL);
CREATE INDEX profiles_last_active_at_idx ON public.profiles USING btree (last_active_at DESC) WHERE ((is_active = true) AND (deleted_at IS NULL));
CREATE INDEX evidence_items_active_work_order_idx ON public.evidence_items USING btree (work_order_id, category) WHERE (deleted_at IS NULL);
CREATE INDEX work_orders_facility_idx ON public.work_orders USING btree (facility_id);
CREATE INDEX facility_areas_facility_idx ON public.facility_areas USING btree (facility_id, active);
CREATE INDEX assets_facility_idx ON public.assets USING btree (facility_id, lifecycle_status);
CREATE UNIQUE INDEX facility_memberships_active_unique_idx ON public.facility_memberships USING btree (facility_id, profile_id, membership_role) WHERE active;
CREATE INDEX facility_memberships_profile_lookup_idx ON public.facility_memberships USING btree (profile_id, facility_id) WHERE active;
CREATE INDEX contractor_quotations_work_order_idx ON public.contractor_quotations USING btree (work_order_id, status, quotation_date DESC);
CREATE INDEX contractor_quotation_lines_quote_idx ON public.contractor_quotation_lines USING btree (quotation_id, line_no);
CREATE UNIQUE INDEX contractor_actual_imports_source_uq ON public.contractor_actual_imports USING btree (work_order_id, source_sha256) WHERE (source_sha256 IS NOT NULL);
CREATE INDEX contractor_actual_imports_work_order_idx ON public.contractor_actual_imports USING btree (work_order_id, confirmed_at DESC);
CREATE INDEX contractor_actual_import_lines_import_idx ON public.contractor_actual_import_lines USING btree (import_id, line_no);
CREATE INDEX work_order_cost_lines_actual_idx ON public.work_order_cost_lines USING btree (work_order_id, created_at, id) WHERE (cost_phase = 'actual'::text);
CREATE INDEX work_order_commercial_documents_active_idx ON public.work_order_commercial_documents USING btree (work_order_id, document_type, uploaded_at DESC) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX work_order_document_corrections_one_open_idx ON public.work_order_document_corrections USING btree (work_order_id) WHERE (status = 'open'::text);
CREATE TRIGGER set_notification_outbox_updated_at BEFORE UPDATE ON public.notification_outbox FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER set_department_updated_at BEFORE INSERT OR UPDATE ON public.departments FOR EACH ROW EXECUTE FUNCTION set_department_updated_at();
CREATE TRIGGER sync_profile_department_label BEFORE INSERT OR UPDATE OF department_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION sync_profile_department_label();
CREATE TRIGGER assign_work_order_number BEFORE INSERT ON public.work_orders FOR EACH ROW EXECUTE FUNCTION assign_work_order_number();
CREATE TRIGGER protect_terminal_work_order BEFORE DELETE OR UPDATE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION protect_terminal_work_order();
CREATE TRIGGER assign_incident_number BEFORE INSERT ON public.incidents FOR EACH ROW EXECUTE FUNCTION assign_incident_number();
CREATE TRIGGER set_incidents_updated_at BEFORE UPDATE ON public.incidents FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER set_emergency_roster_updated_at BEFORE UPDATE ON public.emergency_response_roster FOR EACH ROW EXECUTE FUNCTION set_row_updated_at();
CREATE TRIGGER validate_emergency_roster_entry BEFORE INSERT OR UPDATE ON public.emergency_response_roster FOR EACH ROW EXECUTE FUNCTION validate_emergency_roster_entry();
CREATE TRIGGER validate_work_order_asset_link BEFORE INSERT OR UPDATE OF asset_id ON public.work_orders FOR EACH ROW EXECUTE FUNCTION validate_new_asset_link();
CREATE TRIGGER validate_incident_asset_link BEFORE INSERT OR UPDATE OF asset_id ON public.incidents FOR EACH ROW EXECUTE FUNCTION validate_new_asset_link();
CREATE TRIGGER protect_pm_revision BEFORE DELETE OR UPDATE ON public.maintenance_requirement_revisions FOR EACH ROW EXECUTE FUNCTION protect_pm_revision();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.incidents FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.emergency_response_roster FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.evidence_items FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.asset_systems FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.assets FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.maintenance_requirements FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.maintenance_requirement_revisions FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.pm_occurrences FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER enforce_pilot_actor_ready BEFORE INSERT OR DELETE OR UPDATE ON public.pm_occurrence_deferrals FOR EACH ROW EXECUTE FUNCTION enforce_pilot_actor_ready();
CREATE TRIGGER protect_profile_authorization_fields BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_authorization_fields();
CREATE TRIGGER protect_profile_deletion BEFORE DELETE ON public.profiles FOR EACH ROW EXECUTE FUNCTION protect_profile_deletion();
CREATE TRIGGER default_work_order_sla_category BEFORE INSERT ON public.work_orders FOR EACH ROW EXECUTE FUNCTION default_work_order_sla_category();
CREATE TRIGGER attach_approved_sla_clock AFTER INSERT ON public.work_orders FOR EACH ROW EXECUTE FUNCTION attach_approved_sla_clock();
CREATE TRIGGER assign_work_order_facility BEFORE INSERT OR UPDATE OF facility_id, asset_id, facility_area_id ON public.work_orders FOR EACH ROW EXECUTE FUNCTION assign_work_order_facility();
CREATE TRIGGER assign_asset_facility BEFORE INSERT OR UPDATE OF facility_id ON public.assets FOR EACH ROW EXECUTE FUNCTION assign_asset_facility();
CREATE TRIGGER assign_facility_area_facility BEFORE INSERT OR UPDATE OF facility_id ON public.facility_areas FOR EACH ROW EXECUTE FUNCTION assign_facility_area_facility();
alter table public.profiles enable row level security;
alter table public.account_invitations enable row level security;
alter table public.categories enable row level security;
alter table public.work_order_number_counters enable row level security;
alter table public.work_orders enable row level security;
alter table public.activity_logs enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.departments enable row level security;
alter table public.vendors enable row level security;
alter table public.maintenance_teams enable row level security;
alter table public.maintenance_team_members enable row level security;
alter table public.incident_number_counters enable row level security;
alter table public.incidents enable row level security;
alter table public.emergency_response_roster enable row level security;
alter table public.evidence_items enable row level security;
alter table public.asset_systems enable row level security;
alter table public.assets enable row level security;
alter table public.maintenance_requirement_number_counters enable row level security;
alter table public.maintenance_requirements enable row level security;
alter table public.maintenance_requirement_revisions enable row level security;
alter table public.pm_occurrences enable row level security;
alter table public.pm_occurrence_deferrals enable row level security;
alter table public.service_categories enable row level security;
alter table public.sla_agreements enable row level security;
alter table public.sla_agreement_versions enable row level security;
alter table public.sla_rules enable row level security;
alter table public.sla_extraction_proposals enable row level security;
alter table public.work_order_sla_clocks enable row level security;
alter table public.escalation_matrix_steps enable row level security;
alter table public.sla_escalation_events enable row level security;
alter table public.sites enable row level security;
alter table public.buildings enable row level security;
alter table public.location_levels enable row level security;
alter table public.location_zones enable row level security;
alter table public.report_schedules enable row level security;
alter table public.report_runs enable row level security;
alter table public.sla_documents enable row level security;
alter table public.staffing_assessments enable row level security;
alter table public.staffing_recommendations enable row level security;
alter table public.ai_provider_configurations enable row level security;
alter table public.ai_prompt_versions enable row level security;
alter table public.ai_operation_audit enable row level security;
alter table public.contractor_service_categories enable row level security;
alter table public.contractor_services enable row level security;
alter table public.contractor_rate_items enable row level security;
alter table public.work_order_cost_lines enable row level security;
alter table public.contractor_payment_assessments enable row level security;
alter table public.facility_areas enable row level security;
alter table public.authorised_work_liaisons enable row level security;
alter table public.facility_memberships enable row level security;
alter table public.work_order_approval_basis enable row level security;
alter table public.contractor_quotations enable row level security;
alter table public.contractor_quotation_lines enable row level security;
alter table public.contractor_actual_imports enable row level security;
alter table public.contractor_actual_import_lines enable row level security;
alter table public.work_order_markups enable row level security;
alter table public.work_order_procurement_commitments enable row level security;
alter table public.commercial_approval_rules enable row level security;
alter table public.work_order_financial_controls enable row level security;
alter table public.work_order_commercial_documents enable row level security;
alter table public.work_order_document_corrections enable row level security;
alter table public.vendor_facility_eligibility enable row level security;
alter table public.work_order_final_cost_submissions enable row level security;
alter table public.work_order_final_cost_documents enable row level security;
alter table public.work_order_financial_dispositions enable row level security;
create policy notification_outbox_read_admin on notification_outbox as permissive for select to authenticated using ((current_user_role() = 'administrator'::text));
create policy profiles_active_technicians_for_assigners on profiles as permissive for select to authenticated using (((role = 'technician'::text) AND (is_active = true) AND (deleted_at IS NULL) AND (current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text]))));
create policy emergency_roster_manage on emergency_response_roster as permissive for all to authenticated using (((current_user_role() = 'administrator'::text) OR ((current_user_role() = 'supervisor'::text) AND ((team_id IS NOT NULL) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = emergency_response_roster.profile_id) AND (p.role = ANY (ARRAY['technician'::text, 'supervisor'::text]))))))))) with check (((current_user_role() = 'administrator'::text) OR ((current_user_role() = 'supervisor'::text) AND ((team_id IS NOT NULL) OR (EXISTS ( SELECT 1
   FROM profiles p
  WHERE ((p.id = emergency_response_roster.profile_id) AND (p.role = ANY (ARRAY['technician'::text, 'supervisor'::text])))))))));
create policy asset_systems_authenticated_read on asset_systems as permissive for select to authenticated using (((current_user_role() IS NOT NULL) AND (is_active OR (current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])))));
create policy assets_authenticated_read on assets as permissive for select to authenticated using (((current_user_role() IS NOT NULL) AND ((lifecycle_status <> 'decommissioned'::text) OR (current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])) OR (EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.asset_id = assets.id))))));
create policy maintenance_requirements_read on maintenance_requirements as permissive for select to authenticated using (((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])) OR ((state = 'active'::text) AND (current_user_role() = ANY (ARRAY['reviewer'::text, 'initiator'::text]))) OR ((current_user_role() = 'technician'::text) AND (EXISTS ( SELECT 1
   FROM (pm_occurrences o
     JOIN work_orders w ON ((w.pm_occurrence_id = o.id)))
  WHERE ((o.requirement_id = maintenance_requirements.id) AND (w.assigned_technician_id = auth.uid())))))));
create policy maintenance_revisions_read on maintenance_requirement_revisions as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM maintenance_requirements r
  WHERE (r.id = maintenance_requirement_revisions.requirement_id))));
create policy pm_occurrences_read on pm_occurrences as permissive for select to authenticated using (((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])) OR ((current_user_role() = 'technician'::text) AND (EXISTS ( SELECT 1
   FROM work_orders w
  WHERE ((w.pm_occurrence_id = pm_occurrences.id) AND (w.assigned_technician_id = auth.uid())))))));
create policy pm_deferrals_read on pm_occurrence_deferrals as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM pm_occurrences o
  WHERE (o.id = pm_occurrence_deferrals.occurrence_id))));
create policy profiles_read_self_or_admin on profiles as permissive for select to authenticated using (((id = auth.uid()) OR (current_user_role() = 'administrator'::text)));
create policy profiles_update_self_or_admin on profiles as permissive for update to authenticated using ((pilot_account_ready(auth.uid()) AND ((id = auth.uid()) OR (current_user_role() = 'administrator'::text)))) with check ((pilot_account_ready(auth.uid()) AND ((id = auth.uid()) OR (current_user_role() = 'administrator'::text))));
create policy departments_authenticated_read on departments as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND ((deleted_at IS NULL) OR (current_user_role() = 'administrator'::text))));
create policy categories_read_authenticated on categories as permissive for select to authenticated using (pilot_account_ready(auth.uid()));
create policy vendors_authenticated_read on vendors as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (active = true) AND (deleted_at IS NULL)));
create policy maintenance_teams_authenticated_read on maintenance_teams as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (is_active = true) AND (deleted_at IS NULL)));
create policy maintenance_team_members_authenticated_read on maintenance_team_members as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (is_active = true)));
create policy incidents_authenticated_read on incidents as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])) OR (reported_by = auth.uid()) OR (assigned_technician_id = auth.uid()) OR ((assigned_team_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM maintenance_team_members member
  WHERE ((member.team_id = incidents.assigned_team_id) AND (member.profile_id = auth.uid()) AND member.is_active)))))));
create policy emergency_roster_authenticated_read on emergency_response_roster as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND ((current_user_role() = ANY (ARRAY['supervisor'::text, 'administrator'::text])) OR (profile_id = auth.uid()))));
create policy evidence_parent_authorized_read on evidence_items as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (((work_order_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM work_orders
  WHERE (work_orders.id = evidence_items.work_order_id)))) OR ((incident_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM incidents
  WHERE (incidents.id = evidence_items.incident_id)))))));
create policy activity_logs_read_permitted on activity_logs as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (((work_order_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = activity_logs.work_order_id)))) OR ((incident_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM incidents i
  WHERE (i.id = activity_logs.incident_id)))) OR ((asset_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM assets a
  WHERE (a.id = activity_logs.asset_id)))) OR ((maintenance_requirement_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM maintenance_requirements r
  WHERE (r.id = activity_logs.maintenance_requirement_id)))) OR ((pm_occurrence_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM pm_occurrences o
  WHERE (o.id = activity_logs.pm_occurrence_id)))) OR (current_user_role() = 'administrator'::text))));
create policy service_categories_management_read on service_categories as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy sla_agreements_management_read on sla_agreements as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy sla_agreement_versions_management_read on sla_agreement_versions as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy sla_rules_management_read on sla_rules as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy sla_extraction_proposals_management_read on sla_extraction_proposals as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy work_order_sla_clocks_management_read on work_order_sla_clocks as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy escalation_matrix_steps_management_read on escalation_matrix_steps as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy sla_escalation_events_management_read on sla_escalation_events as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy report_schedules_management_read on report_schedules as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy report_runs_management_read on report_runs as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy sites_authenticated_read on sites as permissive for select to authenticated using ((current_user_role() IS NOT NULL));
create policy buildings_authenticated_read on buildings as permissive for select to authenticated using ((current_user_role() IS NOT NULL));
create policy location_levels_authenticated_read on location_levels as permissive for select to authenticated using ((current_user_role() IS NOT NULL));
create policy location_zones_authenticated_read on location_zones as permissive for select to authenticated using ((current_user_role() IS NOT NULL));
create policy sla_documents_management_read on sla_documents as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy staffing_assessments_management_read on staffing_assessments as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy staffing_recommendations_management_read on staffing_recommendations as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy ai_config_management_read on ai_provider_configurations as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['supervisor'::text, 'administrator'::text])));
create policy ai_prompts_management_read on ai_prompt_versions as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['approver'::text, 'supervisor'::text, 'administrator'::text])));
create policy ai_audit_management_read on ai_operation_audit as permissive for select to authenticated using ((current_user_role() = ANY (ARRAY['supervisor'::text, 'administrator'::text])));
create policy authenticated_read on contractor_service_categories as permissive for select to authenticated using (pilot_account_ready());
create policy authenticated_read on contractor_services as permissive for select to authenticated using (pilot_account_ready());
create policy authenticated_read on contractor_rate_items as permissive for select to authenticated using (pilot_account_ready());
create policy authenticated_read on work_order_cost_lines as permissive for select to authenticated using (pilot_account_ready());
create policy authenticated_read on contractor_payment_assessments as permissive for select to authenticated using (pilot_account_ready());
create policy authenticated_read on facility_areas as permissive for select to authenticated using (pilot_account_ready());
create policy authenticated_read on authorised_work_liaisons as permissive for select to authenticated using (pilot_account_ready());
create policy facility_memberships_read_permitted on facility_memberships as permissive for select to authenticated using (((profile_id = auth.uid()) OR (current_user_role() = 'administrator'::text)));
create policy work_orders_read_permitted on work_orders as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (((current_user_role() = 'technician'::text) AND technician_facility_read_permitted(facility_id)) OR ((current_user_role() <> 'technician'::text) AND ((requested_by = auth.uid()) OR (assigned_technician_id = auth.uid()) OR (current_user_role() = ANY (ARRAY['approver'::text, 'administrator'::text])) OR supervisor_facility_permitted(facility_id) OR facility_manager_facility_permitted(facility_id))))));
create policy work_order_approval_basis_read_permitted on work_order_approval_basis as permissive for select to authenticated using ((pilot_account_ready(auth.uid()) AND (EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_approval_basis.work_order_id)))));
create policy work_order_markups_read on work_order_markups as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_markups.work_order_id))));
create policy work_order_procurement_read on work_order_procurement_commitments as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_procurement_commitments.work_order_id))));
create policy commercial_approval_rules_read on commercial_approval_rules as permissive for select to authenticated using (pilot_account_ready());
create policy work_order_financial_controls_read on work_order_financial_controls as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_financial_controls.work_order_id))));
create policy work_order_commercial_documents_read on work_order_commercial_documents as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_commercial_documents.work_order_id))));
create policy work_order_document_corrections_read on work_order_document_corrections as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_document_corrections.work_order_id))));
create policy vendor_facility_eligibility_read on vendor_facility_eligibility as permissive for select to authenticated using (pilot_account_ready());
create policy final_cost_read on work_order_final_cost_submissions as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_final_cost_submissions.work_order_id))));
create policy final_cost_documents_read on work_order_final_cost_documents as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_final_cost_documents.work_order_id))));
create policy work_order_financial_dispositions_read on work_order_financial_dispositions as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM work_orders w
  WHERE (w.id = work_order_financial_dispositions.work_order_id))));
