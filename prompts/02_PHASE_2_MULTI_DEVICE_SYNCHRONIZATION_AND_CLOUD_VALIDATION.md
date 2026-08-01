# Remediation Phase 2 — Multi-device synchronization and cloud validation

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-002, KNZ-SEC-002, KNZ-SEC-004

    ## Entry gate

    Phase 1 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 2 — Multi-device synchronization and cloud validation.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 2 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 2 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_1_COMPLETION.md;
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

    Execute only Remediation Phase 2 — Revision-based synchronization and Firestore business validation.

AUDIT ISSUES

- DFR-002 / KNZ-SEC-002:
  absolute merge writes allow concurrent devices to lose stock deductions or overwrite debt/payment state.
- KNZ-SEC-004:
  Firestore business documents lack sufficient field-level and transition validation.

PRODUCT DECISION

Recommended design:
support true multi-device use with revision-based conflict detection.

Before editing:
- verify whether the current architecture can support revision-based synchronization safely;
- document the proposed conflict policy;
- stop for owner approval if the proposed schema could reinterpret existing production records.

REQUIRED DESIGN

1. Add version or revision metadata to synchronized entities:
   - products;
   - orders;
   - debts;
   - payments or embedded payment state;
   - resellers;
   - custom orders;
   - activity logs when appropriate;
   - tombstones.

2. Include:
   - schema_version;
   - revision;
   - updated_at;
   - updated_by_device or writer identifier when privacy-safe;
   - stable operation or command ID;
   - deleted/tombstone revision.

3. Do not use blind absolute last-write-wins for stock, debt, or payment state.

4. Implement conflict-safe behavior:
   - compare expected revision with remote revision;
   - reject stale writes;
   - use Firestore transactions where business invariants require them;
   - preserve the local record and failed outbox row when conflict occurs;
   - show a user-visible conflict or manual-resolution state;
   - never silently overwrite newer remote data.

5. Preserve local-first behavior:
   - local mutation and outbox insertion remain atomic;
   - no outbox row is removed until confirmed remote success;
   - conflicts remain retryable or resolvable;
   - network availability is not treated as Firebase success.

6. Add explicit DTO schema migration and backward-compatible decoding.
7. Existing records without revisions must receive safe initial versions.
8. Do not fabricate missing historical ownership or payment information.

FIRESTORE RULES

Add Spark-compatible validation for:
- allowed keys;
- authenticated UID ownership;
- immutable document ID and owner;
- nonnegative integer-centavo prices and totals;
- nonnegative stock and quantities;
- known status values;
- bounded text lengths;
- valid revision increments;
- immutable creation fields;
- safe tombstone transitions;
- order and custom-order transition rules where Rules can verify them;
- debt/payment fields that cannot become negative;
- activity-log schema boundaries.

Required tests:
- two devices selling the same product concurrently;
- two devices recording debt payments concurrently;
- stale product update;
- stale order update;
- stale tombstone or restore;
- duplicate delivery attempt;
- offline write followed by newer remote write;
- conflict survives restart;
- valid revision increment accepted;
- skipped or decreasing revision rejected;
- malformed money, stock, quantity, status, owner, and field sets rejected;
- old unversioned records migrate safely.

Acceptance criteria:
- Two valid concurrent operations cannot silently lose a stock deduction or payment.
- Stale writes are rejected and visible.
- Firestore rejects malformed business data independently of Flutter.
- The solution remains Spark-compatible.
- No production data is deleted.

Save:
docs/progress/REMEDIATION_PHASE_2_COMPLETION.md

Do not begin Phase 3.
    ```
