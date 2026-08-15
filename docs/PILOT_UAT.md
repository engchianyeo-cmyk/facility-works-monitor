# WP-PILOT-001 UAT Checklist

These items depend on a configured disposable or approved pilot Supabase Auth environment and cannot be established by local static/unit tests alone. Do not test them against production without separate authorization.

## Supabase Auth behavior

- [ ] Project setting prevents public email/password self-signup, or an external signup is confirmed to create only the inactive quarantine profile.
- [ ] Administrator invitation redirect is allowlisted and reaches `/auth/callback` on the configured application origin.
- [ ] Direct-created user signs in with the temporary password and is forced to `/account/password` before any operational page or API succeeds.
- [ ] Invitation-created user completes the invitation flow, sets a private password and reaches the role-appropriate destination.
- [ ] Recovery email uses the configured redirect URL, exchanges the recovery code and reaches `/account/password`.
- [ ] Unknown and known recovery email submissions receive indistinguishable application responses.
- [ ] Recovery and invitation email wording does not claim notification delivery beyond Supabase Auth accepting the request.
- [ ] Changing role or activation while a user has an existing session becomes effective on the next authoritative request.
- [ ] Permanent deletion records a pending request before Auth deletion, reports a truthful failure when retained references block deletion, and records completion only after Supabase Auth confirms deletion.
- [ ] Existing sessions for an archived, disabled, role-changed, or permanently deleted user fail closed on the next hosted request; do not infer immediate token revocation from local tests.

## Browser sizes

- [ ] At 390 px, sign-in, first-password setup, password recovery, Technician My Work, Work Order detail and archive confirmation have no horizontal page overflow or unreachable controls.
- [ ] At desktop width, Administrator user management, Approval Centre and all four export links are usable with keyboard focus visible.

## Export spot check

- [ ] Open each CSV in a spreadsheet application and confirm formula-like user data is displayed as text.
- [ ] Confirm the Work Order, Asset, Incident and PM outcome extracts include only records visible to the signed-in manager role.
- [ ] Confirm no Auth user ID, evidence/storage path, provider reference/payload or raw JSON appears.

## Hosted platform boundaries

- [ ] Migration 0020 applies cleanly to the approved Supabase schema and its grants/RLS match disposable PostgreSQL results.
- [ ] Private Evidence Storage access and signed-object behavior remain correctly scoped after migration.
- [ ] Redirect URLs and application domains are allowlisted for invitation and recovery callbacks.
