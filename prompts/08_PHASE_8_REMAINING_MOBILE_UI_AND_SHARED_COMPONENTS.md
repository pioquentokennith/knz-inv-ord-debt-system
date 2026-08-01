# Remediation Phase 8 — Remaining mobile UI and shared components

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-012..024, DFR-027..028, DFL-004, DFL-006

    ## Entry gate

    Phase 7 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 8 — Remaining mobile UI and shared components.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 8 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 8 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_7_COMPLETION.md;
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

    Execute only Remediation Phase 8 — Remaining responsive screens and shared UI system.

This is not the old release-hardening Phase 8. It belongs only to the new remediation series.

AUDIT ISSUES

- DFR-012 through DFR-024;
- DFL-004 and DFL-006;
- related low-severity visual consistency issues.

SHARED COMPONENTS

Create or consolidate:
- ResponsivePageScaffold;
- ResponsiveHeader;
- ResponsiveFilterBar;
- AdaptiveMetricGrid;
- AdaptiveDataView;
- FeatureStateView;
- shared 48×48 action controls;
- shared spacing, image, card, and typography tokens.

SCREENS

Overview:
- show all cards at every breakpoint;
- role-neutral heading for Staff;
- card navigation;
- refresh and last-updated state;
- accessible metric labels.

Inventory:
- empty and no-results states;
- responsive search/filter;
- sorting;
- consistent stock and image presentation.

Orders:
- responsive filter bar;
- overflow-safe count/bulk action;
- clear filtered empty state;
- sort options;
- no regression to Phase 1 idempotency.

Product Catalogue:
- resolve duplication with Inventory.
Recommended:
  - Inventory remains management;
  - Catalogue becomes read-focused visual browsing.
- adaptive card height;
- consistent image policy;
- remove unauthorized management controls when applicable.

Analytics:
- responsive chart sizes;
- textual chart alternatives;
- lazy sections;
- shared date filter from Phase 6.

Utang:
- responsive statistics;
- responsive actions;
- clear states and debt components.

Sales:
- compact cards below 600;
- expanded data table above;
- responsive totals and filters.

Resellers:
- search;
- sorting;
- accurate soft-delete wording;
- adaptive cards;
- duplicate-name policy.

Reseller Accounting:
- responsive metrics and drill-down.

Custom Orders:
- responsive amount display;
- action overflow menu;
- search/filter/sort;
- correct empty state;
- no regression to the state machine.

Accounting:
- compact cards or scrollable tables;
- accurate labels;
- responsive tabs;
- filter-reset empty state.

Admin Portal:
- responsive account rows;
- permission state;
- retry;
- active/suspended/pending tabs from Phase 3.

DRAWER AND HEADERS

- remove duplicate SafeArea plus manual status-bar padding;
- consistent top spacing;
- bottom SafeArea;
- minimum touch targets;
- tooltips and Semantics;
- keyboard and view-inset safety.

Required tests:
- every drawer destination at 360, 400, 600, and 840 widths;
- portrait and landscape;
- text scales 1.0, 1.3, and 2.0;
- keyboard open;
- long names;
- long prices and totals;
- no Flutter overflow exceptions;
- semantic labels and touch-target assertions.

Acceptance criteria:
- All drawer features are usable on small phones.
- No fixed-height card clips required content.
- No search/filter row overflows.
- Empty/no-results states are useful and consistent.
- No verified business logic changes.

Save:
docs/progress/REMEDIATION_PHASE_8_COMPLETION.md

Do not begin Phase 9.
    ```
