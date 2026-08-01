# Remediation Phase 0 — Attributable baseline

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** All audit registries and baseline classification

    ## Entry gate

    This phase establishes the baseline.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 0 — Attributable baseline.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 0 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 0 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - the current Git and repository baseline;


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

    Execute only Remediation Phase 0 — Establish an attributable remediation baseline.

This phase must not change application behavior.

Tasks:

1. Inspect:
   - git branch --show-current
   - git rev-parse HEAD
   - git status --short
   - git diff --check
   - git diff --stat
   - git diff --name-status
   - all untracked files
   - ignored sensitive and generated files

2. Classify every changed or untracked path as:
   - accepted existing implementation;
   - previous Phase 8 work;
   - security remediation;
   - drawer or feature remediation;
   - tests;
   - documentation;
   - generated output;
   - sensitive file that must never be tracked;
   - obsolete backup;
   - unrelated or uncertain.

3. Confirm these are not tracked:
   - service-account JSON;
   - keystores;
   - key.properties;
   - environment-secret files;
   - passwords;
   - private keys;
   - build outputs;
   - local databases;
   - logs.

4. Review android/app/google-services.old.json.
   - Confirm whether it is obsolete and unreferenced.
   - Do not delete it automatically.
   - Mark it as never-to-stage when obsolete.

5. Confirm active identifiers:
   - package and namespace: com.knzscent.admin
   - Firebase project: knz-scent
   - Firebase Android App ID:
     1:120139747390:android:823a15d9a89f4cfaf6816f

6. Create:
   docs/remediation/REMEDIATION_BASELINE.md

7. Record the audit issue inventory:
   - DFR-001 through DFR-029;
   - DFL-001 through DFL-007;
   - KNZ-SEC-001 through KNZ-SEC-014;
   - likely security findings;
   - phase ownership for every issue.

8. Do not stage or commit.

Acceptance criteria:
- Every current path is classified.
- No secret is tracked.
- The starting branch and commit are documented.
- Every audit issue is assigned to one later remediation phase.
- No source behavior changed.

Save:
docs/progress/REMEDIATION_PHASE_0_COMPLETION.md

Do not begin Phase 1.
    ```
