# Phase 2 Completion Report

> Current status: the Spark registration correction dated 2026-07-27 at the
> end of this report supersedes the earlier production Cloud Functions
> registration/deployment instructions and Android configuration status.

## Implemented
- Replaced local/custom password authentication with native Firebase Authentication email/password identity and normalized email login.
- Removed client-side password verification, anonymous startup authentication, custom-token login, and the legacy custom-password Function handlers and helpers.
- Added explicit `pending`, `approved`, `rejected`, and `suspended` account states; protected access requires `approved` and `active == true`.
- Added backend-controlled registration requests, verified-email refresh, Administrator review, central username reservation, and a default approved role of `Staff`.
- Added a one-time owner bootstrap script for the first verified Administrator, including transactional username-collision protection.
- Added non-enumerating Firebase password-reset responses while preserving visible timeout, transport, and delivery failures.
- Prevented registration-request callable failures from displaying success; failed new-account setup attempts delete the unsubmitted Firebase user when possible and report cleanup failure when not possible.
- Bound local active identity and all supported Firestore business paths to the authenticated, non-anonymous Firebase UID.
- Replaced generic Firestore child access with explicit `products`, `orders`, `debts`, and `activity_logs` rules that validate UID ownership and string document IDs on writes.
- Added awaited logout, sync shutdown, notification cancellation, local state clearing, stale-load invalidation, and approved-session-only offline restoration.
- Added SQLite schema version 9, transactionally removed `users.password`, quarantined legacy profiles as inactive and unmapped, preserved all business owner keys, and scrubbed credential-shaped outbox JSON.
- Added an explicit non-destructive legacy identity migration plan; no legacy partition is assigned without an owner-approved username-to-UID mapping.
- Removed sensitive business counts and details from lock-screen notification text.
- Added Administrator registration-review UI and auth-gated startup routing.

## Files changed
- `.github/workflows/ci.yml`
- `firebase.json`
- `firestore.indexes.json`
- `firestore.rules`
- `functions/access_helpers.js`
- `functions/index.js`
- `functions/package.json`
- `functions/package-lock.json`
- `functions/scripts/bootstrap_admin.js`
- `functions/test/access_helpers.test.js`
- `functions/test/emulator/otp_endpoints.test.js`
- `lib/core/app_state.dart`
- `lib/core/startup_gate.dart`
- `lib/database/database_helper.dart`
- `lib/main.dart`
- `lib/models/user_model.dart`
- `lib/repositories/firestore_sync.dart`
- `lib/repositories/local_user_repository.dart`
- `lib/repositories/sync_queue.dart`
- `lib/repositories/user_repository.dart`
- `lib/screens/forgot_password_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/main_shell.dart`
- `lib/screens/otp_screen.dart`
- `lib/screens/register_screen.dart`
- `lib/screens/registration_requests_screen.dart`
- `lib/services/auth_service.dart`
- `lib/services/cloud_auth_service.dart`
- `lib/services/notification_service.dart`
- `rules-tests/package.json`
- `rules-tests/package-lock.json`
- `rules-tests/test/firestore_rules.test.js`
- `test/database/identity_migration_test.dart`
- `test/project_configuration_test.dart`
- `test/services/auth_service_test.dart`
- `docs/IDENTITY_MIGRATION_PLAN.md`
- `docs/progress/PHASE_2_COMPLETION.md`

## Database or API contract changes
- SQLite database version increased to 9.
- The local `users` table no longer contains `password`; it now contains `firebase_uid`, `account_status`, `is_active`, `legacy_owner_key`, and `migration_state`.
- Existing profiles migrate to inactive `pending` and `unmapped` records with no Firebase UID. Existing product, order, item, debt, payment, log, reseller, custom-order, and outbox owner keys are not rewritten.
- Malformed outbox JSON aborts and rolls back the v9 migration instead of partially migrating identity data.
- Client authentication now uses Firebase `signInWithEmailAndPassword`, `createUserWithEmailAndPassword`, email verification, and `sendPasswordResetEmail`.
- Added callable Functions `submitRegistrationRequest`, `refreshRegistrationVerification`, and `reviewRegistrationRequest`.
- Removed deployable `registerAccount`, `resetAccountPassword`, and `loginAccount` custom-credential Functions.
- Added UID-keyed `accountAccess`, `registrationRequests`, and `_usernames` backend records.
- Firestore profile and access writes are backend-only; supported business writes require an approved active session, matching UID ownership, and a string `id` equal to the document ID.
- Soft-delete sync payloads now include `user_id` so ownership validation also applies when a merge creates a missing cloud document.

## Tests added or updated
- Added SQLite v8-to-v9 migration tests for verifier removal, unchanged legacy ownership, credential-field scrubbing, and rollback on malformed outbox JSON.
- Added authentication service tests for approved caching, pending/rejected/suspended denial, approved offline restoration, Firebase logout, and password-reset error propagation.
- Added static configuration tests for verifier removal, UID-bound paths, removed custom-password Functions, secret boundaries, and bootstrap username protection.
- Added Functions validation tests for registration metadata, review states, and default `Staff` role.
- Expanded Functions emulator coverage for native caller requirements, pending Staff creation, normalized email, username collision, Administrator-only review, self-review denial, unverified-request denial, and safe OTP configuration failure.
- Added Firestore Emulator rules tests for unauthenticated and anonymous denial, cross-UID denial, state enforcement, allowed same-UID document and collection reads, ownership and ID validation, unknown collection denial, self-approval denial, and backend-only role changes.
- Full Flutter suite: 52 passed.
- Functions unit suite: 11 passed.
- Functions emulator suite: 10 passed.
- Firestore rules emulator suite: 7 passed.

## Commands run
- `git status --short --branch`
- `git rev-parse --abbrev-ref HEAD`
- `git rev-parse HEAD`
- `git log --oneline -10`
- `git diff --stat`
- `git diff --name-only`
- `dart format lib/core/app_state.dart lib/screens/forgot_password_screen.dart lib/screens/otp_screen.dart lib/services/cloud_auth_service.dart lib/repositories/firestore_sync.dart test/project_configuration_test.dart test/services/auth_service_test.dart`
- `dart format --output=none --set-exit-if-changed lib test`
- `dart analyze lib/core/app_state.dart lib/screens/forgot_password_screen.dart lib/screens/otp_screen.dart lib/services/cloud_auth_service.dart lib/repositories/firestore_sync.dart test/project_configuration_test.dart test/services/auth_service_test.dart`
- `flutter analyze`
- `flutter test test/services/auth_service_test.dart test/project_configuration_test.dart test/database/identity_migration_test.dart`
- `flutter test --coverage`
- `flutter build apk --debug --no-pub`
- `npm ci --ignore-scripts --no-audit --no-fund --prefer-offline` in `functions`
- `npm ci --ignore-scripts --no-audit --no-fund --prefer-offline` in `rules-tests`
- `npm run lint` in `functions`
- `npm test` in `functions`
- `npm audit --omit=dev --audit-level=high` in `functions`
- `npm audit --omit=dev --audit-level=high` in `rules-tests`
- `$env:JAVA_HOME="E:\Andriod Studio\jbr"; $env:PATH="$env:JAVA_HOME\bin;$env:PATH"; npm run test:emulator`
- Static scans for anonymous authentication, client password verifiers, custom-token/legacy auth endpoints, username-bound cloud paths, provider secrets, permissive rules, and Android Firebase package identity.
- `git diff --check`

## Validation results
- PASS: Full `flutter test --coverage` passed 52 of 52 tests.
- PASS: Focused analysis of all final Phase 2 Dart edits found no issues.
- PASS: Functions syntax/lint completed without errors.
- PASS: Functions unit tests passed 11 of 11.
- PASS: The Emulator Suite loaded only `requestOtp`, `verifyOtp`, `submitRegistrationRequest`, `refreshRegistrationVerification`, and `reviewRegistrationRequest`; Functions tests passed 10 of 10 and rules tests passed 7 of 7.
- PASS: Emulator rules deny unauthenticated, anonymous, cross-UID, unapproved, suspended, role-escalation, invalid ownership/ID, and unknown-child-collection access while allowing approved same-UID reads and writes.
- PASS: SQLite migration tests demonstrate verifier removal, unchanged business owner keys, outbox scrubbing, and transaction rollback on malformed JSON.
- PASS: Static scans found no client anonymous sign-in, deployable custom-password Function, custom token creation, or Brevo/OTP secret identifier in Flutter source. Credential field names remain only in migration/outbox scrub deny lists.
- PASS: `npm ci` installed 239 locked Functions packages and 111 locked rules-test packages.
- PASS: Functions `npm audit --omit=dev --audit-level=high` returned success at the high-severity threshold; it reports 9 moderate transitive `uuid` vulnerabilities whose automated fix requires breaking Firebase major upgrades.
- PASS: `git diff --check` found no whitespace errors; Git emitted existing LF-to-CRLF conversion warnings.
- FAIL: `dart format --output=none --set-exit-if-changed lib test` cannot parse `lib/screens/analytics_screen.dart` at lines 781 and 861 and reports 61 other files outside the focused Phase 2 formatting set would change.
- FAIL: Full `flutter analyze` reports 3 parse errors in `lib/screens/analytics_screen.dart` plus 9 existing informational `unnecessary_this` diagnostics.
- FAIL: Android debug build fails at Flutter compilation on the same `analytics_screen.dart` syntax defect.
- FAIL: Rules-test `npm audit --omit=dev --audit-level=high` produced no output and timed out at both 180 and 360 seconds; it is not reported as passed.
- NOT RUN: Live Firebase deployment, first-Administrator bootstrap, production registration/login/reset, and physical Android offline/account-switch checks require owner project access, corrected Android Firebase configuration, a successful build, and a device.
- The Phase 2 automated security acceptance criteria are demonstrated locally. Full operational acceptance remains blocked by the existing analytics compile defect and owner-only Firebase/device actions.

## Product decisions made
- Firebase Authentication email/password is the sole password identity authority.
- The first Administrator is an owner-created, email-verified Firebase UID provisioned through the bootstrap script.
- New approved registrations default to `Staff`; only an already approved active Administrator may grant a role.
- Username remains centrally unique metadata and is not an authorization key.
- Legacy data is quarantined unchanged and may be mapped only through explicit owner-approved username-to-UID records and a later controlled migration.
- Offline access requires both a persisted non-anonymous Firebase session and a previously cached approved active UID profile; signed-out local password login is not supported.
- Forgot-password responses do not reveal whether an account exists, but actual transport or delivery failures do not display success.
- Reporting basis, reseller total, and synchronization scope decisions remain outside Phase 2.

## Owner-only actions still required
- Enable Firebase Authentication Email/Password sign-in and email-enumeration protection for the production project.
- Create and email-verify the first owner Administrator Firebase Auth account.
- From `functions`, set `BOOTSTRAP_ADMIN_UID` and `BOOTSTRAP_ADMIN_USERNAME`, optionally set `BOOTSTRAP_LEGACY_OWNER_KEY` only after approving that mapping, then run `npm run bootstrap:admin` with authorized Application Default Credentials.
- Register Android application ID `com.knzscent.admin` in Firebase and replace `android/app/google-services.json`; the current file still declares `com.example.inventoryordtrack`.
- Deploy Functions, Firestore rules, and indexes with `npm run deploy` after reviewing the target Firebase project and credentials.
- Validate registration, email verification, Staff approval, rejection, suspension, password reset, logout, offline restoration, and account switching against a non-production Firebase project.
- Resolve the existing `analytics_screen.dart` syntax defect and run the clean-install physical Android online/offline checklist.
- Approve authoritative legacy username-to-UID mappings before any local or cloud business partition is copied or rewritten.
- Isolate the heavily dirty worktree through an owner-approved commit or other non-destructive workflow before release work.

## Remaining risks
- Existing legacy local and cloud username partitions are deliberately inaccessible until authoritative mappings and controlled migration tooling exist.
- A previously approved cached session can continue offline until Firebase becomes reachable; suspension and token revocation cannot be observed while fully offline.
- Production Firebase configuration, deployment, bootstrap, and end-to-end email flows have not been exercised in this workspace.
- Android Firebase package mismatch prevents release-valid Firebase behavior.
- The repository-wide parse/build defect prevents device validation and a green CI Flutter job.
- App Check enforcement remains off until the Flutter client supplies valid App Check tokens.
- The local host uses Flutter 3.41.2, Node 24.18.0, and Android Studio JDK 21.0.9, while the pinned project/CI toolchains are Flutter 3.38.4, Node 20, and Java 17.
- Functions dependencies retain 9 moderate transitive vulnerabilities; major Firebase upgrades are deferred until Phase 7 safety gates.
- The rules-test production audit remains unknown because both attempts timed out without output.
- The worktree remains heavily dirty; no existing work was reset, stashed, committed, or discarded.

## Recommended next phase
- Do not begin Phase 3 yet. First resolve the existing analytics compile blocker and complete the owner-only Firebase bootstrap, deployment, Android configuration, and device validation for Phase 2. Begin Phase 3 only when explicitly requested.

---

## Spark Registration Correction - 2026-07-27

### Implemented
- Removed production Flutter calls to `submitRegistrationRequest`, `refreshRegistrationVerification`, and `reviewRegistrationRequest` without deleting their Functions source or emulator tests.
- Created Firebase Auth accounts with email/password and sent Firebase's standard email-verification link.
- Required a refreshed verified Firebase token before submitting registration data.
- Created `accountAccess/{uid}`, `users/{uid}`, and `_usernames/{normalizedUsername}` in one Firestore batch.
- Made every new registration `Staff`, `pending`, and inactive, with identity bound to the authenticated UID and email.
- Replaced the production review Function with an atomic Firestore batch across `accountAccess/{uid}` and `users/{uid}`.
- Removed Administrator role selection from Flutter; Spark client review always retains `Staff`.
- Used `accountAccess` pending documents as the Administrator review queue. The legacy `registrationRequests` collection remains only for retained Functions compatibility.
- Preserved only non-secret name/username registration drafts locally so verified sign-in can complete a deferred request.
- Classified only confirmed immediate Firestore rejection codes as safe cleanup failures. Timeout and unknown outcomes preserve the Auth account, local draft, and retry state.
- Added server-only retry reconciliation against `accountAccess/{uid}` before resubmission. A matching access document proves the original three-document batch committed atomically, preventing duplicate retry writes.
- Kept Firebase Auth password-reset email as the forgotten-password flow and removed registration OTP claims from the production UI.
- Added `npm --prefix functions run deploy:spark` for Firestore rules/index deployment without Functions deployment.

### Files changed
- `README.md`
- `docs/progress/PHASE_2_COMPLETION.md`
- `firestore.rules`
- `functions/package.json`
- `lib/core/app_state.dart`
- `lib/screens/otp_screen.dart`
- `lib/screens/register_screen.dart`
- `lib/screens/registration_requests_screen.dart`
- `lib/services/auth_service.dart`
- `lib/services/cloud_auth_service.dart`
- `rules-tests/test/firestore_rules.test.js`
- `test/integration/auth_user_switching_test.dart`
- `test/project_configuration_test.dart`
- `test/services/auth_service_test.dart`
- `test/services/cloud_auth_service_test.dart`

### Database or API contract changes
- No SQLite schema, migration, local business record, or cloud business-data path changed.
- Spark registration writes only the audited `accountAccess`, `users`, and `_usernames` contracts.
- New access records are fixed to `role: Staff`, `status: pending`, and `active: false`.
- New root profiles are fixed to `role: Staff`, `account_status: pending`, and `is_active: false`.
- Production registration and review no longer require a deployed callable endpoint or Blaze billing.
- Functions implementations and legacy `registrationRequests` support remain available only for emulator tests or a future owner-approved Blaze migration.

### Tests added or updated
- Firebase Auth account creation and standard verification-link wording.
- Unverified-email registration denial.
- Verified pending Staff registration creation.
- Confirmed immediate registration failure cleanup of only the newly created current Auth account.
- Ambiguous timeout preservation of the Auth account and local draft.
- Retry after a pre-commit timeout.
- Reconciliation after a post-commit timeout with no duplicate access, profile, or username record.
- Pending, approved, rejected, and suspended login outcomes and messages.
- Static proof that production Cloud Auth does not call the retained registration Functions.
- Firestore Emulator coverage for verified ownership, pending Staff-only creation, atomic registration, username uniqueness, second-reservation denial, ordinary Staff review denial, self-review denial, Administrator review, Staff-only review outcome, protected identity immutability, and rejected/suspended enforcement.

### Commands run
- `flutter test test/services/cloud_auth_service_test.dart test/services/auth_service_test.dart test/screens/register_screen_test.dart test/screens/forgot_password_screen_test.dart test/integration/auth_user_switching_test.dart test/project_configuration_test.dart`
- `dart analyze lib/services/cloud_auth_service.dart lib/screens/register_screen.dart test/services/cloud_auth_service_test.dart`
- `npm exec --yes --package=node@20 --package=firebase-tools@14.27.0 -- cmd /c "node --version && firebase --version && npm run test:emulator"` from `functions/`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `git diff --check`
- Scoped searches for production endpoint names, role assignment, verified-email rules, atomic `getAfter()` checks, and Firebase identifiers.

### Validation results
- PASS: final focused Flutter authentication/registration suite completed all 35 tests.
- PASS: focused Dart analysis reported no issues.
- PASS: pinned Node 20.20.2/Firebase CLI 14.27.0 emulator gate completed all 10 retained Functions endpoint tests and all 23 Firestore Rules tests.
- PASS: formatting checked 120 `lib`/`test` files with zero changes required.
- PASS WITH EXISTING INFO: `flutter analyze` reported no errors or warnings and 26 existing informational lints outside this Spark correction.
- PASS: `git diff --check` found no whitespace errors; Git printed existing Windows LF-to-CRLF notices.
- PASS: the earlier full `flutter test --coverage` run in this correction session completed all 151 tests before the final timeout-only change; the final focused suite directly covers that change.
- PASS WITH WARNINGS: retained Functions unit tests completed 17/17 and the high-severity audit gate passed with 9 known moderate transitive `uuid` advisories requiring breaking Firebase dependency upgrades.
- FAIL, RESOLVED: the first timeout-test run used `Map.single`, causing one compile error; it was corrected to `Map.keys.single`, after which all 35 focused tests passed.
- FAIL, RESOLVED: an earlier Rules assertion recreated a disabled-rules Firestore context and failed after the allowed approval committed; the assertion was corrected and the final emulator run passed 23/23.
- WARNING: the emulator reports the retained older `firebase-functions` major and the expected missing OTP secret negative-path log. Neither is used by Spark production registration.

### Product decisions made
- Firebase Spark remains the production plan; no deployed Functions or Blaze billing are required for registration, review, verification, or password reset.
- A Firestore timeout is an unknown outcome, not a confirmed failure. The Auth account and local draft must survive until a server reconciliation or safe retry.
- Flutter may submit an Administrator review batch but has no trusted approval authority. Firestore rules authorize it only from an existing approved active Administrator and force the target role to `Staff`.
- Administrator creation remains owner-controlled through `functions/scripts/bootstrap_admin.js` only.

### Owner-only actions still required
- Resolve the Android Firebase App ID discrepancy in Firebase Console and regenerate/download both FlutterFire and Android configuration from the same `com.knzscent.admin` app. The requested App ID is `1:120139747390:android:823a15d9a89f4cfa6816f`, while both current files use `1:120139747390:android:823a15d9a89f4cfaf6816f`.
- Review the target project, then deploy only Firestore rules/indexes with `npm --prefix functions run deploy:spark`. Do not deploy Functions for the Spark path.
- Enable Email/Password Authentication and email-enumeration protection in Firebase Console if not already enabled.
- Create the first owner Auth account, set its display name, and verify its Firebase email.
- With Application Default Credentials explicitly targeting `knz-scent`, set `BOOTSTRAP_ADMIN_UID` and `BOOTSTRAP_ADMIN_USERNAME`, then run `npm --prefix functions run bootstrap:admin`. Set `BOOTSTRAP_LEGACY_OWNER_KEY` only for an owner-approved legacy mapping.
- Validate registration, verification, pending login, Staff approval/rejection/suspension, password reset, and logout on an Android device against the owner-controlled project.

### Remaining risks
- Production rules and the Spark flow have emulator evidence but have not been deployed or exercised against the owner project in this workspace.
- The requested and downloaded Android Firebase App IDs disagree by one `f`; production Android Firebase validation remains blocked until the owner confirms the canonical Console app and regenerates configuration.
- A deferred registration draft is device-local. If it is lost before the verified request is created, the user needs an owner-assisted account cleanup or a future explicit recovery flow.
- A previously cached approved session can remain usable while fully offline and cannot observe a later suspension until Firebase is reachable.
- The worktree contains extensive pre-existing phase and owner changes. This correction did not reset, stash, delete, or overwrite them.

### Recommended next phase
- Stop after this Phase 2 Spark correction. Do not begin Phase 8 without a separate explicit request.
