# Remediation Phase 12 — Device validation, release, and distribution gate

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** Final verification of all findings

    ## Entry gate

    Phase 11 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 12 — Device validation, release, and distribution gate.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 12 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 12 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_11_COMPLETION.md;
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

    Execute only Remediation Phase 12 — Final physical-device, release, documentation, and reseller-distribution gate.

Do not implement new features unless a confirmed release-blocking defect requires the smallest focused correction.

DEVICES

1. TECNO CK8n
   - Android 14 / API 34
   - Device ID: 106272539Q101518

2. TECNO LJ9
   - Android 15 / API 35
   - Device ID: 14451255BL109587

OWNER-OBSERVED DEVICE TESTS

Guide the owner one action at a time.

Test:
- cold launch;
- Administrator login;
- Staff login;
- role restrictions;
- logout;
- session timeout;
- suspension/reactivation;
- offline authorization lease;
- drawer scrolling;
- Android Back;
- system bars;
- keyboard insets;
- text scale;
- rotation;
- Overview;
- Inventory;
- Product Catalogue;
- Orders;
- duplicate-tap protection;
- exact stock deduction;
- Analytics;
- Utang;
- Sales;
- Resellers;
- Reseller Accounting;
- Custom Orders;
- Accounting;
- Reports;
- Recycle Bin;
- restore;
- Administrator-only permanent delete;
- offline creation;
- reconnection;
- conflict handling;
- account switching;
- notifications;
- PDF/CSV sharing;
- Bluetooth permission;
- supported printer output;
- wrong/unavailable printer;
- screenshot/recent-app protection.

Use dedicated records:
- RELEASE-TEST-PRODUCT
- RELEASE-TEST-ORDER
- RELEASE-TEST-DEBT
- RELEASE-TEST-RESELLER
- RELEASE-TEST-CUSTOM
- RELEASE-TEST-STAFF

Do not alter real business records.

MULTI-DEVICE TEST

Using safe dedicated accounts/data:
- same UID on both devices when permitted;
- concurrent order attempts;
- concurrent product update;
- concurrent debt payment;
- tombstone and restore conflict;
- confirm stale writes are rejected and visible;
- confirm no lost stock or payment.

RELEASE BUILD

Verify:
- package com.knzscent.admin;
- Firebase project knz-scent;
- same release signing identity;
- release never falls back to debug signing;
- no secrets included;
- backup policy;
- release merged manifest;
- permissions;
- Crashlytics redaction;
- release logs;
- R8/minification only when tested;
- universal APK;
- optional split-per-ABI APKs;
- SHA-256 checksums;
- version name and code;
- supported ABIs.

Do not expose signing values.

DOCUMENTATION

Create or update:
- docs/remediation/FINAL_REMEDIATION_REPORT.md
- docs/testing/DEVICE_COMPATIBILITY_MATRIX.md
- docs/testing/FINAL_DEVICE_ACCEPTANCE.md
- docs/release/RELEASE_BUILD_GUIDE.md
- docs/release/RESELLER_INSTALLATION_GUIDE.md
- docs/release/RELEASE_CHECKLIST.md
- docs/security/SECURITY_REVIEW.md
- docs/security/ANDROID_DATA_PROTECTION.md
- docs/privacy/DATA_HANDLING_AND_RETENTION.md
- docs/plans/DRAWER_FEATURE_AUDIT.md
- docs/plans/MOBILE_UI_REMEDIATION_PLAN.md
- docs/plans/FEATURE_DATA_CONSISTENCY_PLAN.md
- docs/plans/DRAWER_TEST_PLAN.md

Do not invent:
- legal entity;
- jurisdiction;
- privacy contact;
- retention period;
- effective date.

GIT REVIEW

Produce exact lists:
1. Safe to stage.
2. Requires owner review.
3. Must never be staged.
4. Generated output.
5. Unrelated or uncertain.

Do not stage or commit.

Ask exactly:

APPROVE FINAL REMEDIATION COMMIT?

FINAL VERDICT

Use one:
- READY FOR RESELLER DISTRIBUTION
- NOT READY FOR RESELLER DISTRIBUTION

Return READY only when:
- all critical and high defects are closed;
- multi-device tests pass;
- Administrator and Staff authorization pass;
- no protected route survives logout;
- order commands are idempotent;
- stock/debt/payment synchronization does not lose updates;
- screen and export totals match;
- Android 14 and 15 tests pass;
- Bluetooth passes or is explicitly accepted as deferred;
- release APK is correctly signed;
- no secret is tracked or packaged;
- Firebase remains Spark-compatible;
- no production Cloud Functions dependency exists;
- no real data was deleted;
- all completion reports are accurate.

Save:
docs/progress/REMEDIATION_PHASE_12_COMPLETION.md

Stop after the final report.
    ```
