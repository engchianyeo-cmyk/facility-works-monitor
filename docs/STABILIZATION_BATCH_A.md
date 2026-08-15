# FMWorks 1.1 Stabilization Record

## Purpose

This historical release record preserves the operational decisions from Stabilization Batch A without serving as the primary architecture specification.

## Delivered decisions

- UAT must verify version, commit SHA, and environment through `/api/health` and the authenticated footer.
- Administrator provisioning requires `NEXT_PUBLIC_SUPABASE_URL` and server-only `SUPABASE_SERVICE_ROLE_KEY`.
- Browser authentication requires `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- Stable application and callback origins use `NEXT_PUBLIC_APP_URL` plus restricted Supabase redirect configuration.
- Profile creation preserves `profiles.id = auth.users.id` and canonical roles.
- Missing, inactive, or unsupported profiles fail explicitly.
- Technician assignment notification uses a stable authenticated record path.
- No provider means `NOT_CONFIGURED`; assignment still succeeds.

## Deployment controls

- Prefer stable Preview domains over broad ephemeral redirect wildcards.
- Never configure deployed callback origins as localhost.
- Invitation/confirmation templates must honor the supplied redirect target.
- Confirm build identity before recording UAT evidence.

## Superseded details

Old deployment identifiers and one-off Preview URLs are intentionally omitted. Current environment configuration and security requirements are in [SECURITY.md](SECURITY.md) and [ADMIN_GUIDE.md](ADMIN_GUIDE.md).
