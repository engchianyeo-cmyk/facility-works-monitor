-- ===========================================
-- Facility Works Monitor
-- Migration : 0003_assignment.sql
-- Version   : 3.0
-- Author    : EC Yeo
-- Purpose   : Technician / Vendor Assignment
-- Date      : 2026-07-16
-- ===========================================

ALTER TABLE work_orders

ADD COLUMN IF NOT EXISTS assigned_technician_id UUID,

ADD COLUMN IF NOT EXISTS assigned_vendor_id UUID,

ADD COLUMN IF NOT EXISTS assigned_by TEXT,

ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ,

ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,

ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,

ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,

ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;