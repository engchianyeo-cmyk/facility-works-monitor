# FMWorks Product Editions

## Status

Proposed packaging framework. Names, prices, limits, and contractual availability are not committed until approved commercially.

## Capability packaging

| Capability | Core | Operations | Enterprise |
|---|---:|---:|---:|
| Authenticated work orders and dashboard | Yes | Yes | Yes |
| Users, roles, departments | Yes | Yes | Yes |
| Emergency Incident Management | Optional | Yes | Yes |
| Asset and preventive maintenance | — | Yes | Yes |
| Inventory and commissioning | — | Optional | Yes |
| Commercial controls | — | Optional | Yes |
| SSO, advanced audit/export, integrations | — | — | Planned |

## Packaging principles

- Security fixes, data export, and essential audit must not be artificially withheld.
- Edition enforcement is server-side and testable, not cosmetic navigation hiding.
- Downgrade behavior preserves customer data and explains read-only/archive effects.
- Usage limits require transparent measurement and administrative visibility.
- Provider consumption charges are disclosed separately.

## Open commercial decisions

Tenant model, site/user/asset limits, support levels, retention, regional hosting, SLA, onboarding, implementation services, provider pass-through, and contract terms.

See [COMMERCIAL.md](COMMERCIAL.md), [ROADMAP.md](ROADMAP.md), and [SECURITY.md](SECURITY.md).
