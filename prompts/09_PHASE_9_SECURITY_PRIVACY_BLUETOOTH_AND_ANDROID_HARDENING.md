# Remediation Phase 9 — Security, privacy, Bluetooth, and Android hardening

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** KNZ-SEC-005..007, 009..014, DFL-007

    ## Entry gate

    Phase 8 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 9 — Security, privacy, Bluetooth, and Android hardening.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 9 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 9 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_8_COMPLETION.md;
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

    Execute only Remediation Phase 9 — Security, privacy, input, Bluetooth, and Android hardening.

AUDIT ISSUES

- KNZ-SEC-005 through KNZ-SEC-014;
- KNZ-LIKELY findings;
- DFL-007.

ANDROID DATA PROTECTION

1. Add explicit Android backup and data-extraction rules.
2. Exclude sensitive databases, SharedPreferences where appropriate, outbox, exports, caches, and product images from backup unless an approved encrypted backup design exists.
3. Do not introduce database encryption without a tested migration and key-recovery plan.
4. Add screenshot/recent-app protection for authenticated sensitive screens.
5. Verify Android 14 and Android 15 behavior.
6. Do not enable cleartext traffic.

CRASHLYTICS

1. Add a redaction layer.
2. Report:
   - operation code;
   - exception category;
   - sanitized stack;
   - non-sensitive context.
3. Never report:
   - customer details;
   - email;
   - phone;
   - GCash details;
   - debt amount;
   - payment reference;
   - DTO payload;
   - SQL record contents;
   - local file paths containing personal data.

GCASH PRIVACY

- remove phone and account-name duplication from free-text notes;
- preserve only approved operationally required structured reference data;
- document retention;
- do not silently rewrite historical notes without an owner-approved migration.

BLUETOOTH

1. Create shared printer connection logic.
2. Verify expected printer service and characteristic UUIDs.
3. Do not send receipt data to the first arbitrary writable characteristic.
4. Display stable device identity before first trust.
5. Persist trusted printer only when safe.
6. Handle:
   - wrong device;
   - wrong service;
   - permission denial;
   - disconnect;
   - unavailable printer;
   - duplicate print taps.
7. Do not let printing failure duplicate an order or payment.

INPUT BOUNDS

Define and enforce at form, domain, DTO, SQLite, and Firestore layers:
- maximum lengths;
- control-character policy;
- numeric maxima;
- nonnegative values;
- image byte-size limit;
- image decoded-dimension limit;
- file-signature validation;
- interest-rate business maximum;
- username normalization;
- cleartext URL rejection when applicable.

EXPORT PRIVACY

- retain CSV formula neutralization;
- add startup cleanup for stale temporary exports;
- use a dedicated cache directory;
- document that external share targets retain their copies.

CONFIGURATION

- remove obsolete google-services.old.json only after owner approval;
- correct release documentation so Spark deployment does not require Anonymous Auth or Cloud Functions;
- document local login throttling as UX only, not authoritative security;
- do not deploy optional OTP Functions;
- keep App Check considerations documented when Functions are ever deployed.

Required tests:
- backup exclusion inspection;
- screenshot/recent-app behavior;
- Crashlytics redaction sink;
- GCash serialization privacy;
- wrong Bluetooth device and service;
- permission denial;
- repeated print;
- oversized strings and images;
- control characters;
- extreme numeric values;
- temporary-export startup cleanup.

Acceptance criteria:
- No sensitive data enters Crashlytics unintentionally.
- Backups do not expose local financial records by default.
- Receipt data is sent only to a verified supported printer.
- Persisted inputs stay within documented limits.
- Spark architecture documentation is consistent.

Save:
docs/progress/REMEDIATION_PHASE_9_COMPLETION.md

Do not begin Phase 10.
    ```
