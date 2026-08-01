# Remediation Phase 3 — Suspension, revocation, and offline authorization

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-007, DFR-026, KNZ-SEC-003, KNZ-SEC-012

    ## Entry gate

    Phase 2 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 3 — Suspension, revocation, and offline authorization.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 3 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 3 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_2_COMPLETION.md;
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

    Execute only Remediation Phase 3 — Administrator lifecycle and bounded offline authorization.

AUDIT ISSUES

- KNZ-SEC-003:
  cached approved users may restore access while suspended or disabled.
- DFR-007:
  the Administrator workflow handles pending accounts but cannot safely suspend or reactivate approved Staff.
- KNZ-SEC-012:
  privileged screen access relies partly on navigation hiding.

PRODUCT DECISION

The owner must approve the offline authorization lease duration.

Before implementation:
1. Recommend a lease duration based on the app’s local-first requirements.
2. Explain security and usability consequences.
3. Do not silently choose an unlimited lease.

ADMINISTRATOR LIFECYCLE

Implement Administrator-only workflows for:
- list active Staff;
- list suspended Staff;
- suspend approved Staff;
- reactivate suspended Staff;
- view pending, rejected, approved, and suspended status;
- prevent self-suspension or self-review;
- prevent Staff from performing lifecycle actions;
- prevent client assignment of Administrator role;
- record an auditable access-lifecycle event.

FIRESTORE RULES

Support only valid transitions:
- pending → approved Staff;
- pending → rejected;
- pending → suspended when intentionally supported;
- approved Staff → suspended;
- suspended Staff → approved;
- no Staff self-review;
- no Staff role escalation;
- no Administrator role assignment through client review;
- no owner or UID replacement.

OFFLINE AUTHORIZATION

Design:
- last successful access verification timestamp;
- authorization lease expiry;
- access generation or revocation epoch;
- cached profile tied to UID and access epoch;
- revalidation after reconnecting;
- session restoration must reject expired offline authorization;
- logout clears active sensitive in-memory state;
- switching UID cannot reuse another account’s cache.

Firebase Auth disablement:
- handle disabled Auth accounts safely;
- do not assume issued tokens are immediately revoked;
- require accountAccess revocation as the application authorization boundary.

ROUTE AND SERVICE ENFORCEMENT

Enforce role requirements at:
- drawer visibility;
- navigation selection;
- screen construction;
- service method;
- Firestore Rules.

Required tests:
- approved Staff suspended while online;
- approved Staff suspended while device is offline;
- offline lease still valid;
- offline lease expired;
- Auth user disabled with an unexpired token;
- reactivation;
- Staff direct navigation to Administrator screen;
- Staff attempting lifecycle writes;
- Administrator attempting self-review;
- account switching and cached profile isolation.

Acceptance criteria:
- Suspended or expired users cannot restore protected access.
- Active approved users retain the explicitly approved offline behavior.
- Staff cannot invoke Administrator operations from a modified UI.
- Administrator lifecycle management works without Cloud Functions.

Save:
docs/progress/REMEDIATION_PHASE_3_COMPLETION.md

Do not begin Phase 4.
    ```
