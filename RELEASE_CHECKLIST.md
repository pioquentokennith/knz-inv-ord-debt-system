# Android Release Checklist

The supported release target is Android. Do not publish iOS, macOS, web, Windows, or Linux builds until their Firebase registrations and platform-specific test plans are complete.

## 1. Source and version

- [ ] Work from a reviewed, clean commit on the intended release branch.
- [ ] Update `version` in `pubspec.yaml`; ensure both semantic version and build number are new.
- [ ] Confirm Flutter `>=3.38.4` and Java 17 are installed.
- [ ] Review dependency updates with `flutter pub outdated`; commit the intended lockfile.
- [ ] Generate and commit `functions/package-lock.json`, then use `npm ci` for reproducible backend builds.

## 2. Firebase and backend

- [ ] Register Android package `com.knzscent.admin` in the production Firebase project.
- [ ] Run `flutterfire configure --project=knz-scent --platforms=android`.
- [ ] Confirm `google-services.json` and generated Firebase options refer to the same new Firebase app.
- [ ] Enable Anonymous Authentication, Firestore, Functions, and Crashlytics.
- [ ] Configure `BREVO_API_KEY` and `OTP_SECURITY_SECRET` with `firebase functions:secrets:set`.
- [ ] Configure the sender email parameter and verify that Brevo authorizes the sender/domain.
- [ ] Test rules and OTP functions with the Firebase Emulator Suite.
- [ ] Deploy reviewed Functions, Firestore rules, and indexes.
- [ ] Turn on App Check enforcement only after verified client tokens are available.

## 3. Android signing

Create a dedicated upload keystore and keep it outside Git. Copy `android/key.properties.example` to the ignored `android/key.properties`, or provide these CI environment variables:

- `ANDROID_KEYSTORE_PATH`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The Gradle build intentionally fails release tasks when these values or the keystore file are missing. It never falls back to the debug key.

## 4. Quality gates

- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `flutter analyze`
- [ ] `flutter test --coverage`
- [ ] `npm run lint` and `npm test` in `functions/`
- [ ] `npm audit --omit=dev --audit-level=high` in `functions/`
- [ ] `flutter build appbundle --release`
- [ ] Verify the AAB is signed by the intended upload certificate.
- [ ] Force one controlled Crashlytics test failure in a non-production test build and confirm symbolicated reporting.

## 5. Device acceptance

- [ ] Fresh install and upgrade from the previous database schema/version.
- [ ] Registration, login, OTP resend/expiry, password reset, logout, and lockout.
- [ ] Offline CRUD, app restart, reconnection, sync retries, and conflict behavior.
- [ ] Order, reseller, debt, partial-payment, accounting, and export totals.
- [ ] Camera/gallery denial and grant flows.
- [ ] Android notification denial and grant flows.
- [ ] Bluetooth denial, scan, connect, disconnect, and receipt printing on supported hardware.
- [ ] Low-memory/background/resume behavior and a representative range of Android API levels.

## 6. Store and operations

- [ ] Replace all remaining placeholder metadata and provide screenshots and support contact.
- [ ] Complete the Play Data safety form and publish an operator-approved privacy policy.
- [ ] Confirm requested permissions match current behavior; exact-alarm and boot permissions must remain absent unless the product changes.
- [ ] Confirm backup, retention, incident-response, and account/data-deletion procedures.
- [ ] Preserve mapping/symbol files and the signed artifact for the release record.
- [ ] Use staged rollout, monitor Crashlytics/sync/OTP delivery, and document rollback criteria.
