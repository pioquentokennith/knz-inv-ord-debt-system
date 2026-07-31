# Phase 0 Completion Report

## Implemented
- Recorded baseline branch `main` and commit `c4f6284e018d00fd2f8b0b9d2b5e1c944e5b770b`.
- Recorded installed tools: Flutter `3.41.2`, Dart `3.11.0`, Node `24.18.0`, npm `11.16.0`, and Firebase CLI `15.12.0`.
- Confirmed `java` is unavailable on `PATH`; Flutter uses Android Studio OpenJDK `21.0.9` from `E:\Andriod Studio\jbr\bin\java`.
- Confirmed the project requirement is Flutter `>=3.38.4` and Java 17. Flutter satisfies the minimum, but the local Java installation does not match Java 17. CI uses Flutter `3.38.4`, Dart bundled with that SDK, Java 17, and Node 20.
- Confirmed `pubspec.yaml` and `pubspec.lock` both constrain Dart to `>=3.10.3 <4.0.0` and Flutter to `>=3.38.4`.
- Added an FVM SDK pin for Flutter `3.38.4`, matching CI.
- Generated the missing Functions lockfile and changed CI to use `npm ci --ignore-scripts`.
- Made the existing Gradle wrapper scripts and JAR visible to Git so clean checkouts can bootstrap Android builds.
- Added configuration tests for the Flutter pin, locked Functions install, and Gradle wrapper availability.
- Inventoried Firebase, Functions, Firestore, tests, CI, Android signing, and SQLite schema/migration state.
- No authentication, OTP, synchronization, accounting, database behavior, dependency-major, or UI changes were made.

## Files changed
- `.fvmrc`
- `.github/workflows/ci.yml`
- `android/.gitignore`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradlew`
- `android/gradlew.bat`
- `functions/package-lock.json`
- `test/project_configuration_test.dart`
- `docs/progress/PHASE_0_COMPLETION.md`

## Database or API contract changes
- No database schema, migration, runtime API, Firebase API, or business-data contract was changed.
- The current SQLite database is `knz_scent.db`, version 8.
- The current upgrade routine converges older databases rather than using explicit `oldVersion` blocks.
- The identified migration history is v1 to v2 user email/sync fields, v2 to v3 sync queue, v3 to v4 soft-delete fields, v4 to v5 indexes, v5 to v6 payment/reseller/order-type/debt-interest fields plus reseller and custom-order tables, v6 to v7 order-item SRP, and v7 to v8 durable outbox metadata plus unique per-user order IDs.
- No migration fixture tests exist for versions 1 through 8. The original v1 fixture is not preserved.
- Fresh v8 creates `sync_queue.updated_at` as `NOT NULL`; upgrades add it nullable and backfill values, leaving a schema-constraint drift risk.
- Upgrade verification checks selected columns and one unique index, not complete types, nullability, defaults, foreign keys, or all indexes.

## Tests added or updated
- Added three reproducibility tests to `test/project_configuration_test.dart`.
- Flutter suite result: 35 tests passed.
- Functions suite result: 8 tests passed and 1 failed. The existing legacy SHA-256 fixture in `functions/test/auth_helpers.test.js:40` does not match SHA-256 for `password`; this was not changed because authentication is outside Phase 0.
- No migration, Firestore Emulator rules, widget, integration, restore, or device tests currently exist.

## Commands run
- `git status --short --branch`
- `git branch --show-current`
- `git rev-parse HEAD`
- `flutter --version`
- `dart --version`
- `java -version`
- `node --version`
- `npm --version`
- `firebase --version`
- `flutter doctor -v`
- `flutter pub get`
- `flutter pub outdated`
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- `flutter test --coverage`
- `npm install --package-lock-only --ignore-scripts`
- `npm ci --ignore-scripts`
- `npm run lint`
- `npm test`
- `npm audit --omit=dev --audit-level=high`
- `flutter test test/project_configuration_test.dart`
- `.\gradlew.bat --version`
- `flutter build apk --debug --no-pub`

## Validation results
- PASS: The project opens and commands execute from `E:\flutter_test_projects\inventoryordtrack`.
- PASS: `flutter pub get` resolved the existing lockfile without a major dependency upgrade.
- PASS: `flutter pub outdated` completed; 27 packages are lockfile-upgradable and 32 are constrained below currently resolvable releases. No upgrades were applied.
- FAIL: `dart format --output=none --set-exit-if-changed lib test` found 69 files requiring formatting and could not parse `lib/screens/analytics_screen.dart` at lines 781 and 861.
- FAIL: `flutter analyze` reported 14 issues: 9 info diagnostics and 5 errors in `lib/screens/analytics_screen.dart` and `lib/screens/main_shell.dart`.
- PASS: `flutter test --coverage` passed all 35 tests after the Phase 0 changes.
- PASS: `flutter test test/project_configuration_test.dart` passed all 7 focused tests.
- PASS: `npm ci --ignore-scripts` installed 239 packages from `functions/package-lock.json`; it warned that local Node 24 does not match the required Node 20.
- PASS: `npm run lint` completed with no syntax errors.
- FAIL: `npm test` passed 8 of 9 tests; the legacy SHA-256 migration fixture failed.
- PASS: `npm audit --omit=dev --audit-level=high` returned success at the high-severity threshold, while reporting 9 moderate `uuid`-chain vulnerabilities whose automated fix requires breaking Firebase dependency upgrades.
- FAIL: `.\gradlew.bat --version` could not run because `JAVA_HOME` is unset and `java` is absent from `PATH`.
- FAIL: `flutter build apk --debug --no-pub` failed after 284.6 seconds on the existing Dart compilation errors in analytics and main-shell screens.
- FAIL: The worktree remains heavily dirty because pre-existing work was not committed or stashed without owner approval.
- Phase 0 acceptance is therefore not fully demonstrated and must not be considered complete.

## Product decisions made
- No product behavior decision was implemented in Phase 0.
- Reporting basis remains unresolved; the guide recommends cash basis.
- Reseller total remains unresolved; the guide recommends discounted `customerPayAmount` as the actual total, with SRP as reference only.
- Release scope remains unresolved; the guide recommends Android-only, local-first, primarily single-device operation with reliable outbox and restore semantics.

## Owner-only actions still required
- Commit or stash the pre-existing work separately, then rerun Phase 0 from a clean worktree. No existing work was committed, stashed, reset, deleted, or overwritten in this phase.
- Install/configure Java 17 and expose it through `JAVA_HOME` and `PATH`, or explicitly approve a documented supported Java 21 toolchain instead.
- Use Node 20 for local Functions validation to match `functions/package.json`, `firebase.json`, and CI.
- Register Firebase Android application ID `com.knzscent.admin` and regenerate `android/app/google-services.json`; the current file targets `com.example.inventoryordtrack`.
- Supply release keystore credentials through `android/key.properties` or the documented environment variables when release validation is authorized.
- Explicitly approve or override the guide's recommended reporting basis, reseller total, and release scope before their implementation phases.

## Remaining risks
- Phase 0 blocker: the dirty worktree prevents a clean baseline and makes attribution of pre-existing uncommitted work dependent on the owner.
- Phase 0 blocker: local Java and Node versions do not match the Java 17 and Node 20 reproducibility contracts.
- Phase 1 issue: startup/offline behavior and OTP backend capability remain unvalidated and unchanged.
- Phase 2 issue: the failing legacy verifier fixture and Firebase UID authorization architecture require authentication-phase review.
- Phase 3 issue: migrations lack fixtures; v8 upgrade constraints can drift; duplicate order IDs block the unique-index migration; no Firestore Emulator rules tests exist.
- Phase 4 issue: existing SQLite money fields use `REAL`; no conversion was attempted in Phase 0.
- Phase 6 issue: reporting-basis and reseller-total decisions remain unresolved.
- Phase 7 issue: formatting, analysis, Functions tests, Android debug build, migration tests, emulator tests, integration tests, and device tests are not green.
- Phase 7 issue: Functions dependencies report 9 moderate vulnerabilities; resolving them requires controlled major Firebase upgrades after safety tests exist.
- Phase 8 issue: Android Firebase package configuration does not match the branded application ID, and release signing credentials are absent.
- CI currently uses movable `ubuntu-latest` and action major tags; this is a lower-priority reproducibility risk.

## Recommended next phase
- First obtain owner approval to isolate the existing worktree, configure Java 17 and Node 20, and resolve the Phase 0 validation blockers. After Phase 0 is rerun successfully, proceed to Phase 1 only when explicitly requested.
