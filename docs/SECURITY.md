# Security — Facility Works Monitor

## Secret Handling
- `OPENAI_API_KEY` and `SUPABASE_SERVICE_ROLE_KEY` live in Vercel environment variables only
- Frontend uses `NEXT_PUBLIC_SUPABASE_URL` + `NEXT_PUBLIC_SUPABASE_ANON_KEY` — anon key is safe to expose; RLS enforces access
- AI calls go through `/api/score-priority` server route — key never reaches the browser

## Permission Model (v1 → lock-down)
| Phase | Read | Write |
|---|---|---|
| v1 demo | Anyone (open RLS) | Anyone (open RLS) |
| Lock-down | Anyone can read dashboard | `auth.uid() = user_id` for writes |

## Approved Tools Rule
- Agents may only call named tools listed in AGENTIC_LAYER.md
- `run_any` / `exec_sql` / `send_any` are never exposed to agent context
- Every tool call is logged with actor, timestamp, input hash, and result status

## Audit Principle
- Every status transition writes an `activity_logs` row server-side — client cannot skip it
- Deletion is UI-only, requires confirmation, and is logged before execution
- At lock-down sprint: add a human security review before real facility data enters the system

## Pre-launch Checklist
- [ ] No secrets in `git log` or browser network tab
- [ ] RLS policies confirmed active in Supabase dashboard
- [ ] Demo account credentials rotated before sharing live URL
- [ ] `NEXT_PUBLIC_` vars contain nothing sensitive