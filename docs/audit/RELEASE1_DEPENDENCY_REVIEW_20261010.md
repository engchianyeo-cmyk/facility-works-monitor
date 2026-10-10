# Release-1 dependency security review

Reviewed: 10 October 2026, 22:24 SGT. Scope: development candidate; no Production changes.

The non-force audit repair retained Next.js and its ESLint configuration at 15.5.27 and removed the previously reported critical advisories. This increment addresses remaining patchable dependencies without framework major upgrades, package downgrades, or Supabase API changes.

## Implemented dependency controls

| Dependency | Candidate version/control | Reason |
|---|---|---|
| `vitest`, `@vitest/coverage-v8` | Exact `4.1.11`, together | Resolves the redirect-mock arbitrary-file-read advisory; preserves the existing test major. |
| Next.js nested `postcss` | Scoped override `8.5.25` | Resolves source-map disclosure and CSS stringify advisories while retaining Next.js 15.5.27. This is an explicit transitive override, validated by a clean install and production build. |
| `@supabase/ssr` | Exact `0.5.2` | Pins the existing resolved version; no runtime API change. |
| `@supabase/supabase-js` | Exact `2.110.6` | Pins the existing resolved version; no runtime API change. |

The lockfile accompanies the dependency changes for publication with the candidate. A clean `npm ci` validates reproducibility. The first lockfile-only regeneration retained a stale nested PostCSS entry; `npm ci` rejected it. A normal non-force installation regenerated the lockfile correctly, and the subsequent clean install passed.

## Validation

- `npm ci`: PASS.
- `npm run check`: PASS — TypeScript, ESLint, 79 Vitest files / 796 tests, and Next.js production build.
- Full dependency audit: **8 affected package entries: 5 high, 3 moderate, 0 critical**.
- Runtime dependency audit (`npm audit --omit=dev`): **3 moderate package entries, 0 high, 0 critical**.
- Resolved dependency inspection confirms paired Vitest 4.1.11, Next.js 15.5.27 with PostCSS 8.5.25 override, and exact Supabase SDK versions.

These checks do not substitute for authenticated Preview browser UAT or PostgreSQL verification. Audit totals count affected dependency entries and propagation through parent packages; they are not eight distinct vulnerability mechanisms.

## Remaining advisories and reachability

| Mechanism | Affected dependency chain | Upstream patch status | FMWorks applicability |
|---|---|---|---|
| Deeply nested brace-pattern stack exhaustion | `eslint-config-next` → `@next/eslint-plugin-next` → `fast-glob` → `micromatch` → `braces` 3.0.3 | No patched version listed; registry latest remains 3.0.3. | Development tooling. The Next ESLint plugin expands configured `settings.next.rootDir` globs. FMWorks application/API code does not directly accept or process user brace patterns. This establishes no identified runtime path, not a proof of universal non-exploitability. |
| Unbounded `sprintf-js` precision causing `RangeError` | `mammoth` → `argparse` 1.0.10 → `sprintf-js` 1.0.3 | No patched version listed; registry latest remains 1.1.3. | Runtime dependency inventory includes this chain. FMWorks uses `mammoth.extractRawText` in `lib/sla/documents.ts`; Mammoth's `argparse` is imported by its CLI (`bin/mammoth`), which FMWorks does not invoke. No identified path from an uploaded DOCX to an attacker-controlled sprintf format string. |

Do not apply audit suggestions to downgrade `eslint-config-next` to 14.2.35 or Mammoth to 0.3.29. They do not provide a compatible supported repair for this candidate. Do not force an `argparse` major override or substitute a brace parser merely to remove the audit entry. Preserve the unresolved advisories in the defect register and reassess maintained upstream releases or a separately tested removal/replacement when available.

## Sources

- [Vitest advisory GHSA-82fw-gwwq-j7x9](https://github.com/advisories/GHSA-82fw-gwwq-j7x9): patched in 4.1.11; development-server mock registration trust boundary.
- [PostCSS advisory GHSA-fxqj-rqcc-2cmp](https://github.com/advisories/GHSA-fxqj-rqcc-2cmp): affected through 8.5.22, patched 8.5.23.
- [PostCSS advisory GHSA-6g55-p6wh-862q](https://github.com/advisories/GHSA-6g55-p6wh-862q): sourceMappingURL file disclosure.
- [PostCSS advisory GHSA-r28c-9q8g-f849](https://github.com/advisories/GHSA-r28c-9q8g-f849): previous source-map path traversal.
- [PostCSS advisory GHSA-qx2v-qp2m-jg93](https://github.com/advisories/GHSA-qx2v-qp2m-jg93): CSS stringify output vulnerability.
- [Braces advisory GHSA-vfj7-8cjw-p6xm](https://github.com/advisories/GHSA-vfj7-8cjw-p6xm): no patched version listed at review.
- [sprintf-js advisory GHSA-hp3w-g68c-fv3c](https://github.com/advisories/GHSA-hp3w-g68c-fv3c): no patched version listed at review.
- [Supabase npm security guidance](https://supabase.com/docs/guides/security/npm-security): version pinning and lockfile controls. Supabase changelog checked; pinning changes neither SDK version nor API.

Applicability statements combine upstream descriptions with inspection of the installed dependency source and repository call sites. They are an engineering assessment, not acceptance of residual release risk or a zero-vulnerability claim.
