# Phase 3 Completion Report

## Implemented
- Added atomic SQLite transactions for order, line-item, stock, optional debt, payment, and sync-outbox writes.
- Added a strict order state machine for Pending, Processing, Shipped, Delivered, Utang, and Cancelled states.
- Added conditional stock reservation and release for cancellation, reactivation, soft deletion, restoration, and permanent deletion.
- Blocked cancellation, soft deletion, and permanent deletion while a linked debt remains open.
- Moved readable `KNZ-NNN` allocation into the order insertion transaction and removed the external preview generator.
- Added durable outbox states, retry metadata, exponential backoff, restart recovery, idempotency keys, ordered processing, and visible failure/retry status.
- Added transactional outbox coverage for products, orders, debts, payments, resellers, custom orders, and activity logs.
- Added complete cloud tombstones containing the fields, items, and payments required for fresh-device restore. Hard deletes remain explicit remote deletes.
- Added Firestore restore reads that include active records and tombstones without sparse-field `orderBy` filtering.
- Added typed read, stock, state-transition, open-debt, and synchronization failures. Failed writes and reads no longer report false success or false empty data.
- Added Firestore ownership and order-transition rules with Emulator Suite coverage.
- Added `docs/SYNC_PLAN.md` documenting entity coverage, restore behavior, tombstones, idempotency, and the supported release scope.

## Files changed
- `docs/SYNC_PLAN.md`
- `lib/core/app_state.dart`
- `lib/core/domain_exceptions.dart`
- `lib/database/database_helper.dart`
- `lib/dialogs/order_dialog.dart`
- `lib/models/order_state_machine.dart`
- `lib/repositories/activity_log_repository.dart`
- `lib/repositories/base_repository.dart`
- `lib/repositories/firestore_sync.dart`
- `lib/repositories/local_custom_order_repository.dart`
- `lib/repositories/local_debt_repository.dart`
- `lib/repositories/local_order_repository.dart`
- `lib/repositories/local_product_repository.dart`
- `lib/repositories/local_reseller_repository.dart`
- `lib/repositories/order_repository.dart`
- `lib/repositories/sync_queue.dart`
- `lib/screens/main_shell.dart`
- `lib/screens/orders_screen.dart`
- `lib/screens/recycle_bin_screen.dart`
- `lib/services/order_service.dart`
- `lib/services/product_service.dart`
- `lib/widgets/sync_status_banner.dart`
- `firestore.rules`
- `rules-tests/test/firestore_rules.test.js`
- `test/database/phase3_migration_test.dart`
- `test/models/domain_invariants_test.dart`
- `test/recycle_bin_contract_test.dart`
- `test/repositories/entity_outbox_test.dart`
- `test/repositories/order_transaction_test.dart`
- `test/repositories/read_failure_test.dart`
- `test/repositories/sync_queue_test.dart`
- `test/widgets/sync_status_banner_test.dart`

## Database or API contract changes
- Upgraded SQLite to schema version 10.
- Added `order_sequences(user_id PRIMARY KEY, last_value)` for monotonic per-user readable order IDs.
- Added `orders.stock_deducted` and `orders.stock_released_on_delete`.
- Added a real `UNIQUE(user_id, order_id)` constraint and compatibility unique index.
- Added `sync_queue.status`, `last_attempt_at`, `idempotency_key`, retry/error metadata, and due/status/idempotency indexes.
- Added `deleted_at` to resellers and custom orders.
- The v10 migration preserves rows, seeds sequences, reconciles previously held stock for active cancelled orders, and enqueues complete cloud snapshots for all restorable entities.
- `OrderRepository.addWithInventory` and `OrderService.createOrder` return the committed order containing its final readable ID.
- Removed the unused non-authoritative `generateOrderId` and `getNextOrderNumber` contracts.
- Firestore soft-delete operations now upsert complete restorable payloads; order items and debt payments remain embedded in their parent documents.

## Tests added or updated
- Added migration coverage for v9-to-v10 row preservation, sequence seeding, stock reconciliation, outbox durability, and deleted-order stock markers.
- Added interruption and partial-failure rollback tests covering order, items, stock, debt, payments, sequence, and outbox records.
- Added concurrent order, stock-shortage, duplicate readable-ID, and non-reuse-after-purge tests.
- Added strict transition, cancellation/reactivation, delivery/delete/restore, insufficient-stock restore, and open-debt tests.
- Added Firestore failure, durable retry, confirmed completion, idempotency-key, and database-restart tests.
- Added complete reseller, custom-order, and order tombstone-payload assertions, plus product, debt/payment, reseller, and custom-order migration snapshot assertions.
- Added explicit read-failure propagation and visible sync failure/retry widget tests.
- Added Firestore Emulator tests for ownership, authentication, access state, required collection paths, and invalid order transitions.

## Commands run
- `dart format <Phase 3 files>`
- `dart analyze <Phase 3 files>`
- `flutter test <Phase 3 focused tests>`
- `flutter test --coverage`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter build apk --debug --no-pub`
- `npm ci`
- `npm run lint`
- `npm test`
- `npm audit --omit=dev --audit-level=high`
- `npm ci` in `rules-tests`
- `npm run test:emulator`
- `$env:PATH = "E:\\Andriod Studio\\jbr\\bin;$env:PATH"; npm run test:emulator`
- `git diff --check` for the Phase 3 paths
- Static searches for swallowed reads, partial critical writes, outbox coverage, stock mutations, and readable-ID generation outside insertion.

## Validation results
- PASS: Targeted formatting completed with no remaining Phase 3 changes.
- PASS: Targeted Phase 3 analysis reported `No issues found!`.
- PASS: `flutter test --coverage` passed all 74 tests.
- PASS: Functions lint passed.
- PASS: Functions unit tests passed 11 of 11.
- PASS: Functions high-severity audit threshold exited successfully; it reported 9 moderate transitive `uuid` vulnerabilities.
- PASS: Emulator rerun passed 10 of 10 Functions tests and 9 of 9 Firestore rules tests.
- PASS: Phase 3 `git diff --check` reported no whitespace errors; Git emitted only existing LF-to-CRLF warnings.
- FAIL: Full formatting cannot parse `lib/screens/analytics_screen.dart` at lines 781 and 861. It also reports that `test/services/accounting_service_test.dart` would change. The analytics syntax defect existed outside the Phase 3 changes.
- FAIL: Full `flutter analyze` reports 3 analytics syntax errors and 25 informational findings, for 28 findings total. Targeted Phase 3 analysis is clean.
- FAIL: Debug APK compilation stops on the same unmatched `Semantics` expression and spread at `lib/screens/analytics_screen.dart:743-861`.
- PASS after environment correction: The first emulator run failed because `java` was absent from the shell `PATH`; using Flutter's detected Android Studio JDK for that command passed the suite.
- PASS after timeout retry: The first `rules-tests` `npm ci` timed out at 300 seconds; the retry completed in approximately 7 minutes.
- WARN: Validation used host Node 24.18.0 while both Node packages request Node 20. The emulator still passed but production/CI validation should use Node 20.
- WARN: `rules-tests` dependency installation reports 10 vulnerabilities: 9 moderate and 1 high. These are test-only dependencies but remain dependency-hygiene work.

## Product decisions made
- Enforced `Pending -> Processing -> Shipped -> Delivered` as the normal fulfillment path.
- Allowed Pending, Processing, or Shipped orders to become Utang or Cancelled.
- Required a transactional stock recheck for `Cancelled -> Pending`.
- Required settled debt for `Utang -> Delivered`.
- Cancellation and soft deletion release stock exactly once; restoration re-reserves only stock released by deletion.
- The internal UUID is the record identity; `KNZ-NNN` is monotonic display metadata.
- Cloud tombstones retain complete restorable data. Permanent purge is the only operation that removes the cloud document.
- Release scope remains Android-only, local-first, primarily single-device, with durable cloud outbox and restore. Complete multi-device synchronization is not claimed.
- Existing `REAL`/`double` money storage remains unchanged for Phase 4 remediation; Phase 3 introduced no new money representation.

## Owner-only actions still required
- Correct the Android Firebase application configuration; `google-services.json` still targets `com.example.inventoryordtrack` instead of `com.knzscent.admin`.
- Deploy Firestore rules, indexes, and Functions using authorized Firebase credentials after reviewing production configuration.
- Run production-project restore validation and real-device interruption/offline/reconnection checks.
- Use the declared Node 20 runtime for CI and deployment validation.
- Resolve or schedule the Functions and rules-test dependency audit findings under Phase 7 rather than forcing breaking upgrades now.
- Resolve the unrelated `analytics_screen.dart` syntax defect before an APK can be built.

## Remaining risks
- The complete Flutter application cannot currently be analyzed, formatted, or compiled because of the unrelated analytics syntax defect.
- Cloud restore is covered by repository logic and emulator authorization tests but has not been exercised against the production Firebase project.
- Synchronization is durable and idempotent but does not provide revisions, conflict resolution, or complete multi-device convergence.
- Existing monetary values still use SQLite `REAL` and Dart `double`; conversion and calculation correctness remain Phase 4 work.
- The worktree contains extensive pre-existing and broadly formatted changes, so review or commit preparation must isolate Phase 3 paths without discarding owner work.

## Recommended next phase
- Resolve the unrelated analytics compile blocker, then explicitly request Phase 4 for debt, interest, payments, and currency remediation. Do not begin Phase 4 implicitly.
