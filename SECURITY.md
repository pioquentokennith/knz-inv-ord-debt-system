# Security Policy

## Supported version

Security fixes currently target the latest revision of `main`. No published binary is considered supported until the Android release checklist is complete.

## Reporting a vulnerability

Do not publish credentials, customer records, exploit details, or screenshots containing personal data in a public issue. Contact the repository owner through a private project channel and include:

- the affected revision and platform;
- reproduction steps and impact;
- logs with tokens, emails, names, and identifiers removed; and
- any proposed mitigation.

The project owner must publish a dedicated security contact before public distribution.

## Secret handling

- Brevo and OTP signing secrets belong in Google Cloud Secret Manager.
- Android keystores and `key.properties` must remain outside version control.
- CI credentials must use encrypted repository/environment secrets with least privilege.
- Firebase client configuration identifies a Firebase app but must still match the final package ID.
- Never bundle provider API keys in Flutter assets, source code, logs, or crash reports.

If a secret is committed or exposed, revoke and rotate it immediately; deleting it from the latest commit is not sufficient.

## Release expectations

Before release, run the automated checks, review Firestore rules using the Emulator Suite, verify App Check and Anonymous Authentication configuration, test Crashlytics with a controlled non-production crash, and complete the checks in `RELEASE_CHECKLIST.md`.
