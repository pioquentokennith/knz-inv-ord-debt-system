# Phase 8 Manual Smoke Tests

## Evidence policy

- Target device: `TECNO LJ9`
- Device ID: `14451255BL109587`
- Every item starts as `NOT RUN` and must be changed only from owner-provided evidence.
- Allowed final statuses are `PASS`, `FAIL`, or `BLOCKED`.
- Never clear app storage, uninstall the app, reset a database, or delete/replace production business data for this checklist.
- Use only dedicated test records and accounts, including `PHASE8-TEST-PRODUCT`, `PHASE8-TEST-ORDER`, `PHASE8-TEST-DEBT`, and `PHASE8-TEST-STAFF`.
- Cleanup may affect only dedicated Phase 8 test data and must be recorded. Do not clean up evidence before persistence and synchronization checks finish.
- Redact credentials, tokens, API keys, private keys, passwords, and unrelated personal data from screenshots and logs.

## Run metadata

Record these fields for each test session. If a test uses different account or role data, record the difference in its Actual result cell.

| Field | Owner evidence |
| --- | --- |
| Date and time with time zone | 2026-07-30; exact time zone not provided |
| Device model | TECNO LJ9 |
| Device ID | 14451255BL109587 |
| Android version | Android 15 / API 35 |
| App version/build | Debug APK, version 1.0.0+1 |
| Account email or anonymized identifier | Administrator UID ending `iwA3`; Staff UID ending `MG2` |
| Role tested | Administrator and Staff |
| Network state | Online for completed authentication and product tests |
| Screenshot/log bundle reference | Owner-provided Firebase verification screenshot; ADB process/fatal-log checks in gate transcript |

## Administrator tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ADM-01 | Log in with the bootstrapped Administrator | Administrator; UID ending `iwA3` | Login succeeds with no false-success message | Owner entered credentials on the phone and the dashboard opened | PASS | Owner report; fatal-log scan clean | None |
| ADM-02 | Open the dashboard or authorized interface | Administrator | Authorized interface opens | Administrator dashboard opened | PASS | Owner report and ADB foreground activity | None |
| ADM-03 | Open registration review | Administrator | Registration-review screen is available | Screen opened with review controls | PASS | Owner report | None |
| ADM-04 | Log out | Administrator | Session ends and protected UI closes | Login screen appeared; reopening while logged out still showed login | PASS | Owner report | None |
| ADM-05 | Log in, close the app, and restart it | Administrator | Valid Administrator session restores correctly | Dashboard restored after normal close and reopen without re-entering credentials | PASS | Owner report; process fatal-log scan clean | None |
| ADM-06 | Review permitted pending Staff account | Administrator; `PHASE8-TEST-STAFF` target | Administrator can approve or reject only a permitted account and cannot self-review | Dedicated pending Staff request was visible and approved; self-review denial is emulator-tested | PASS | Owner report plus Firestore Rules tests | Dedicated account retained for gate testing |

## Staff lifecycle

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| STF-01 | Register a new dedicated Staff account named `PHASE8-TEST-STAFF` | Staff UID ending `MG2` | Firebase Authentication account is created without affecting existing accounts | Dedicated Auth account created | PASS | Owner report and read-only Admin SDK lookup | Dedicated account retained |
| STF-02 | Receive the Firebase verification email | New Staff test identity | Firebase verification email is received | Verification message was found and opened | PASS | Owner report | None |
| STF-03 | Open the Firebase verification link | New Staff test identity | Firebase reports the email verified | Firebase page displayed `Your email has been verified`; Admin SDK returned `EMAIL_VERIFIED=YES` | PASS | Owner screenshot and read-only Admin SDK | None |
| STF-04 | Complete registration before approval | Pending Staff | Account remains pending and inactive | Staff login displayed pending Administrator approval | PASS | Owner report | None |
| STF-05 | Attempt protected access before approval | Pending Staff | Protected application features remain inaccessible | Pending message shown; no dashboard access | PASS | Owner report | None |
| STF-06 | Review and approve the pending account | Administrator and pending Staff | Administrator sees and approves the dedicated request | Administrator approved the dedicated request | PASS | Owner report | None |
| STF-07 | Log in after approval | Approved Staff | Approved Staff login succeeds | Staff account opened successfully | PASS | Owner report | None |
| STF-08 | Attempt Administrator feature access | Approved Staff | Administrator features remain inaccessible | Owner confirmed no Administrator controls are visible | PASS | Owner report | None |
| STF-09 | Attempt account review or self-approval | Staff or pending Staff | Staff cannot approve themselves or any other account | No review controls are exposed; direct Staff/self-review writes are denied by emulator tests | PASS | Owner report plus Functions/Rules emulator tests | None |
| STF-10 | Test rejected status with a dedicated test identity | Rejected Staff test identity | Correct rejected message appears and protected access is denied | Not exercised on a physical dedicated account; automated status and rules tests pass | BLOCKED | Automated evidence only | None |
| STF-11 | Test suspended status with a dedicated test identity | Suspended Staff test identity | Correct suspended message appears and protected access is denied | Not exercised on a physical dedicated account; automated status and rules tests pass | BLOCKED | Automated evidence only | None |

## Product tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRD-01 | Create `PHASE8-TEST-PRODUCT` | Approved Staff | Dedicated product is created once | Created with price 100 and quantity 10; appeared correctly | PASS | Owner report | Dedicated product retained |
| PRD-02 | Edit `PHASE8-TEST-PRODUCT` | Approved Staff | Edited fields persist with no false-success message | Description changed; price 125 and quantity 12 persisted after refresh | PASS | Owner report | None |
| PRD-03 | Change dedicated product quantity and price | Approved Staff | Quantity and integer-centavo price changes are exact | Final price 125 and quantity 12; UI prevented quantity -1 and retained 12 | PASS | Owner report plus product automated tests | None |

## Order and stock tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ORD-01 | Create `PHASE8-TEST-ORDER` using the dedicated product | Approved authorized role | Test order is created once | NOT RUN | NOT RUN | NOT PROVIDED | Record dedicated order cleanup only |
| ORD-02 | Compare stock before and after `PHASE8-TEST-ORDER` | Approved authorized role | Ordered quantity is deducted exactly once | NOT RUN | NOT RUN | NOT PROVIDED | None |
| ORD-03 | Retry/reopen the order flow without creating another order | Approved authorized role | Stock is not deducted a second time | NOT RUN | NOT RUN | NOT PROVIDED | None |
| ORD-04 | Attempt an order exceeding available dedicated stock | Approved authorized role | Negative stock is prevented and no partial order is stored | NOT RUN | NOT RUN | NOT PROVIDED | None |

## Debt and payment tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DBT-01 | Create `PHASE8-TEST-DEBT` | Approved authorized role | Dedicated debt is created with exact amount and status | NOT RUN | NOT RUN | NOT PROVIDED | Record dedicated debt cleanup only |
| DBT-02 | Record a partial payment on `PHASE8-TEST-DEBT` | Approved authorized role | Partial payment commits once | NOT RUN | NOT RUN | NOT PROVIDED | None |
| DBT-03 | Verify the debt after partial payment | Approved authorized role | Paid amount, remaining balance, and status are exact and mutually consistent | NOT RUN | NOT RUN | NOT PROVIDED | None |
| DBT-04 | Open accounting and reports for dedicated data | Approved authorized role | Reports display the expected dedicated test values without double counting | NOT RUN | NOT RUN | NOT PROVIDED | None |

## Persistence tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PER-01 | Close and reopen the app after dedicated product/order/debt changes | Approved authorized role | All dedicated records and values persist | NOT RUN | NOT RUN | NOT PROVIDED | None |
| PER-02 | Restart after Administrator session establishment | Administrator | Session and authorization restore correctly | Dashboard restored after normal close and reopen | PASS | Owner report | None |

## Offline and synchronization tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SYN-01 | Start the app with network unavailable | Previously approved role | Required local startup succeeds without internet | NOT RUN | NOT RUN | NOT PROVIDED | None |
| SYN-02 | Create or update dedicated offline test data | Previously approved role | Local write confirms once and remains queued durably | NOT RUN | NOT RUN | NOT PROVIDED | Record dedicated data cleanup only |
| SYN-03 | Reconnect the device | Previously approved role | Synchronization completes and visible pending/error status clears appropriately | NOT RUN | NOT RUN | NOT PROVIDED | None |
| SYN-04 | Inspect local and cloud-visible dedicated records after reconnect | Previously approved role | No duplicate product, order, debt, payment, or stock effect exists | NOT RUN | NOT RUN | NOT PROVIDED | None |
| SYN-05 | Test reseller privacy with two dedicated reseller identities/owners | Approved authorized role | One reseller cannot access another reseller's private records unless the product explicitly intends it | NOT RUN | NOT RUN | NOT PROVIDED | Record dedicated reseller cleanup only |

## Bluetooth printer tests

| ID | Test | Role/account | Expected result | Actual result | Status | Screenshot or log | Dedicated cleanup |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PRT-01 | Grant required Bluetooth permission and print a dedicated test receipt | Approved authorized role | Intended printer connects and prints correct dedicated receipt data | NOT RUN | NOT RUN | NOT PROVIDED | Dispose of test paper securely |
| PRT-02 | Deny Bluetooth permission | Approved authorized role | App reports the denial without crashing or claiming a print succeeded | NOT RUN | NOT RUN | NOT PROVIDED | None |
| PRT-03 | Attempt printing while the printer is unavailable | Approved authorized role | App reports failure and does not claim success | NOT RUN | NOT RUN | NOT PROVIDED | None |

## Per-test evidence template

Use this block when a table cell does not have enough space. Complete it for every test whose status changes from `NOT RUN`.

```text
Test ID:
Date and time with time zone:
Device model:
Android version:
App version/build:
Account email or anonymized identifier:
Role tested:
Expected result:
Actual result:
Status: PASS | FAIL | BLOCKED
Screenshot or log reference:
Cleanup performed on dedicated test data only:
Notes:
```

## Cleanup record

Cleanup is optional until all persistence and synchronization evidence is collected. Never remove production data.

| Dedicated record | Cleanup action | Date/time | Owner confirmation |
| --- | --- | --- | --- |
| `PHASE8-TEST-PRODUCT` | NOT PERFORMED | NOT PROVIDED | NOT PROVIDED |
| `PHASE8-TEST-ORDER` | NOT PERFORMED | NOT PROVIDED | NOT PROVIDED |
| `PHASE8-TEST-DEBT` | NOT PERFORMED | NOT PROVIDED | NOT PROVIDED |
| `PHASE8-TEST-STAFF` | NOT PERFORMED | NOT PROVIDED | NOT PROVIDED |

## Automated evidence supplement

- Complete Flutter suite: 154 passed, 0 failed after a local generated-cache workaround for Windows Application Control.
- Coverage: 4281/7789 lines, 54.96%, above the 40% gate.
- Automated order tests cover atomic stock deduction, duplicate/oversell prevention, rollback, cancellation, restore, and insufficient stock.
- Automated debt tests cover partial payment allocation, overpayment rejection, durable history, accrual, and transaction rollback.
- Automated sync tests cover durable outbox restart, retry after reconnection, idempotency keys, and confirmed-row completion.
- Automated evidence does not replace the unperformed physical order, debt, offline/reconnection, or Bluetooth checks.

## Current manual verdict

Administrator, core Staff lifecycle, session restoration, and product CRUD are verified. Physical order, debt/payment, complete business persistence, offline/reconnection, rejected/suspended messaging, and Bluetooth remain `BLOCKED` or unverified.
