# AGENTS.md — KNZ Scent Admin

## Project purpose

KNZ Scent Admin is an Android-focused Flutter application for inventory, orders, resellers, custom orders, debts, payments, accounting, reports, receipt printing, and optional Firebase synchronization.

Primary stack:

- Flutter and Dart
- SQLite for local operational data
- Firebase Authentication, Firestore, Functions, and Crashlytics
- Brevo for email delivery through Firebase Cloud Functions only
- Android as the supported release platform

The detailed remediation source is:

```text
ORCHESTRATED_IMPLEMENTATION_GUIDE.md
```

Do not read that entire file automatically. Read only the sections needed for the current phase.

---

## Current operating mode

Work on exactly one implementation phase per session.

Never begin the next phase unless the user explicitly requests it.

Recommended order:

```text
Phase 0 — Baseline and reproducibility
Phase 1 — Startup and OTP
Phase 2 — Authentication and authorization
Phase 3 — Atomic data integrity and synchronization
Phase 4 — Debt, interest, payments, and currency
Phase 5 — DTOs and migrations
Phase 6 — Accounting and reporting
Phase 7 — Tests, CI, and dependency hygiene
Phase 8 — Android release and security hardening
Phase 9 — Refactor, performance, and accessibility
```

At the start of a phase, locate and read only:

1. `ORCHESTRATED_IMPLEMENTATION_GUIDE.md` sections 2, 4, and 5;
2. the requested phase section;
3. sections 27–29 for completion evidence and stop conditions;
4. the previous phase report under `docs/progress/`, when available.

Do not repeatedly reopen the same large files after their relevant content is established.

---

## Agent workflow and token control

Use a bounded three-step workflow.

### 1. Explore

Use at most one read-only Explore subagent when repository discovery is needed.

The Explore task must:

- inspect only files relevant to the current phase;
- return paths, current flow, dependencies, risks, and suggested edit order;
- make no edits;
- avoid broad repository re-audits;
- stay concise.

Do not launch General, Scout, or nested subagents unless the user explicitly requests them.

### 2. Build

The Build agent:

- implements only the requested phase;
- relies on the Explore summary instead of rescanning the entire repository;
- makes small, reviewable changes;
- adds or updates tests;
- runs focused validation;
- stops before the next phase.

### 3. Review

After implementation, review only:

- the current Git diff;
- affected tests;
- migrations;
- security and data-integrity consequences;
- accidental unrelated changes.

Do not conduct another complete audit unless requested.

---

## Mandatory safety rules

### Preserve user work

Before editing:

- inspect `git status`;
- record the current branch and commit;
- never discard, reset, overwrite, stash, or commit existing work without explicit user approval;
- do not delete databases or business records to simplify a migration.

### Do not hide failures

Never swallow errors for:

- authentication;
- registration or password reset;
- product, order, reseller, custom-order, debt, or payment writes;
- stock updates;
- migrations;
- cloud synchronization;
- exports;
- report generation;
- activity-log persistence.

A failed operation must not display success.

Use typed results or propagated domain exceptions.

### Protect business data

Operations involving order, line items, stock, optional debt, and sync outbox must be atomic where required.

All schema changes require explicit migrations and migration tests.

### Money

Do not introduce new money storage or calculations using `double` or SQLite `REAL`.

Use integer centavos consistently unless the approved current phase specifies a tested decimal alternative.

### Authentication

Cloud identity and Firestore ownership must use the authenticated Firebase UID.

Do not use username or anonymous installation identity as the authorization boundary.

Do not store or compare password verifiers in Firestore or client code.

### Brevo

Brevo is allowed only as the email-delivery provider behind Firebase Cloud Functions.

Never expose these in Flutter source, assets, logs, or crash reports:

```text
BREVO_API_KEY
OTP_SECURITY_SECRET
sender credentials
provider secrets
```

Store secrets in Google Cloud Secret Manager or supported Firebase Functions parameters.

Brevo does not decide who may register.

Controlled registration must use a trusted application mechanism such as:

- administrator approval;
- invitations;
- an approved-email list;
- another backend-enforced allowlist.

A verified email alone must not automatically become an active administrator.

### Firestore

Rules must:

- deny by default;
- deny unauthenticated access;
- deny cross-UID access;
- prevent self-approval and role escalation;
- be covered by Emulator Suite tests.

### Offline behavior

Required local initialization must not depend on internet access.

Firebase, Crashlytics, notifications, synchronization, and email are optional startup capabilities and must degrade safely.

### Synchronization

Local mutation and transactional outbox entry must commit together.

Never delete an outbox item until remote success is confirmed.

A network-interface check is not proof that Firebase is reachable.

### Dependencies

Do not perform major dependency upgrades before the Phase 7 safety tests exist.

Upgrade major dependencies one at a time.

---

## Product decisions

Do not silently choose these. State the decision and recommendation in the phase report.

### Reporting basis

Recommended default: cash basis.

Do not count an unpaid credit sale as received revenue and then count its collection again.

### Reseller total

Recommended default: `customerPayAmount` or the discounted customer total is the actual total.

SRP may be shown only as a reference or before-discount amount.

### Release scope

Recommended current scope:

```text
Android-only
local-first
primarily single-device
reliable cloud outbox and restore
```

Do not claim complete multi-device synchronization without conflict, revision, and tombstone handling.

---

## Project validation commands

Use focused commands during implementation and the complete phase-required set before completion.

Flutter:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --coverage
```

Firebase Functions:

```bash
cd functions
npm ci
npm run lint
npm test
npm audit --omit=dev --audit-level=high
cd ..
```

Android release when the phase requires it:

```bash
flutter build appbundle --release
```

Do not report a timed-out command as passed.

Record failures exactly and identify whether they existed before the phase.

---

## File inspection guidance

Inspect contracts across all affected layers before editing:

```text
models
database schema and migrations
repositories
services
state management
screens and dialogs
Firebase Functions
Firestore rules and indexes
tests
Android configuration
exports and reports
```

Do not modify a method in isolation when its behavior is relied on by several layers.

Prefer targeted search over opening every source file.

---

## Implementation style

- Make the smallest complete change that satisfies the current phase.
- Preserve existing naming and architecture unless the phase explicitly requires refactoring.
- Keep business logic out of widgets.
- Keep UI success messages dependent on confirmed results.
- Use parameterized SQL.
- Validate at model or service boundaries, not only in screens.
- Add comments only where the reason is not evident from the code.
- Avoid unrelated formatting or cleanup in phase-specific diffs.
- Do not create giant replacement files when focused changes are safer.

---

## Required pre-edit response

Before making changes, report:

```markdown
### Files inspected
- ...

### Commands planned
- ...

### Safe changes planned
- ...

### Risks or decisions
- ...
```

Keep this concise.

---

## Required phase completion report

Save each completed phase report as:

```text
docs/progress/PHASE_N_COMPLETION.md
```

Use this format:

```markdown
# Phase N Completion Report

## Implemented
- ...

## Files changed
- `path/to/file`

## Database or API contract changes
- ...

## Tests added or updated
- ...

## Commands run
- `command`

## Validation results
- PASS or FAIL with exact summary

## Product decisions made
- ...

## Owner-only actions still required
- ...

## Remaining risks
- ...

## Recommended next phase
- ...
```

Do not claim completion unless the phase acceptance criteria are demonstrated.

---

## Stop conditions

Stop and ask for direction when:

- a migration may destroy or incorrectly transform data;
- a required product decision remains unresolved;
- Firebase Console, Brevo, Play Console, or signing credentials are required;
- a release keystore is required;
- the code differs materially from the audit assumptions;
- the requested phase would require unsafe unrelated changes;
- tests reveal a broader architecture defect outside the current phase.

Do not bypass blockers or fabricate successful validation.

---

## Phase request interpretation

When the user says:

```text
Execute Phase N
```

perform only that phase.

When the user asks for a review:

- make no edits unless explicitly requested;
- review only the specified diff or files;
- return confirmed issues with file locations and impact.

When the user asks to fix a specific bug outside the current phase:

- inspect whether it conflicts with an unfinished critical phase;
- explain the dependency briefly;
- make only the requested safe fix.

---

## Final priority order

Always prioritize:

1. startup reliability;
2. account security;
3. prevention of silent data loss;
4. atomic stock, order, debt, and payment correctness;
5. accurate money and reporting;
6. tested migrations and restore;
7. automated safety gates;
8. Android release readiness;
9. maintainability and accessibility.
