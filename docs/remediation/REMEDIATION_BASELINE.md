# KNZ Scent Remediation Baseline V2

## Baseline Identity

| Item | Baseline value |
|---|---|
| Remediation phase | Phase 0 - Attributable baseline |
| Recorded date | 2026-07-31 |
| Repository | `E:\flutter_test_projects\inventoryordtrack` |
| Branch | `main` |
| Starting commit | `11cfe2a68451a2ba6ee0786555f2a657d8d16260` |
| Android namespace/application ID | `com.knzscent.admin` |
| Firebase project | `knz-scent` |
| Firebase plan | Spark, as declared by the owner and repository authority documents |
| Firebase Android App ID | `1:120139747390:android:823a15d9a89f4cfaf6816f` |

The Firebase Console billing state was not queried or changed. The Spark-plan entry is the authoritative documented project constraint, not a claim of remote Console verification.

## Scope And Authority

Phase 0 is documentation and baseline work only. No Flutter source, tests, database schema, SQLite data, Firestore data, Firestore Rules, Firebase resource, or Cloud Functions source was changed by this phase.

The current authority order for this baseline is:

1. The owner's current-phase instruction.
2. `AGENTS.md`.
3. `ORCHESTRATED_IMPLEMENTATION_guidev2.md`.
4. `KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md`.
5. The previous approved phase-completion report.
6. Current repository code, schema, tests, and generated evidence.

The V2 guide lists `docs/remediation/AUDIT_ISSUE_CROSSWALK_SOURCE.md` and `docs/remediation/AUDIT_ISSUE_CROSSWALK.md`, but the higher-authority initial Phase 0 prompt and `AGENTS.md` designate `KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md`. The current focused-fix instruction explicitly authorizes correcting that root crosswalk together with this baseline and the Phase 0 completion report. No duplicate crosswalk files were created.

The later Phase 9 text refers to `KNZ-LIKELY findings`, but the audit source defines no `KNZ-LIKELY` registry or finding details. That label is recorded as `SOURCE DEFINITION NOT FOUND`. No title, severity, path, root cause, impact, or test was invented. The required Phase 0 registries remain the exact 50 definitions documented below.

## Starting Git State

No files were staged. The starting `git status --short --untracked-files=all` was:

```text
 M AGENTS.md
 D KNZ-Scent-Full-Verification-Report-v2.md
 D ORCHESTRATED_IMPLEMENTATION_GUIDE.md
?? ALL_PHASE_PROMPTS_V2.md
?? KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md
?? ORCHESTRATED_IMPLEMENTATION_guidev2.md
?? README_START_HERE.md
?? prompts/00_PHASE_0_ATTRIBUTABLE_BASELINE.md
?? prompts/00_PROMPT_INDEX.md
?? prompts/01_PHASE_1_DUPLICATE_ORDERS_AND_PROTECTED_LOGOUT.md
?? prompts/02_PHASE_2_MULTI_DEVICE_SYNCHRONIZATION_AND_CLOUD_VALIDATION.md
?? prompts/03_PHASE_3_SUSPENSION_REVOCATION_AND_OFFLINE_AUTHORIZATION.md
?? prompts/04_PHASE_4_RESELLER_IDENTITY_CUSTOM_ORDER_WORKFLOW_AND_EXPORT_PERIOD.md
?? prompts/05_PHASE_5_DRAWER_NAVIGATION_ROLES_AND_BACK_BEHAVIOR.md
?? prompts/06_PHASE_6_ACCOUNTING_ANALYTICS_UTANG_AND_SALES_CONSISTENCY.md
?? prompts/07_PHASE_7_REPORTS_AND_RECYCLE_BIN_MOBILE_REDESIGN.md
?? prompts/08_PHASE_8_REMAINING_MOBILE_UI_AND_SHARED_COMPONENTS.md
?? prompts/09_PHASE_9_SECURITY_PRIVACY_BLUETOOTH_AND_ANDROID_HARDENING.md
?? prompts/10_PHASE_10_PERFORMANCE_AND_MAINTAINABILITY.md
?? prompts/11_PHASE_11_COMPLETE_TEST_SAFETY_NET_CI_AND_DEPENDENCIES.md
?? prompts/12_PHASE_12_DEVICE_VALIDATION_RELEASE_AND_DISTRIBUTION_GATE.md
?? prompts/90_REVIEW_CURRENT_PHASE.md
?? prompts/91_FIX_REVIEW_FINDINGS.md
?? prompts/92_RESUME_INTERRUPTED_PHASE.md
?? prompts/93_PREPARE_PHASE_COMMIT.md
?? prompts/94_OWNER_DECISION_RESPONSE.md
```

The starting tracked diff contained 223 insertions and 2,408 deletions across three documentation files. `git diff --check` returned no whitespace error, with only Git's LF-to-CRLF working-copy warning for `AGENTS.md`. The two Phase 0 documents did not exist at the start.

## Focused Review Corrections

The independent Phase 0 review identified the two tracked legacy-document deletions as blockers because they lacked owner authorization. The owner explicitly decided that `KNZ-Scent-Full-Verification-Report-v2.md` and `ORCHESTRATED_IMPLEMENTATION_GUIDE.md` must remain in the repository. Both files were restored directly from `HEAD`, retain their tracked contents exactly, and are no longer unresolved deletions.

The restored files are historical/reference documentation only. They do not supersede or modify the authority order above, and in particular they are not authoritative over `ORCHESTRATED_IMPLEMENTATION_guidev2.md`.

The review also confirmed that the `KNZ-SEC-012` definition assigns split ownership to Phases 3 and 5 while the crosswalk's Phase Ownership Summary omitted it from Phase 5. The summary was corrected without changing the finding's title, severity, confidence, evidence, impact, remediation, tests, or any other issue assignment. The definition, crosswalk summary, and baseline assignment now consistently identify Phases 3 and 5.

These focused corrections changed no application source, test, Android configuration, database schema, Firestore Rule, Firebase configuration or resource, or business data.

## Changed And Untracked Path Classification

All paths below predate the Phase 0 output documents. "Owner review" means no staging decision was made in this phase.

| Starting status | Path | Remediation classification | Git safety classification |
|---|---|---|---|
| Modified | `AGENTS.md` | V2 governance documentation | Requires owner review |
| Deleted at baseline; restored after review | `KNZ-Scent-Full-Verification-Report-v2.md` | Historical/reference documentation retained by explicit owner decision; not current V2 authority | Restored exactly from `HEAD`; tracked and clean |
| Deleted at baseline; restored after review | `ORCHESTRATED_IMPLEMENTATION_GUIDE.md` | Historical/reference documentation retained by explicit owner decision; not current V2 authority | Restored exactly from `HEAD`; tracked and clean |
| Untracked | `ALL_PHASE_PROMPTS_V2.md` | Remediation documentation | Requires owner review |
| Untracked | `KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md` | Audit-source/remediation documentation | Requires owner review |
| Untracked | `ORCHESTRATED_IMPLEMENTATION_guidev2.md` | Remediation orchestration documentation | Requires owner review |
| Untracked | `README_START_HERE.md` | V2 package documentation | Requires owner review |
| Untracked | `prompts/00_PHASE_0_ATTRIBUTABLE_BASELINE.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/00_PROMPT_INDEX.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/01_PHASE_1_DUPLICATE_ORDERS_AND_PROTECTED_LOGOUT.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/02_PHASE_2_MULTI_DEVICE_SYNCHRONIZATION_AND_CLOUD_VALIDATION.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/03_PHASE_3_SUSPENSION_REVOCATION_AND_OFFLINE_AUTHORIZATION.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/04_PHASE_4_RESELLER_IDENTITY_CUSTOM_ORDER_WORKFLOW_AND_EXPORT_PERIOD.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/05_PHASE_5_DRAWER_NAVIGATION_ROLES_AND_BACK_BEHAVIOR.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/06_PHASE_6_ACCOUNTING_ANALYTICS_UTANG_AND_SALES_CONSISTENCY.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/07_PHASE_7_REPORTS_AND_RECYCLE_BIN_MOBILE_REDESIGN.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/08_PHASE_8_REMAINING_MOBILE_UI_AND_SHARED_COMPONENTS.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/09_PHASE_9_SECURITY_PRIVACY_BLUETOOTH_AND_ANDROID_HARDENING.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/10_PHASE_10_PERFORMANCE_AND_MAINTAINABILITY.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/11_PHASE_11_COMPLETE_TEST_SAFETY_NET_CI_AND_DEPENDENCIES.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/12_PHASE_12_DEVICE_VALIDATION_RELEASE_AND_DISTRIBUTION_GATE.md` | Remediation prompt documentation | Requires owner review |
| Untracked | `prompts/90_REVIEW_CURRENT_PHASE.md` | Review-process documentation | Requires owner review |
| Untracked | `prompts/91_FIX_REVIEW_FINDINGS.md` | Review-process documentation | Requires owner review |
| Untracked | `prompts/92_RESUME_INTERRUPTED_PHASE.md` | Recovery-process documentation | Requires owner review |
| Untracked | `prompts/93_PREPARE_PHASE_COMMIT.md` | Commit-process documentation | Requires owner review |
| Untracked | `prompts/94_OWNER_DECISION_RESPONSE.md` | Owner-decision process documentation | Requires owner review |

No starting changed or untracked path was classified as accepted implementation, previous Phase 8 implementation, application security implementation, drawer/feature implementation, tests, generated output, a sensitive file, or unrelated source. The two legacy deletions were resolved only after the owner's explicit restoration decision; the legacy files remain non-authoritative historical/reference documents.

## Ignored Path Classification

The ignored inventory was inspected without opening or printing sensitive local values.

| Classification | Ignored paths |
|---|---|
| Generated/cache/dependency output | `.dart_tool/`, `.flutter-plugins-dependencies`, `.idea/`, `android/.gradle/`, `android/.kotlin/`, `android/app/src/main/java/`, `android/inventoryordtrack_android.iml`, `build/`, `coverage/`, `functions/node_modules/`, `inventoryordtrack.iml`, `ios/Flutter/Generated.xcconfig`, `ios/Flutter/ephemeral/`, `ios/Flutter/flutter_export_environment.sh`, `ios/Runner/GeneratedPluginRegistrant.h`, `ios/Runner/GeneratedPluginRegistrant.m`, `linux/flutter/ephemeral/`, `macos/Flutter/ephemeral/`, `rules-tests/node_modules/`, `windows/flutter/ephemeral/` |
| Local machine configuration; must never be staged | `android/local.properties` |
| Sensitive/local environment files; must never be staged | `functions/.env.demo-knz-scent`, `functions/.secret.local` |
| Debug log; must never be staged | `functions/firestore-debug.log` |

No ignored local database, release keystore, or real `key.properties` appeared in the ignored status inventory. Absence from that inventory is not permission to stage any such file if it appears later.

## Audit Source Validation

The definition rows in `KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md` were checked by exact ID pattern and sequence.

| Registry | Required IDs | Definition rows found | Missing | Duplicate | Result |
|---|---|---:|---:|---:|---|
| DFR | `DFR-001` through `DFR-029` | 29 | 0 | 0 | Complete |
| DFL | `DFL-001` through `DFL-007` | 7 | 0 | 0 | Complete |
| KNZ-SEC | `KNZ-SEC-001` through `KNZ-SEC-014` | 14 | 0 | 0 | Complete |
| Total | Exact required inventory | 50 | 0 | 0 | Complete |

The source-reported severity totals reconcile with the definition rows:

| Registry | Severity distribution |
|---|---|
| DFR | 3 Critical, 5 High, 18 Medium, 3 Low |
| DFL | 1 High, 5 Medium, 1 Low |
| KNZ-SEC | 2 High, 7 Medium, 5 Low |

## DFR Registry And Ownership

| ID | Source area | Severity | Assigned phase |
|---|---|---|---:|
| DFR-001 | Orders | Critical | 1 |
| DFR-002 | Inventory, Orders, Utang, Sync | Critical | 2 |
| DFR-003 | Recycle Bin, Sign Out | Critical | 1, 5 |
| DFR-004 | Reseller Accounting | High | 4 |
| DFR-005 | Custom Orders | High | 4 |
| DFR-006 | Accounting Export | High | 4 |
| DFR-007 | Admin Portal | High | 3 |
| DFR-008 | Recycle Bin | High | 7 |
| DFR-009 | Reports | Medium | 7 |
| DFR-010 | Recycle Bin | Medium | 7 |
| DFR-011 | Accounting | Medium | 7 |
| DFR-012 | Overview | Medium | 8 |
| DFR-013 | Overview | Medium | 8 |
| DFR-014 | Inventory | Medium | 8 |
| DFR-015 | Orders | Medium | 8 |
| DFR-016 | Sales Table | Medium | 6 |
| DFR-017 | Resellers | Medium | 8 |
| DFR-018 | Reseller Accounting | Medium | 6 |
| DFR-019 | Custom Orders | Medium | 6 |
| DFR-020 | Utang | Medium | 6 |
| DFR-021 | Analytics | Medium | 6 |
| DFR-022 | All screens | Medium | 8 |
| DFR-023 | Drawer, Recycle, Custom, Filters | Medium | 8 |
| DFR-024 | Product Catalogue | Medium | 8 |
| DFR-025 | Analytics, Reports, Sales | Medium | 10 |
| DFR-026 | MainShell | Medium | 3, 5 |
| DFR-027 | Multiple headers | Low | 8 |
| DFR-028 | Catalogue / Inventory | Low | 8 |
| DFR-029 | Drawer | Low | 5 |

## DFL Registry And Ownership

DFL is the source-defined likely drawer and feature registry. Each item remains a finding to verify during its assigned implementation phase.

| ID | Source area | Severity | Assigned phase |
|---|---|---|---:|
| DFL-001 | Staff permanent delete | High | 5 |
| DFL-002 | Android Back with drawer open | Medium | 5 |
| DFL-003 | Bottom navigation overlap | Medium | 5 |
| DFL-004 | Large-text overflow | Medium | 8 |
| DFL-005 | Large export jank | Medium | 10 |
| DFL-006 | Landscape dialog crowding | Medium | 8 |
| DFL-007 | Missing image-file residue | Low | 9 |

## KNZ-SEC Registry And Ownership

| ID | Source title | Severity | Assigned phase |
|---|---|---|---:|
| KNZ-SEC-001 | Duplicate Order Submission | High | 1 |
| KNZ-SEC-002 | Multi-Device Last-Write-Wins Synchronization Can Lose Stock and Financial State | High | 2 |
| KNZ-SEC-003 | Suspended or Disabled Users Can Retain Offline Access | Medium | 3 |
| KNZ-SEC-004 | Firestore Business Documents Lack Field-Level and Transition Validation | Medium | 2 |
| KNZ-SEC-005 | Sensitive Local Data Is Unencrypted and Backup Policy Is Unspecified | Medium | 9 |
| KNZ-SEC-006 | Raw Repository Exceptions Are Sent to Crashlytics | Medium | 9 |
| KNZ-SEC-007 | GCash Personal Data Is Duplicated in Payment Notes | Medium | 9 |
| KNZ-SEC-008 | Production Functions Dependencies Have Known Advisories | Medium | 11 |
| KNZ-SEC-009 | BLE Printer Identity Is Not Verified | Medium | 9 |
| KNZ-SEC-010 | Login Rate Limit Is Client-Only | Low | 9 |
| KNZ-SEC-011 | Business Text and Image Inputs Are Insufficiently Bounded | Low | 9 |
| KNZ-SEC-012 | Administrator Screen Relies on Navigation Hiding | Low | 3, 5 |
| KNZ-SEC-013 | Android Privacy and Release Hardening Are Incomplete | Low | 9 |
| KNZ-SEC-014 | Backend and Release Documentation Have Policy Drift | Low | 9 |

## Phase Assignment Verification

Every defined issue has at least one implementation owner after Phase 0. Split ownership is intentional for route/session issues that cross phase boundaries.

| Phase | Assigned issue IDs |
|---:|---|
| 1 | DFR-001, DFR-003 session-reset portion, KNZ-SEC-001 |
| 2 | DFR-002, KNZ-SEC-002, KNZ-SEC-004 |
| 3 | DFR-007, DFR-026 privileged-navigation portion, KNZ-SEC-003, KNZ-SEC-012 authorization portion |
| 4 | DFR-004, DFR-005, DFR-006 |
| 5 | DFR-003 navigation portion, DFR-026 centralized-navigation portion, DFR-029, DFL-001, DFL-002, DFL-003, KNZ-SEC-012 destination-guard portion |
| 6 | DFR-016, DFR-018, DFR-019, DFR-020, DFR-021 |
| 7 | DFR-008, DFR-009, DFR-010, DFR-011 |
| 8 | DFR-012, DFR-013, DFR-014, DFR-015, DFR-017, DFR-022, DFR-023, DFR-024, DFR-027, DFR-028, DFL-004, DFL-006 |
| 9 | DFL-007, KNZ-SEC-005, KNZ-SEC-006, KNZ-SEC-007, KNZ-SEC-009, KNZ-SEC-010, KNZ-SEC-011, KNZ-SEC-013, KNZ-SEC-014 |
| 10 | DFR-025, DFL-005 |
| 11 | KNZ-SEC-008 |
| 12 | Final device, multi-device, release, and distribution verification for all findings; not a substitute for implementation ownership |

The `KNZ-SEC-012` definition and ownership summaries consistently assign its authorization portion to Phase 3 and its destination-guard portion to Phase 5.

No issue is assigned to Phase 0 for behavior remediation, and no issue was marked fixed by this baseline.

## Active Identifier Evidence

| Identifier | Repository evidence | Result |
|---|---|---|
| Android namespace | `android/app/build.gradle.kts` | `com.knzscent.admin` |
| Android application ID | `android/app/build.gradle.kts` | `com.knzscent.admin` |
| Main activity package | `android/app/src/main/kotlin/com/knzscent/admin/MainActivity.kt` | `com.knzscent.admin` |
| Firebase default project | `.firebaserc` | `knz-scent` |
| Firebase Android mapping | `firebase.json` | Expected project and App ID |
| Active Android client | `android/app/google-services.json` | Contains the branded package and expected App ID |
| Flutter Firebase options | `lib/firebase_options.dart` | Contains the expected project and App ID |

No identifier file was modified during Phase 0.

## Google Services Backup Review

`android/app/google-services.old.json` is tracked and unchanged at the starting commit. It contains the Firebase project name but only the obsolete `com.example.inventoryordtrack` Android package. It contains no `com.knzscent.admin` client.

The Android Gradle build reads only `android/app/google-services.json`. Repository reference search found the old filename only in documentation and remediation instructions, not in build logic, runtime source, scripts, or tests. The old file is therefore an obsolete, unreferenced backup rather than an active build input.

The file was not deleted. Under the V2 guide it is classified as an obsolete backup that must never be staged when changed. Owner-approved removal is deferred to Phase 9.

## Secret Review

Tracked filename scans found no service-account JSON, JKS/keystore, real `key.properties`, PEM/P12/PFX private-key file, local database, log, or build output. The only environment-name matches were tracked example templates. `android/key.properties.example` and environment examples contain configuration shape and are not signing credentials.

Tracked content-marker scans found no service-account type marker, service-account private-key field, private-key block, AWS key pattern, GitHub token pattern, or Slack token pattern. Signing-password matches were variable/property references in Gradle and an example file, not a tracked real `key.properties` file.

Firebase client-key patterns were detected only at these locations; values were not printed:

| Path and line | Type | Redacted preview | Classification |
|---|---|---|---|
| `android/app/google-services.json:18` | Firebase Android client API key | `[REDACTED]` | Active client configuration; not a service-account private key |
| `android/app/google-services.json:37` | Firebase Android client API key | `[REDACTED]` | Active client configuration; not a service-account private key |
| `android/app/google-services.old.json:18` | Firebase Android client API key | `[REDACTED]` | Obsolete client backup; must never be staged when changed |
| `lib/firebase_options.dart:56` | Firebase Flutter client API key | `[REDACTED]` | Active generated client configuration; not a service-account private key |

`gitleaks` was not installed, so no `gitleaks` result is claimed. The Git filename/content-marker review and repository configuration test remain the Phase 0 evidence. No secret value was printed, copied into this report, staged, or committed.

## Git Safety Classification

| Classification | Exact scope |
|---|---|
| Safe to stage after independent Phase 0 review and explicit owner approval | `docs/remediation/REMEDIATION_BASELINE.md`, `docs/progress/REMEDIATION_PHASE_0_COMPLETION.md` |
| Requires owner review | Every starting modified or untracked documentation path listed in the classification table; active Firebase client configuration if it is ever changed |
| Must never be staged | `android/app/google-services.old.json` when changed while obsolete; `android/local.properties`; real environment-secret files; local secret files; service-account credentials; private keys; keystores; real `key.properties`; passwords/tokens; local databases; logs; temporary exports |
| Generated output | Every generated/cache/dependency path listed in the ignored inventory, including build output and coverage |
| Unrelated or uncertain | None in the starting changed/untracked status; the legacy documentation deletions are resolved by owner-approved restoration |

No staging, commit, push, deployment, publication, or distribution occurred.

## Data And Rollback Safety

No database migration exists in Phase 0. No SQLite or Firestore record was read for business-data analysis, rewritten, deleted, reset, or replaced. Application storage was not cleared, and the application was not uninstalled.

No Firebase resource or Cloud Function was deployed. No Administrator bootstrap was run. No Blaze dependency was introduced. Phase 0 remains Spark-compatible.

The focused documentation corrections require no application or production-like data rollback. The two restored legacy documents must remain at their exact tracked `HEAD` contents under the owner's decision.

## Analyzer Baseline

The continuation run of `flutter analyze` reported exactly 26 diagnostics: zero errors, zero warnings, and 26 information-level diagnostics. The exact command exited nonzero because information diagnostics are fatal by default. The permitted verification command `flutter analyze --no-fatal-infos` reported the same 26 information diagnostics and exited successfully. `--no-fatal-warnings` was not used.

These diagnostics predate Phase 0 and remain unresolved. They are accurately summarized as:

| Lint | Count | Affected areas |
|---|---:|---|
| `prefer_interpolation_to_compose_strings` | 1 | `lib/core/money.dart` |
| `unnecessary_this` | 9 | Custom order, order, product, and reseller models |
| `curly_braces_in_flow_control_structures` | 16 | Database helper, Analytics, Products, and Recycle Bin |
| Total information diagnostics | 26 | Existing Flutter application source |

Phase 0 did not modify, suppress, or represent any analyzer diagnostic as resolved. No Flutter source or test file was changed. Cleanup is deferred to the appropriate later remediation phase, with full regression validation required in that phase.

The analyzer classification does not change the source-integrity rule for unsupported findings. The later `KNZ-LIKELY` reference remains `SOURCE DEFINITION NOT FOUND` and is not represented as a confirmed issue.

## Focused Validation Plan

The Phase 0 completion report records focused-fix results for:

```powershell
git branch --show-current
git rev-parse HEAD
git status --short
git diff --check
git diff --stat
git diff --name-status
git diff -- KNZ-Scent-Full-Verification-Report-v2.md
git diff -- ORCHESTRATED_IMPLEMENTATION_GUIDE.md
git diff -- KNZ_AUDIT_ISSUE_CROSSWALK_SOURCE.md
git diff -- docs/remediation/REMEDIATION_BASELINE.md
git diff -- docs/progress/REMEDIATION_PHASE_0_COMPLETION.md
git diff -- lib test integration_test android
git diff --cached --check
git diff --cached --stat
git diff --cached --name-status
```

Exact registry-definition counts, uniqueness, and `KNZ-SEC-012` split ownership are also rechecked. The Flutter suite is not rerun because the focused corrections do not change source-controlled application files. Firestore Rules and Functions tests remain not applicable because neither source area changed. Physical-device, Firebase Console, printer, and production-data tests are not claimed.
