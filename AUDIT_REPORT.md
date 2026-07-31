Full project audit

Overall verdict: not release-ready. The project has a solid school-project foundation and a polished feature set, but production use could currently cause lost sync operations, incorrect stock/debt balances, misleading financial reports, and insecure account recovery.

I audited commit c4f6284 plus the current uncommitted worktree: 13 modified and 3 untracked entries. The current tree contains 72 Dart files and roughly 24,409 lines. I made no file changes.

| Area | Verdict |
|---|---|
| Startup/build | Blocked |
| Authentication/security | Critical risk |
| Local data integrity | Critical risk |
| Cloud synchronization | Critical risk |
| Accounting/debt accuracy | Critical risk |
| Tests/CI | Missing |
| Architecture | Good foundation, excessive coupling |
| Accessibility | Needs substantial work |
| Release configuration | Incomplete |

## Critical findings

### 1. The current app can fail before showing its first screen
[main.dart (line 39)](/E:/flutter_test_projects/inventoryordtrack/lib/main.dart:39) unconditionally loads .env, but [pubspec.yaml (line 73)](/E:/flutter_test_projects/inventoryordtrack/pubspec.yaml:73) no longer includes .env as a Flutter asset. The file existing locally does not make it available through flutter_dotenv in a packaged app.

This occurs before Firebase and Crashlytics initialization, so the failure is neither recoverable nor remotely reported.

Fix: finish removing client-side Brevo configuration, remove flutter_dotenv and dotenv.load, and make email functionality an optional backend capability rather than a startup dependency.

### 2. The new OTP migration is not operational
[otp_service.dart (line 5)](/E:/flutter_test_projects/inventoryordtrack/lib/services/otp_service.dart:5) calls:
https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/sendOtp

Additionally:
- functions/ is completely untracked.
- [firebase.json (line 1)](/E:/flutter_test_projects/inventoryordtrack/firebase.json:1) has no Functions deployment configuration.
- .firebaserc and functions/package-lock.json are absent.
- The Functions package has no test, lint, emulator, or deployment scripts.
- functions.config() is legacy configuration that should move to Secret Manager/parameters. Firebase migration guidance

The Cloud Function JavaScript is syntactically valid, but the complete feature cannot currently be deployed or called successfully.

### 3. OTP does not form a real security boundary
[otp_screen.dart (line 80)](/E:/flutter_test_projects/inventoryordtrack/lib/screens/otp_screen.dart:80) generates the OTP in the client, sends that OTP to the server, and then verifies it locally at line 130. The backend never creates, stores, expires, or verifies a challenge.

[functions/index.js (line 18)](/E:/flutter_test_projects/inventoryordtrack/functions/index.js:18) accepts arbitrary email, otp, and purpose values and sends them without:
- Authentication or App Check enforcement
- OTP format validation
- Server-side verification
- Durable expiry or attempt tracking
- A reliable distributed rate limit

The in-memory cooldown at lines 27–35 resets on cold starts and separate instances, and parallel requests can pass before the cooldown is recorded. Arbitrary HTML can also be supplied through the unvalidated OTP value.

Fix: generate the OTP server-side, store only a hash with expiry and attempt limits, return a challenge ID, verify it in a second server operation, and issue a short-lived reset authorization. Firebase Auth email-link/password-reset functionality would be safer and simpler.

### 4. Custom authentication and Firebase authorization are disconnected
[main.dart (line 51)](/E:/flutter_test_projects/inventoryordtrack/lib/main.dart:51) signs every installation into Firebase anonymously, while application login is performed separately against SQLite/Firestore password records.

Problems:
- Firebase anonymous UID is not associated with the locally authenticated username.
- Firestore paths are based on usernames, not Firebase UIDs.
- No Firestore rules are tracked in the repository.
- Logout does not sign out or replace the Firebase anonymous identity.
- A rule that only checks request.auth != null would permit every anonymous installation.
- The client must read a Firestore user document containing its password verifier to perform login.

This makes secure per-account Firestore authorization extremely difficult with the current model.

Fix: use Firebase Auth or a real server authentication service and bind every cloud record to that authenticated UID. Track and emulator-test deny-by-default Firestore rules.

### 5. Password storage is not production-grade
[local_user_repository.dart (line 23)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/local_user_repository.dart:23) uses unsalted, fast SHA-256 hashes. These hashes are stored in SQLite and Firestore and compared client-side.

If a user document or device database is obtained, short passwords can be cracked efficiently. The 30-second, device-local rate limiter does not protect the stored hashes or the cloud API.

Fix: stop storing password verifiers in Firestore. Prefer Firebase Auth. If local password verification is unavoidable, use Argon2id/scrypt with a per-user salt and secure migration.

### 6. Cloud sync silently discards failed writes
[firestore_sync.dart (line 38)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/firestore_sync.dart:38) catches and suppresses nearly every Firestore exception. [sync_queue.dart (line 90)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/sync_queue.dart:90) therefore sees a normal return, deletes the queue entry at line 165, and treats the operation as synced.

The online path is worse: repositories call Firestore directly when connectivity reports a network interface, but do not enqueue a fallback when the real write fails.

Consequences include:
- Permanently lost cloud updates
- Deletes later reappearing on another device
- Local and cloud balances silently diverging
- No useful error or pending-sync state for the user

Fix: use a transactional outbox. Commit every local mutation and queue entry together, regardless of connectivity. Let cloud failures propagate and delete an outbox row only after confirmed remote success.

### 7. Orders, stock, and automatic debt are not atomic
[order_service.dart (line 63)](/E:/flutter_test_projects/inventoryordtrack/lib/services/order_service.dart:63) saves an order, then separately updates each product's stock while suppressing deduction failures. [app_state.dart (line 461)](/E:/flutter_test_projects/inventoryordtrack/lib/core/app_state.dart:461) creates automatic debt afterward as another independent operation.

Delete and restore have similar multi-step behavior at lines 534–620.

Possible outcomes:
- Order saved but stock unchanged
- Some products deducted and others not
- Utang order saved without its debt
- UI reports failure even though part of the operation committed
- Retrying creates duplicates
- Concurrent orders both validate against the same cached stock

Fix: implement one SQLite transaction covering the order, items, conditional stock updates, and optional debt. Use conditional updates and verify affected row counts.

### 8. Interest-bearing debts can be incorrectly forgiven
[debt_model.dart (line 106)](/E:/flutter_test_projects/inventoryordtrack/lib/models/debt_model.dart:106) calculates interest from the current remaining principal over the entire historical period. Payments are then applied directly to amountPaid in [local_debt_repository.dart (line 152)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/local_debt_repository.dart:152).

Example: a ₱100 principal with ₱10 accrued interest accepts a ₱100 payment. Principal becomes zero, accrued interest recomputes to zero, and the debt is marked paid—silently forgiving ₱10.

Partial payments also retroactively reduce previously accrued interest.

Fix:
- Persist principal outstanding and interest outstanding separately.
- Store the last accrual timestamp.
- Allocate payments using an explicit rule, normally interest first and principal second.
- Determine settlement from the complete due amount.
- Store currency as integer centavos or a decimal type, not binary double.

### 9. Cloud restore deletes important business meaning
Order restoration at [local_order_repository.dart (line 67)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/local_order_repository.dart:67) omits:
- Payment method/reference
- Reseller flag
- Deduction
- Discounted total
- Order type

Debt restoration at [local_debt_repository.dart (line 42)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/local_debt_repository.dart:42) omits interest rate, type, and start date.

A new device can therefore turn reseller orders into ordinary orders and remove debt-interest terms.

Fix: define one versioned DTO mapper per entity and use it for local writes, cloud writes, and restore. Add complete round-trip tests.

## High-priority correctness and product findings

### 10. Repository methods routinely report false success
[base_repository.dart (line 26)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/base_repository.dart:26) converts read failures into empty lists, while safeVoidCall at line 38 converts write failures into successful Future<void> results.

Screens subsequently display success, for example [product_dialog.dart (line 162)](/E:/flutter_test_projects/inventoryordtrack/lib/dialogs/product_dialog.dart:162), even if nothing was saved.

Use a typed Result or propagated exceptions. Preserve last-known-good state on read errors and only show success after a confirmed local commit.

### 11. Order IDs are neither unique nor atomically generated
[local_order_repository.dart (line 423)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/local_order_repository.dart:423) calculates MAX(...) + 1 in a transaction that ends before insertion. The insertion transaction at line 287 trusts the pre-generated value.

Despite comments claiming otherwise, [database_helper.dart (line 77)](/E:/flutter_test_projects/inventoryordtrack/lib/database/database_helper.dart:77) has no unique constraint on (user_id, order_id).

Concurrent submissions can both receive KNZ-042.

### 12. Order lifecycle and inventory rules are inconsistent
[app_state.dart (line 515)](/E:/flutter_test_projects/inventoryordtrack/lib/core/app_state.dart:515) changes status without adjusting inventory:
- Cancelling does not return stock.
- Moving a cancelled order back to active does not reserve stock again.
- Delete/restore does adjust stock, but through non-atomic operations.
- Restore clamps insufficient stock to zero instead of rejecting the restore.
- The utang → delivered guard can be swallowed by safeVoidCall, allowing in-memory state to disagree with SQLite.

Define and test a formal state machine for cancellation, deletion, restore, debt settlement, and delivery.

### 13. Financial reporting is not internally consistent
Confirmed inconsistencies include:
- [accounting_service.dart (line 32)](/E:/flutter_test_projects/inventoryordtrack/lib/services/accounting_service.dart:32) calls every non-cancelled order "net sales," including pending and completely unpaid utang orders.
- [reports_screen.dart (line 596)](/E:/flutter_test_projects/inventoryordtrack/lib/screens/reports_screen.dart:596) combines date-filtered sales with all-time debt collections.
- Credit sales can be counted when created and again when collected.
- "Profit & Loss" has no cost-of-goods or expense model and therefore is not a real P&L.
- Analytics uses different definitions of "revenue" in different widgets.
- Cancelled orders are excluded from previews but included in several exports.
- "Custom Order Status" PDF exports the generic analytics document.
- "Reseller Detailed" reuses the standard orders PDF.
- "Debt With Interest" uses an export whose columns omit interest.
- Custom-order revenue and deposits do not reach accounting or normal sales reports.

Choose an explicit cash or accrual basis, centralize calculations in one pure accounting domain service, and verify every report using fixed fixtures.

### 14. "Offline-first" is currently only partial local caching
Products, orders, and debts pull from Firestore only when the corresponding local table is completely empty. Existing local data is never merged with remote additions, edits, or deletions.

Additionally:
- Resellers have no cloud sync.
- Custom orders have no cloud sync.
- Product images are stored as device-local absolute paths and those paths are uploaded as text.
- There is no revision, conflict, or tombstone protocol.
- Connectivity indicates a network interface, not actual Firebase reachability.

Either document the app as single-device local-first, or implement complete revisioned two-way synchronization for every entity.

### 15. Database migrations can silently leave a broken schema
[database_helper.dart (line 207)](/E:/flutter_test_projects/inventoryordtrack/lib/database/database_helper.dart:207) suppresses almost every migration error. The database version may advance even when a required column, table, or index failed to be created.

Only explicitly expected duplicate-column cases should be tolerated. Every other failure should roll back, and migrations from versions 1–7 should be tested.

### 16. There are no meaningful automated tests
The current test/ directory is empty and there is no integration_test/. The native iOS/macOS tests are untouched templates.

This contradicts [README.md (line 338)](/E:/flutter_test_projects/inventoryordtrack/README.md:338), which claims authentication, CRUD, order, debt, logging, session, and rate-limiter coverage and says fake_async is used.

There is also no CI workflow, coverage threshold, dependency automation, or release gate.

### 17. Release configuration is incomplete
Android release is signed using the debug key at [android/app/build.gradle.kts (line 34)](/E:/flutter_test_projects/inventoryordtrack/android/app/build.gradle.kts:34).

Firebase configuration supports Android only; [firebase_options.dart (line 19)](/E:/flutter_test_projects/inventoryordtrack/lib/firebase_options.dart:19) throws on every other platform.

iOS lacks Firebase configuration and camera/photo/Bluetooth usage descriptions.

Bundle/application IDs still use com.example.

Web and desktop metadata still use Flutter template branding.

macOS sandbox entitlements do not enable required networking/Bluetooth.

Crashlytics' Android Gradle integration is incomplete. FlutterFire setup guidance

The effective target is Android development builds only.

### 18. Startup is all-or-nothing and contradicts offline-first behavior
[main.dart (line 25)](/E:/flutter_test_projects/inventoryordtrack/lib/main.dart:25) waits for notifications, preferences, .env, Firebase, Crashlytics, and anonymous network authentication before runApp.

A first-run offline user cannot reach the supposedly offline-first local UI. The guarded zone is installed only at line 78, after initialization, and the Flutter binding and runApp are created in different zones.

Move the complete bootstrap into one guarded zone and separate required local initialization from optional cloud and notification initialization.

## Security, privacy, and authorization findings
- Every newly registered account is assigned Administrator in [local_user_repository.dart (line 75)](/E:/flutter_test_projects/inventoryordtrack/lib/repositories/local_user_repository.dart:75); the role is cosmetic and never authorizes operations.
- Offline registration can create a username already owned by another cloud account. Later sync can overwrite the shared username document.
- Login throttling is local, resettable, only 30 seconds, and not a server defense.
- Forgot-password responses disclose whether a username exists and whether its email matches.
- Customer names, usernames, balances, and overdue periods are placed in notifications at [notification_service.dart (line 100)](/E:/flutter_test_projects/inventoryordtrack/lib/services/notification_service.dart:100), potentially exposing them on lock screens.
- CSV exports include unsanitized user-entered cells. Names beginning with =, +, -, or @ can become spreadsheet formulas when opened. See [export_service.dart (line 65)](/E:/flutter_test_projects/inventoryordtrack/lib/services/export_service.dart:65).
- Exported CSV/PDF files remain in the temporary directory after sharing.
- SQLite contains password verifiers, customer data, debt data, and payment references without application-level encryption.
- Android requests location and Bluetooth-advertise permissions even though printing only needs scanning/connection on newer Android versions.
- USE_EXACT_ALARM, boot permission, and scheduled receivers are declared even though the app only shows immediate notifications. This can create store-policy problems. Android exact-alarm guidance

Positive security result: .env is ignored, .env.example is a placeholder, and I found no obvious tracked private key or live Brevo secret. Firebase client API keys are expected to be public and were not treated as secrets.

## Code quality, performance, and accessibility
- [app_state.dart (line 37)](/E:/flutter_test_projects/inventoryordtrack/lib/core/app_state.dart:37) is a 902-line singleton combining authentication, six data domains, notifications, logging, orchestration, loading, and UI state.
- analytics_screen.dart is 1,744 lines, order_dialog.dart 1,181, and export_service.dart 1,014.
- Product/order/debt use interfaces, but reseller/custom-order features bypass the service abstraction.
- All listeners share one global notifier; unrelated updates rebuild multiple features.
- List getters create new objects on every access, defeating identity-based analytics caching.
- Aggregation and PDF generation run on the UI isolate.
- Repositories load full datasets without paging.
- The project contains roughly 64–65 GestureDetector controls, zero explicit Semantics widgets, and only three explicit tooltips.
- Shared GoldButton and DarkIconButton are pointer-only; the latter is 36×36 rather than a recommended touch-sized target.
- Charts have no textual accessibility alternatives.
- Session timeout observes pointer/tap/pan activity but not keyboard input, so a keyboard user can be logged out while actively typing.
- Product numeric fields convert invalid input to zero at [product_dialog.dart (line 139)](/E:/flutter_test_projects/inventoryordtrack/lib/dialogs/product_dialog.dart:139).
- Custom orders can accept deposits greater than the agreed price.
- Constructors and copyWith methods bypass several model setter validations.
- Money uses double/SQLite REAL throughout.

## Dependency and tooling audit
The SDK contract is inconsistent: [pubspec.yaml (line 7)](/E:/flutter_test_projects/inventoryordtrack/pubspec.yaml:7) and README claim Dart >=3.4, while [pubspec.lock (line 1192)](/E:/flutter_test_projects/inventoryordtrack/pubspec.lock:1192) requires Dart >=3.10.3 and Flutter >=3.38.4. No FVM/asdf/mise version pin exists.

Major upgrades are pending, including firebase_core, firebase_auth, cloud_firestore, firebase_crashlytics, flutter_local_notifications, and flutter_lints. These should be upgraded only after tests exist because they cross major versions.

The Functions package has no lockfile, making backend dependency resolution non-reproducible.

## Additional confirmed functional defects
- Invalid product price/stock input silently becomes zero.
- Custom-order payments have no immutable payment history.
- Resellers and custom orders are soft-deleted but cannot be restored through the Recycle Bin.
- Debt receipts omit accrued interest.
- Reseller order line items and recycle-bin totals can display SRP while totals use the discounted amount.
- Accounting ledger rows include cancelled orders excluded from summary cards.
- Multiple columns display the same financial value under different names.
- Date ranges are not consistently applied to debt payments.
- The low-stock dashboard list has no height cap.
- Sign-out has no confirmation.
- Email comparison during reset is case-sensitive.
- Username/email/domain validation exists mainly in screens and can be bypassed by other callers.
- Activity logs are client-generated, suppress persistence failures, and are not tamper-resistant.

## What is good
The project is not a bad codebase; its weaknesses are concentrated around production guarantees.

Confirmed strengths:
- Clear model/repository/service/screen organization
- Interfaces for core product, order, debt, and authentication services
- Parameterized SQLite queries
- Foreign keys enabled
- Useful database indexes
- Transactions for order-with-items and debt-with-payments
- Per-user local filtering
- Soft-delete and recycle-bin workflow
- Bounded local activity-log retention
- Initial core data loads run in parallel
- Several immutable-style copyWith updates and unmodifiable getters
- Good controller/timer disposal in inspected screens
- Responsive breakpoints, SafeArea, scrolling dialogs, and confirmation prompts
- Tracked Flutter lockfile with checksums
- Java/Kotlin 17, AndroidX, and core-library desugaring configured
- Cloud Function passes Node syntax checking
- Inspected JSON/XML configuration files parse successfully

## Verification performed
- node --check functions/index.js: passed
- Firebase/web/package JSON parsing: passed
- Android/iOS/macOS XML/plist parsing: passed
- git diff --check: no whitespace errors; only line-ending warnings
- Tracked Dart tests: 0
- CI workflows: 0
- Release automation files: 0

flutter analyze --no-pub timed out after approximately 131 seconds, and dart analyze lib timed out after approximately 301 seconds without output because of shared Windows Flutter/Dart SDK contention. I cleaned up only the analyzer processes started during this audit. This is not recorded as a project failure, but it means the current dirty tree's compilation status remains unproven. No release build was attempted.

## Recommended remediation order
1. Make startup and OTP functional: remove client .env loading, deploy a real backend endpoint, use Secret Manager, and add backend tests.
2. Replace the authentication boundary: use Firebase Auth/server identity, bind cloud data to UID, and commit deny-by-default Firestore rules plus emulator tests.
3. Protect data integrity: replace swallowed errors with typed results, introduce a transactional outbox, and make order/stock/debt operations atomic and idempotent.
4. Repair debt accounting: persist accrued interest correctly, allocate payments explicitly, and migrate money to integer centavos/decimal values.
5. Fix DTO restore and migrations: round-trip every field and test upgrades from every database version.
6. Define accounting rules: choose cash or accrual basis and rebuild reports/exports from one tested domain service.
7. Add safety gates: unit, repository, migration, concurrency, widget, integration, Functions emulator, and report-fixture tests; then add CI.
8. Finish release engineering: real IDs, Android signing, Firebase/Crashlytics setup, permissions, supported-platform decision, privacy documentation, and dependency upgrades.
9. Then refactor: split AppState, modularize large screens, add selectors/paging/isolate exports, and address keyboard/screen-reader accessibility.

The existing [verification report (line 1)](/E:/flutter_test_projects/inventoryordtrack/KNZ-Scent-Full-Verification-Report-v2.md:1) remains directionally useful. Its stored-email check and anonymous-sign-in recommendations were partially implemented, but the new OTP/backend patch is incomplete and most data-integrity, reporting, and UX findings remain unresolved.
