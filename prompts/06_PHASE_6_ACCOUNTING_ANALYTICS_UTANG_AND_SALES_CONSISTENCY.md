# Remediation Phase 6 — Accounting, analytics, Utang, and Sales consistency

    **Mode:** Build  
    **Model:** GPT-5.6 Sol  
    **Reasoning:** High  
    **Issue scope:** DFR-016, DFR-018..021

    ## Entry gate

    Phase 5 must be `PHASE COMPLETE`, and its independent review must return `APPROVE`.

    ## Copy-paste prompt

    ```text
    Continue only Remediation Phase 6 — Accounting, analytics, Utang, and Sales consistency.

    Follow AGENTS.md strictly.

    Read only:
    - AGENTS.md;
    - the shared safety, evidence, stop-condition, and Phase 6 sections of ORCHESTRATED_IMPLEMENTATION_guidev2.md;
    - Phase 6 findings in KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md;
    - docs/progress/REMEDIATION_PHASE_5_COMPLETION.md;
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

    Execute only Remediation Phase 6 — Cross-screen financial and business consistency.

AUDIT ISSUES

- DFR-016:
  Sales Table lacks export/status visibility and has an end-date boundary defect.
- DFR-018:
  Reseller Accounting lacks date filters, export, drill-down, and reliable settlement meaning.
- DFR-019:
  Custom Orders active counts and filters are incomplete.
- DFR-020:
  Utang progress ignores accrued interest and overdue semantics are unclear.
- DFR-021:
  Analytics uses inconsistent items-sold definitions.
- Cross-screen accounting and reporting consistency findings.

REPORTING POLICY

Use cash basis unless the owner explicitly approves another basis.

Do not:
- count unpaid credit creation as received revenue;
- count the same credit sale again when collected;
- describe revenue as profit without cost and expense data.

AUTHORITATIVE SERVICE

Use AccountingService as the single source for:
- recognized delivered non-credit sales;
- discounts;
- net sales;
- cash received;
- debt collections by payment timestamp;
- outstanding receivables;
- reseller totals;
- custom-order deposits and later payments;
- cancelled-order exclusion;
- date filtering;
- units fulfilled;
- units sold for cash;
- units sold on credit.

Do not duplicate formulas in UI or export classes.

ANALYTICS

1. Separate:
   - units fulfilled;
   - recognized cash-sale units;
   - credit units.
2. Apply one shared date range.
3. Exclude pending/processing records from recognized metrics.
4. Use persisted reseller identity.
5. Payment-method analytics must use an explicitly documented status scope.

UTANG

1. Show:
   - original principal;
   - principal outstanding;
   - interest outstanding;
   - total outstanding;
   - total paid.
2. Calculate progress against the full obligation, not original principal alone.
3. Provide:
   - All;
   - Unpaid;
   - Paid;
   - Overdue.
4. Do not claim a customer-specific due date when only a seven-day age policy exists.
5. Ask the owner before introducing a persisted due-date migration.
6. Add duplicate-payment replay protection and tests.

SALES TABLE

1. Clarify whether it is Recognized Sales or all orders.
2. Add:
   - status visibility;
   - payment method;
   - filtered CSV/PDF export;
   - correct end-exclusive date filtering;
   - clear-filters action.
3. Screen summary and exports must match.

RESELLER ACCOUNTING

After Phase 4 reseller migration:
- date filtering;
- search;
- reseller drill-down;
- gross SRP reference;
- discounts;
- actual customer-pay revenue;
- order count;
- export.

Do not invent commission payable or reseller receivables unless the owner defines that business model.

CUSTOM ORDERS

- correct active count;
- add search, status filter, and sorting;
- use approved custom-order state machine;
- include deposits and later payments correctly.

FIXED TEST FIXTURE

Create one hand-computed fixture containing:
- normal paid order;
- pending order;
- cancelled order;
- reseller order;
- Utang order;
- partial debt payment;
- interest-bearing debt;
- custom order deposit;
- later custom payment;
- date-boundary records.

Assert identical results across:
- Overview;
- Analytics;
- Accounting;
- Sales;
- Utang;
- Reseller Accounting;
- Reports;
- CSV;
- PDF.

Acceptance criteria:
- The same filtered source produces the same totals everywhere.
- Credit sales are never double-counted.
- Interest is not hidden in Utang progress.
- Sales and exports have identical date boundaries.

Save:
docs/progress/REMEDIATION_PHASE_6_COMPLETION.md

Do not begin Phase 7.
    ```
