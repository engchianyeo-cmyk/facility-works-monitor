-- -- ===========================================
-- Facility Works Monitor
-- Migration : 0002_workflow_update.sql
-- Version   : 2.0
-- Author    : EC Yeo
-- Purpose   : Upgrade work order workflow
-- Date      : 2026-07-14
-- ===========================================

-- Existing Workflow
-- submitted
-- approved
-- in_progress
-- done
-- rejected

-- New Workflow
-- submitted
-- reviewed
-- approved
-- assigned
-- accepted
-- in_progress
-- completed
-- verified
-- closed
-- rejected


-- ===========================================
-- Step 1
-- Convert existing status values
-- ===========================================

UPDATE work_orders
SET status = 'completed'
WHERE status = 'done';


-- ===========================================
-- Step 2
-- Remove old status constraint
-- ===========================================

ALTER TABLE work_orders
DROP CONSTRAINT IF EXISTS work_orders_status_check;


-- ===========================================
-- Step 3
-- Create new status constraint
-- ===========================================

ALTER TABLE work_orders
ADD CONSTRAINT work_orders_status_check
CHECK
(
    status IN
    (
        'submitted',
        'reviewed',
        'approved',
        'assigned',
        'accepted',
        'in_progress',
        'completed',
        'verified',
        'closed',
        'rejected'
    )
);

-- ===========================================
-- End of Migration
-- ===========================================
