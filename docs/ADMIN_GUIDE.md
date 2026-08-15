# Administrator Guide

Administrators govern identities, roles, departments, configuration, audited overrides, deployment readiness, and support. Administrator access never justifies sharing service credentials or bypassing workflows.

## User provisioning

1. Open **Users** and verify the build/environment.
2. Enter a unique email, display name, canonical role, active department where required, contact number, and supported activation/password details.
3. Submit once, confirm success, and verify the Auth user has a matching active profile.
4. Have the user test sign-in and authorized navigation.

Duplicate email, invalid role/department, weak password, and missing server configuration return safe errors. Never expose `SUPABASE_SERVICE_ROLE_KEY` in a browser.

## Governance

- Assign least privilege; correct missing/inactive/unsupported profiles rather than bypassing checks.
- Review overdue work, approvals, assignments, completion/review queues, and audit history.
- Use overrides only for documented need. Cancel/deactivate records instead of hard deletion.
- Verify emergency recipient and delivery states without claiming unconfigured delivery.

## Environment readiness

Confirm `/api/health`, footer build identity, Auth redirects, required variables, RLS/migrations, provider state, tests, and rollback plan. Apply migrations only through the approved process.

## Troubleshooting

- Admin operations not configured: verify the server-side URL and service-role variable for that deployment.
- Login does not load: distinguish Auth failure from missing, inactive, or invalid profile and route authorization.
- Notification absent: inspect safe result codes; `NOT_CONFIGURED` requires provider approval/configuration.

See [SECURITY.md](SECURITY.md), [USER_MANUAL.md](USER_MANUAL.md), and [STABILIZATION_BATCH_A.md](STABILIZATION_BATCH_A.md).
