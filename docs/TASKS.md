# Tasks — Facility Works Monitor

## Gantt Overview
```
Sprint 1  [DB + CRUD + seed]          Week 1 days 1-2
Sprint 2  [Status engine] ← v1 ✅    Week 1 days 3-4
Sprint 3  [Dashboard + polish + deploy] Week 1 days 5-7
Sprint 4  [Lock it down — auth]       Week 2
Sprint 5  [AI priority scoring]       Week 2-3
```

---

## Sprint 1 — Database, seed data & work order CRUD
**Goal:** The app renders real data without login; submit form writes to DB.

- [ ] Run migration SQL; verify all tables exist in Supabase
- [ ] Confirm 5 seed work orders visible in Supabase table editor
- [ ] Build `/works` page: list with status badge, priority badge, location
- [ ] Build `/works/[id]` detail page: all fields + activity log
- [ ] Build `Submit Work Order` form — POST to `/api/work-orders`, redirects to detail
- [ ] Loading skeleton on list; empty state copy on empty list; error banner on API failure

**Definition of Done:** Open `/works` in an incognito tab — 5 seed orders appear. Submit a new order via the form — it appears at top of list and detail page shows all fields entered.

---

## Sprint 2 — Status engine · ✅ v1 functional milestone
**Goal:** The full Submitted → Approved → In Progress → Done workflow works end-to-end.

- [ ] Approve button on `submitted` orders → PATCH status, insert activity log
- [ ] Start button on `approved` orders → PATCH status, insert activity log
- [ ] Complete button on `in_progress` orders → PATCH status, insert activity log
- [ ] Reject button (any status) → PATCH to `rejected`, requires note
- [ ] Invalid transitions return 400; UI shows error toast
- [ ] Activity log panel on detail page refreshes after each action
- [ ] Status badge updates without page reload

**Definition of Done:** Open a seed order in `in_progress`. Click Complete. Status badge changes to Done. Activity log shows new entry with timestamp. Reload page — state persists.

---

## Sprint 3 — Manager dashboard & deploy
**Goal:** Polished, deployed app a recruiter can demo in 30 seconds.

- [ ] `/` dashboard: 4 count cards (Submitted, Approved, In Progress, Done)
- [ ] Recent activity feed (last 10 log entries, all orders)
- [ ] Filter work orders by status; sort by priority and date
- [ ] Empty state on each filter; loading skeletons everywhere
- [ ] Responsive layout (desktop + tablet)
- [ ] Deploy to Vercel; smoke test live URL end-to-end
- [ ] `README.md` with one-paragraph description + live URL

**Definition of Done:** Live Vercel URL opens to dashboard showing status counts. A visitor can filter, view detail, and complete a work order — all persist after refresh.

---

## Sprint 4 — Lock it down (auth + per-user RLS)
**Goal:** Real data is owner-scoped; demo account exists for recruiters.

- [ ] Enable Supabase Auth (email/password)
- [ ] Add login + signup pages; redirect unauthenticated write attempts to login
- [ ] Replace open RLS policies with `auth.uid() = user_id` for all writes
- [ ] Backfill `user_id` on seed rows to demo account UUID
- [ ] Create `demo@facilityworks.app` account; document credentials in README
- [ ] Confirm no secrets exposed in network tab

**Definition of Done:** Incognito visitor can read dashboard. Clicking Approve redirects to login. After login as demo account, Approve works and change is visible only to that user.

---

## Sprint 5 — AI priority scoring
**Goal:** Submitted work orders get an AI urgency score without blocking the form.

- [ ] `/api/score-priority` server route — calls OpenAI, returns score + confidence
- [ ] On work order submission, fire-and-forget call to score endpoint
- [ ] Store `ai_priority_score`, `ai_priority_source`, `ai_priority_confidence`, `ai_priority_review_status`
- [ ] Show AI score badge on work order card with "AI suggested" label
- [ ] Manager can override; store override value in `priority` field, set `review_status = overridden`
- [ ] Rule-based fallback if OpenAI unavailable
- [ ] Log every AI call in `activity_logs` with model + confidence

**Definition of Done:** Submit a work order with description containing "water leak near electrics". Within 5 s, card shows AI score badge. Override score — badge updates. Reload — both values persist.