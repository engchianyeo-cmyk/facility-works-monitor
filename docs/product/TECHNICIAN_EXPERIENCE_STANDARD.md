# Technician Experience Standard

## Commercial outcome

A technician can understand, perform and truthfully record assigned work with minimal typing and without exposure to irrelevant administration. The product must never compress a desktop management interface onto a phone.

## Target journey

`Open FMWorks → My Work → understand job → understand location → see asset/system when available → see instructions and controls → perform work → record status or blocker → capture evidence → submit/complete`

## Screen contract

### My Work

- assigned work only by default;
- critical/safety items first, then due time and age;
- location, job, priority, state and next action visible without opening;
- clear sync/freshness and empty/error state;
- no user, department or commercial administration.

### Job view

- plain-language scope and success condition;
- exact site/building/floor/zone and asset/system when known;
- safety prerequisites and required authority above routine detail;
- instructions, history and required evidence;
- one primary action appropriate to the technician and current state;
- explicit reason when an action is unavailable.

### Field recording

- start, pause/block, resume and submit/complete are distinct truthful actions;
- blocker capture requires a category, short explanation and optional evidence—not a false completion;
- camera-first before/after/supporting evidence with recoverable drafts;
- client cannot choose actor IDs, assignment or lifecycle timestamps;
- submission states what review remains outstanding.

## Interaction requirements

- Minimum 44×44 px touch target; preferred 48 px for primary field actions.
- Primary action reachable without horizontal scrolling at 390 px.
- No database terms, UUIDs or raw status codes in user text.
- Common outcomes require taps/selections rather than repeated typing.
- Required fields and completion evidence are known before work begins.
- Validation preserves notes and captured files.
- Colour never carries status alone; focus, labels and error summaries are accessible.
- Offline unavailability is explicit before the technician relies on the product; no implied offline safety.

## Measurable acceptance criteria

| Measure | Pass threshold |
|---|---|
| Find next assigned job | ≥90% of representative technicians within 15 seconds, unassisted |
| Understand location and required action | ≥90% answer both correctly within 30 seconds |
| Start routine work | Median ≤3 interactions after opening the job |
| Record a blocker | Median ≤45 seconds; no false completion required |
| Add one photograph | Median ≤30 seconds after camera permission is available |
| Submit valid completion | ≥90% first-attempt success with no lost notes/evidence |
| Unauthorized access | 0 access to another technician’s work/evidence in security UAT |
| Mobile layout | No horizontal scroll at 390 px for core journey; 200% zoom remains operable |
| Terminology | ≥90% comprehension without training in moderated test |
| Weak connection | Honest failure/retry state; no duplicate transition or lost confirmed record |

Test on representative iOS and Android browsers, bright/low-light environments, gloves where relevant, camera permission denied, large text, keyboard-only administrative review, slow network and session expiry.

## Commercial readiness position

Current state is **PARTIAL / RED for paid go-live**. Assigned-work access and core transition concepts exist, but protected completion evidence is blocked at migration design, device UAT is absent, and offline operation is unavailable. Responsive presentation alone is not commercial mobile readiness.

## Offline limitation statement

Until offline behavior is implemented and validated:

> FMWorks requires a working data connection to load, update and submit work. Do not rely on it as the sole source of safety-critical instructions where connectivity is uncertain. Confirm that a submission is recorded before leaving the job.

## Data and security standard

- Technician access is limited server-side and by RLS to current assignments.
- Workflow mutation occurs through narrow protected operations, never unrestricted row update.
- Evidence URLs are short-lived and issued only after work/incident access validation.
- Evidence add/remove/review is attributable in `activity_logs`.
- Geolocation and media metadata require a documented purpose and privacy treatment.

## Not included in this definition

No offline engine, native application, asset module, evidence endpoint or workflow change is authorized by this document.
