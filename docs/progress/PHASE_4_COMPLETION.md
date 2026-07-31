# Phase 4 Completion Report

## Implemented
- Added an immutable `Money` value object backed by integer centavos with decimal parsing, deterministic half-up rounding, formatting, arithmetic, and an explicit chart-only `double` boundary.
- Migrated operational money contracts for products, order items, orders, resellers, custom orders, deposits, debts, payments, accounting, reports, exports, receipts, dialogs, repositories, and cloud outbox payloads to integer centavos.
- Added persisted debt principal, interest, rate-basis-point, accrual-timestamp, and status state.
- Added simple daily and 30-day monthly interest accrual based only on complete periods since the persisted last-accrual timestamp.
- Added immutable interest-first payment allocation, atomic debt/payment/outbox persistence, duplicate-payment rejection, and overpayment rejection.
- Made settlement require both outstanding principal and outstanding interest to be zero.
- Added SQLite v11 migration with decimal-string REAL conversion, chronological payment replay, complete centavo cloud snapshots, and transactional rollback for invalid or inconsistent legacy ledgers.
- Made customer-pay total authoritative for reseller orders while retaining SRP as reference data.
- Applied cash-basis reporting: delivered non-credit orders are order revenue; Utang receipts are recognized only from immutable payment rows, including after the linked order is delivered.
- Updated debt previews and thermal receipts to show principal due, accrued interest, full outstanding, and payment allocations.
- Rejected legacy cloud debt restoration until an upgraded source device has synchronized the v11 contract.

## Files changed
- `lib/core/money.dart`
- `lib/core/app_state.dart`
- `lib/database/database_helper.dart`
- `lib/models/product_model.dart`
- `lib/models/order_model.dart`
- `lib/models/debt_model.dart`
- `lib/models/reseller_model.dart`
- `lib/models/custom_order_model.dart`
- `lib/models/sales_record_model.dart`
- `lib/models/reseller_accounting_summary.dart`
- `lib/repositories/debt_repository.dart`
- `lib/repositories/firestore_sync.dart`
- `lib/repositories/sync_queue.dart`
- `lib/repositories/local_product_repository.dart`
- `lib/repositories/local_order_repository.dart`
- `lib/repositories/local_debt_repository.dart`
- `lib/repositories/local_reseller_repository.dart`
- `lib/repositories/local_custom_order_repository.dart`
- `lib/services/product_service.dart`
- `lib/services/debt_service.dart`
- `lib/services/accounting_service.dart`
- `lib/services/export_service.dart`
- `lib/services/agreement_pdf_service.dart`
- `lib/dialogs/product_dialog.dart`
- `lib/dialogs/order_dialog.dart`
- `lib/dialogs/mark_as_utang_dialog.dart`
- `lib/dialogs/utang_payment_dialog.dart`
- `lib/dialogs/utang_receipt_printer.dart`
- `lib/dialogs/reseller_dialog.dart`
- `lib/dialogs/custom_order_dialog.dart`
- `lib/dialogs/export_dialog.dart`
- `lib/screens/accounting_screen.dart`
- `lib/screens/analytics_screen.dart`
- `lib/screens/custom_orders_screen.dart`
- `lib/screens/overview_screen.dart`
- `lib/screens/products_screen.dart`
- `lib/screens/receipt_screen.dart`
- `lib/screens/recycle_bin_screen.dart`
- `lib/screens/reports_screen.dart`
- `lib/screens/reseller_accounting_screen.dart`
- `lib/screens/reseller_screen.dart`
- `lib/screens/sales_screen.dart`
- `lib/screens/utang_screen.dart`
- `test/database/phase3_migration_test.dart`
- `test/database/phase4_money_migration_test.dart`
- `test/dialogs/utang_receipt_printer_test.dart`
- `test/models/debt_model_test.dart`
- `test/models/domain_invariants_test.dart`
- `test/repositories/debt_payment_transaction_test.dart`
- `test/repositories/entity_outbox_test.dart`
- `test/repositories/order_transaction_test.dart`
- `test/services/accounting_service_test.dart`
- `docs/progress/PHASE_4_COMPLETION.md`

## Database or API contract changes
- Increased the SQLite schema version from 10 to 11.
- Replaced operational money `REAL` columns with `INTEGER` centavo columns across `products`, `orders`, `order_items`, `debts`, `payments`, `resellers`, and `custom_orders`.
- Added `orders.srp_total_centavos` while keeping customer-pay total authoritative.
- Replaced percentage-named reseller storage with `deduction_per_item_centavos`; legacy values are interpreted as fixed-peso deductions during migration.
- Replaced aggregate debt storage with `principal_original_centavos`, `principal_outstanding_centavos`, `interest_outstanding_centavos`, `interest_rate_basis_points`, `interest_start_timestamp`, `last_accrual_timestamp`, and persisted `status`.
- Payment rows now store `amount_centavos`, `interest_applied_centavos`, `principal_applied_centavos`, `payment_method`, `reference`, and `note`, with a database constraint requiring allocations to equal the amount.
- Firestore/outbox snapshots use the same centavo fields. Persisted pre-v11 payment outbox operations are converted to centavos when drained.
- The v11 migration aborts and rolls back if aggregate paid amount differs from payment rows, or if it encounters invalid money, invalid interest type, future payments, or overpayment.
- Fresh-device restore intentionally rejects legacy cloud debt documents because their outstanding principal/interest allocation cannot be reconstructed safely without the source ledger.

## Tests added or updated
- Added v10 REAL-to-v11 centavo migration and mismatch-rollback tests.
- Added the mandatory ₱100 principal, ₱10 interest, ₱100 payment regression.
- Added no-interest, partial-payment, repeated-accrual, post-payment accrual, half-up rounding, overpayment, settlement, and immutable-history model tests.
- Added repository tests for atomic payment/debt/outbox persistence, persisted accrual, repeat-read stability, and rollback on outbox failure.
- Added receipt coverage for principal, accrued interest, and full outstanding.
- Added cash-basis coverage proving a settled and delivered Utang order is not counted again as order revenue.
- Updated existing migration, model, repository, outbox, order-transaction, and accounting fixtures for the v11 centavo schema.

## Commands run
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test --coverage`
- `flutter test test/database/phase3_migration_test.dart`
- `flutter test test/repositories/debt_payment_transaction_test.dart`
- `flutter test test/dialogs/utang_receipt_printer_test.dart`
- `flutter test test/services/accounting_service_test.dart`
- `npm ci` in `functions/`
- `npm run lint` in `functions/`
- `npm test` in `functions/`
- `npm audit --omit=dev --audit-level=high` in `functions/`
- `git diff --check -- lib test`

## Validation results
- PASS: Dart formatting check completed with 97 files checked and 0 changes required.
- PASS: `flutter analyze` reported 0 errors and 0 warnings; 28 style-only info findings remain.
- PASS: Flutter test suite completed with 83 tests passed and coverage generated.
- PASS: Functions lint completed successfully.
- PASS: Functions unit suite completed with 11 tests passed.
- PASS: production dependency audit found no high-severity vulnerabilities. It reports 9 moderate `uuid` dependency-chain advisories whose automated resolution requires breaking Firebase dependency upgrades.
- PASS: focused diff whitespace validation completed without errors; Git emitted only existing LF-to-CRLF worktree notices.
- NOTE: the first two-minute `npm ci` attempt timed out and was not counted as passed. The retry completed in three minutes.

## Product decisions made
- Legacy `discount_percent` values are fixed-peso per-item deductions and migrate to centavos.
- The reseller customer-pay amount is the authoritative order total; SRP is reference data.
- A v11 migration with a legacy `amount_paid`/payment-ledger mismatch must abort rather than guess or discard data.
- Interest is simple, using complete 24-hour daily periods or complete 30-day monthly periods.
- Interest rates are stored in integer basis points and monetary results use deterministic half-up centavo rounding.
- Payments apply to outstanding interest first and principal second.
- Overpayments are rejected; no implicit customer-credit balance is created.
- Accounting and reports use cash basis. Utang order revenue is recognized from payment records and never again from the delivered order.

## Owner-only actions still required
- Back up a production database and run the v10-to-v11 upgrade on a copy before distributing the upgraded application.
- If migration reports a paid-aggregate mismatch, reconcile the affected debt and payment ledger from business records; do not delete the database or bypass the rollback.
- Open and synchronize each existing source device after upgrade before attempting a fresh-device cloud restore.
- Verify debt receipt preview and Bluetooth thermal output on the supported Android hardware, including interest and allocation lines.
- Run Functions validation and deployment with the pinned Node 20 runtime; this workstation used Node 24 and emitted an engine warning.
- Correct the Android Firebase configuration/package mismatch before production Firebase or release validation.

## Remaining risks
- Legacy cloud debt documents cannot safely restore directly to an empty v11 database until an upgraded source device publishes complete principal, interest, and payment-allocation snapshots.
- Nine moderate transitive `uuid` advisories remain in the Functions dependency tree. The available automated fix requires breaking Firebase dependency upgrades and is deferred to Phase 7 dependency hygiene.
- The analyzer retains 28 non-blocking style info findings outside the financial acceptance criteria.
- Physical printer output, production-data migration, offline interruption, and real Firebase restore behavior still require owner/device testing.
- The supported scope remains Android-only, local-first, primarily single-device with durable outbox/restore; complete multi-device conflict resolution is not claimed.

## Recommended next phase
- Phase 5 — DTOs and migrations, only when explicitly requested.
