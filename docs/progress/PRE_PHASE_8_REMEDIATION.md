# Pre-Phase 8 Remediation

## Implemented

- Required `GOOGLE_CLOUD_PROJECT=knz-scent` before Admin SDK initialization.
- Initialized Firebase Admin explicitly for `knz-scent`.
- Required an existing, verified, enabled Firebase Authentication account.
- Read `accountAccess/{uid}`, `users/{uid}`, and `_usernames/{username}` in one transaction.
- Refused username collisions, existing user collisions, partial records, and inconsistent records with document paths only.
- Created all three records atomically with `create` operations when all were absent.
- Returned `already bootstrapped` without writes when all records already matched.
- Added read-only Administrator Auth/Firestore verification tooling.

## Files changed

- `functions/scripts/bootstrap_admin.js`
- `functions/scripts/verify_bootstrap_admin.js`
- `functions/test/bootstrap_admin.test.js`
- `functions/package.json`

## Bootstrap evidence

- 11/11 focused bootstrap tests passed under Node 20.
- Preflight: project matched, Auth UID existed, email was verified, and account was enabled.
- Authorized command: `npm --prefix functions run bootstrap:admin`.
- Result: `Administrator already bootstrapped.`
- Read-only result: project matched, Auth identity was eligible, and all Administrator records were valid.

## Device evidence

- Device: TECNO LJ9, Android 15/API 35, ID `14451255BL109587`.
- Package: `com.knzscent.admin` installed and launched without uninstalling or clearing data.
- ADB showed `.MainActivity` visible/resumed and no process-scoped fatal error.
- Administrator login, authorization, logout, logged-out protection, repeat login, and session restoration passed by owner report.
- Core Staff registration, verification, pending restriction, Administrator approval, approved login, and role restriction passed by owner report and read-only verification.
- Dedicated product create/edit/refresh and negative-quantity prevention passed by owner report.

## Automated validation

- Flutter: 154/154 passed; 54.96% line coverage.
- Functions: 28/28 passed under Node 20.
- Functions emulator: 10/10 passed.
- Firestore Rules emulator: 23/23 passed.
- Analyzer: no errors or warnings; 26 informational lints.
- Debug APK: PASS.

## Environment remediation

Windows Application Control blocked the unsigned generated SQLite native asset after `flutter clean`. A Microsoft-signed system SQLite DLL was substituted only in the ignored `.dart_tool` native-asset cache, after which all SQLite-backed tests passed. No repository source, production SQLite database, or application data was changed by this workaround.

## Remaining blockers

- Physical order total, exact-once stock deduction, refresh/reconnection, and insufficient-stock behavior.
- Physical debt partial payment, balance, overpayment, reports, and persistence.
- Full physical restart persistence and duplicate checks.
- Physical offline/reconnection synchronization and cross-account local privacy.
- Rejected/suspended message observation on dedicated physical accounts.
- Bluetooth receipt and unavailable-printer behavior, or explicit owner-approved deferral.
- Owner-approved attributable baseline preservation.

## Data safety

- No real business record was deleted, reset, or overwritten.
- No app storage was cleared and the app was not uninstalled.
- No Firebase resource or Cloud Function was deployed.
- No secret, key, credential content, or password was printed, staged, or committed.
