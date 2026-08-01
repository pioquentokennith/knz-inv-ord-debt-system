# Remediation Phase 4 — Reseller identity, custom-order workflow, and export period

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-004, DFR-005, DFR-006

    ## Entry gate

    Phase 3 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 4 — Reseller identity, custom-order workflow, and export period.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 4 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 4 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_3_COMPLETION.md;
    - the previous independent review result confirming APPROVE.

    Do not repeat the full repository audit.
    Do not begin another remediation phase.
    Do not stage, commit, push, deploy, publish, or distribute.
    Preserve all existing business and account data.

    Follow AGENTS.md strictly.

PROJECT

Repository:
E:\flutter_test_projects\inventoryordtrack

Application:
KNZ Scent inventory, orders, debt, payment, reseller, accounting, reporting, offline synchronization, Administrator/Staff authorization, and Bluetooth receipt-printing system.

Android package:
com.knzscent.admin

Firebase project:
knz-scent

Firebase plan:
Spark

Test devices:
- TECNO CK8n — Android 14 / API 34 — 106272539Q101518
- TECNO LJ9 — Android 15 / API 35 — 14451255BL109587

GLOBAL SAFETY RULES

- Execute only the requested remediation phase.
- Do not begin the next phase.
- Inspect affected source, models, repositories, database schema, migrations, synchronization, Firestore Rules, UI, and tests before editing.
- Preserve all existing user, product, order, debt, payment, reseller, custom-order, report, SQLite, and Firestore data.
- Do not reset, delete, replace, or clear production-like data.
- Do not uninstall the app or clear application storage.
- Use explicit additive migrations for schema changes.
- Never advance the database version after a failed migration.
- Do not swallow authentication, database, synchronization, report, export, or business-write errors.
- Do not show success unless the local transaction actually committed.
- Do not weaken Firestore Rules to make tests pass.
- Do not deploy Cloud Functions.
- Do not add a production dependency on Cloud Functions.
- Do not require Firebase Blaze.
- Firebase must remain Spark-compatible.
- Do not deploy Firebase resources without separate owner authorization.
- Do not expose or print passwords, tokens, private keys, service-account contents, keystore values, key.properties values, or environment secrets.
- Do not stage, commit, push, publish, or distribute anything.
- Do not use git add -A.
- Do not perform unrelated refactoring.
- Do not claim manual or physical-device tests passed without owner evidence.
- Use integer centavos for money. Do not introduce new money calculations using double or SQLite REAL.
- Bind cloud ownership to authenticated Firebase UID.
- Treat all Flutter client code as untrusted.
- Add failing-before and passing-after regression tests for confirmed defects.
- Preserve the currently working local-first transactional behavior.

BEFORE EDITING

Report:
1. Current branch and commit.
2. git status --short.
3. Files inspected.
4. Current behavior.
5. Planned changes.
6. Database and Firestore impact.
7. Data-loss and rollback risks.
8. Product decisions requiring owner approval.
9. Exact validation commands.

VALIDATION

Run all tests relevant to the phase, then run:

- dart format --output=none --set-exit-if-changed lib test
- flutter analyze
- flutter test
- relevant Firestore Rules emulator tests
- relevant Functions unit/emulator tests when their retained source is affected
- flutter build apk --debug
- git diff --check
- git status --short
- git diff --stat
- targeted git diff for every changed file

Do not treat a timeout or failed command as PASS.

PHASE COMPLETION REPORT

End with:

1. Objective
2. Root Causes
3. Files Changed
4. Database Migration
5. Firestore and Firebase Impact
6. Implementation
7. Tests Added
8. Validation Results
9. Data-Safety Confirmation
10. Spark-Plan Confirmation
11. Security Review
12. Remaining Blockers
13. Owner Actions
14. Exact Files Safe for Later Review
15. Final Verdict: PHASE COMPLETE or PHASE INCOMPLETE

Stop after the report.

    Execute only Remediation Phase 4 — Reseller attribution, custom-order state integrity, and accounting export parity.

AUDIT ISSUES

- DFR-004:
  reseller identity is not persisted on orders; reseller accounting groups sales by customer name.
- DFR-005:
  custom orders allow arbitrary status transitions.
- DFR-006:
  Accounting’s selected date range is not carried into ExportDialog.

PART A — RESELLER ATTRIBUTION

1. Add nullable reseller identity fields to orders:
   - reseller_id;
   - reseller_name_snapshot;
   - applicable deduction snapshot;
   - any required reseller-pricing snapshot.

2. Add an explicit additive migration.
3. Do not guess reseller identity for historical orders.
4. Mark historical reseller orders without identity as:
   Unattributed legacy reseller sale.
5. Preserve snapshots even when the reseller is later renamed or deleted.
6. Update:
   - OrderDialog;
   - Order model;
   - DTO;
   - SQLite;
   - repository;
   - synchronization;
   - Recycle Bin;
   - receipts;
   - AccountingService;
   - Analytics;
   - Reports;
   - Reseller Accounting.

7. Group reseller accounting by persisted reseller ID, not customer name.

PART B — CUSTOM-ORDER STATE MACHINE

Define legal transitions explicitly.

At minimum address:
- pending;
- confirmed or processing when present;
- completed or delivered;
- cancelled;
- deleted;
- restored.

Do not allow:
- delivered → pending;
- cancelled → delivered without a documented recovery action;
- arbitrary transition selection.

Product decision:
- whether delivery requires a zero outstanding balance.
Provide a recommendation and obtain owner approval before enforcing that policy.

Correct:
- cancelled orders counted as active;
- misleading delete text;
- duplicate submission;
- payment history immutability;
- report and accounting status treatment.

PART C — ACCOUNTING EXPORT PARITY

1. Create one immutable accounting period/filter object.
2. Pass the exact selected screen period into:
   - preview;
   - CSV;
   - PDF;
   - Accounting;
   - relevant Reports.
3. Screen, preview, and exported values must use the same data snapshot.
4. Correct full-day end-exclusive date behavior.

Required tests:
- reseller selected for a customer with a different name;
- reseller rename after historical order;
- reseller soft deletion and order history;
- legacy unattributed order;
- every legal and illegal custom-order transition;
- balance-policy test after owner decision;
- cancelled custom order excluded correctly;
- screen/export fixture equality;
- date boundary at 00:00 following the end date.

Acceptance criteria:
- Reseller totals are attributed to the real reseller.
- Legacy orders are not falsely linked.
- Invalid custom-order transitions are impossible.
- Accounting screen and exports match exactly.

Save:
docs/progress/REMEDIATION_PHASE_4_COMPLETION.md

Do not begin Phase 5.
    ```
