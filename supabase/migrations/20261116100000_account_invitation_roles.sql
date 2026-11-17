-- M30 (16 Nov 2026, found in UAT): creating a Facility Administrator failed with "The user provisioning request could
-- not be prepared". Two old checks on the provisioning ticket (account_invitations) still listed the roles of
-- October: one lacked Facility Manager and Finance, both lacked Facility Administrator. The profile itself already
-- allows every role (M29), so the ticket now allows the same nine roles.
begin;

alter table public.account_invitations drop constraint if exists account_invitations_assigned_role_check;
alter table public.account_invitations drop constraint if exists account_invitations_role_check;
alter table public.account_invitations add constraint account_invitations_role_check check (assigned_role in (
  'reviewer','initiator','approver','technician','supervisor','facility_manager','administrator','finance','facility_administrator'));

commit;
