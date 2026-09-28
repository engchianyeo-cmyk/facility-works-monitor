# FMWorks Environment Architecture

## Mandatory separation

| Environment | Git / Vercel | Supabase | Data and migration rule |
|---|---|---|---|
| Local / disposable | Developer worktree; local commands only | Disposable PostgreSQL/Supabase instance | Synthetic data; recreate freely; migration regression source |
| Preview / UAT | Immutable release-candidate commit deployed as Vercel Preview | Dedicated Preview Supabase project | Synthetic/UAT data only; recovery verified before migration; role UAT |
| Production | Approved main/release commit deployed through Production | Dedicated Production Supabase project | Live data; separate explicit GO, backup, window and post-validation |

Preview and Production must never share Supabase project IDs, URLs, keys, database credentials, Storage buckets or migration history.

The project `pyapukytcrsuowmgzqzh` is referenced by `.env.local`, but its relationship is undocumented. Treat it as potentially Production and do not migrate or reconfigure it.

## Required Preview setup

Status: **PREVIEW DATABASE REQUIRED**.

An authorized account owner must create or designate a dedicated Supabase project and record, without committing secrets:

- environment name `FMWorks Preview/UAT`;
- project reference and region;
- owner and billing approval;
- allowed data classification (synthetic/UAT only);
- database and Storage backup mechanism/retention;
- restore target and restore authority;
- linked Vercel project/environment;
- migration operator and release approvers.

Do not clone Production data unless separately approved, minimized and anonymized.

## Vercel mapping control

| Vercel scope | Required variables | Control |
|---|---|---|
| Development | Local/disposable URL and keys | `.env.local` is developer-specific and uncommitted |
| Preview | Preview Supabase URL, anon key and server-only service key | Vercel Preview scope only; verify project reference during deployment gate |
| Production | Production Supabase values | Vercel Production scope only; protected change authority |

The deployment gate must print only environment name, Vercel deployment/build identity and safe Supabase project reference. It must fail when Preview resolves to the Production reference or when either reference is unknown. Secrets are never logged. Branch names alone do not select a safe database.

## Candidate migration classification

| Migration | Classification | Dependency and decision |
|---|---|---|
| 0011 secure legacy tables | **LEGACY / conditional** | Assumes `public.technicians`, which is not created by the repository baseline/fixture. Run only where catalog preflight proves the legacy objects and review approves it. Not part of a fresh Preview baseline. |
| 0012 department foundation | **BASELINE REQUIRED** | Requires profiles/auth foundation; normalizes departments without discarding the label. |
| 0013 core work-order engine | **BASELINE REQUIRED + RELEASE 1.2 REQUIRED** | Requires 0012-compatible identity/department schema; explicitly does not require blocked 0010. |
| 0014 emergency incidents | **RELEASE 1.2 REQUIRED** | Requires 0013 objects plus `notification_outbox`; creates incident, roster, linkage, RLS and workflow. |
| 0015 incident safe projection and roster API | **RELEASE 1.2 REQUIRED** | Requires 0014. Current Mission Control, incident list/detail and roster API call its RPCs. |

Migration 0015 was created locally on 10 August 2026 and is currently untracked, so no commit history establishes its authoring context. It adds five `SECURITY DEFINER` RPCs with fixed `search_path`, authenticated role/visibility checks and explicit EXECUTE grants: safe incident projection, roster projection, responder options, roster upsert and active-state control. It solves unsafe/awkward joined reads and provides protected roster mutations for the current UI/API. It does not change 0014; it makes the candidate order `0014 → 0015` mandatory.

## Fresh Preview candidate sequence

1. Identify the Preview project and release-candidate commit.
2. Run read-only catalog/migration pre-validation and capture fingerprint.
3. Verify required baseline and decide whether Preview is fresh or incremental.
4. Create backup/snapshot and record identifier, retention and restore target.
5. Apply 0012 only when absent and prerequisite comparison passes; validate departments/auth.
6. Apply 0013 only when absent; run core work-order regression/smoke tests.
7. Confirm exact `notification_outbox` prerequisite.
8. Apply 0014; run incident SQL validation.
9. Apply 0015; verify projection/roster RPC authorization.
10. Capture post-migration fingerprint and compare approved changes.
11. Run application smoke tests and role UAT.
12. Record outcome; do not promote to Production without a separate GO.

For an existing environment, never replay a migration solely because a table appears absent. Reconcile migration metadata and all affected objects first.

## Schema fingerprint

Run [schema_fingerprint.sql](../../tests/sql/schema_fingerprint.sql) with a read-only database role where available:

```text
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/sql/schema_fingerprint.sql
```

Do not paste credential-bearing connection strings into evidence. The script opens a read-only transaction and hashes ordered inventories of tables/RLS flags, columns, constraints, indexes, functions, triggers, policies, table grants and routine grants. It reports migration metadata when `supabase_migrations.schema_migrations` is available.

Store the output with environment, safe project reference, database version, release commit, migration hashes, capture time and operator. Differences require object-level review; matching MD5 inventories support comparison but are not a security proof.

Disposable candidate fingerprint on PostgreSQL 15.18:

| Kind | Count | MD5 |
|---|---:|---|
| table | 13 | `482e210d333a070b0457b8d19f70e25b` |
| column | 188 | `fdc9cec409dc294300ecbf6e3155f554` |
| constraint | 74 | `48184f2190a2b622291039770379d1d1` |
| index | 38 | `890f87b02087e9bfff87021e23fc8aa5` |
| function | 69 | `1a525708bb06bbe96361bf5bdbb99980` |
| trigger | 12 | `a06b64ce3ca53844e97b4b5cbc2758c2` |
| policy | 10 | `08998f57fdb44276d6703175cbaca48b` |
| table grant | 105 | `f3b4bbdd1788a7f638b934be33e909ac` |
| function grant | 128 | `3e1d38f6cb351ce5a6d2afb73fbe95f2` |

The disposable fixture has no Supabase migration metadata, as expected.

## Recovery prerequisite

Before any persistent Preview migration, record:

| Evidence | Required value |
|---|---|
| Mechanism | Supabase/project backup, snapshot or verified logical backup appropriate to plan |
| Identifier | Provider/job ID and UTC completion time |
| Retention | Long enough for migration, UAT and stabilization decision |
| Restore method | Documented command/console procedure and authorized operator |
| Restore target | Separate non-production restore project/database, never Production |
| Verification | Restore completes; counts/fingerprint and representative work-order data reconcile |

A restore rehearsal is permitted only in verified non-production. Until this evidence exists, Preview rollout is blocked.

## Current status

No Preview project was identifiable and no recovery evidence exists. The architecture and candidate chain are understood, but persistent rollout remains **AMBER / blocked**.

See [Schema Reconciliation](RELEASE_1_2_SCHEMA_RECONCILIATION.md), [Rollback Plan](ROLLBACK_PLAN.md), and [Post-Deployment Validation](POST_DEPLOYMENT_VALIDATION.md).
