# Release 1.2 Schema Reconciliation — WP-REL-001

**Assessment date:** 11 August 2026

**Decision:** AMBER — 0014 is locally validated, but remote rollout is blocked because no verified non-production target or recoverable backup strategy is available.

## Environment inventory

| Environment | Safe identifier | Relationship | Migration state |
|---|---|---|---|
| Disposable local PostgreSQL 15 | Docker container `fmworks-wp-rel-001-pg` | SQL regression only; removed after validation | 0012 → 0013 → 0014 passed |
| Local application target | Supabase project `pyapukytcrsuowmgzqzh` | `.env.local`; production/preview relationship not documented | Read-only REST probes indicate 0012–0014 objects absent; history metadata unavailable |
| Preview/test | Not configured or identifiable | None proven | Unknown; no rollout authorized |
| Production | Not safely identifiable from local metadata | Must be treated as potentially production | No write attempted; rollout prohibited |

No credential values, tokens or connection strings are recorded here.

## Migration inventory

| Migration | Configured remote assessment | Confidence / evidence |
|---|---|---|
| 0011 secure legacy tables | Unknown | Behavior cannot establish policies/function grants; migration history is inaccessible |
| 0012 department foundation | Not represented | `departments` returned PostgREST 404 rather than an RLS response |
| 0013 core work-order engine | Not represented | `vendors` returned PostgREST 404; full migration metadata unavailable |
| 0014 emergency incidents | Not represented | `incidents` and `emergency_response_roster` returned PostgREST 404 |

`notification_outbox` also returned 404. These are object probes, not a substitute for `supabase_migrations.schema_migrations` or catalog reconciliation. Before any persistent rollout, an authorized database connection must capture exact migration history, catalogs, grants, policies, constraints, row counts and schema fingerprints.

## Disposable regression

The initial run using the 0013 prerequisite fixture failed safely at 0014 because that fixture does not create `notification_outbox`. No migration transaction was committed for 0014. A clean rerun used the approved `0014_prerequisite_schema.sql`, which includes the 0013 fixture and outbox prerequisite.

Final clean chain:

1. `tests/sql/0014_prerequisite_schema.sql` — PASS
2. `supabase/migrations/0012_department_management_foundation.sql` — PASS
3. `supabase/migrations/0013_core_work_order_engine.sql` — PASS
4. `supabase/migrations/0014_emergency_incident_management.sql` — PASS
5. `tests/sql/0014_emergency_incident_management.test.sql` — PASS
6. `tests/sql/0013_core_work_order_engine.test.sql` — PASS

The temporary container was removed. The final chain completed in approximately 2.3 seconds on local disposable infrastructure; this is not a remote execution-time guarantee.

The incident-number correction remains present and tested: `next_incident_number` qualifies the counter update as `public.incident_number_counters.last_value + 1`, and the SQL suite verifies formatted unique creation.

## 0014 change inventory

### Creates

- Tables: `incident_number_counters`, `incidents`, `emergency_response_roster`.
- Functions: `next_incident_number`, `assign_incident_number`, `validate_emergency_roster_entry`, `incident_result_error`, `create_incident`, `assign_incident`, `transition_incident`, `record_incident_notification_result`, `link_work_order_to_incident`.
- Triggers: incident numbering, incident/roster `updated_at`, roster validation.
- Nine operational/relationship indexes, including incident priority/deadline, responder, linkage and outbox indexes.
- RLS policies for incident visibility, roster visibility/management and related activity-log visibility.

### Alters

- `profiles`: adds `whatsapp_number`.
- `work_orders`: adds nullable `incident_id`, validated foreign key and partial index.
- `activity_logs`: adds nullable `incident_id`, validated foreign key, index and replacement read policy.
- `notification_outbox`: permits null `work_order_id`; adds incident, recipient, channel/provider/result/retry fields; replaces deduplication and target constraints; adds incident index.
- Grants/revokes direct writes and narrows function execution to authenticated callers as defined by the migration.

### Data impact

No existing row is rewritten by explicit DML. Existing tables receive nullable columns/defaulted outbox columns and validated constraints. New incident, roster, activity and outbox rows appear only after application use.

## Risk assessment

- `ALTER TABLE` and constraint changes require table locks; lock duration depends on live activity and table size.
- foreign-key validation scans `work_orders` and `activity_logs`;
- non-concurrent index creation can affect writes and consumes storage;
- changing `notification_outbox.work_order_id` nullability and deduplication changes queue semantics;
- replacing the activity-log read policy can create an authorization regression if live prerequisite roles/policies differ;
- PostgREST schema reload/connection behavior may delay application visibility;
- 0014 assumes 0012/0013-compatible objects and a pre-existing `notification_outbox`.

Do not claim zero risk. Capture row counts, table sizes, active sessions, constraints, policies and representative execution time in Preview before planning Production.

## Recovery and rollback

Persistent rollout requires a provider-backed backup/snapshot identifier, retention, restore target and a rehearsed restore check. None was verifiable in WP-REL-001, so remote migration is blocked.

Preferred failure response before incident writes: disable incident routes/navigation and apply a reviewed forward fix. Destructive reversal after writes can lose incidents, roster records, incident audit entries and notification rows. A reverse migration must remove policies/grants and dependent triggers/functions first, unlink/drop foreign keys and indexes, then remove columns/tables only after export and data-loss approval. Database restore may lose all writes after the snapshot and requires reconciliation.

See [Rollback Plan](ROLLBACK_PLAN.md).

## Preview deployment gate

Before running 0014 remotely:

1. prove the target is non-production and map it to the Preview application;
2. query migration history and catalog state for 0011–0013;
3. confirm `notification_outbox` exact definition and existing data;
4. capture policies, grants, constraints, sizes, counts and fingerprints;
5. create and verify a recoverable backup/snapshot;
6. review migration hash and execution plan;
7. schedule a controlled window with rollback owner;
8. apply through an approved migration mechanism and retain output.

## Post-migration smoke tests

Use marked Preview data and authenticated role accounts. Validate incident list/create/detail, unique number, assignment, acknowledgement, phases, closure authority, corrective linkage, roster resolution, Administrator/Supervisor/responder recipients, outbox creation and RLS denial for another Technician. Confirm Mission Control, Operations Today/Exceptions and Incident Command Centre read via RLS-scoped clients and no longer show migration-degraded fallback. Do not send real SMS or WhatsApp.

See [Post-Deployment Validation](POST_DEPLOYMENT_VALIDATION.md).

## Current application regression

- `npm run typecheck` — PASS
- `npm run lint` — PASS
- `npm test` — PASS: 37 files, 341 tests
- `npm run build` — PASS: Next.js production build, 28 static pages generated
- `git diff --check` — PASS at assessment time

## Remaining blockers

- exact remote migration history and catalog reconciliation;
- proven non-production Supabase target/application mapping;
- backup identifier and tested recovery procedure;
- Preview migration and application-path validation;
- UAT and release approval;
- Production remains explicitly out of scope.
