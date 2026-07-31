# KNZ Scent Admin — Godmode Re-Verification (v2)

Every finding below was re-confirmed directly against source in this pass, including 6 items documented in the original six audit reports that were missing from the v1 consolidated list, plus 3 genuinely new findings.

**Totals:** 4 critical · 4 high · 14 medium · 10 low — 32 findings, all confirmed from source.

---

## Bugs and logic errors

### Critical

#### C1. Forgot Password lets anyone take over any account
**File:** `forgot_password_screen.dart` → `auth_service.dart` → `local_user_repository.dart`

**What the code shows:** `_proceed()` sends the OTP to whatever email is typed into the form, with zero lookup of the email actually on file for that username. `resetPassword(username, newPassword)` has no email parameter anywhere in the call chain, down to the abstract `UserRepository` interface itself — the missing check is baked into the contract, not just one overlooked line.

**Fix direction:** Before sending the OTP, look up the stored email for that username and send it there — never to the typed value. Update the `UserRepository` interface signature too, not just the implementation.

#### C2. signInAnonymously was never added — the auth fix is only half-shipped
**File:** `main.dart` (missing call) + `firestore.rules` (already written)

**What the code shows:** `firestore.rules` opens with its own comment: "Requires: `FirebaseAuth.instance.signInAnonymously()` called in `main.dart` before any Firestore read/write." All 69 Dart files contain zero calls to `signInAnonymously` or any `FirebaseAuth` method. If these rules are already live, every sync call is being silently denied right now (reads and writes). If they're not live yet, the database is still fully open exactly as the original audit found.

**Fix direction:** Add `await FirebaseAuth.instance.signInAnonymously()` in `main.dart`, after `Firebase.initializeApp()` and before `SyncQueue.instance.startMonitoring()`, then confirm in the Firebase console which state the rules are actually in.

#### C3. The email-sending API key ships inside the compiled app *(new this pass)*
**File:** `otp_screen.dart` + `pubspec.yaml`

**What the code shows:** `pubspec.yaml` lists `.env` under `assets`, so `flutter_dotenv`'s file is bundled into the compiled APK/IPA like any other resource. The live Brevo API key, sender email, and sender name all live in that file. Unzipping a release APK hands anyone that key — the same exposure pattern as the Firebase config issue already flagged, but for the account that can send email as the business.

**Fix direction:** Move OTP-sending behind a small server function (a Firebase Cloud Function works well) that holds the Brevo key server-side. The app should call that function, never Brevo directly.

#### C4. OTP sending has no ownership check and no real rate limit *(new this pass)*
**File:** `forgot_password_screen.dart` + `register_screen.dart` + `otp_screen.dart`

**What the code shows:** Both screens navigate to `OtpScreen` — which immediately fires a real email — before checking whether the username exists or owns that email. The only throttle is a 60-second countdown in that screen's local widget state, which resets the moment you back out and re-enter. Paired with C3, anyone with the extracted key can call Brevo directly and bypass the UI entirely.

**Fix direction:** Verify the username/email pairing before ever calling the email API (the same lookup C1 needs — one change fixes both), and move the cooldown server-side.

---

### High

#### H1. Sync queue's retry logic is correct — but never actually triggered
**File:** `firestore_sync.dart` + `sync_queue.dart`

**What the code shows:** `sync_queue.dart`'s catch block correctly keeps a queue row when an exception is thrown. The problem is upstream: every method in `firestore_sync.dart` wraps its body in `catch (_) {}` with no rethrow, so the awaited call inside `sync_queue.dart` can never actually throw. The row gets deleted as "synced" even when the Firestore write failed.

**Fix direction:** The whole fix lives in one file: remove `catch (_) {}` from `firestore_sync.dart`'s methods. `sync_queue.dart` needs no changes — it's already waiting for a real exception.

#### H2. Product price and stock silently save as zero on bad input
**File:** `dialogs/product_dialog.dart`

**What the code shows:** `double.tryParse(_priceCtrl.text) ?? 0` with no `TextFormField` validator on price, stock, or min-stock — only the name field blocks submission. The confirmation dialog shows a generic "Add Product?" with no preview of the actual numbers about to be written.

**Fix direction:** Add real validators to all three numeric fields, copying the `TextFormField` + validator pattern `reseller_dialog.dart` already uses correctly.

#### H3. Custom Orders money is invisible to every report — and has no payment trail either
**File:** `core/app_state.dart` + `custom_order_model.dart`

**What the code shows:** `addCustomOrder()` only writes to its own table and never touches `OrderService`, so `AccountingService`, Overview revenue, the Sales Table, and P&L never see this money. One layer deeper: there's no `PaymentRecord`-style history here at all — `depositPaid` is one freely editable number, with no record of when an installment came in or how.

**Fix direction:** Either have custom-order payments also create an `Order` record, or give `CustomOrder` its own `PaymentRecord` list mirroring `CustomerDebt`, then fold that into `AccountingService` as its own category.

#### H4. A failed save still shows the success toast
**File:** `repositories/base_repository.dart`

**What the code shows:** `safeVoidCall()`'s own doc comment says "use only for non-critical side effects (logging, sync)" — but it's the wrapper used for product, order, and debt writes, exactly the operations a business owner most needs to know failed. It swallows the error and returns a normal `Future<void>`, so the dialog's hard-coded success toast fires regardless.

**Fix direction:** Give write-path methods a `Future<bool>` or small `Result<T>` return, and reserve `safeVoidCall` for what it was actually designed for.

---

### Medium

#### M1. P&L mixes a date-filtered figure with an all-time figure
**File:** `screens/reports_screen.dart` → `_buildPLSummary()`

**What the code shows:** `net` comes from `_filteredOrders()` and respects the date range. `utangCollected` sums `AppState().debts.toList()` with zero date filter — every utang payment ever recorded. A "this month" P&L shows an accurate Net Sales line next to a Net Income figure inflated by the entire payment history.

**Fix direction:** Flatten every debt's payments list and filter each `PaymentRecord.paidAt` against the selected range.

#### M2. Three different numbers all claim to be "revenue" on one screen
**File:** `analytics_screen.dart` + `accounting_service.dart` + `app_state.dart`

**What the code shows:** Delivered Revenue = delivered orders only. Net Sales = every non-cancelled order including ones still Processing or Shipped. The trend chart and MoM% count a Utang order at its full `customerPayAmount` the instant it's created, even with ₱0 collected. `AppState.totalRevenue` already gets this right (delivered plus utang collected so far) but nothing on this screen calls it.

**Fix direction:** Pick one definition — `totalRevenue`'s logic is correct — and have `netSales()` and the trend/MoM calculations route through it.

#### M3. Exported sales and reseller reports include cancelled orders the preview excluded
**File:** `screens/reports_screen.dart` export handler

**What the code shows:** The preview correctly filters out cancelled orders. The export handler builds its list from `_filteredOrders()` (date only) and hands it straight to `ExportService` with no status filter, so the PDF's grand-total footer can include voided orders.

**Fix direction:** Filter out `OrderStatus.cancelled` once, in the export handler, before any order list reaches `ExportService`.

#### M4. "Custom Order Status" PDF export is the wrong document entirely
**File:** `screens/reports_screen.dart`

**What the code shows:** The CSV branch correctly exports `state.customOrders`. The PDF branch routes to `exportAnalyticsPdf()` — the generic 3-page analytics report with the title changed — and `customOrders` is never passed in. Exporting this as PDF gets a document with zero agreements in it.

**Fix direction:** Build a dedicated custom-orders PDF (`agreement_pdf_service.dart`'s layout is a good template) instead of routing to the generic builder.

#### M5. "Profit & Loss" PDF is also the wrong document
**File:** `screens/reports_screen.dart`

**What the code shows:** Same pattern as M4: the in-app preview shows a proper Gross → Discounts → Net → Utang → Net Income structure, but the exported PDF calls the same generic `exportAnalyticsPdf()` used for Accounting Summary, with no P&L structure anywhere.

**Fix direction:** Give Profit & Loss its own PDF builder mirroring the on-screen `_PLRow` breakdown.

#### M6. Order Tracker line items don't sum to the order total on reseller orders
**File:** `screens/orders_screen.dart`

**What the code shows:** Each line item renders `item.srpPrice * item.quantity` (full catalog price) above a total that correctly shows `order.customerPayAmount`. `receipt_screen.dart` already does this right using `item.subtotal`.

**Fix direction:** Swap in `item.subtotal`, already on `OrderItem` as `unitPrice × quantity` — the real, discounted line amount.

#### M7. Bulk "mark all delivered" can skip the utang warning — exact trigger traced
**File:** `screens/orders_screen.dart` + `local_order_repository.dart`

**What the code shows:** The bulk action only gathers Pending/Processing/Shipped orders, and the repository hard-blocks `status == utang` from reaching Delivered — so in the common case a debt-bearing order can't be bulk-delivered. The real gap: the status dialog lets you manually move an order from Utang back to Processing with no warning, while its debt stays open. Once that happens the bulk loop — unlike the single-order path — never checks the debts list directly, only the status field.

**Fix direction:** Have the bulk loop check `AppState().debts` for an open balance on each order's `orderId` directly, the same way the single-order dialog already does.

#### M8. Utang receipts omit accrued interest
**File:** `dialogs/utang_receipt_printer.dart`

**What the code shows:** Both receipt layouts print `totalAmount`, `amountPaid`, and `remainingBalance` — zero references to `accruedInterest` or `totalWithInterest`, even though the in-app Utang screen and payment dialog both correctly show and enforce the interest-inclusive total.

**Fix direction:** Add an interest line to both receipt layouts when `debt.hasInterest` is true, and print `totalWithInterest` as the amount due.

#### M9. Accounting ledger rows include cancelled orders the summary cards exclude — on all three tabs
**File:** `screens/accounting_screen.dart`

**What the code shows:** `filterByDateRange()` only filters by date. The summary cards separately filter out cancelled orders internally, but that same unfiltered list feeds `_OrderTable` for All Sales, Reseller, and Customized alike — breaking the visual reconciliation on every tab, not just the default one.

**Fix direction:** Apply the cancelled-order filter once, right after `filterByDateRange()`, before it reaches any of the three `_OrderTable` instances.

#### M10. "Disc. Price" and "Net" columns always show the same number
**File:** `screens/accounting_screen.dart` + `order_model.dart`

**What the code shows:** `discPrice` reads `customerPayAmount`; `netAmount` reads `netAfterAllDiscounts`, defined as just `=> customerPayAmount`. The screen's own inline comment already says "Net = same as discPrice" — a known, accepted duplication that was never cleaned up.

**Fix direction:** Either make the two genuinely different (per-unit price vs. order total) or remove one column.

#### M11. Export date range never reaches the debts list
**File:** `screens/reports_screen.dart` export handler

**What the code shows:** `final debts = state.debts.toList()` has no date filter, feeding Outstanding Debts, Debt+Interest, Custom Order Status PDF, Accounting Summary, and P&L alike. Outstanding Debts/Debt+Interest are fine regardless since "unpaid right now" is meant to be a snapshot — Accounting Summary and P&L are the two that actually produce wrong numbers.

**Fix direction:** Wherever "collected in period X" is calculated, filter each `PaymentRecord.paidAt` against the range, not the parent debt's `createdAt`.

#### M12. Stock check at order creation reads memory, not the database *(missed last time, added now)*
**File:** `services/order_service.dart`

**What the code shows:** `createOrder()` validates requested quantity against the products list passed in from `AppState`'s in-memory cache, not a fresh query at save time. Fine on one device since Dart is single-threaded — cannot catch overselling if the same account is ever used from two devices at once.

**Fix direction:** Worth documenting as a known limit; a transaction-time stock re-check would be needed before any multi-device use.

#### M13. Restoring an order can silently under-count stock *(missed last time, added now)*
**File:** `core/app_state.dart` → `restoreOrder()`

**What the code shows:** `newQty = (product.stockQty - item.quantity).clamp(0, 999999)` — if stock already dropped too low to cover the restored quantity, the deduction clamps to zero instead of going negative or flagging the mismatch. The discrepancy is absorbed silently.

**Fix direction:** Log or surface a warning when the clamp actually changes the would-be value.

#### M14. A specific, useful error message gets thrown away *(new this pass)*
**File:** `core/app_state.dart` → `addOrder()`

**What the code shows:** `OrderService.createOrder()` throws a precise message ("Not enough stock for X. Available: Y, requested: Z") for the rare case where stock changes between adding to cart and tapping Create Order. `AppState.addOrder()`'s catch block discards it and always calls `onError` with a generic "Failed to create order. Please try again."

**Fix direction:** Pass the actual exception message through to `onError`, the way `orders_screen.dart`'s own status-update handler already does.

---

### Low

#### L1. Recycle Bin shows the SRP total, not what the customer paid, for reseller orders
**File:** `screens/recycle_bin_screen.dart`

**What the code shows:** Line 302 formats `order.totalAmount`, the full catalog price for a reseller order. Every other screen — Orders, Receipt — correctly uses `customerPayAmount`.

**Fix direction:** One-line swap to `order.customerPayAmount`.

#### L2. No UNIQUE constraint on orders.order_id, despite what the comments claim
**File:** `database/database_helper.dart`

**What the code shows:** `order_id` is `TEXT NOT NULL` with no `UNIQUE` keyword — only `users.username` actually has one. A comment elsewhere claims the UNIQUE constraint is "the final safety net," which isn't true of the schema as written.

**Fix direction:** Add the constraint with a migration, or correct the comment.

#### L3. The OTP's "10 minutes" expiry is never checked
**File:** `screens/otp_screen.dart`

**What the code shows:** The email template promises a 10-minute window. The verification code never records a timestamp or checks elapsed time — it stays valid indefinitely until "Resend" is tapped.

**Fix direction:** Store the generation time and reject verification once 10 minutes have passed.

#### L4. A missing .env asset would crash the app before any crash log exists
**File:** `main.dart`

**What the code shows:** `dotenv.load()` has no try/catch and runs before `Firebase.initializeApp()` — before Crashlytics is configured. A packaging mistake that drops the asset hard-crashes on launch with nothing recorded remotely.

**Fix direction:** Wrap the load in try/catch and fall back to "email features disabled" instead of failing the app.

#### L5. Passwords are hashed but never salted
**File:** `repositories/local_user_repository.dart`

**What the code shows:** Plain `sha256.convert(utf8.encode(password))` with no per-user salt. Reasonable at today's single-admin scale, fast to attack with rainbow tables if the users table is ever exposed — which C2 makes somewhat more plausible until resolved.

**Fix direction:** Move to bcrypt or add a per-user salt, upgrading existing accounts on next login.

#### L6. "Reseller Detail" report silently reuses the standard orders PDF
**File:** `screens/reports_screen.dart`

**What the code shows:** The code's own comment says it plainly: "Falls back to `exportOrdersPdf` — add `exportResellerDetailedPdf` when ready." Tapping this today gives the same file as plain "Reseller Sales," just retitled.

**Fix direction:** Build the real per-item discount breakdown, or label it "(coming soon)."

#### L7. A dead-code factory carries a latent double-discount bug
**File:** `models/sales_record_model.dart`

**What the code shows:** `SalesRecord.fromJoinMap()` is never called anywhere today — the real Sales Table path builds records correctly elsewhere — but this factory misreads a peso-amount column as a percentage, which would silently double-discount if a future refactor reaches for it.

**Fix direction:** Delete the unused factory, or correct its logic to match the working path.

#### L8. Resellers and Custom Orders never appear in the Recycle Bin — schema isn't ready either *(missed last time, added now)*
**File:** `local_reseller_repository.dart` + `local_custom_order_repository.dart` + `database_helper.dart`

**What the code shows:** Both tables implement the same `is_deleted` pattern as Products/Orders/Debts, but neither type is read by the Recycle Bin screen. One layer deeper: unlike every other soft-deletable table, neither was given a `deleted_at` column — the fix needs a schema migration first, not just UI wiring.

**Fix direction:** Add `deleted_at` to both tables in the same migration as the `orders.order_id` constraint, then surface both as Recycle Bin tabs.

#### L9. Overview's Low Stock list has no height cap *(missed last time, added now)*
**File:** `screens/overview_screen.dart`

**What the code shows:** The Activity feed beside it is wrapped in a 280px `ConstrainedBox` + `ListView.builder`. The Low Stock list has no equivalent wrapper, so 20–30 low-stock items will stretch the whole dashboard.

**Fix direction:** Wrap it in the same `ConstrainedBox(maxHeight: 280)` pattern.

#### L10. Sign Out is the one disruptive action with no confirmation *(missed last time, added now)*
**File:** `screens/main_shell.dart`

**What the code shows:** Delete, hard-delete, and restore are all gated behind `showConfirmDialog` everywhere. Sign Out is a bare `GestureDetector` that logs out on a single tap — the lone exception.

**Fix direction:** Wrap it in the same `showConfirmDialog` used everywhere else.

---

## Improvement suggestions

### UI and UX

**Preview the value before confirming.** Product and order dialogs ask "Add Product?" with no preview of the price or stock about to be saved. `edit_stock_dialog.dart` already shows "Set stock to X units?" — copy that pattern everywhere a number gets committed.

**Merge Inventory into Products.** Both screens edit the exact same product list with near-identical UI. A single screen with a Catalog/Stock toggle keeps both workflows without the duplicate drawer entry.

**Card layout below 600px for tables.** Sales Table and Accounting are the only two screens still using a horizontally-scrolling `DataTable` on a phone-first app. Inventory and Products already show the responsive pattern to extend.

**Wire up the overdue-utang badge.** `state.overdueDebts` already powers the login notification. Orders and Products both show drawer badges from equivalent data — Utang is the one nav item still missing one.

**Confirm before signing out.** Delete, hard-delete, and restore all ask first, everywhere. Sign Out is the one single-tap exception to that pattern.

**Cap the Low Stock list height.** The Activity feed beside it is already wrapped in a 280px scroll cap — a long low-stock list deserves the same wrapper.

**Surface the real stock-shortage message.** `OrderService` already throws a specific, useful message on the rare cart/stock race. `AppState.addOrder()` discards it for a generic "failed" toast.

**Give Custom Orders a payment history.** `depositPaid` is one freely editable number with no audit trail, next to a Utang feature that already has the right pattern in `PaymentRecord`.

### Backend and architecture

**The sync fix is one file, not two.** `sync_queue.dart`'s retry-on-failure logic is already correct. Removing `catch (_) {}` from `firestore_sync.dart`'s methods is the entire fix.

**Move the email API key server-side.** A small Cloud Function holding the Brevo key keeps it out of every compiled build, and gives you a real place to enforce rate limits.

**Gate OTP-sending on real ownership.** One username-to-email lookup closes the account-takeover bug and the open email-sending vector at the same time — they share a root cause.

**Let writes report failure.** `safeVoidCall`'s own doc comment scopes it to logging/sync, not product/order/debt writes. A `Future<bool>` or small `Result<T>` lets a failed save look different from success.

**Add deleted_at to two tables.** `resellers` and `custom_orders` are schema-incomplete for the Recycle Bin fix that's already planned. Bundle it into the `orders.order_id` migration.

**Unique-index debts.order_id too.** Only an in-memory check in one dialog currently guards against two debt rows landing on the same order.

**Split analytics_screen.dart's build().** 1,743 lines recalculate gross sales, discounts, and trend data from scratch on every `AppState` change anywhere in the app.

**Scope rebuilds the way Orders already does.** `orders_screen.dart` documents a scoped `AppStateBuilder` pattern. Accounting and Analytics still rerun their full computation graph on any change.

---

*4 critical · 4 high · 14 medium · 10 low — 32 findings, all confirmed from source.*
