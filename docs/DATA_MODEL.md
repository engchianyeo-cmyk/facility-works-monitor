# Data Model — Facility Works Monitor

## categories
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | gen_random_uuid() |
| user_id | uuid nullable | owner scope (lock-down sprint) |
| name | text | e.g. Electrical, Plumbing |
| created_at | timestamptz | default now() |

## work_orders
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid nullable | |
| title | text | required |
| description | text | optional |
| location | text | required |
| category_id | uuid FK → categories | |
| priority | text | low / medium / high / critical |
| status | text | submitted → approved → in_progress → done / rejected |
| submitted_by | text | free-text name (auth link later) |
| assigned_to | text | optional |
| photo_url | text | optional |
| ai_priority_score | numeric | AI field: 1–5 urgency |
| ai_priority_source | text | AI field: model used |
| ai_priority_confidence | numeric | AI field: 0–1 |
| ai_priority_review_status | text | AI field: unreviewed / accepted / overridden |
| created_at | timestamptz | |
| updated_at | timestamptz | |

## activity_logs
| Field | Type | Notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid nullable | |
| work_order_id | uuid FK → work_orders | cascade delete |
| action | text | e.g. status_change, comment |
| from_status | text | |
| to_status | text | |
| actor | text | name or system |
| note | text | optional |
| ai_model | text | set when action is AI-driven |
| ai_confidence | numeric | |
| created_at | timestamptz | |

## RLS
- v1: permissive open policies on all tables (demo-first)
- Lock-down sprint: replace with `auth.uid() = user_id` policies

## Status Machine
`submitted → approved → in_progress → done`  
`submitted → rejected` (any step)  
Enforced server-side in API route; invalid transitions return 400.