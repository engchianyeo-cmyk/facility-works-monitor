# Architecture — Facility Works Monitor

## Stack
- **Frontend:** Next.js 14 (App Router) + Tailwind CSS
- **Database:** Supabase (Postgres + RLS)
- **Hosting:** Vercel
- **AI (Sprint 5):** OpenAI via server-side API route only

## Now vs Later
| Now (v1) | Later |
|---|---|
| Open read/write for demo | Auth + owner-scoped RLS |
| Manual priority selection | AI priority scoring |
| Status transitions in UI | Email notifications on approval |
| Single facility | Multi-facility support |

## Key User Action — Flow
1. **Capture** — Manager clicks "Complete" on a work order detail page
2. **Validate** — Client checks current status is `in_progress`; rejects invalid transitions
3. **Write** — `PATCH /api/work-orders/[id]` sets `status = done`, `updated_at = now()`
4. **Log** — Server inserts row into `activity_logs` (from_status, to_status, actor, timestamp)
5. **Return** — API responds with updated work order
6. **Show** — UI updates status badge and prepends log entry — no page reload needed

## Layer Plan
1. **Data first** — tables + seed rows + RLS policies (Sprint 1)
2. **App logic** — CRUD forms + status machine enforced server-side (Sprints 1–2)
3. **Smart features** — AI priority scoring layered on top (Sprint 5)

## Core Without AI
All status transitions, approvals, logging, and dashboard counts work entirely from Postgres queries. AI scoring is additive; removing it leaves the app fully functional.