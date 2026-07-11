# PRD — Facility Works Monitor

## Problem
Facility managers have no single place to track work orders from submission through approval to completion. Status lives in WhatsApp threads and spreadsheets; things fall through the cracks.

## Target User
Facility Manager (primary) — monitors all open works and drives them to completion.  
Staff / Requestors (secondary) — submit new work orders.

## Core Objects
| Object | Purpose |
|---|---|
| Work Order | A task to be performed in the facility |
| Category | Type of work (Electrical, Plumbing, HVAC, Structural, Cleaning) |
| Activity Log | Every status transition with actor + timestamp |

## MVP Must-Haves
- [ ] Submit a work order (title, location, priority, category, description)
- [ ] Work order list with real-time status badges
- [ ] Approve → Start → Complete workflow — every button writes to the database
- [ ] Work order detail page with full activity timeline
- [ ] Manager dashboard: counts by status + recent activity feed
- [ ] Seed demo data visible without login

## Non-Goals (v1)
- User authentication / per-user isolation
- Assignee scheduling or calendar integration
- File/photo attachments
- Email or push notifications
- Multi-facility or multi-team support

## Success Criteria
A recruiter opens the live URL, sees the dashboard with real work orders, clicks one marked **In Progress**, and uses the **Complete** button — the status updates instantly, the activity log gains a new entry, and the dashboard count reflects the change. All without logging in.