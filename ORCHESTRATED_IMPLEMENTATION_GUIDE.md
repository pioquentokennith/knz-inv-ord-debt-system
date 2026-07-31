# KNZ Scent Admin — Orchestrated Comprehensive Audit Consolidation and Unified Implementation Guide

**Project:** KNZ Scent Admin  
**Technology:** Flutter + Firebase Authentication/Firestore/Functions/Crashlytics + SQLite  
**Primary release target:** Android  
**Current status:** **Not release-ready**  
**Purpose of this file:** Provide one authoritative, AI-readable implementation guide that consolidates the current audit, remediation plan, security policy, privacy requirements, release checklist, and historical verification report.

---

## 1. Mission

The implementation agent must repair and improve the system until it is safe, internally consistent, testable, and ready for an Android release.

The work must prioritize:

1. preventing startup failures;
2. securing authentication and account recovery;
3. preventing silent local or cloud data loss;
4. making order, stock, debt, and payment operations atomic;
5. correcting debt interest and financial reporting;
6. preserving every field during synchronization and restore;
7. adding automated tests and CI;
8. completing Android release engineering;
9. improving maintainability, performance, and accessibility.

Do not treat this document as a request for another plan. Use it as an **implementation contract**.

---

## 2. Source-of-truth order

When information conflicts, use this precedence:

1. **This unified implementation guide**
2. **AUDIT_REPORT.md** — current audit and current code-state authority
3. **REMEDIATION_PLAN.md** — phase sequencing and implementation discipline
4. **RELEASE_CHECKLIST.md** — release gates
5. **SECURITY.md** — security handling and disclosure expectations
6. **PRIVACY.md** — privacy disclosure and operator obligations
7. **KNZ-Scent-Full-Verification-Report-v2.md** — historical context only

The older verification report remains useful for history, but some of its findings were partially applied or changed. Do not reintroduce an older fix when the current audit describes a newer architecture or a different current state.

---

## 3. Current audit verdict

The project has a strong school-project foundation and a polished feature set, but production use can currently cause:

- startup failure before the first screen;
- insecure password reset and OTP handling;
- weak or disconnected authentication and Firestore authorization;
- lost cloud synchronization operations;
- order, inventory, and debt records becoming inconsistent;
- incorrectly forgiven debt interest;
- duplicate order identifiers;
- incomplete cloud restore;
- misleading accounting and reporting;
- migration failures being hidden;
- release builds using incomplete configuration;
- privacy and permission issues;
- limited accessibility;
- no meaningful automated test safety net.

The current audit reviewed commit `c4f6284` plus an uncommitted worktree and reported 13 modified and 3 untracked entries. Start remediation from a clean, attributable baseline.

---

# PART I — AGENT OPERATING CONTRACT

## 4. Non-negotiable implementation rules

The implementation agent must follow all rules below.

### 4.1 Read before editing

Before changing code:

- inspect the affected source files;
- inspect the database schema and migrations;
- inspect related models, repositories, services, state management, screens, tests, Firebase configuration, and Android configuration;
- identify dependencies between local storage, cloud sync, UI state, exports, and reports.

Do not modify a method in isolation when its contract is used by multiple layers.

### 4.2 Implement, do not merely describe

For each assigned phase:

- make the actual code changes;
- add or update tests;
- run validation commands;
- report exact files changed;
- report remaining blockers;
- identify actions requiring the repository owner or Firebase/Play Console credentials.

A phase is not complete because the code “looks correct.”

### 4.3 Preserve data

Before schema or authentication changes:

- create explicit migrations;
- preserve existing user, product, order, reseller, custom-order, debt, payment, and activity data;
- do not delete or overwrite production-like data to simplify implementation;
- document any unavoidable migration limitation.

### 4.4 Never hide failures

Do not catch and discard exceptions for:

- authentication;
- password reset;
- product writes;
- order writes;
- stock updates;
- debt writes;
- payments;
- database migrations;
- synchronization;
- report generation;
- export generation;
- activity-log persistence.

Use typed results or propagated exceptions. The UI must only show success after a confirmed local commit.

### 4.5 Money must not use binary floating-point

No newly written money logic may store or calculate currency using `double` or SQLite `REAL`.

Use one of these consistently:

- integer centavos; or
- a proper decimal type.

The preferred project-wide representation is **integer centavos** because it is deterministic and SQLite-friendly.

### 4.6 Cloud identity must use authenticated UID

Cloud documents and Firestore authorization must be bound to the authenticated Firebase UID, not a username and not an anonymous installation identity.

### 4.7 Local-first must have explicit semantics

Local writes must remain usable offline. Cloud synchronization must use a durable transactional outbox.

A network-interface check is not proof that Firebase is reachable.

### 4.8 No dependency upgrades before safety tests

Do not upgrade the listed major Firebase, notification, or lint dependencies before the relevant unit, integration, migration, and emulator tests exist.

### 4.9 One phase per focused implementation session

Do not attempt all phases in one giant diff.

Recommended branch names:

```text
fix/phase-0-baseline
fix/phase-1-startup-otp
fix/phase-2-auth-boundary
fix/phase-3-data-integrity
fix/phase-4-debt-accounting
fix/phase-5-dto-migrations
fix/phase-6-reporting
fix/phase-7-tests-ci
fix/phase-8-release-hardening
refactor/phase-9-accessibility
```

### 4.10 Required end-of-phase report

Every phase report must contain:

```markdown
## Phase N Completion Report

### Implemented
- ...

### Files changed
- `path/to/file.dart`
- ...

### Database or API contract changes
- ...

### Tests added or updated
- ...

### Commands run
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test`
- ...

### Validation results
- PASS/FAIL with exact output summary

### Product decisions made
- ...

### Owner-only actions still required
- ...

### Remaining risks
- ...

### Recommended next phase
- ...
```

---

## 5. Product decisions that must be explicit

Do not silently decide these.

### Decision A — Reporting basis

Choose one:

- **Cash basis:** count revenue when payment is actually received.
- **Accrual basis:** count revenue when earned, with receivables tracked separately.

**Recommended default for the current app:** Cash basis, because the system already tracks debt collections and the current risk is double-counting credit sales when created and again when collected.

The owner may override this.

### Decision B — Reseller totals

Choose one customer-facing total:

- SRP total; or
- discounted reseller/customer-pay total.

**Recommended default:** Use the discounted `customerPayAmount` as the actual order total, receipt total, recycle-bin total, ledger total, and report total. Display SRP only as a reference or “before discount” value.

### Decision C — Real release scope

Choose one:

- Android-only, local-first, primarily single-device, with cloud backup/sync limitations clearly documented; or
- full multi-platform and true multi-device two-way synchronization.

**Recommended default for the current release:** Android-only, local-first, single-account/single-device-oriented release with a reliable cloud outbox and restore. Defer complete multi-device conflict resolution until after the critical release.

The owner may choose full multi-device synchronization, but that significantly expands Phase 3.

---

# PART II — ORCHESTRATED IMPLEMENTATION WORKFLOW

## 6. Phase 0 — Baseline, inventory, and reproducibility

### Objective

Create a clean, reproducible starting point before functional changes.

### Tasks

- Commit or stash the existing uncommitted worktree separately.
- Record the current branch and commit.
- Confirm the project opens from:

```text
E:\flutter_test_projects\inventoryordtrack
```

- Record installed versions:

```bash
flutter --version
dart --version
java -version
node --version
npm --version
firebase --version
```

- Confirm Flutter `>=3.38.4` and Java 17.
- Reconcile `pubspec.yaml` SDK constraints with `pubspec.lock`.
- Add an SDK pin using FVM, asdf, or another documented method.
- Run and record:

```bash
flutter pub get
flutter pub outdated
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

- Do not treat analyzer timeout as a pass.
- Create a baseline issue list mapped to the phases in this guide.
- Confirm the current SQLite database version and all migrations from version 1 through the current version.
- Confirm whether the project already contains:
  - `firestore.rules`
  - Firestore indexes
  - `.firebaserc`
  - `firebase.json`
  - `functions/package.json`
  - `functions/package-lock.json`
  - Functions tests
  - CI workflow
  - release signing configuration

### Done when

- the worktree is clean;
- the baseline commit is recorded;
- SDK versions are reproducible;
- current analyze/test/build failures are documented;
- no remediation code is mixed with pre-existing uncommitted changes.

---

## 7. Phase 1 — Startup and OTP functionality

**Severity:** Critical  
**Audit findings:** 1, 2, 18

### Objective

The app must start successfully without `.env`, without internet, and without optional cloud services.

### Required implementation

#### 7.1 Remove client-side email secret dependency

- Remove `flutter_dotenv` startup loading.
- Remove any requirement for a packaged `.env` file.
- Remove Brevo API keys, sender secrets, and OTP secrets from Flutter assets and client code.
- Email/OTP must be an optional backend capability, not a boot dependency.

#### 7.2 Build a deployable Firebase Functions backend

Create or complete:

```text
.firebaserc
firebase.json
functions/package.json
functions/package-lock.json
functions/index.js or typed equivalent
functions/tests/
```

Configure Functions deployment in `firebase.json`.

Use Secret Manager or supported parameters for:

- `BREVO_API_KEY`
- `OTP_SECURITY_SECRET`
- sender email/configuration

Do not use legacy `functions.config()` for new implementation.

#### 7.3 Restructure bootstrap

Use one guarded initialization zone.

Split initialization into:

**Required local initialization**
- Flutter binding
- SQLite
- local preferences/session
- local repositories and state

**Optional initialization**
- Firebase
- Crashlytics
- notifications
- remote configuration
- OTP/email capability
- sync worker

Optional failures must be logged and surfaced as degraded capability, not a startup crash.

#### 7.4 Offline first-run behavior

A clean install in airplane mode must reach the local app shell or a clearly usable offline login/setup flow.

Do not wait indefinitely for:

- Firebase authentication;
- Crashlytics;
- notification setup;
- OTP backend;
- cloud sync.

### Tests

- startup test without `.env`;
- startup test with Firebase unavailable;
- startup test with notifications unavailable;
- startup test in offline mode;
- Function syntax/lint tests;
- Functions emulator test for request validation;
- backend configuration test that fails clearly when secrets are missing.

### Acceptance criteria

- clean install + airplane mode reaches the app;
- missing `.env` cannot crash the app;
- Functions package installs reproducibly using `npm ci`;
- backend can be deployed with `firebase deploy --only functions` after owner credentials are supplied;
- no live provider secret exists in Flutter source, assets, logs, or crash reports.

---

## 8. Phase 2 — Authentication and authorization boundary

**Severity:** Critical  
**Audit findings:** 3, 4, 5 and related security findings

### Objective

Replace client-side custom authentication with an identity model that securely binds every account and cloud document to a Firebase UID.

### Required implementation

#### 8.1 Choose one identity system

Preferred:

- Firebase Authentication for account identity and password reset.

Alternative:

- a real custom server authentication service.

Do not combine local username/password verification with an unrelated anonymous Firebase identity.

#### 8.2 Secure OTP/password reset

Preferred option:

- use Firebase Auth password-reset email or email-link flow.

If custom OTP remains:

- generate OTP server-side;
- validate email and purpose;
- store only an OTP hash;
- set expiry;
- enforce attempt limit;
- enforce resend cooldown;
- return a challenge ID;
- verify in a second server operation;
- issue a short-lived reset authorization;
- require App Check and appropriate authentication where applicable;
- use a persistent or distributed rate limiter;
- sanitize all email template inputs;
- never accept arbitrary OTP HTML from the client.

#### 8.3 Prevent account enumeration

Forgot-password response must be identical whether:

- username does not exist;
- email does not match;
- account exists;
- reset email was sent.

Normalize email case before comparison.

#### 8.4 Remove client-side password verifiers

- Stop storing password hashes/verifiers in Firestore.
- Stop downloading password verifiers to the client.
- Migrate away from unsalted SHA-256.
- If a temporary local verifier is unavoidable, use Argon2id or scrypt with per-user salt and a documented migration.

#### 8.5 Bind data to UID

Every Firestore path must be scoped to the authenticated UID.

Examples:

```text
/users/{uid}
/users/{uid}/products/{productId}
/users/{uid}/orders/{orderId}
/users/{uid}/debts/{debtId}
```

Do not use username as the authorization key.

#### 8.6 Firestore rules

- track `firestore.rules` in the repository;
- deny by default;
- deny unauthenticated reads/writes;
- deny cross-account reads/writes;
- validate ownership and critical field types;
- use the Emulator Suite to test rules.

#### 8.7 Session handling

- logout must end the authenticated Firebase session;
- local session state must clear consistently;
- stale background sync must stop after logout;
- switching users must not expose the previous user’s local state.

#### 8.8 Roles

Either:

- implement a real Administrator authorization gate; or
- remove the cosmetic role until it has enforcement.

Do not assign every newly registered account an unrestricted “Administrator” role.

#### 8.9 Username uniqueness

If usernames remain a user-facing identifier:

- enforce uniqueness centrally;
- prevent offline registration from later overwriting a cloud account;
- use UID as identity and username as mutable metadata.

#### 8.10 Notification privacy

Remove from lock-screen notification text:

- customer names;
- usernames;
- balances;
- overdue periods;
- other sensitive business details.

Use generic wording and reveal details only after opening the authenticated app.

### Tests

- registration and login;
- logout ends session;
- forgot-password non-enumeration;
- OTP expiry;
- OTP attempt limit;
- OTP resend limit;
- cross-account rule denial;
- unauthenticated rule denial;
- same-account allowed operations;
- username collision;
- email case normalization;
- role enforcement;
- user-switch local data isolation.

### Acceptance criteria

- no password verifier reaches the client for comparison;
- cloud data is authorized by Firebase UID;
- emulator rules deny cross-account and unauthenticated access;
- password reset cannot be used to take over another account;
- logout actually terminates the session.

---

## 9. Phase 3 — Atomic data integrity and durable synchronization

**Severity:** Critical  
**Audit findings:** 6, 7, 10, 11, 12 and synchronization portion of 14

### Objective

Local business operations must be atomic, and cloud operations must never be silently discarded.

### Required implementation

#### 9.1 Replace swallowed repository errors

Replace `safeVoidCall` or equivalent on critical writes with:

- typed `Result<T>`; or
- propagated domain exceptions.

Read failures must not silently become empty datasets.

Preserve the last-known-good state and show an actionable error.

#### 9.2 Transactional order creation

One SQLite transaction must include:

- generating the order identifier;
- inserting the order;
- inserting all order line items;
- conditional stock decrement;
- validating affected row counts;
- creating optional automatic debt;
- creating outbox entries for every cloud mutation.

Rollback everything if any step fails.

#### 9.3 Unique order identifiers

Add a real database constraint:

```text
UNIQUE(user_id, order_id)
```

Generate the order ID inside the same transaction as insertion.

Do not use a separate `MAX(...) + 1` transaction followed by a later insert.

Consider an internal UUID as the true primary identity and keep the readable KNZ sequence as display metadata.

#### 9.4 Transactional outbox

Create an outbox table with fields such as:

```text
id
user_id
entity_type
entity_id
operation
payload
created_at
attempt_count
last_attempt_at
last_error
status
```

Rules:

- local mutation and outbox row commit together;
- create the outbox entry regardless of connectivity;
- delete or mark complete only after confirmed remote success;
- never suppress Firestore exceptions;
- retry with bounded backoff;
- show pending/failed sync state in the UI;
- preserve failed rows for diagnostics;
- make operations idempotent.

#### 9.5 Order state machine

Define legal states and transitions explicitly, including:

```text
active
processing
shipped
delivered
utang
cancelled
soft-deleted
restored
```

For every transition, define:

- whether stock is reserved;
- whether stock is released;
- whether debt may remain open;
- whether delivery is allowed;
- whether restore requires stock;
- whether cancellation is reversible.

Reject invalid transitions.

Do not clamp insufficient restore stock to zero.

#### 9.6 Stock checks

At commit time:

- query current stock inside the transaction;
- use conditional SQL updates;
- verify the number of affected rows;
- return the precise stock-shortage error to the UI.

Do not rely only on the in-memory product cache.

#### 9.7 Synchronization scope

Implement the selected Product Decision C.

At minimum, durable sync/restore must cover:

- products;
- orders and line items;
- debts and payment records;
- resellers;
- custom orders;
- soft deletions/tombstones.

Device-local absolute image paths must not be treated as portable cloud image references.

If full two-way multi-device sync is selected, add:

- revision/version;
- updated timestamp;
- tombstones;
- conflict policy;
- idempotency keys;
- merge or last-write policy;
- test coverage for concurrent edits.

### Tests

- kill app during order creation;
- force stock failure after order insert begins;
- two concurrent order attempts;
- duplicate readable order ID;
- Firestore write failure;
- retry after reconnection;
- deletion and restore;
- invalid state transition;
- restore with insufficient stock;
- outbox survives restart;
- successful retry removes/completes only the correct outbox row;
- user-visible sync failure.

### Acceptance criteria

- app termination mid-order cannot leave order, items, stock, and debt inconsistent;
- duplicate order IDs are prevented by the database;
- cloud failures remain pending and visible;
- no Firestore exception is swallowed;
- restore cannot silently corrupt stock.

---

## 10. Phase 4 — Debt, interest, payment allocation, and currency

**Severity:** Critical  
**Audit finding:** 8 plus all money-as-`double` issues

### Objective

Debt balances and payments must remain mathematically correct and auditable.

### Required implementation

#### 10.1 Debt model

Persist separately:

```text
principal_original_centavos
principal_outstanding_centavos
interest_outstanding_centavos
interest_rate
interest_type
interest_start_timestamp
last_accrual_timestamp
status
```

#### 10.2 Interest accrual

- accrue interest only for the elapsed period since `lastAccrualTimestamp`;
- persist newly accrued interest;
- do not recompute the entire historical interest using today’s remaining principal;
- define simple/compound behavior explicitly if multiple types exist;
- use deterministic rounding.

#### 10.3 Payment allocation

Use an explicit allocation rule.

Recommended:

1. interest outstanding;
2. principal outstanding.

Store an immutable payment record:

```text
payment_id
debt_id
amount_centavos
interest_applied_centavos
principal_applied_centavos
paid_at
payment_method
reference
notes
```

#### 10.4 Settlement

A debt is paid only when:

```text
principal_outstanding == 0
AND
interest_outstanding == 0
```

#### 10.5 Currency migration

Migrate all money fields from `REAL`/`double` to integer centavos.

Include:

- product prices;
- SRP;
- discounted prices;
- order totals;
- deposits;
- debt principal;
- interest;
- payments;
- deductions;
- report totals.

Provide a reversible or well-documented migration strategy.

### Mandatory regression example

A debt with:

- ₱100 principal;
- ₱10 accrued interest;
- ₱100 payment;

must result in:

- ₱10 applied to interest;
- ₱90 applied to principal;
- ₱10 principal remaining;
- debt not marked paid.

### Tests

- no-interest payment;
- interest-first allocation;
- partial payment;
- overpayment rejection or explicit credit handling;
- zero balance;
- repeated accrual;
- accrual after partial payment;
- rounding;
- migration from old REAL values;
- receipt includes interest;
- full outstanding determines paid status.

### Acceptance criteria

- accrued interest cannot be forgiven by a principal payment;
- no new money value is stored as `double`;
- payment history is immutable and auditable;
- the mandatory regression example passes.

---

## 11. Phase 5 — Versioned DTOs and safe migrations

**Severity:** High  
**Audit findings:** 9 and 15

### Objective

Synchronization and restore must preserve every business field, and migrations must fail safely.

### Required implementation

#### 11.1 Versioned DTO mappers

Create one mapper per entity:

- Product DTO
- Order DTO
- Order Item DTO
- Debt DTO
- Payment DTO
- Reseller DTO
- Custom Order DTO
- Custom Order Payment DTO
- Activity Log DTO, if synced

Each DTO must have:

- schema version;
- local-to-DTO mapping;
- cloud-to-DTO mapping;
- DTO-to-domain mapping;
- DTO-to-local mapping;
- default handling for older versions;
- validation for required fields.

#### 11.2 Preserve all audited fields

Order restore must preserve, where applicable:

- payment method;
- payment reference;
- reseller flag;
- deduction;
- discounted total;
- order type;
- customer-pay amount;
- status;
- timestamps;
- line-item unit price;
- SRP reference.

Debt restore must preserve:

- interest rate;
- interest type;
- interest start date;
- principal and interest balances;
- last accrual timestamp;
- payment history.

#### 11.3 Migration safety

- wrap each migration in a transaction;
- only tolerate explicitly expected duplicate-column/index cases;
- rethrow every unexpected error;
- do not advance database version after a failed migration;
- verify required tables, columns, indexes, foreign keys, and unique constraints.

#### 11.4 Required schema changes

Include as applicable:

- unique `(user_id, order_id)`;
- unique debt/order association where required;
- `deleted_at` for resellers;
- `deleted_at` for custom orders;
- outbox table;
- money-centavo columns;
- debt principal/interest columns;
- immutable payment history tables;
- DTO/schema version metadata.

### Tests

For every entity:

```text
create local
→ map to DTO
→ write cloud representation
→ restore into fresh database
→ assert full equality
```

Migration tests must start from fixture databases for every version 1 through the current version.

### Acceptance criteria

- restore reproduces every original business field;
- migration failure rolls back;
- all version fixture tests pass;
- database version cannot advance with an incomplete schema.

---

## 12. Phase 6 — Unified accounting and reporting

**Severity:** High  
**Audit finding:** 13 and reporting-related confirmed defects

### Objective

Every screen, summary, export, and PDF must use the same tested accounting definitions.

### Required implementation

#### 12.1 One pure accounting domain service

Centralize:

- gross sales;
- discounts;
- net sales;
- cash received;
- debt collections;
- outstanding receivables;
- reseller sales;
- custom-order deposits and payments;
- cancelled-order exclusion;
- date filtering;
- profit calculation, only if costs/expenses exist.

UI screens and exporters must not independently reimplement financial formulas.

#### 12.2 Apply selected reporting basis

For the recommended cash basis:

- normal paid sales count when received;
- unpaid utang does not count as received revenue;
- debt collections count only when paid;
- date filters apply to payment timestamps;
- do not count credit sale creation and collection twice.

If accrual basis is selected, document receivables and recognition rules explicitly.

#### 12.3 Correct misleading labels

Do not call a report “Profit & Loss” unless the model includes meaningful:

- revenue;
- cost of goods sold;
- expenses;
- resulting profit/loss.

Otherwise rename it to an accurate sales or collections summary.

#### 12.4 Fix audited export defects

- Custom Order Status PDF must contain custom orders.
- Reseller Detailed PDF must contain reseller-specific detail.
- Debt With Interest export must include interest.
- Profit & Loss PDF must mirror its on-screen breakdown.
- Exports must exclude cancelled orders consistently.
- Accounting ledger rows and summary cards must use the same filters.
- Duplicate columns showing the same value must be removed or made genuinely distinct.
- Date-filtered reports must filter debt payment timestamps.
- Custom-order revenue and deposits must enter the accounting service.

#### 12.5 Reseller consistency

Use the selected Product Decision B consistently:

- order line items;
- order total;
- receipt;
- recycle bin;
- ledger;
- export;
- PDF;
- dashboard.

#### 12.6 Fixed-fixture validation

Create a small hand-computed fixture containing:

- paid normal order;
- cancelled order;
- reseller order with discount;
- utang order;
- partial debt payment;
- interest-bearing debt;
- custom order with deposit;
- custom-order later payment;
- date-range boundary cases.

Compute expected totals manually and assert that all views and exports match.

### Tests

- cash/accrual rule;
- cancelled exclusion;
- reseller discounted total;
- debt collection by payment date;
- no double-counting;
- custom-order inclusion;
- receipt and export interest;
- same fixture across dashboard, accounting, reports, CSV, and PDF.

### Acceptance criteria

- dashboard, accounting, reports, CSV, and PDF produce the same totals from the same fixture;
- cancelled orders do not appear in active sales totals;
- debt collections respect the selected date range;
- custom-order money is no longer invisible.

---

## 13. Phase 7 — Tests, CI, and dependency hygiene

**Severity:** Important  
**Audit finding:** 16 plus dependency/tooling findings

### Objective

Create a safety net before major dependency upgrades and release work.

### Required test coverage

#### Unit tests

- authentication service;
- session handling;
- validation;
- username uniqueness;
- OTP/reset flow;
- product calculations;
- order state machine;
- debt accrual and allocation;
- accounting service;
- CSV sanitization;
- DTO mapping;
- rate limiter.

#### Repository/database tests

- CRUD;
- transactions;
- conditional stock updates;
- unique constraints;
- outbox;
- migrations;
- soft delete/restore;
- immutable payments;
- error propagation.

#### Integration tests

- order + items + stock + optional debt;
- app restart during pending outbox;
- failed sync then retry;
- debt interest + payment allocation;
- restore on a fresh database;
- login/logout/user switching;
- export generation.

#### Firebase Functions tests

- request validation;
- OTP generation;
- expiry;
- attempt limit;
- resend limit;
- challenge verification;
- invalid purpose;
- App Check/auth enforcement as designed;
- secret/config failure.

#### Firestore emulator tests

- unauthenticated denial;
- cross-UID denial;
- owner access;
- field validation;
- tombstone/revision behavior if enabled.

### CI requirements

On every push and pull request:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --coverage
npm ci
npm run lint
npm test
npm audit --omit=dev --audit-level=high
```

Add a coverage threshold appropriate to the project and raise it gradually.

### Dependency upgrades

Only after tests are green, upgrade one at a time:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_crashlytics`
- `flutter_local_notifications`
- `flutter_lints`

Each major upgrade must be its own reviewable change.

### Acceptance criteria

- CI is green on a clean clone;
- tests run reproducibly;
- no README claim exceeds actual coverage;
- each major dependency upgrade is isolated and validated.

---

## 14. Phase 8 — Android release engineering, security, and privacy hardening

**Severity:** Important  
**Audit finding:** 17 plus security/privacy findings

### Objective

Produce a correctly signed, correctly identified, policy-ready Android release.

### Required implementation

#### 14.1 Android package and Firebase registration

- replace `com.example` with the final package ID;
- the checklist currently targets:

```text
com.knzscent.admin
```

- register this package in the production Firebase project;
- run:

```bash
flutterfire configure --project=knz-scent --platforms=android
```

- verify `google-services.json` and generated Firebase options refer to the same Firebase Android app.

#### 14.2 Firebase services

Enable and verify:

- Firebase Authentication method used by the final design;
- Firestore;
- Functions;
- Crashlytics;
- App Check, after valid client tokens are confirmed.

Deploy reviewed:

- Functions;
- Firestore rules;
- Firestore indexes.

#### 14.3 Android signing

Create a dedicated upload keystore outside Git.

Use ignored `android/key.properties` or CI environment variables:

```text
ANDROID_KEYSTORE_PATH
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

Release tasks must fail if signing values are missing.

Never fall back to the debug key.

#### 14.4 Permissions

Remove permissions not required by current behavior, including unless the product changes:

- exact alarm;
- boot scheduling;
- scheduled notification receivers;
- Bluetooth advertise;
- unnecessary location permissions.

Keep only permissions required for:

- Bluetooth printer discovery/connection;
- camera/gallery image selection;
- notifications;
- internet.

Test Android permission denial and grant flows.

#### 14.5 CSV injection

Sanitize cells beginning with:

```text
=
+
-
@
```

Prevent spreadsheet formula execution while preserving readable exported data.

#### 14.6 Temporary export cleanup

Delete temporary CSV/PDF files after successful sharing or after a controlled retention window.

#### 14.7 SQLite at-rest protection

After removing password verifiers, evaluate whether remaining customer, order, debt, payment, and reference data requires SQLCipher or equivalent encryption.

Document the decision.

#### 14.8 Crashlytics

- complete Android Crashlytics Gradle integration;
- trigger one controlled crash in a non-production test build;
- verify symbolicated reporting;
- ensure secrets and personal data are not included in logs.

#### 14.9 Privacy operations

Before publishing, supply:

- effective date;
- legal entity/operator name;
- jurisdiction;
- retention schedule;
- privacy contact;
- access/correction/deletion procedure;
- backup deletion behavior;
- account/data deletion process;
- incident response procedure.

The existing privacy text is a template, not legal advice and not a claim of compliance with a specific regime.

#### 14.10 Store readiness

- replace placeholder metadata;
- provide screenshots;
- provide support contact;
- complete Play Data safety form;
- publish operator-approved privacy policy;
- confirm permission declarations match behavior;
- preserve mapping/symbol files;
- preserve signed artifact;
- use staged rollout;
- document rollback criteria.

### Acceptance criteria

- release AAB builds successfully;
- AAB is signed by the intended upload certificate;
- clean-device install succeeds;
- Firebase configuration matches the package;
- unnecessary permissions are absent;
- CSV injection fixture opens safely;
- privacy and security contacts are supplied;
- Crashlytics test is confirmed.

---

## 15. Phase 9 — Refactor, performance, UX, and accessibility

**Severity:** Polish, but required for maintainability

### Objective

Reduce excessive coupling and make core workflows accessible and responsive.

### Required implementation

#### 15.1 Split `AppState`

Separate by domain:

- authentication;
- products;
- orders;
- debts;
- resellers;
- custom orders;
- notifications;
- activity logs;
- synchronization.

Use scoped listeners/selectors so unrelated changes do not rebuild the whole app.

#### 15.2 Break up oversized files

Refactor large files such as:

- `app_state.dart`;
- `analytics_screen.dart`;
- `order_dialog.dart`;
- `export_service.dart`.

Target roughly 400–500 lines or fewer for touched files when practical.

#### 15.3 Repository and service consistency

Bring resellers and custom orders under the same interface/service structure as products, orders, and debts.

#### 15.4 Performance

- move heavy aggregation and PDF generation off the UI isolate using `compute()` or another safe isolate strategy;
- paginate large repository reads;
- avoid returning a new list object from every getter;
- cache derived calculations by stable inputs;
- avoid recalculating all analytics on unrelated updates.

#### 15.5 Accessibility

- add `Semantics` labels;
- add tooltips;
- use minimum touch targets of 44–48 dp;
- support keyboard navigation;
- include keyboard activity in session timeout;
- add textual alternatives for charts;
- ensure screen reader flow works for core operations;
- replace pointer-only custom controls with accessible buttons where possible.

#### 15.6 Validation

Move validation into model/domain/service layers.

Reject:

- invalid numeric input;
- negative values;
- malformed email/username;
- deposits above agreed price;
- invalid state transitions;
- invalid money values.

Constructors and `copyWith` must preserve validation.

#### 15.7 Remaining confirmed defects

Implement:

- immutable custom-order payment history;
- recycle-bin restore for resellers;
- recycle-bin restore for custom orders;
- `deleted_at` support for both;
- low-stock list height cap;
- sign-out confirmation;
- durable activity-log failure reporting;
- overdue debt badge if consistent with the navigation design;
- responsive card layouts for phone-sized accounting/sales tables;
- correct line-item subtotal display;
- precise stock-shortage message in UI.

### Acceptance criteria

- core workflows are usable with a screen reader;
- keyboard users are not logged out while actively typing;
- touched oversized files are meaningfully modularized;
- heavy report generation does not freeze the UI;
- smaller confirmed defects are closed.

---

# PART III — CROSS-CUTTING SECURITY POLICY

## 16. Secret handling

The following must remain outside source control and compiled Flutter assets:

- Brevo API key;
- OTP signing secret;
- Android keystore;
- `key.properties`;
- CI credentials;
- provider secrets.

Use:

- Google Cloud Secret Manager;
- encrypted CI repository/environment secrets;
- least privilege.

Firebase client configuration is not a private secret, but it must match the final Firebase app and package ID.

If a secret was exposed:

1. revoke it;
2. rotate it;
3. update dependent systems;
4. inspect logs and releases;
5. do not assume deleting the latest commit removes exposure.

---

## 17. Vulnerability reporting requirements

Before public distribution, publish a private security contact.

A valid vulnerability report should include:

- affected revision and platform;
- reproduction steps;
- impact;
- sanitized logs;
- proposed mitigation, if available.

Do not publish:

- credentials;
- customer records;
- exploit details exposing users;
- screenshots containing personal data.

---

# PART IV — PRIVACY AND DATA HANDLING

## 18. Data categories processed

The app may process:

- administrator account names, usernames, and email addresses;
- customer and reseller names and contact details;
- products;
- orders;
- payments;
- debts;
- receipts;
- accounting records;
- product images;
- activity and synchronization records;
- Crashlytics diagnostics.

## 19. Processing locations

- operational data is stored locally in SQLite;
- configured records may synchronize to Firebase;
- OTP delivery may send the email address and a short-lived code to Brevo through a protected Cloud Function;
- providers process data under their own terms and operator agreements.

## 20. Permission-purpose mapping

- Bluetooth/location-related permissions: supported receipt printer discovery and connection;
- camera/photo library: product images;
- notifications: low-stock and overdue reminders;
- internet: authentication, synchronization, OTP, and crash reporting.

Do not claim behavioral location tracking.

## 21. Retention and deletion

Soft deletion and recycle-bin behavior are not a complete legal retention policy.

Before release, define:

- record retention periods;
- backup retention;
- deletion from backups;
- access controls;
- account deletion;
- data access/correction/deletion requests;
- legal hold procedure, if relevant;
- incident response.

---

# PART V — RELEASE GATES

## 22. Source and version gate

- [ ] Clean reviewed commit on release branch
- [ ] New semantic version and build number in `pubspec.yaml`
- [ ] Flutter `>=3.38.4`
- [ ] Java 17
- [ ] Intended lockfiles committed
- [ ] `functions/package-lock.json` committed
- [ ] `npm ci` succeeds

## 23. Firebase/backend gate

- [ ] Android package registered
- [ ] FlutterFire configuration regenerated
- [ ] Auth method enabled
- [ ] Firestore enabled
- [ ] Functions enabled
- [ ] Crashlytics enabled
- [ ] Secrets configured
- [ ] Sender/domain verified with Brevo
- [ ] Functions emulator tests pass
- [ ] Firestore rules emulator tests pass
- [ ] Functions/rules/indexes deployed
- [ ] App Check rollout plan documented

## 24. Automated quality gate

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --coverage
cd functions
npm ci
npm run lint
npm test
npm audit --omit=dev --audit-level=high
cd ..
flutter build appbundle --release
```

All must pass.

## 25. Device acceptance gate

Test:

- [ ] Fresh install
- [ ] Upgrade from previous database version
- [ ] Registration
- [ ] Login
- [ ] OTP resend
- [ ] OTP expiry
- [ ] Password reset
- [ ] Logout
- [ ] Lockout/rate limit
- [ ] Offline CRUD
- [ ] App restart
- [ ] Reconnection
- [ ] Sync retry
- [ ] Conflict behavior
- [ ] Orders
- [ ] Resellers
- [ ] Debts
- [ ] Partial payments
- [ ] Accounting totals
- [ ] Export totals
- [ ] Camera/gallery denial and grant
- [ ] Notification denial and grant
- [ ] Bluetooth denial, scan, connect, disconnect
- [ ] Receipt printing on supported hardware
- [ ] Low-memory/background/resume
- [ ] Representative Android API levels

## 26. Store and operations gate

- [ ] Final metadata
- [ ] Screenshots
- [ ] Support contact
- [ ] Play Data safety form
- [ ] Published privacy policy
- [ ] Correct permissions
- [ ] Backup procedure
- [ ] Retention procedure
- [ ] Incident response
- [ ] Account/data deletion procedure
- [ ] Mapping/symbol files stored
- [ ] Signed AAB archived
- [ ] Staged rollout plan
- [ ] Monitoring plan
- [ ] Rollback criteria

---

# PART VI — GLOBAL DEFINITION OF DONE

## 27. Functional definition of done

The system is functionally complete only when:

- startup works offline;
- authentication is UID-bound;
- account recovery is secure;
- cloud rules block unauthorized access;
- writes cannot report false success;
- orders, stock, items, and debt commit atomically;
- sync failures are durable and visible;
- debt interest and payments are correct;
- money calculations are deterministic;
- restore preserves all fields;
- migrations are tested;
- financial outputs agree;
- custom orders and reseller totals are consistent;
- Android release build is signed and installable.

## 28. Evidence required

Do not claim completion without:

- passing automated tests;
- exact validation commands;
- emulator rule results;
- migration fixture results;
- accounting fixture results;
- release build result;
- manual device checklist result;
- list of owner-only console actions.

## 29. Stop conditions

Stop and report immediately when:

- a migration may destroy data;
- a required product decision is unresolved;
- Firebase credentials or console access are required;
- a release keystore is required;
- a test exposes a broader architecture defect;
- current code differs materially from the audited structure;
- a phase would require unsafe changes outside its scope.

Do not guess or silently bypass the blocker.

---

# PART VII — STANDARD AI EXECUTION PROMPT

Use the following prompt in OpenCode for each phase.

```text
Read ORCHESTRATED_IMPLEMENTATION_GUIDE.md in full.

Execute only Phase [NUMBER AND NAME].

Rules:
1. Inspect all affected files before editing.
2. Implement the code changes; do not only describe them.
3. Preserve existing data and add explicit migrations when needed.
4. Do not swallow errors.
5. Add or update automated tests.
6. Run the phase validation commands.
7. Do not claim completion unless the acceptance criteria pass.
8. Flag product decisions and owner-only Firebase/Play Console actions.
9. End with the required Phase Completion Report format.
10. Stop before beginning the next phase.
```

---

# PART VIII — RECOMMENDED SESSION ORDER

```text
Session 1: Phase 0 — Baseline
Session 2: Phase 1 — Startup and OTP
Session 3: Phase 2 — Authentication boundary
Session 4: Phase 3 — Data integrity and outbox
Session 5: Phase 4 — Debt and currency
Session 6: Phase 5 — DTOs and migrations
Session 7: Phase 6 — Reporting
Session 8: Phase 7 — Tests and CI
Session 9: Phase 8 — Android release hardening
Session 10: Phase 9 — Refactor and accessibility
Session 11: Full regression, device acceptance, and release review
```

If the deadline is tight, complete Phases 0–6 first. These address startup, security, silent data loss, stock/debt corruption, and incorrect financial results. Do not rush release polish while critical correctness remains unresolved.

---

# PART IX — FINAL MASTER CHECKLIST

## Critical correctness

- [ ] Offline startup succeeds
- [ ] No `.env` startup dependency
- [ ] No provider secret in client
- [ ] Secure OTP or Firebase reset flow
- [ ] UID-bound Firestore data
- [ ] Deny-by-default rules
- [ ] Logout ends Firebase session
- [ ] No client password verifier
- [ ] Typed write failures
- [ ] Transactional order creation
- [ ] Unique order identity
- [ ] Transactional outbox
- [ ] Explicit order state machine
- [ ] Principal and interest separated
- [ ] Interest-first payments
- [ ] Integer-centavo money
- [ ] Complete DTO restore
- [ ] Safe tested migrations
- [ ] Unified accounting definitions

## Testing and release

- [ ] Unit tests
- [ ] Repository tests
- [ ] Migration tests
- [ ] Integration tests
- [ ] Functions tests
- [ ] Firestore emulator tests
- [ ] CI
- [ ] Coverage threshold
- [ ] Final Android package ID
- [ ] Production Firebase registration
- [ ] Release keystore
- [ ] Signed AAB
- [ ] Crashlytics verified
- [ ] Permission audit complete
- [ ] Privacy operator details supplied
- [ ] Data safety form complete
- [ ] Device acceptance complete
- [ ] Staged rollout and rollback plan complete

## Maintainability and UX

- [ ] AppState split by domain
- [ ] Oversized files modularized
- [ ] Heavy exports off UI isolate
- [ ] Pagination added
- [ ] Scoped rebuilds
- [ ] Accessible controls
- [ ] Keyboard activity recognized
- [ ] Chart text alternatives
- [ ] Custom-order payment history
- [ ] Reseller/custom-order recycle restore
- [ ] Low-stock height cap
- [ ] Sign-out confirmation
- [ ] Activity-log failures visible

---

## Final instruction to the implementation agent

Treat startup, authentication, money, stock, debt, migration, and synchronization changes as high-risk production work.

Make small, reviewable changes. Preserve data. Add tests before major upgrades. Verify every claim. Never convert a failed operation into apparent success. Do not move to the next phase until the current phase’s acceptance criteria are demonstrated.
