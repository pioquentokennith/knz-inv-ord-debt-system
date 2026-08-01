# Remediation Phase 11 — Complete test safety net, CI, and dependencies

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** KNZ-SEC-008 and remaining test/CI/dependency gaps

    ## Entry gate

    Phase 10 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 11 — Complete test safety net, CI, and dependencies.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 11 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 11 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_10_COMPLETION.md;
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

    Execute only Remediation Phase 11 — Automated safety coverage, CI, and dependency hygiene.

Do not implement new application features.

TEST MATRIX

Add or complete:

Unit:
- domain validation;
- accounting fixtures;
- custom-order transitions;
- authorization lease;
- Crashlytics redaction;
- input boundaries;
- printer service validation;
- responsive decisions.

Repository/SQLite:
- command idempotency;
- duplicate payment replay;
- migration fixtures from every supported version;
- reseller attribution;
- restore;
- hard delete;
- image-file cleanup;
- account partitioning.

Widget:
- every drawer screen;
- role visibility;
- route guards;
- drawer and Back;
- empty/loading/error/offline states;
- search/filter/sort;
- touch targets;
- text scaling;
- compact/medium/expanded layouts.

Integration:
- order → stock → debt;
- offline order → reconnect;
- logout from protected routes;
- account switching;
- suspension and lease expiry;
- two-device conflict;
- Recycle Bin restore;
- permanent-delete role checks.

Firestore Rules emulator:
- every business field invariant;
- revisions;
- stale writes;
- suspension/reactivation;
- cross-UID access;
- Staff privilege attempts;
- malformed documents;
- tombstones.

Bluetooth:
- wrong service;
- wrong characteristic;
- permission denial;
- disconnection;
- duplicate print.

Golden:
- drawer;
- Reports;
- Recycle Bin;
- Overview;
- Orders;
- Custom Orders;
- Accounting;
- key empty/error states.

CI

Run on pull request and main:
- formatting;
- analyze;
- Flutter tests;
- Rules emulator;
- Functions retained-source tests;
- debug APK build;
- secret scan;
- dependency audit;
- coverage reporting.

Set a realistic coverage threshold based on the current baseline and raise it deliberately.

DEPENDENCIES

1. Run audits read-only first.
2. Classify:
   - production runtime;
   - build-time;
   - emulator-only;
   - development-only.
3. Upgrade one direct dependency at a time.
4. Do not use npm audit fix --force.
5. Do not bundle unrelated major upgrades.
6. Re-run complete relevant suites after each update.
7. Pin GitHub Actions to immutable commit SHAs.
8. Preserve lockfiles.

Acceptance criteria:
- Every critical and high finding has a regression test.
- Complete CI passes from a clean checkout.
- No high or critical production-runtime advisory remains untriaged.
- Emulator-only risks are documented.
- No secret appears in CI output.
- APK debug build succeeds.

Save:
docs/progress/REMEDIATION_PHASE_11_COMPLETION.md

Do not begin Phase 12.
    ```
