# FMWorks 1.1 Stabilization Batch A

## Deployment identity

Batch A UAT must use the Preview deployment produced from the Batch A commit.
Do not use the older `m7ongy4n9` deployment. Confirm `/api/health` reports
version `1.1`, the expected Git commit SHA, and environment `preview` before UAT.

## Required configuration

| Target | Required settings |
|---|---|
| Vercel Preview | `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, server-only `SUPABASE_SERVICE_ROLE_KEY`, and `NEXT_PUBLIC_APP_URL` set to the stable Preview origin |
| Vercel Production | The same four variables, with `NEXT_PUBLIC_APP_URL` set to the canonical production origin |
| Supabase Auth | Site URL set to the canonical production origin; Redirect URLs allow the production callback and the approved Preview callback |

Recommended Supabase Auth values:

- Site URL: `https://<production-domain>`
- Production redirect: `https://<production-domain>/auth/callback`
- Preferred Preview redirect: `https://<stable-preview-domain>/auth/callback`
- If ephemeral Vercel URLs must be tested: add Supabase's documented Vercel Preview wildcard `https://*-<team-or-account-slug>.vercel.app/**`, scoped as narrowly as the project permits.

Supabase invitation/confirmation templates must use `{{ .RedirectTo }}` for the
confirmation target when the flow supplies `redirectTo`; otherwise a template
that uses only `{{ .SiteURL }}` can ignore the application callback URL.

A stable Preview domain is preferred because it reduces redirect allow-list
scope and avoids coupling invitations to short-lived deployment URLs. Never set
a deployed `NEXT_PUBLIC_APP_URL` to localhost. The server rejects localhost
origins when `VERCEL_ENV` indicates Preview or Production.

## Assignment notification dependency

Technician assignment produces a stable authenticated application path:
`/work-orders/<work-order-id>`. Existing users can sign in and open that path;
first-time users must first complete the existing administrator provisioning or
Supabase invitation flow. Transactional assignment email delivery is not
implemented because no outbound email provider or credential is provisioned.
