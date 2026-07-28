# Phase 2B-2C Authentication and Authorization Design

This design is staged. The SQL in `0004_auth_foundation.sql` is review-only and
must not be applied until the application rollout and recovery plan are
approved.

## Roles and permissions

| Capability | Reviewer | Initiator | Approver | Technician | Supervisor | Administrator |
|---|---:|---:|---:|---:|---:|---:|
| Register and sign in | Yes | Assigned role | Assigned role | Assigned role | Assigned role | Assigned role |
| Create work orders | Yes | Yes | Yes | No by default | Yes | Yes |
| View own work orders | Yes | Yes | Yes | Assigned only | Yes | Yes |
| Edit own submitted work | Yes | Yes | Authorized | No | Yes | Yes |
| Approve or reject | No | No | Yes | No | Yes | Yes |
| Assign personnel | No | No | Yes | No | Yes | Yes |
| Accept/start assigned work | No | No | No | Yes | Yes | Yes |
| Add progress notes | No | No | No | Yes | Yes | Yes |
| Complete assigned work | No | No | No | Yes | Yes | Yes |
| Verify completed work | No | Yes | No | No | Yes | Yes |
| Manage roles/users | No | No | No | No | No | Yes |
| Permanent deletion | No | No | No | No | No | Controlled admin workflow only |

Self-registration always creates a `reviewer`. Higher roles are assigned by an
administrator through a future controlled user-management interface.

## Rollout stages

1. Review and back up the live database.
2. Apply `0004_auth_foundation.sql` in a controlled non-production environment.
3. Verify profiles, 24 deterministic work-order references, counters, indexes,
   and policies.
4. Create test users through Supabase Authentication; do not store passwords in
   source control.
5. Verify each role against both UI and API routes.
6. Only then schedule the live migration and RLS cutover.

Stage C must authorize actions in API routes as well as hide unavailable UI
controls. UI-only authorization is not security.

## Work-order references

References use `FW-YYYY-NNNN`. A per-year counter row is incremented atomically
inside PostgreSQL, so concurrent inserts cannot receive the same reference.
The UUID remains the primary key.

For the current 24 rows, deterministic ordering is `created_at ASC, id ASC`.
If all current rows are from 2026, the proposed range is `FW-2026-0001` through
`FW-2026-0024`. The migration calculates this from live data rather than
assuming row order.

References are never renumbered after assignment.

## Existing identities

Legacy `submitted_by` and `activity_logs.actor` text remains readable. New
authenticated records use `user_id` for identity and cache the profile display
name in the existing text fields for historical readability.

Fallback display order is:

1. Profile display name.
2. Existing text identity.
3. Email local part.
4. `Unknown user`.

## Drawings

Drawing document numbers such as `FW-001` through `FW-004` remain independent
document identifiers. A future attachments/drawings table should map them to a
work-order UUID/reference. Drawing filenames must not become work-order primary
keys, and no drawing is attached arbitrarily during this phase.

## Security notes

The current demo policies allow anonymous reads and writes to categories, work
orders, and activity logs. The proposed policies require authenticated users,
preserve transitional visibility of legacy work orders, scope reviewers and
initiators to their own records, scope technicians to assigned records, and
reserve deletion for administrators.

RLS cannot by itself express every workflow transition or prevent all
column-level changes. API-side role and transition authorization remains
mandatory before Stage C is enabled.
