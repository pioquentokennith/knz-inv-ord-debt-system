# KNZ Scent — Audit Remediation Plan

## Context
Flutter + Firebase (Auth/Firestore/Crashlytics) + SQLite app for inventory, order, and debt tracking. A full audit (`AUDIT_REPORT.md`, commit `c4f6284` + uncommitted worktree) found it's not release-ready: critical risk in authentication, local data integrity, cloud sync, and debt/accounting accuracy, plus missing tests and incomplete release configuration. This plan operationalizes the audit's own "Recommended remediation order" into concrete, checkable phases.

## How to use this
- Save this file and `AUDIT_REPORT.md` together in the repo (root or `/docs`) before starting.
- There's an older `KNZ-Scent-Full-Verification-Report-v2.md` already in the repo — worth a skim for history, but `AUDIT_REPORT.md` is the current source of truth; it explicitly says the older report's fixes were only partially applied.
- **Before Phase 1:** commit or stash the current uncommitted worktree (13 modified + 3 untracked files per the audit) on its own, so remediation work starts from a clean, attributable baseline.
- Work one phase per Claude Code session. Don't try to run all nine in one sitting — these changes touch auth, money, and sync, and they're not safe to do as one giant diff. Consider a branch per phase (`fix/phase-1-startup-otp`, etc.) so each is reviewable on its own.
- Only move to the next phase once the current one's "Done when" line is actually true, not just "looks done."
- Copy-paste starters for each phase are at the bottom.

## Ground rules (apply to every phase)
- Read `AUDIT_REPORT.md` in full before touching code — this plan only sequences it; the audit has the exact file/line detail.
- Make the actual code changes. Don't describe a plan and stop — implement it.
- End of phase: run `flutter analyze` (can take 2+ minutes on this machine — let it finish rather than assuming it hung), run whatever tests exist, commit with `fix(phaseN): <summary>`, then report back — what changed, what's still open, and anything that needs Lenzo specifically (Firebase console changes, `firebase deploy`, a release keystore, Play Console settings — the agent won't have credentials for these).
- Default to the fix the audit already specifies. Don't ask permission for routine implementation calls.
- Do flag the items under "Product decisions" the moment they're relevant. Make a recommendation and proceed with it, but say explicitly that the call was made so it can be overruled.
- Don't touch the Phase 7 dependency upgrades (firebase_core, firebase_auth, cloud_firestore, firebase_crashlytics, flutter_local_notifications, flutter_lints) before Phase 7's tests exist — they're major-version jumps and need a safety net first.

## Product decisions — flag, don't silently pick
1. **Cash vs. accrual** basis for reports (finding 13).
2. **Reseller totals:** should SRP or the discounted price be "the" total, consistently across line items, the recycle bin, and receipts?
3. **Real scope:** Android-only / local-first single device for now, vs. building full multi-platform support and true two-way cloud sync (findings 14, 17). This changes how much of Phase 3 and Phase 9 is worth doing in full vs. documenting as a deliberate limitation.

## Phase 1 — Startup and OTP have to actually work · Critical
Findings: 1, 2, 18
- Remove the client-side `.env`/`flutter_dotenv` startup dependency; make email/OTP delivery an optional backend capability, not something that can crash boot.
- Get the OTP Cloud Function to a deployable state: add `.firebaserc`, `functions/package-lock.json`, real Functions config in `firebase.json`, and move `functions.config()` values to Secret Manager/parameters.
- Collapse bootstrap into one guarded zone; split required local init (SQLite, prefs) from optional cloud/notification init, so a first-run offline install still reaches the app instead of hanging on Firebase.

**Done when:** a clean install, airplane mode, no `.env` file, still reaches the home screen without crashing — and `functions/` would deploy cleanly if Lenzo ran `firebase deploy --only functions`.

## Phase 2 — Replace the authentication boundary · Critical
Findings: 3, 4, 5, plus the security-section items on the admin role, username collisions, login throttling, forgot-password enumeration, and notification content.
- Move OTP generation and verification server-side: hash + expiry + attempt limit stored in the Function, a challenge ID returned to the client, a second call to verify, a short-lived token issued for the actual reset. (Or switch to Firebase Auth's own password-reset/email-link flow instead of maintaining custom OTP code.)
- Pick one identity system and bind every Firestore path to the authenticated UID, not the username. Write deny-by-default Firestore rules and test them against the emulator.
- If moving to Firebase Auth, stop storing password verifiers in Firestore entirely. If any local verifier must remain, salt it and use Argon2id/scrypt, with a migration off the current unsalted SHA-256.
- Make "Administrator" on new accounts actually gate something, or remove it until it does.
- Enforce username uniqueness against the cloud before an offline registration is allowed to sync, instead of letting sync silently overwrite an existing account's document.
- Normalize email case before comparing on reset; make the forgot-password response identical whether or not the account/email match; move username/email validation into the model/service layer so screens can't be the only gate.
- Strip customer names, balances, and overdue periods out of notification text so they don't sit on a lock screen.

**Done when:** logging out actually ends the session; an emulator-run Firestore rules test suite denies cross-account and unauthenticated reads; no password verifier reaches the client to be compared locally.

## Phase 3 — Data integrity: atomic writes, real sync · Critical
Findings: 6, 7, 10, 11, 12, and the Phase-3-relevant half of 14 (see product decision #3).
- Replace the swallow-everything error handling in `base_repository.dart` with a typed `Result`/propagated exception — no more turning a failed write into a "successful" `Future<void>`.
- Wrap order creation + line items + stock decrement + optional debt creation in one SQLite transaction, using conditional updates and checked row counts, not four independent calls.
- Add a real unique constraint on `(user_id, order_id)` and generate the ID inside the same transaction as the insert, not in an earlier, separate one.
- Build a transactional outbox for cloud writes: local mutation and outbox row commit together regardless of connectivity; an outbox row is deleted only after confirmed remote success; failures stay visible instead of being caught and dropped.
- Define the order state machine explicitly (active / cancelled / delivered / restored) and make every transition adjust stock atomically; restoring into insufficient stock should be rejected, not clamped to zero.
- Resolve the scope decision (product decision #3): either explicitly document this as local-first/single-device with cloud-as-backup only, or build the revision/conflict/tombstone handling that real two-way sync needs — including resellers, custom orders, and product images, none of which currently sync at all.

**Done when:** killing the app mid-order never leaves stock and order out of sync; two "simultaneous" orders (test with a second device or an emulator in airplane mode) never collide on the same ID; a forced Firestore failure surfaces in the UI instead of vanishing.

## Phase 4 — Debt and accounting correctness · Critical
Finding 8, and the double/SQLite `REAL` currency issue.
- Split debt into `principalOutstanding` and `interestOutstanding`, stored separately, with a `lastAccrualTimestamp`.
- Allocate payments interest-first, then principal — explicitly, not by netting against a single `amountPaid`.
- Migrate currency to integer centavos (or a proper `Decimal` type) everywhere; no new code should write a `double` for money, and existing `REAL` columns need a migration.
- Determine "paid off" from the full outstanding amount (principal + interest), not principal alone.

**Done when:** the audit's own example — ₱100 principal, ₱10 accrued interest, ₱100 payment — no longer zeroes the interest out; a unit test locks in interest-first allocation.

## Phase 5 — DTOs and migrations · High
Findings: 9, 15
- One versioned DTO mapper per entity (order, debt, reseller, custom order), used identically for local writes, cloud writes, and restore, so restore can't silently drop `paymentMethod`, `resellerFlag`, `discountedTotal`, `orderType`, or a debt's interest rate/type/start date.
- Add round-trip tests per entity: create → sync → restore → assert equality.
- Tighten `database_helper.dart`'s migration error handling: only swallow the specific expected duplicate-column case, roll back on everything else, and test migrations from every version 1 through 7 against a fixture database.

**Done when:** restoring an order or debt on a fresh install reproduces every field it had before — checked by a test, not a manual look.

## Phase 6 — Reporting · High
Finding 13, plus the reporting-adjacent items from "additional confirmed functional defects": debt receipts omitting interest, the reseller SRP-vs-discounted mismatch (product decision #2), the ledger-vs-summary-card mismatch, duplicate-named columns, and inconsistent date filtering on debt payments.
- Centralize all revenue/sales/profit math into one pure accounting domain service; every screen, export, and PDF should read from it instead of computing its own definition.
- Once the cash-vs-accrual call is made (product decision #1), make "net sales" consistently exclude unpaid utang, and make debt collections respect the same date filter as sales instead of pulling all-time.
- Fix the mismatched exports: "Custom Order Status" and "Reseller Detailed" currently reuse the wrong PDF template; the interest-with-debt export is missing its interest column.
- Route custom-order revenue and deposits into the same accounting service so they actually appear in reports.

**Done when:** a small hand-computed fixture (a handful of orders, debts, and payments) produces matching numbers on the dashboard, in every export, and in every PDF — checked by a test.

## Phase 7 — Tests, CI, and dependency hygiene · Important
Finding 16, plus the dependency/tooling audit.
- Real coverage for auth, CRUD, orders, debt, logging, session, and the rate limiter — the README currently claims this exists and it doesn't.
- `integration_test/` for the critical flows touched in Phases 3–4: order+stock+debt, the sync outbox, debt payment allocation.
- Pin the Dart/Flutter SDK (FVM or asdf) and align `pubspec.yaml`'s stated constraint with what `pubspec.lock` actually requires.
- Add `functions/package-lock.json` and Functions emulator tests.
- Stand up basic CI (analyze + test on push) and a coverage threshold.
- Only now: take on the firebase_core/firebase_auth/cloud_firestore/firebase_crashlytics/flutter_local_notifications/flutter_lints major-version upgrades, one at a time, with the new tests as a safety net.

**Done when:** CI is green on a clean clone, and each dependency upgrade lands as its own PR without breaking the suite.

## Phase 8 — Release engineering and remaining hardening · Important
Finding 17, plus the leftover security/privacy items: CSV formula injection, leftover temp export files, unencrypted SQLite, over-broad Android permissions.
- Real Android release signing (not the debug key); a real application ID (drop `com.example`); trim the manifest — no `USE_EXACT_ALARM`, boot permission, or scheduled receivers for immediate-only notifications, and drop Bluetooth-advertise/location unless they're actually used.
- Settle supported platforms for real (product decision #3) — if Android-only, remove or clearly mark the iOS/web/desktop scaffolding instead of leaving broken template branding in place.
- Sanitize CSV exports against formula injection (leading `=`, `+`, `-`, `@`), and delete exported CSV/PDF files from temp storage after sharing.
- Decide whether SQLite needs at-rest encryption (SQLCipher) given what's stored there after Phase 2's changes.

**Done when:** a release build installs on a clean device under a real signing key and package ID, and a CSV export containing a formula-injection-style name opens safely in Excel/Sheets.

## Phase 9 — Refactor and accessibility · Polish
Everything in "Code quality, performance, and accessibility," plus the remaining smaller items from "additional confirmed functional defects": payment history for custom orders, recycle-bin restore for resellers/custom orders, the low-stock list height cap, sign-out confirmation, and durable activity logging.
- Split the 902-line `AppState` singleton by domain (auth / products / orders / debts / notifications / logging); do the same for `analytics_screen.dart`, `order_dialog.dart`, `export_service.dart`. While in there: split the single global notifier into scoped ones so unrelated updates stop triggering full rebuilds, and stop returning fresh list objects from getters so identity-based caching actually works.
- Bring resellers and custom orders under the same service interfaces as products/orders/debts.
- Move aggregation and PDF generation off the UI isolate (`compute()`); add pagination to repository reads instead of loading full tables.
- Add `Semantics` labels and real touch targets (44/48dp minimum) to the custom buttons; add a textual fallback for charts; include keyboard activity in session-timeout detection, not just pointer/tap/pan.
- Push validation into the model layer: reject invalid numeric input instead of coercing to zero, cap custom-order deposits at the agreed price, and enforce setter validation from constructors and `copyWith`, not just from screens.
- Add the smaller fixes: an immutable, append-only payment history for custom orders; recycle-bin restore for soft-deleted resellers/custom orders; a height cap on the low-stock list; a sign-out confirmation dialog; and stop suppressing activity-log persistence failures (full tamper-resistance is probably out of scope for a local SQLite app, but silent data loss in the log isn't).

**Done when:** no touched file exceeds roughly 400–500 lines, a screen reader can get through the core flows, and the smaller-bugs list above is empty.

## If the deadline is tight
Phases 1–6 are the "critical risk" items from the audit's own table — crashes, security holes, wrong money, silent data loss. Phases 7–9 (tests/CI, release polish, refactor/accessibility) matter a lot for a real release but matter less for a defense than "the numbers are right and nothing gets silently lost." If time runs out, stop after Phase 6 and say so explicitly rather than rushing the rest.

## Session starters — paste one per Claude Code session
1. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full. Commit/stash the current uncommitted worktree separately first, then execute **Phase 1 — Startup and OTP** exactly as scoped. Checkpoint and report before stopping.
2. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 2 — Authentication boundary** exactly as scoped. Checkpoint and report before stopping.
3. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 3 — Data integrity** exactly as scoped. Checkpoint and report before stopping.
4. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 4 — Debt and accounting correctness** exactly as scoped. Checkpoint and report before stopping.
5. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 5 — DTOs and migrations** exactly as scoped. Checkpoint and report before stopping.
6. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 6 — Reporting** exactly as scoped. Checkpoint and report before stopping.
7. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 7 — Tests, CI, dependency hygiene** exactly as scoped. Checkpoint and report before stopping.
8. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 8 — Release engineering** exactly as scoped. Checkpoint and report before stopping.
9. Read `AUDIT_REPORT.md` and `REMEDIATION_PLAN.md` in full, then execute **Phase 9 — Refactor and accessibility** exactly as scoped. Checkpoint and report before stopping.
