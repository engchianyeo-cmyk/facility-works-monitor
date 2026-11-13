# D-50 / D-53 build plan — Facility One, Facility 2, Facility Administrators and the Super-Administrator

Status: plan, 12 November 2026 23:20 (owner: "Yes, proceed" to planning). Nothing is built or applied yet.
Decisions: D-50 (11 Nov), D-53 (12 Nov). Branch `uat/claude-review`; Preview `pvajuywwwpjlikqjnvgv` only after
`release:verify` passes locally and the owner has reviewed it. Production is not touched.

## What the app does today (found in the code)

- One global `administrator` role: about 90 checks in the database and about 117 in the app treat it as all-powerful
  across every facility. It is also an approval authority and a field execution role.
- Accounts belong to the app; `facility_memberships` links Technicians, Approvers, Supervisors and Facility Managers
  to a facility. Work Order visibility already follows those memberships, except Administrators and Finance, who see
  every facility.
- No facility switch; no facility filter on the Work Orders list; the trial facility still has its trial name.

## Approach (lowest risk)

Keep the existing `administrator` role as the **Super-Administrator** (every existing check keeps its meaning, so
nothing that works today loses power by accident). Add a **new, narrow role `facility_administrator`**, linked to
facilities through `facility_memberships`, which gets only the powers listed below, each granted explicitly.

## Phases

1. **Rename** in the app (Facilities › Details): "FMWorks UAT Facility" (UAT-FAC-001) -> "Facility One"; code kept.
2. **Migration M29** `facility_administrator`:
   - role added to the profile role check and `USER_ROLES`; membership role allowed;
   - helper `facility_administrator_permitted(facility_id)`;
   - for its own facilities only: facility details, areas, drawings, staff, settings (Designated Approver,
     endorsement), area locations on drawings, read all its Work Orders, notices, Facility Overview, contractor
     directory; create user accounts that are added to its facility at once (never Administrator or
     Super-Administrator accounts);
   - cannot: add facilities, see other facilities, change approval limits or app-wide settings (terminology,
     procurement policy, departments), or approve/execute Work Orders;
   - SQL tests for each allowed and refused action.
3. **App**: label the `administrator` role "Super-Administrator"; Facilities and Users pages show a Facility
   Administrator only its facilities and their staff; a **facility switch** in the header (Super-Administrator and
   anyone in more than one facility: "All facilities / Facility One / Facility 2"), remembered per browser, which
   filters the Work Orders list, Operations Workspace, notices and Finance lists; a Facility filter on the Work Orders
   list.
4. **D-53 for engchian.yeo@gmail.com** (depends on the owner's answers below).
5. **Checks**: unit and SQL tests, `release:verify`, owner review, then Preview (migration + rename script), then
   UAT: create the Facility 2 Administrator, Approver, two Technicians, Finance; confirm Facility 2 staff cannot see
   Facility One and the reverse.

## Owner answers (D-54)

Super-Administrator keeps emergency approval/field powers (audited reason); Facility Administrator may create
accounts for its own facility only; Finance per facility (existing Finance added to Facility One); Super-Administrator
starts on "All facilities".
