# Phase 6 Completion Report

## Implemented
- Added one immutable, pure cash-basis `AccountingReport` for paid-order sales, discounts, debt collections, receivables, reseller totals, and custom-order receipts.
- Applied inclusive reporting periods to order transaction dates and immutable debt/custom payment timestamps without double-counting Utang orders.
- Routed AppState dashboard totals, accounting, reports, analytics, CSV, and PDF summaries through the shared accounting result.
- Made the accounting ledger and cards use the same recognized paid-order population, removed the duplicate net column, and corrected accounting export routing.
- Added initial custom-order deposit rows and a later-payment action backed by the existing transactional payment-ledger/outbox update.
- Preserved legacy aggregate custom payments as all-time receipts without inventing timestamps for bounded reports.
- Corrected Revenue & Collections naming and aligned its screen, CSV, and PDF breakdowns.
- Added explicit principal, interest, and total-due data to debt PDFs and payment history to custom-order exports.
- Added reseller per-item detail and consistently used customer-pay totals in the ledger, receipt, recycle bin, exports, and dashboard.
- Excluded cancelled orders from active order exports and recognized sales totals.
- Changed PDF currency output to an ASCII `PHP` prefix so monetary values remain readable with the offline Helvetica fallback.

## Files changed
- `lib/core/app_state.dart`
- `lib/dialogs/custom_order_dialog.dart`
- `lib/dialogs/export_dialog.dart`
- `lib/models/custom_order_model.dart`
- `lib/screens/accounting_screen.dart`
- `lib/screens/analytics_screen.dart`
- `lib/screens/custom_orders_screen.dart`
- `lib/screens/overview_screen.dart`
- `lib/screens/receipt_screen.dart`
- `lib/screens/recycle_bin_screen.dart`
- `lib/screens/reports_screen.dart`
- `lib/services/accounting_service.dart`
- `lib/services/export_service.dart`
- `test/fixtures/accounting_fixture.dart`
- `test/repositories/entity_outbox_test.dart`
- `test/screens/accounting_views_test.dart`
- `test/screens/receipt_screen_test.dart`
- `test/services/accounting_service_test.dart`
- `test/services/export_service_test.dart`
- `docs/progress/PHASE_6_COMPLETION.md`

## Database or API contract changes
- No schema version or migration change was required; Phase 6 uses the Phase 5 `custom_order_payments` table and embedded cloud DTO contract.
- Added `AccountingPeriod`, `AccountingReport`, debt/custom collection rows, and `OrderFinancialBreakdown` as derived non-persisted contracts.
- Added `AppState.accountingReport` and `AppState.addCustomOrderPayment()`.
- New custom orders persist a timestamped immutable row for a non-zero initial deposit.
- `CustomOrder` now distinguishes timestamped payment rows from an unattributed legacy aggregate. Recorded rows may not exceed the stored paid total.
- Analytics export methods now accept custom orders and payment-period boundaries.

## Tests added or updated
- Added a shared hand-computed fixture with a normal paid order, cancelled order, discounted reseller order, delivered Utang order, partial principal/interest collection, outstanding interest, initial/later custom payments, and both date boundaries.
- Added service assertions for exact centavo totals, cancelled/credit exclusion, no double-counting, receivables, reseller totals, and legacy custom-payment handling.
- Added dashboard, accounting-ledger, and report-preview parity widget tests using the same fixture.
- Added CSV cell and PDF generation tests using the same fixture.
- Added reseller receipt SRP/customer-pay assertions.
- Extended repository/outbox coverage for atomically appending a later custom-order payment.

## Commands run
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test --coverage`
- `flutter test test/services/accounting_service_test.dart test/services/export_service_test.dart test/screens/accounting_views_test.dart`
- `flutter test test/models/domain_invariants_test.dart test/repositories/entity_outbox_test.dart test/dialogs/utang_receipt_printer_test.dart`
- `flutter test test/screens/receipt_screen_test.dart`
- `git diff --check`

## Validation results
- PASS: formatting check completed with 110 files checked and 0 changes required.
- PASS: `flutter analyze` reported 0 errors and 0 warnings. It retained 27 informational lint notices already present in the worktree.
- PASS: `flutter test --coverage` completed all 116 tests.
- PASS: focused accounting, dashboard, reports, CSV, PDF, receipt, model, and transactional outbox tests passed.
- PASS: `git diff --check` found no whitespace errors; Git emitted only existing Windows line-ending notices.
- Firebase Functions commands were not run because Phase 6 did not modify Functions, Firestore rules, or backend dependencies.

## Product decisions made
- Reporting remains cash basis: delivered non-credit orders count once, Utang counts only from payment rows, and custom orders count from actual receipts.
- `customerPayAmount` remains the authoritative reseller total; SRP is reference-only.
- The report remains named Revenue & Collections Summary because COGS and expenses are not modeled.
- Ordinary `orderDate` remains the documented paid-order transaction timestamp proxy for this phase because ordinary orders have no separate persisted `paidAt`.
- Receivables are an as-of snapshot and are not filtered by debt creation date; collections are filtered by immutable payment timestamps.

## Owner-only actions still required
- Decide in a future schema phase whether ordinary sales need a separate immutable payment ledger/timestamp instead of the current `orderDate` proxy.
- If fully offline non-ASCII customer names must render in PDFs, provide an approved bundled Unicode font asset; PDF monetary values already remain readable offline through the ASCII `PHP` format.

## Remaining risks
- Historical ordinary orders cannot distinguish order creation time from actual payment time because no separate `paidAt` exists.
- Legacy custom-order aggregate deposits with no payment rows appear in all-time totals but cannot safely enter bounded date reports.
- PDF generation attempts to fetch Noto Sans and falls back safely to Helvetica when offline; non-ASCII free-text names may have limited glyph coverage in that fallback.
- The repository remains heavily dirty with prior phase and owner changes; Phase 6 did not reset, stash, commit, or alter unrelated work.

## Recommended next phase
- Phase 7 - Tests, CI, and dependency hygiene, only when explicitly requested.
