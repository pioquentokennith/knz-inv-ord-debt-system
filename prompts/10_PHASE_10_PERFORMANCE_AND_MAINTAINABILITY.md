# Remediation Phase 10 — Performance and maintainability

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-025, DFL-005

    ## Entry gate

    Phase 9 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 10 — Performance and maintainability.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 10 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 10 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_9_COMPLETION.md;
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

    Execute only Remediation Phase 10 — Performance, caching, and maintainable architecture.

AUDIT ISSUES

- DFR-025;
- DFL-005;
- AppState and Analytics performance findings.

Do not change verified financial or transaction results.

DATA REVISION AND CACHING

1. Add a monotonically increasing AppState data revision.
2. Increment only when authoritative data changes.
3. Cache AccountingReport by:
   - data revision;
   - selected accounting period;
   - relevant business policy.
4. Cache AnalyticsSnapshot using stable inputs.
5. Stop returning new list objects from getters when stable identity is required.
6. Preserve immutability without defeating memoization.

UI PERFORMANCE

- replace eager large SingleChildScrollView trees with lazy slivers;
- split Analytics into independently rebuilding sections;
- reduce nested shrinkWrap lists;
- avoid full-screen rebuilds for unrelated state changes;
- preserve all responsive work from Phases 7 and 8.

EXPORT PERFORMANCE

- move pure PDF/CSV aggregation and formatting off the UI isolate when compatible;
- keep plugin calls on supported isolates;
- show progress;
- handle cancellation or failure;
- do not create inconsistent partial export files.

DATA VOLUME

Profile representative datasets:
- 100 products;
- 1,000 orders;
- 1,000 debts/payments;
- 10,000 sales rows where feasible.

Do not add pagination blindly.
Add repository-level pagination only where measurements show it is needed and correctness is preserved.

ARCHITECTURE

Break down only oversized files touched by this phase:
- app_state.dart;
- analytics_screen.dart;
- export_service.dart;
- other measured hotspots.

Do not perform a broad rewrite.

Required tests:
- cached and uncached accounting equality;
- cached and uncached analytics equality;
- cache invalidation;
- period change;
- unrelated state update does not recalculate;
- large export equality;
- scroll/build benchmarks;
- no memory growth from repeated navigation;
- synchronization behavior remains unchanged.

Acceptance criteria:
- No calculation drift.
- Representative datasets scroll without severe jank.
- Report recalculation occurs only when inputs change.
- Large exports do not freeze core navigation.
- Existing business and synchronization tests remain green.

Save:
docs/progress/REMEDIATION_PHASE_10_COMPLETION.md

Do not begin Phase 11.
    ```
