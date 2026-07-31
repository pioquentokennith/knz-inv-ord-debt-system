# Privacy Disclosure Template

Last reviewed: 2026-07-17

This document is a release-preparation template, not legal advice. The app operator must add an effective date, legal entity, jurisdiction, retention schedule, and privacy contact before publishing the app or linking this text from an app store listing.

## Data the app can process

Depending on operator use, KNZ Scent Admin can process:

- administrator account names, usernames, and email addresses;
- customer and reseller names and contact details;
- products, orders, payments, debts, receipts, and accounting records;
- product images selected from the camera or photo library;
- activity and synchronization records; and
- diagnostic information sent to Firebase Crashlytics in production builds.

## Where data is processed

Operational records are stored locally in SQLite and may synchronize to Google Firebase services configured by the operator. OTP delivery sends the recipient email address and a short-lived verification code to Brevo through a protected Firebase Cloud Function. Firebase and Brevo process data under their own terms and the operator's service agreements.

## Device permissions

- **Bluetooth and location-related Android permissions:** discover and connect to supported receipt printers. Location is not used for behavioral tracking.
- **Camera and photo library:** attach product images selected by the administrator.
- **Notifications:** show low-stock and overdue-debt reminders on the device.
- **Internet:** authenticate, synchronize records, send OTP requests, and report production crashes.

The app does not need exact-alarm or reboot scheduling permission for its current notification behavior.

## Retention and deletion

The current codebase includes soft deletion and recycle-bin behavior for some business records, but this is not a complete legal retention or erasure policy. Before release, the operator must define retention periods, backup deletion behavior, administrator-access controls, and a process for data access/correction/deletion requests.

## Security and sharing

Access should be limited to authorized administrators. Data is shared only with configured infrastructure providers as needed to operate the service, unless the operator is legally required to disclose it. No claim is made that this project is compliant with a specific privacy regime until the operator completes a legal and operational review.

## Contact

Privacy contact: **must be supplied before release**.
