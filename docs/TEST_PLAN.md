# Test Plan — Facility Works Monitor

## Core Success Scenario (manual)
1. Open live URL in incognito — dashboard loads with status count cards (no login prompt)
2. Navigate to `/works` — 5+ work orders visible with correct status badges
3. Click the `In Progress` order — detail page shows all fields and activity log entries
4. Click **Complete** — status badge changes to `Done`; activity log prepends new entry with current timestamp
5. Return to dashboard — `Done` count incremented by 1; `In Progress` count decremented
6. Reload detail page — `Done` status persists (server state, not local)

## Submit Form
7. Click **Submit Work Order** — form renders with all fields
8. Submit with required fields empty — inline validation errors appear, no network call
9. Fill all required fields, submit — redirected to new order detail page; order appears in list

## Empty & Error States
10. Filter by `Rejected` (none exist in seed) — empty state message shown, not a blank page
11. Kill internet / set Supabase URL to wrong value — list shows error banner, not a crash
12. Click **Approve** on an already-approved order — UI shows error toast (invalid transition)

## Status Machine
13. `submitted` order shows only Approve and Reject buttons (not Start or Complete)
14. `approved` order shows only Start and Reject buttons
15. `in_progress` order shows only Complete and Reject buttons
16. `done` / `rejected` orders show no action buttons

## Loading States
17. Throttle network to Slow 3G — skeleton loaders appear on list and dashboard before data loads
18. Work order detail shows skeleton while fetching, not a blank white screen

## Data Integrity
19. Every status change: verify new row in `activity_logs` with correct `from_status`, `to_status`, `actor`, and `created_at`
20. Reject action without a note — blocked with validation error; note required