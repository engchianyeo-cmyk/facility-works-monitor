# Intelligence Layer — Facility Works Monitor

## Messy Input
Free-text description: _"Water pooling under kitchen sink, getting worse since yesterday, could damage electrics nearby"_

## Auto-Structure Schema
```json
{
  "ai_priority_score": 4,
  "ai_priority_source": "gpt-4o",
  "ai_priority_confidence": 0.87,
  "ai_priority_review_status": "unreviewed",
  "detected_risk_keywords": ["water", "electrics", "damage"]
}
```

## Events That Trigger Intelligence
| Event | Action | Risk |
|---|---|---|
| Work order submitted | Score urgency (1–5) from description | Low — auto |
| Score shown to manager | Manager accepts or overrides | — |
| Override saved | Store override value + reason | Low — auto log |

## Scoring Rules (v1 — rule-based fallback)
- Keywords: `leak / flood / fire / server / critical` → score 5
- Keywords: `broken / not working / smell` → score 3
- No keywords → score 2
- AI score replaces rule-based score when API available; confidence stored

## What Gets Ranked
- Work order list sortable by `ai_priority_score` descending
- Dashboard highlights any `critical` AI-scored items not yet approved

## v1 vs Later
| v1 | Later |
|---|---|
| AI score on submit | Re-score if description edited |
| Rule-based fallback | Fine-tune on historical approvals |
| Score badge only | Predictive SLA breach warning |