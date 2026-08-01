# Remediation Phase 1 — Duplicate orders and protected logout

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-001, DFR-003, KNZ-SEC-001

    ## Entry gate

    Phase 0 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 1 — Duplicate orders and protected logout.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 1 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 1 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_0_COMPLETION.md;
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

    Execute only Remediation Phase 1 — Order command idempotency and protected-route logout.

AUDIT ISSUES

- DFR-001 / KNZ-SEC-001:
  repeated OrderDialog submission creates separate orders and repeatedly deducts stock.
- DFR-003:
  Recycle Bin is pushed above the authenticated root and can remain visible after logout or session timeout.

PART A — ORDER COMMAND IDEMPOTENCY

1. Inspect:
   - lib/dialogs/order_dialog.dart
   - lib/core/app_state.dart
   - order service and repository
   - order model and DTO
   - database schema and migrations
   - outbox implementation
   - existing order transaction tests

2. Add an in-flight submission guard:
   - reject re-entry at the start of submit;
   - disable all submit actions while saving;
   - restore UI state safely after failure;
   - do not hide the real failure.

3. Add a stable business-command identifier:
   - generate once before transaction execution;
   - reuse across retries and restarts;
   - persist it with the order or command ledger;
   - enforce uniqueness per authenticated UID;
   - replaying the same command must return the original successful result rather than creating a second order.

4. Ensure the same command cannot:
   - insert a second order;
   - deduct stock twice;
   - create duplicate order items;
   - create duplicate automatic debt;
   - enqueue duplicate business mutations.

5. Use an additive SQLite migration.
6. Preserve all existing orders.
7. Do not rely only on button disabling; repository/domain idempotency is required.

Required tests:
- rapid double tap;
- three repeated taps;
- slow-device delayed save;
- same command retried after a simulated timeout;
- same command retried after app restart;
- stock deducted exactly once;
- optional debt created exactly once;
- one outbox business mutation;
- a genuinely new command still creates a new order.

PART B — PROTECTED ROUTE RESET

1. Inspect MainShell, root authentication rebuild, dialogs, session timeout, and Recycle Bin navigation.
2. Ensure logout and session timeout:
   - close the drawer;
   - dismiss protected dialogs and bottom sheets;
   - remove all protected routes;
   - clear in-memory deleted-record lists;
   - stop user synchronization;
   - return only to Login;
   - prevent Android Back from reopening protected content.

3. Do not clear the user’s SQLite business data.

Required tests:
- logout while Recycle Bin is open;
- timeout while Recycle Bin is open;
- logout while an order or payment dialog is open;
- Android Back after logout;
- account switch after logout;
- protected data is not visible for one frame after logout.

Acceptance criteria:
- Repeating one order command changes stock and debt exactly once.
- No protected route survives logout or session timeout.
- Existing data remains intact.

Save:
docs/progress/REMEDIATION_PHASE_1_COMPLETION.md

Do not begin Phase 2.
    ```
