# Remediation Phase 5 — Drawer, navigation, roles, and back behavior

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-003, DFR-026, DFR-029, DFL-001..003, KNZ-SEC-012

    ## Entry gate

    Phase 4 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 5 — Drawer, navigation, roles, and back behavior.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 5 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 5 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_4_COMPLETION.md;
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

    Execute only Remediation Phase 5 — Drawer and authenticated-navigation correctness.

AUDIT ISSUES

- DFR-026:
  navigateTo() and destination construction lack role guards.
- DFL-002:
  custom drawer does not properly handle Android Back.
- DFL-003:
  fixed footer may overlap system navigation.
- DFR-029:
  “Admin Portal” is decorative and visible to Staff.
- DFL-001:
  Staff permanent-delete policy is unresolved.

REQUIRED IMPLEMENTATION

1. Introduce one destination definition model containing:
   - NavItem;
   - label;
   - icon;
   - required role or capability;
   - destination builder;
   - selected-state behavior;
   - whether it is visible;
   - whether it is read-only.

2. Add shared authorization:
   - DrawerDestination;
   - AuthorizedDestination or equivalent;
   - authenticated navigation coordinator.

3. Role checks must exist at:
   - menu visibility;
   - navigateTo();
   - destination builder;
   - service boundary where privileged;
   - Firestore Rules.

4. Integrate Recycle Bin into MainShell rather than using a separate protected pushed route.

5. Add PopScope or equivalent:
   - Back closes drawer first;
   - Back does not reveal unauthorized destinations;
   - Back after logout cannot reopen protected screens.

6. Add correct SafeArea handling:
   - status bar;
   - gesture navigation;
   - three-button navigation;
   - fixed profile and sign-out footer.

7. Replace decorative “Admin Portal” wording:
   - Staff sees role-neutral application branding;
   - Administrator receives a real Administrator destination or clearly labeled access section.

8. Selected-state highlighting must work for every destination.

9. Permanent-delete policy:
   - use Administrator-only as the safe default;
   - do not loosen it without explicit owner approval;
   - Staff may restore only when approved by the documented role matrix.

Required tests:
- Staff direct navigation;
- Administrator direct navigation;
- selected-item state;
- drawer closes after selection;
- Back closes drawer;
- Back does not exit while drawer is open;
- gesture and three-button navigation layouts;
- bottom footer does not overlap system navigation;
- Recycle Bin selected state;
- permanent-delete controls by role;
- logout from every destination.

Acceptance criteria:
- No destination depends only on hidden UI for authorization.
- Back navigation is predictable.
- Drawer content is fully reachable.
- System bars do not cover the footer.
- Recycle Bin behaves like other destinations.

Save:
docs/progress/REMEDIATION_PHASE_5_COMPLETION.md

Do not begin Phase 6.
    ```
