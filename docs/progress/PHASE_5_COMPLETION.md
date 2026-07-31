# Phase 5 Completion Report

## Implemented
- Added strict versioned DTO mappers for Product, Order, Order Item, Debt, Payment, Reseller, Custom Order, Custom Order Payment, and Activity Log.
- Added shared DTO parsing for local rows, cloud documents, domain objects, canonical local rows, and canonical cloud documents.
- Added `schema_version` to every synced business entity and child record, with current DTO version 1 and explicit rejection of unsupported future versions.
- Routed repository local writes, outbox payloads, Firestore writes, Firestore reads, and fresh-database restore through the same DTO contracts.
- Preserved all audited order fields, including payment method/reference, reseller flag, fixed deduction, discounted total, explicit customer-pay amount, order type, status, timestamps, stock state, unit price, and SRP reference.
- Preserved all audited debt fields, including original/outstanding principal, outstanding interest, rate basis points, interest type, interest start, last accrual, status, and immutable payment allocation history.
- Added immutable custom-order payment persistence and cloud embedding instead of retaining only the aggregate deposit.
- Added stable text IDs for activity logs so local and cloud DTOs share one identity contract.
- Preserved historical `Cancelled` custom-order status rather than defaulting it to `Pending`.
- Added explicit legacy aliases for historical Product category `Perfume` and Order payment method `cash`; all other unsupported enum values remain validation failures.
- Retained the Phase 4 safety rule that ambiguous pre-centavo cloud debt documents must be synchronized from an upgraded source device rather than guessed.
- Added SQLite v12 as a transactional, data-preserving migration with canonical DTO snapshots for every synced entity.
- Converted persisted partial order/debt outbox operations into complete canonical DTO snapshots during v12 migration.
- Rebuilt the outbox without deleting rows so upgraded databases enforce the same non-null and unique idempotency contract as fresh databases.
- Added comprehensive schema verification for required tables, columns, selected SQLite types, indexes, unique constraints, cascading foreign keys, and `PRAGMA foreign_key_check`.
- Made activity-log persistence failures propagate instead of using best-effort error suppression.

## Files changed
- `lib/dto/dto_reader.dart`
- `lib/dto/product_dto.dart`
- `lib/dto/order_dto.dart`
- `lib/dto/debt_dto.dart`
- `lib/dto/reseller_dto.dart`
- `lib/dto/custom_order_dto.dart`
- `lib/dto/activity_log_dto.dart`
- `lib/database/database_helper.dart`
- `lib/models/order_model.dart`
- `lib/models/custom_order_model.dart`
- `lib/repositories/activity_log_repository.dart`
- `lib/repositories/firestore_sync.dart`
- `lib/repositories/local_product_repository.dart`
- `lib/repositories/local_order_repository.dart`
- `lib/repositories/local_debt_repository.dart`
- `lib/repositories/local_reseller_repository.dart`
- `lib/repositories/local_custom_order_repository.dart`
- `lib/repositories/sync_queue.dart`
- `lib/screens/custom_orders_screen.dart`
- `lib/screens/recycle_bin_screen.dart`
- `test/dto/entity_dto_round_trip_test.dart`
- `test/database/phase5_migration_matrix_test.dart`
- `test/database/phase3_migration_test.dart`
- `test/repositories/entity_outbox_test.dart`
- `docs/progress/PHASE_5_COMPLETION.md`

## Database or API contract changes
- Increased SQLite schema version from 11 to 12.
- Added `schema_version INTEGER NOT NULL DEFAULT 1` to products, orders, order items, debts, debt payments, resellers, custom orders, custom-order payments, and activity logs.
- Added `orders.customer_pay_amount_centavos`; v12 backfills it from `discounted_total_centavos` or `total_amount_centavos`.
- Added `custom_order_payments` with immutable payment ID, parent ID, centavo amount, timestamp, note, schema version, and cascading custom-order foreign key.
- Changed `activity_logs.id` from local autoincrement integer to stable text identity; existing integer IDs are preserved as their string representation.
- Added unique `idx_debts_user_order_id` to enforce one debt ledger per user/order association.
- Added `idx_custom_orders_user` and `idx_custom_order_payments_order`.
- Rebuilt `sync_queue` transactionally with non-null `status`, `idempotency_key`, and `updated_at`, retaining all existing rows and enforcing unique idempotency keys.
- Canonical cloud documents now include `schema_version`; aggregate Order, Debt, and Custom Order documents embed canonical child DTO lists.
- Unknown future DTO versions, malformed required fields, unknown enum values, duplicate debt/order associations, invalid outbox keys, missing required tables, and schema verification failures abort migration and propagate.
- Production SQLite upgrade callbacks remain one sqflite-managed transaction. The test upgrade entry point also wraps the complete upgrade in a transaction.

## Tests added or updated
- Added separate source and fresh-restore database round trips for Product, Order, Order Item, Debt, Payment, Reseller, Custom Order, Custom Order Payment, and Activity Log.
- Added assertions for all audited order fields, debt accrual fields, payment allocations, custom payment history, tombstones, timestamps, schema versions, and stable activity IDs.
- Added legacy default/alias coverage and future DTO-version rejection.
- Added independent fixture database upgrades for every SQLite version 1 through 12 using the production open/upgrade callbacks.
- Added schema assertions for centavo/principal fields, DTO metadata, custom payment table, required indexes, unique constraints, foreign-key definitions, cascading deletes, outbox nullability, and foreign-key integrity.
- Added duplicate debt/order rollback coverage proving schema and `user_version` remain at 11.
- Added incomplete-schema rollback coverage proving a missing required table cannot advance `user_version`.
- Updated the Phase 3 helper migration test to invoke the migration inside a transaction.
- Extended custom-order outbox tests to prove payment rows and embedded payment DTOs commit together and survive tombstone/restore snapshots.

## Commands run
- `flutter test test/dto/entity_dto_round_trip_test.dart`
- `flutter test test/database/phase5_migration_matrix_test.dart`
- `flutter test test/database`
- `flutter test test/repositories/entity_outbox_test.dart test/database/phase3_migration_test.dart`
- `flutter test test/repositories/order_transaction_test.dart`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test --coverage`
- `npm run lint` in `functions/`
- `npm test` in `functions/`
- `npm audit --omit=dev --audit-level=high` in `functions/`
- `git diff --check` for Phase 5 affected tracked files

## Validation results
- PASS: DTO round-trip suite completed with 10 tests passed using isolated per-test source and restore database files.
- PASS: migration matrix completed with 14 tests passed: versions 1-12 plus duplicate-data rollback and incomplete-schema rollback.
- PASS: all database tests completed with 19 tests passed.
- PASS: deterministic Dart formatting check completed with 106 files checked and 0 changes required.
- PASS: `flutter analyze` reported 0 errors and 0 warnings; 28 style-only info findings remain.
- PASS: full Flutter suite completed with 107 tests passed and coverage generated.
- PASS: Functions syntax lint completed successfully.
- PASS: Functions unit suite completed with 11 tests passed.
- PASS: production dependency audit found no high-severity vulnerabilities; 9 moderate transitive `uuid` advisories remain.
- PASS: focused diff whitespace validation found no errors; Git emitted only existing LF-to-CRLF worktree notices.
- NOTE: one earlier full coverage run timed out while concurrent validation exhausted the VM service. It was not counted as passed; two subsequent isolated full coverage runs completed with all 107 tests passing.

## Product decisions made
- DTO schema version 1 is the canonical local/cloud contract introduced with SQLite schema version 12.
- The customer-pay amount is explicitly stored and must equal the discounted total when present, otherwise the authoritative total amount.
- Historical `Perfume` maps explicitly to Eau de Parfum, and historical `cash` maps explicitly to Cash on Delivery. Unknown values are not silently defaulted.
- Historical `Cancelled` custom orders remain cancelled after restore.
- One user/order may have only one debt ledger, including tombstoned ledgers; duplicate associations stop migration for owner repair.
- Ambiguous pre-centavo cloud debt documents remain rejected because principal/interest allocation cannot be reconstructed safely.
- Existing custom-order aggregate deposits are preserved, but absent historical child payment rows are not fabricated.

## Owner-only actions still required
- Back up a production database and run the v11-to-v12 upgrade on a copy before release distribution.
- If migration reports duplicate debt/order associations, reconcile them from business records before retrying; do not delete rows or bypass the unique constraint.
- If migration reports duplicate/blank outbox idempotency keys, inspect and repair those durable operations without discarding unsynchronized business writes.
- Open and synchronize existing upgraded source devices before using fresh-device restore, especially for legacy debt documents.
- Verify a real Firebase round trip for orders, debts, custom-order payments, tombstones, and activity logs using authorized production credentials.
- Continue using the pinned Node 20 Functions runtime for deployment; local validation currently runs under Node 24 and emits the known engine warning when dependencies are installed.

## Remaining risks
- Historical custom-order rows contain only aggregate deposits, so v12 cannot reconstruct payment IDs, dates, or notes that were never persisted.
- Legacy activity logs did not persist their original cloud UUID locally. Their local integer identity is preserved as text, but an already-synced historical cloud entry may retain a different UUID and can coexist until owner cleanup.
- Ambiguous pre-centavo cloud debts require an upgraded source-device snapshot and cannot restore directly into an empty v12 database.
- Production-scale migration timing, real Firebase restore, interruption during application upgrade, and physical-device behavior still require owner acceptance testing.
- Nine moderate transitive Functions dependency advisories remain deferred to Phase 7 because the available automated fix requires breaking Firebase upgrades.
- The analyzer retains 28 non-blocking style info findings outside the Phase 5 acceptance criteria.
- The supported scope remains Android-only, local-first, and primarily single-device; complete multi-device conflict resolution is not claimed.

## Recommended next phase
- Phase 6 — Accounting and reporting, only when explicitly requested.
