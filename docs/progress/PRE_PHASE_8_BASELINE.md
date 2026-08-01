# Pre-Phase 8 Baseline

## Gate purpose

This document records the attributable starting point for continued Phase 8 work. It is a readiness review only. No new Phase 8 feature implementation, deployment, bootstrap execution, staging, commit, data deletion, app-storage clearing, or application uninstall was performed.

## Starting Git identity

- Repository: `E:\flutter_test_projects\inventoryordtrack`
- Branch: `main`
- Commit before Phase 8 continuation: `c4f6284e018d00fd2f8b0b9d2b5e1c944e5b770b`
- Initial tracked worktree changes: 91 paths
- Initial untracked paths: 102 paths
- Initial `git diff --check`: PASS; no whitespace errors, with Windows line-ending notices only
- Initial tracked diff: 18,853 insertions and 10,529 deletions across 91 files
- Staged paths: none observed

The worktree contains completed Phase 0-7 remediation, owner/governance material, and partial pre-existing Phase 8 baseline work. Phase 8 has therefore already been started in part, but its formal continuation has not begun.

## Complete initial worktree classification

Each modified, deleted, or untracked path reported before this readiness review appears exactly once below. Classification is based on the Phase 7 completion report, current diff inspection, and the current file role. It does not imply owner approval to stage or commit.

### Completed pre-Phase-8 work

- `.env.example`
- `README.md`
- `functions/.env.example`
- `functions/.gitignore`
- `functions/access_helpers.js`
- `functions/index.js`
- `functions/otp_delivery.js`
- `functions/otp_helpers.js`
- `functions/otp_policy.js`
- `functions/package-lock.json`
- `functions/package.json`
- `functions/scripts/bootstrap_admin.js`
- `lib/core/app_bootstrap.dart`
- `lib/core/app_constants.dart`
- `lib/core/app_state.dart`
- `lib/core/domain_exceptions.dart`
- `lib/core/money.dart`
- `lib/core/startup_gate.dart`
- `lib/database/database_helper.dart`
- `lib/dialogs/custom_order_dialog.dart`
- `lib/dialogs/edit_stock_dialog.dart`
- `lib/dialogs/export_dialog.dart`
- `lib/dialogs/mark_as_utang_dialog.dart`
- `lib/dialogs/order_dialog.dart`
- `lib/dialogs/product_dialog.dart`
- `lib/dialogs/reseller_dialog.dart`
- `lib/dialogs/utang_payment_dialog.dart`
- `lib/dialogs/utang_receipt_printer.dart`
- `lib/dto/activity_log_dto.dart`
- `lib/dto/custom_order_dto.dart`
- `lib/dto/debt_dto.dart`
- `lib/dto/dto_reader.dart`
- `lib/dto/order_dto.dart`
- `lib/dto/product_dto.dart`
- `lib/dto/reseller_dto.dart`
- `lib/main.dart`
- `lib/models/custom_order_model.dart`
- `lib/models/debt_model.dart`
- `lib/models/order_model.dart`
- `lib/models/order_state_machine.dart`
- `lib/models/payment_method_model.dart`
- `lib/models/product_model.dart`
- `lib/models/reseller_accounting_summary.dart`
- `lib/models/reseller_model.dart`
- `lib/models/sales_record_model.dart`
- `lib/models/user_model.dart`
- `lib/repositories/activity_log_repository.dart`
- `lib/repositories/base_repository.dart`
- `lib/repositories/debt_repository.dart`
- `lib/repositories/firestore_sync.dart`
- `lib/repositories/local_custom_order_repository.dart`
- `lib/repositories/local_debt_repository.dart`
- `lib/repositories/local_order_repository.dart`
- `lib/repositories/local_product_repository.dart`
- `lib/repositories/local_reseller_repository.dart`
- `lib/repositories/local_user_repository.dart`
- `lib/repositories/order_repository.dart`
- `lib/repositories/sync_queue.dart`
- `lib/repositories/user_repository.dart`
- `lib/screens/accounting_screen.dart`
- `lib/screens/analytics_screen.dart`
- `lib/screens/custom_orders_screen.dart`
- `lib/screens/forgot_password_screen.dart`
- `lib/screens/inventory_screen.dart`
- `lib/screens/login_screen.dart`
- `lib/screens/main_shell.dart`
- `lib/screens/orders_screen.dart`
- `lib/screens/otp_screen.dart`
- `lib/screens/overview_screen.dart`
- `lib/screens/products_screen.dart`
- `lib/screens/receipt_screen.dart`
- `lib/screens/recycle_bin_screen.dart`
- `lib/screens/register_screen.dart`
- `lib/screens/registration_requests_screen.dart`
- `lib/screens/reports_screen.dart`
- `lib/screens/reseller_accounting_screen.dart`
- `lib/screens/reseller_screen.dart`
- `lib/screens/sales_screen.dart`
- `lib/screens/utang_screen.dart`
- `lib/services/accounting_service.dart`
- `lib/services/agreement_pdf_service.dart`
- `lib/services/auth_service.dart`
- `lib/services/cloud_auth_service.dart`
- `lib/services/debt_service.dart`
- `lib/services/export_service.dart`
- `lib/services/login_rate_limiter.dart`
- `lib/services/notification_service.dart`
- `lib/services/order_service.dart`
- `lib/services/otp_service.dart`
- `lib/services/product_service.dart`
- `lib/services/session_timeout_service.dart`
- `lib/widgets/receipt_shared_widgets.dart`
- `lib/widgets/shared_widgets.dart`
- `lib/widgets/sync_status_banner.dart`
- `pubspec.lock`
- `pubspec.yaml`

### Partial pre-existing Phase 8 baseline work

- `android/.gitignore`
- `android/app/build.gradle.kts`
- `android/app/google-services.json`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/inventoryordtrack/MainActivity.kt` (deleted as part of package relocation)
- `android/app/src/main/kotlin/com/knzscent/admin/MainActivity.kt`
- `android/key.properties.example`
- `android/settings.gradle.kts`
- `lib/firebase_options.dart`

### Android and Firebase configuration

- `.firebaserc`
- `firebase.json`
- `firestore.indexes.json`
- `firestore.rules`

### Tests and validation

- `.fvmrc`
- `.github/dependabot.yml`
- `.github/workflows/ci.yml`
- `analysis_options.yaml`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradlew`
- `android/gradlew.bat`
- `functions/test/access_helpers.test.js`
- `functions/test/emulator/otp_endpoints.test.js`
- `functions/test/otp_delivery.test.js`
- `functions/test/otp_helpers.test.js`
- `functions/test/otp_policy.test.js`
- `functions/test/prepare_emulator.js`
- `rules-tests/.gitignore`
- `rules-tests/package-lock.json`
- `rules-tests/package.json`
- `rules-tests/test/firestore_rules.test.js`
- `test/core/app_bootstrap_test.dart`
- `test/database/database_initialization_test.dart`
- `test/database/identity_migration_test.dart`
- `test/database/phase3_migration_test.dart`
- `test/database/phase4_money_migration_test.dart`
- `test/database/phase5_migration_matrix_test.dart`
- `test/dialogs/utang_receipt_printer_test.dart`
- `test/dto/entity_dto_round_trip_test.dart`
- `test/fixtures/accounting_fixture.dart`
- `test/integration/auth_user_switching_test.dart`
- `test/models/debt_model_test.dart`
- `test/models/domain_invariants_test.dart`
- `test/models/order_state_machine_test.dart`
- `test/project_configuration_test.dart`
- `test/recycle_bin_contract_test.dart`
- `test/repositories/debt_payment_transaction_test.dart`
- `test/repositories/entity_outbox_test.dart`
- `test/repositories/order_transaction_test.dart`
- `test/repositories/product_repository_test.dart`
- `test/repositories/read_failure_test.dart`
- `test/repositories/sync_queue_test.dart`
- `test/screens/accounting_views_test.dart`
- `test/screens/forgot_password_screen_test.dart`
- `test/screens/receipt_screen_test.dart`
- `test/screens/register_screen_test.dart`
- `test/services/accounting_service_test.dart`
- `test/services/auth_service_test.dart`
- `test/services/cloud_auth_service_test.dart`
- `test/services/export_service_test.dart`
- `test/services/login_rate_limiter_test.dart`
- `test/services/otp_service_test.dart`
- `test/services/session_timeout_service_test.dart`
- `test/widgets/sync_status_banner_test.dart`
- `tool/check_coverage.dart`

### Documentation

- `AGENTS.md`
- `AUDIT_REPORT.md`
- `KNZ-Scent-Full-Verification-Report-v2.md`
- `ORCHESTRATED_IMPLEMENTATION_GUIDE.md`
- `PRIVACY.md`
- `RELEASE_CHECKLIST.md`
- `REMEDIATION_PLAN.md`
- `SECURITY.md`
- `docs/IDENTITY_MIGRATION_PLAN.md`
- `docs/SYNC_PLAN.md`
- `docs/progress/PHASE_0_COMPLETION.md`
- `docs/progress/PHASE_1_COMPLETION.md`
- `docs/progress/PHASE_2_COMPLETION.md`
- `docs/progress/PHASE_3_COMPLETION.md`
- `docs/progress/PHASE_4_COMPLETION.md`
- `docs/progress/PHASE_5_COMPLETION.md`
- `docs/progress/PHASE_6_COMPLETION.md`
- `docs/progress/PHASE_7_COMPLETION.md`

### Generated or temporary artifacts

- `-Recurse` (empty accidental file; owner may remove later, but it was not deleted during this gate)
- `android/app/google-services.old.json` (obsolete legacy-package backup candidate; not referenced by the project)
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugins.cmake`

### Sensitive files that must never be tracked

- No modified, deleted, or untracked path was identified as an actual service-account credential, private key, release keystore, `key.properties`, password file, or real environment-secret file.
- Sensitive and local ignored paths are inventoried separately below and must never be staged.

### Unrelated or uncertain

- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/Info.plist`
- `macos/Runner.xcodeproj/project.pbxproj`
- `macos/Runner/Configs/AppInfo.xcconfig`
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Info.plist`
- `macos/Runner/Release.entitlements`
- `opencode.json`
- `web/index.html`
- `web/manifest.json`

These platform and tool-configuration paths are outside the Android-only readiness gate. Their changes were preserved and require owner attribution before any staging decision.

## Accepted existing Phase 8 baseline

### Package identity

- `namespace` and `applicationId` are both `com.knzscent.admin`.
- `MainActivity.kt` declares `com.knzscent.admin` and the manifest launcher uses `.MainActivity`.
- The deletion of the old `com.example.inventoryordtrack` activity and the untracked branded activity form one internally consistent package relocation.

### Release signing configuration

- Release signing reads ignored `android/key.properties` or `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
- Release tasks fail when signing inputs are incomplete and do not fall back to the debug signing key.
- `android/key.properties` is absent and all four signing environment variables were reported MISSING without revealing values.
- Debug tasks do not require release-signing inputs. This was validated by the successful debug APK build with every release-signing environment variable missing.

### Crashlytics Gradle integration

- `com.google.firebase.crashlytics` version `3.0.7` is declared alongside Google Services in `android/settings.gradle.kts`.
- Both plugins are applied only when `android/app/google-services.json` contains the branded package.
- Flutter initializes Crashlytics as an optional startup capability and disables collection in debug mode.
- This is internally consistent for debug operation and production plugin wiring, but no controlled Crashlytics upload or symbolication evidence exists.

### Permission hardening

- Exact alarm, reboot scheduling, and scheduled notification receiver declarations were removed.
- Coarse location was removed; fine location is capped at Android 11 and earlier for legacy Bluetooth discovery.
- Bluetooth scan/connect, legacy Bluetooth, notification, vibration, and internet permissions remain.
- The manifest change is internally consistent with the intended printer path. Device grant/denial behavior and Bluetooth hardware remain unverified.

## Android and Firebase identifiers

- Firebase project: `knz-scent`
- Firebase plan: Spark
- Android namespace: `com.knzscent.admin`
- Android application ID: `com.knzscent.admin`
- Firebase Android App ID: `1:120139747390:android:823a15d9a89f4cfaf6816f`
- Test device: `TECNO LJ9`
- Device ID: `14451255BL109587`
- `firebase.json`, `lib/firebase_options.dart`, and the branded client in active `android/app/google-services.json` agree on project and App ID.
- The active Google Services file contains both the branded client and the old `com.example.inventoryordtrack` client. The branded client is present and is the one selected by the branded application package.
- The manifest launcher and branded `MainActivity` agree with the application namespace.

## Google Services backup review

- `android/app/google-services.old.json` targets project `knz-scent` but contains only the obsolete `com.example.inventoryordtrack` Android client.
- No project reference to `google-services.old.json` was found.
- No service-account or private-key marker was found in either Google Services client file.
- The file is an obsolete backup candidate, not an active build input. It was not deleted.
- Recommendation: after owner confirmation that rollback to the old package is unnecessary, move this backup outside the repository rather than staging it.

## Spark-plan architecture

- Production registration uses Firebase Authentication email/password account creation and Firebase email verification.
- After verification, the Flutter client commits `accountAccess/{uid}`, `users/{uid}`, and `_usernames/{normalizedUsername}` with one Firestore batch under reviewed rules.
- Administrator review uses one Firestore batch and is constrained by rules against self-review, role escalation, and non-Staff approval.
- The Flutter Spark registration path contains no call to production Cloud Functions registration endpoints.
- `npm --prefix functions run deploy:spark` targets only `firestore:rules,firestore:indexes`.
- `firestore.indexes.json` contains no `ttl: true` policy.
- OTP and callable Functions remain as emulator-compatible or optional future code, but they are not required by the production Spark registration path.
- No billing-required feature is part of the required production registration path. No Blaze upgrade is required or recommended by this gate.

## Administrator bootstrap review

- Owner command, only after prerequisites and explicit execution authorization: `npm --prefix functions run bootstrap:admin`
- The script runs locally with Firebase Admin SDK and does not deploy Cloud Functions.
- It requires an existing Firebase Authentication UID and refuses an account without an email or without `emailVerified: true`.
- It writes the expected Administrator access, profile, and normalized username reservation in one Firestore transaction.
- Expected records are `accountAccess/{uid}`, `users/{uid}`, and `_usernames/{normalizedUsername}`.
- Expected access fields are `role: Administrator`, `status: approved`, `active: true`, and `bootstrap: true`.
- It does not place Admin SDK credentials or privileged secrets in Flutter.

### Required bootstrap environment

- `GOOGLE_APPLICATION_CREDENTIALS`: MISSING
- `GOOGLE_CLOUD_PROJECT`: MISSING
- `BOOTSTRAP_ADMIN_UID`: MISSING
- `BOOTSTRAP_ADMIN_USERNAME`: MISSING
- `BOOTSTRAP_LEGACY_OWNER_KEY`: MISSING; optional and only set when intentionally migrating a legacy local owner key

### Bootstrap blockers

- The script relies on Application Default Credentials and does not explicitly require or assert `GOOGLE_CLOUD_PROJECT=knz-scent` before writes.
- It refuses an existing `accountAccess/{uid}` and a username held by another UID, but it does not read or refuse an existing `users/{uid}` document before using `transaction.set`. It therefore cannot be confirmed to prevent unsafe replacement of every existing account record.
- There is no owner-provided evidence that the bootstrap has completed successfully for the first Administrator.
- The bootstrap was not run because required variables are absent and no explicit execution authorization was provided for this session.

## Secret and credential review

- A filename and content-marker scan outside generated dependency/build directories found no service-account JSON, private-key block, service-account email marker, JKS, keystore, PEM, P12, PFX, or private-key file in the repository worktree.
- No tracked path matched release-keystore, `key.properties`, environment-secret, service-account JSON, or private-key filename patterns.
- `android/key.properties` and `android/app/key.properties` are absent.
- `.gitignore` excludes root environment files, build outputs, coverage, symbol/map outputs, and Android release outputs.
- `android/.gitignore` excludes `key.properties`, JKS files, and keystore files.
- `functions/.gitignore` excludes Functions environment files, local secret files, debug logs, and `node_modules`.
- Active `android/app/google-services.json` is Firebase Android client configuration, not a service-account private key. It still requires owner approval before staging.
- Secret values were not printed, copied, staged, or committed.

## Relevant ignored inventory

- Local/generated: `.dart_tool/`, `.flutter-plugins-dependencies`, IDE files, platform ephemeral directories, Gradle caches, `build/`, and `coverage/`.
- Local Android: `android/local.properties`, generated Java plugin registration, and Android IDE metadata.
- Local Functions: `functions/node_modules/`, `functions/firestore-debug.log`, `functions/.env.demo-knz-scent`, and `functions/.secret.local`.
- Local rules tests: `rules-tests/node_modules/`.
- The two ignored Functions environment files are emulator-generated placeholders. Their filenames must remain ignored and must never be staged even when real local values replace placeholders.

## Data-safety review

- No Firebase, Firestore, SQLite, product, order, debt, customer, reseller, payment, or accounting data was deleted, reset, or replaced.
- No app storage was cleared and the application was not uninstalled.
- No production bootstrap, Cloud Functions deployment, Firestore deployment, or production integration test was run.
- Automated repository tests may create isolated temporary databases and Firebase emulator data only; they must not target production data.
- Existing business collections and local records are not reset by the readiness commands.

## Baseline preservation recommendation

### Option 1: reviewed baseline commit

Recommended after the owner reviews the exact set: stage the union of all paths listed under Completed pre-Phase-8 work, Partial pre-existing Phase 8 baseline work, Android and Firebase configuration, Tests and validation, and Documentation, plus:

- `docs/progress/PRE_PHASE_8_BASELINE.md`
- `docs/progress/PHASE_8_MANUAL_SMOKE_TESTS.md`

The union is the exact proposed baseline file set; no generated/temporary or unrelated/uncertain path is included. Before approval, the owner should separately confirm the active Firebase client configuration, Gradle wrapper binary provenance, and governance-document provenance.

Suggested commit message: `chore: preserve reviewed pre-phase-8 baseline`

No `git add` or `git commit` command was run.

### Option 2: no-commit preservation

- Preserve this report, a fresh `git status --short --untracked-files=all`, `git diff --stat`, and `git diff --name-status` as the documented inventory.
- If the owner later authorizes it, create a patch outside the repository that excludes untracked secrets, backups, generated output, and local caches.
- No patch or backup was created or overwritten during this gate.
- Limitation: an inventory or patch is less attributable than a commit, does not preserve untracked files automatically, can omit binary files, and does not provide an immutable Git parent for continued Phase 8 work.

## Staging classification

### Safe to stage after final owner review

- The exact paths in Completed pre-Phase-8 work.
- The exact paths in Android and Firebase configuration.
- The exact source and text paths in Tests and validation.
- `docs/IDENTITY_MIGRATION_PLAN.md`, `docs/SYNC_PLAN.md`, all `docs/progress/*.md` reports, and the two readiness documents.

### Require explicit owner review before staging

- Every exact path in Partial pre-existing Phase 8 baseline work because these changes begin Phase 8 behavior.
- `android/app/google-services.json` in particular, because it is owner-generated Firebase client configuration.
- `android/gradle/wrapper/gradle-wrapper.jar`, because it is a binary reproducibility dependency.
- Root governance and policy documents: `AGENTS.md`, `AUDIT_REPORT.md`, `KNZ-Scent-Full-Verification-Report-v2.md`, `ORCHESTRATED_IMPLEMENTATION_GUIDE.md`, `PRIVACY.md`, `RELEASE_CHECKLIST.md`, `REMEDIATION_PLAN.md`, and `SECURITY.md`.
- Every exact path in Unrelated or uncertain.

### Must never be staged

- `android/key.properties`
- Any JKS, keystore, service-account credential, private key, password, real `.env` file, or local secret file
- `functions/.env.demo-knz-scent` and `functions/.secret.local`
- Build outputs, coverage, caches, dependency directories, debug logs, and platform ephemeral output
- `android/app/google-services.old.json`

### Uncertain owner decisions

- Decide whether to remove the empty `-Recurse` file later.
- Decide whether to move `android/app/google-services.old.json` outside the repository.
- Attribute or exclude all iOS, macOS, web, Windows, and `opencode.json` changes.
- Confirm the active Firebase client file is intended for source control.
- Verify the Gradle wrapper JAR provenance before approving it.

## Readiness evidence status

- Automated validation: focused host, emulator, and debug-build checks completed as recorded below.
- Administrator bootstrap: BLOCKED and unverified.
- Administrator device tests: NOT RUN; owner evidence required.
- Staff lifecycle: NOT RUN; owner evidence required.
- Product, order, debt, persistence, offline, synchronization, and Bluetooth tests: NOT RUN; owner evidence required.
- Current gate consequence: NOT READY FOR PHASE 8 until all required evidence and blockers are resolved.

## Automated validation commands

- `flutter clean`
- `flutter --version`
- `dart --version`
- `java -version`
- `node --version`
- `npm --version`
- `firebase --version`
- `flutter pub get`
- `npm ci` in `functions/`
- `npm ci` in `rules-tests/`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `npm run lint` in `functions/`
- `npm test` in `functions/`
- `npm audit --omit=dev --audit-level=high` in `functions/`
- `npm audit --audit-level=high` in `rules-tests/`
- `flutter test test/project_configuration_test.dart test/services/cloud_auth_service_test.dart test/services/auth_service_test.dart test/integration/auth_user_switching_test.dart test/screens/register_screen_test.dart test/screens/forgot_password_screen_test.dart`
- `flutter test test/models/domain_invariants_test.dart test/models/order_state_machine_test.dart test/models/debt_model_test.dart test/repositories/product_repository_test.dart test/repositories/order_transaction_test.dart test/repositories/debt_payment_transaction_test.dart test/repositories/entity_outbox_test.dart`
- `flutter test test/core/app_bootstrap_test.dart test/database/database_initialization_test.dart test/database/identity_migration_test.dart test/database/phase3_migration_test.dart test/database/phase4_money_migration_test.dart test/database/phase5_migration_matrix_test.dart test/dto/entity_dto_round_trip_test.dart`
- `flutter test test/repositories/sync_queue_test.dart test/repositories/read_failure_test.dart test/widgets/sync_status_banner_test.dart`
- `npm exec --yes --package=node@20 -- node --version` in `functions/`
- `npm exec --yes --package=firebase-tools@14.27.0 -- firebase --version` in `functions/`
- `npm exec --yes --package=node@20 -- node --test test/access_helpers.test.js test/otp_delivery.test.js test/otp_helpers.test.js test/otp_policy.test.js` in `functions/`
- `npm exec --yes --package=node@20 --package=firebase-tools@14.27.0 -- npm run test:emulator` in `functions/`
- `flutter build apk --debug`
- `flutter devices`
- `git diff --check`

## Automated validation results

- PASS: `flutter clean` removed generated build/tool output only. It did not clear application storage or business data.
- PASS: `flutter pub get` restored locked dependencies; 74 packages have newer versions incompatible with current constraints. No dependency was upgraded.
- TOOLCHAIN DRIFT: the shell has Flutter 3.41.2/Dart 3.11.0, Node 24.18.0/npm 11.16.0, Java 17.0.19, and global Firebase CLI 15.12.0. The repository/CI pin remains Flutter 3.38.4, Node 20, Java 17, and Firebase CLI 14.27.0.
- PASS: formatting checked 120 files with 0 changes.
- PASS WITH INFO: `flutter analyze` completed with 0 errors, 0 warnings, and 26 informational lints.
- PASS: Functions syntax/lint completed.
- PASS: all 17 Functions unit tests passed under both the local shell and pinned Node 20.20.2.
- PASS: 35 focused authentication, registration, session, configuration, and screen tests passed.
- PASS: 47 focused product, order, stock, debt, payment, invariant, and outbox tests passed. Expected negative-path exception logs were emitted.
- PASS: 36 focused startup, database initialization, persistence, migration, and DTO round-trip tests passed. Expected rollback-fixture errors were emitted.
- PASS: 9 focused durable outbox, reconnection, persistence, read-failure, and sync-status tests passed. Expected negative-path error logs were emitted.
- PASS: all 10 Functions emulator endpoint tests passed against demo project `demo-knz-scent`.
- PASS: all 23 Firestore Rules emulator tests passed against demo project `demo-knz-scent`, including unauthenticated, anonymous, cross-UID, verification, pending, approval, self-approval, role escalation, private-collection, order transition, and tombstone cases.
- PASS: the combined emulator command exited code 0 under Node 20.20.2, Java 17.0.19, and Firebase CLI 14.27.0. It did not access or deploy to production.
- PASS WITH WARNINGS: `flutter build apk --debug` produced `build/app/outputs/flutter-apk/app-debug.apk` without release-signing inputs. Gradle reported obsolete Java 8 source/target warnings and Kotlin incremental-cache daemon exceptions before falling back and completing the build.
- PASS: `flutter devices` detected TECNO LJ9 at device ID `14451255BL109587`, Android 15/API 35, plus three host/web devices. Detection is not evidence that the app launched or passed manual tests.
- PASS WITH WARNING: Functions production dependency audit found 0 high/critical and 9 moderate `uuid`-chain vulnerabilities. The forced remediation requires breaking Firebase Admin/Functions upgrades.
- FAIL, PRE-EXISTING TEST-TOOL RISK: rules-test dependency audit found 1 high and 9 moderate `undici`-chain vulnerabilities. The available forced remediation upgrades the test Firebase JS major and was not performed.
- WARNING: local `npm ci` ran under Node 24 and reported the package engine requirement of Node 20; pinned Node 20 unit and emulator runs passed.
- WARNING: Firebase CLI 14.27.0 reported its future Java 21 requirement for CLI 15, and Functions emulator reported the existing Functions dependency major as outdated. No upgrade was performed.
- PASS: final `git diff --check` found no whitespace errors; Git emitted existing Windows line-ending notices only.

## Physical-device gate continuation

This section supersedes the earlier bootstrap and evidence statuses where they differ.

- Bootstrap safety was remediated with an exact `knz-scent` project guard, verified/enabled Auth checks, three-record collision checks, atomic creates, and safe idempotency.
- All 11 focused bootstrap tests passed under Node 20.
- The authorized production bootstrap returned `Administrator already bootstrapped.`
- Read-only verification confirmed the Auth identity and all three expected Administrator records are valid and consistent.
- TECNO LJ9 remained connected on Android 15/API 35; the debug APK was installed without uninstalling or clearing data and the branded activity launched.
- ADB confirmed the package, running process, visible/resumed branded activity, and no process-scoped fatal Flutter, AndroidRuntime, Firebase, or SQLite error.
- Owner evidence confirms Administrator dashboard access, registration review, logout protection, repeat login, and session restoration.
- Owner evidence confirms the dedicated Staff verification, pending restriction, approval, approved login, and absence of Administrator controls.
- Owner evidence confirms dedicated product creation, editing, persistence after refresh, and negative-quantity prevention.
- Physical order, debt/payment, complete business restart, offline/reconnection, and Bluetooth evidence remains incomplete.

### Post-baseline files

- Safe readiness remediation: `functions/scripts/bootstrap_admin.js`, `functions/scripts/verify_bootstrap_admin.js`, `functions/test/bootstrap_admin.test.js`, and `functions/package.json`.
- Readiness documentation: `docs/progress/PRE_PHASE_8_BASELINE.md`, `docs/progress/PHASE_8_MANUAL_SMOKE_TESTS.md`, `docs/progress/PRE_PHASE_8_REMEDIATION.md`, and `docs/progress/FINAL_PRE_PHASE_8_READINESS.md`.
- Local-only workaround that must never be staged: `.dart_tool/hooks_runner/shared/sqlite3/build/download-858141a2/sqlite3.dll` and all generated `build/` or `coverage/` output.
- No Android application source changed during the continuation.

### Final automated continuation results

- Formatting: 120 files checked, 0 changes.
- Analyzer: 0 errors, 0 warnings, 26 informational lints.
- Flutter: 154 tests passed; line coverage 54.96%.
- Functions: 28 unit tests passed under Node 20, including the 11 bootstrap tests.
- Emulator: 10 Functions endpoint tests and 23 Firestore Rules tests passed against `demo-knz-scent`.
- Android: debug APK built and TECNO LJ9 remained detected.
- Audit: Functions production packages have 9 moderate findings and no high/critical finding; Rules-test tooling has 1 high and 9 moderate development-only findings.
- Environment limitation: Windows Application Control blocked the unsigned generated SQLite DLL. Tests passed after replacing only the ignored generated native-asset cache with Microsoft-signed `winsqlite3.dll`; this workaround is not repository content.
