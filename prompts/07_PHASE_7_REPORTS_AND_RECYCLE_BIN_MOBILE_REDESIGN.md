# Remediation Phase 7 — Reports and Recycle Bin mobile redesign

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-008..011

    ## Entry gate

    Phase 6 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 7 — Reports and Recycle Bin mobile redesign.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 7 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 7 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_6_COMPLETION.md;
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

    Execute only Remediation Phase 7 — Reports and Recycle Bin responsive redesign.

AUDIT ISSUES

- DFR-008:
  Recycle Bin can remain loading indefinitely when one repository read fails.
- DFR-009:
  Reports keeps a narrow permanent sidebar on phones.
- DFR-010:
  Recycle Bin entity tabs are difficult to discover on narrow screens.
- DFR-011:
  Accounting/custom-payment table can overflow narrow screens.
- Screenshot evidence shows truncated report labels and crowded horizontal controls.

SHARED RESPONSIVE BREAKPOINTS

Use one application-wide policy:
- compact: below 600;
- medium: 600–839;
- expanded: 840 and above.

REPORTS

Compact:
- full-width content;
- report-selector button;
- searchable bottom sheet;
- full labels and descriptions;
- selected-state indicator;
- no permanent sidebar.

Medium:
- dropdown, collapsible rail, or compact selector.

Expanded:
- approximately 220-pixel report sidebar;
- full labels without forced ellipsis.

Preserve:
- selected report across orientation changes;
- date filters;
- preview;
- PDF/CSV actions;
- export loading and failure state;
- generated-at and sync context.

RECYCLE BIN

1. Replace narrow tab strip on compact layouts with an entity selector containing:
   - entity name;
   - deleted count;
   - selected state.
2. Keep expanded tabs only when they fit.
3. Add:
   - loading state;
   - partial repository failure handling;
   - retry;
   - no-results state;
   - permission-denied state;
   - deleted-at timestamp;
   - restore consequences;
   - permanent-delete consequences.
4. Do not let one failed repository leave the entire screen spinning.
5. Update local lists immediately after restore or permanent deletion.
6. Preserve Administrator-only hard delete.
7. Do not add Customers because no customer repository exists.

ACCOUNTING TABLE

Use:
- responsive cards on compact screens; or
- correctly bounded horizontal scrolling.

SHARED COMPONENTS

Create:
- ReportSelectorSheet;
- EntityTypeSelector;
- AsyncContentState;
- AdaptiveDataView.

Required golden/widget tests:
- widths 360, 400, 600, 840;
- portrait and landscape;
- text scales 1.0, 1.3, and 2.0;
- report selection;
- long report names;
- repository failure;
- partial failure;
- empty records;
- export in progress;
- restore and hard-delete role behavior.

Acceptance criteria:
- No clipped report label.
- No horizontal layout overflow.
- Recycle Bin never remains indefinitely loading.
- All controls meet at least 48×48 touch targets.
- Compact phone content uses the full available width.

Save:
docs/progress/REMEDIATION_PHASE_7_COMPLETION.md

Do not begin Phase 8.
    ```
