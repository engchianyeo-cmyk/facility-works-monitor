# Agentic Layer — Facility Works Monitor

## Risk Levels & Actions

### Low — auto-execute (no approval needed)
| Action | Trigger | Tool |
|---|---|---|
| `score_priority` | Work order submitted | `openai_score_priority` |
| `log_activity` | Any status change | `supabase_insert_activity_log` |
| `tag_category` | Description parsed | `rule_based_categorise` |

### Medium — draft shown, one-click approval
| Action | Trigger | Tool |
|---|---|---|
| `auto_approve_low_priority` | Score ≤ 2, status submitted > 48 h | `supabase_update_work_order_status` |

### High — always requires explicit manager approval
| Action | Trigger | Tool |
|---|---|---|
| `send_notification` | Status changes to approved/done | `email_send` (Sprint 5) |

### Critical — human-only, no agent
| Action | Notes |
|---|---|
| Delete work order | UI button only; no agent path |
| Reject work order | Manager must type reason |

## Named Tools (approved list)
- `openai_score_priority` — POST to OpenAI, returns score + confidence
- `supabase_insert_activity_log` — inserts row, no deletes
- `supabase_update_work_order_status` — updates status field only
- `rule_based_categorise` — deterministic keyword match, no external call

## Audit Log Fields (every agent action)
`work_order_id, action, actor=system, ai_model, ai_confidence, created_at`

## v1 vs Later
- v1: only `score_priority` + `log_activity` auto-run
- Later: `auto_approve_low_priority`, notifications