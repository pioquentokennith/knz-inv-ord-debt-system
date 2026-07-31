# KNZ Scent — Admin Portal

> A Flutter-based mobile admin application for managing a luxury fragrance business.
> Built with an offline-first architecture, real-time Firebase cloud sync, Bluetooth receipt printing, and a clean dark/gold UI theme.

---

## 📱 Overview

**KNZ Scent Admin** is a business management system designed for a small fragrance business. It allows administrators to manage products, track orders, monitor inventory, handle customer debts (*utang*), manage resellers, export reports, and view sales analytics — all from a mobile device, even without an internet connection.

> Built as a school project demonstrating the practical application of **Object-Oriented Programming (OOP)** principles in a real-world Flutter mobile application.

### Support status

The current supported release target is **Android**. The repository keeps iOS, macOS, web, Windows, and Linux scaffolding for future work, but those targets are not release-supported until their Firebase registrations, native capabilities, and device test matrices are completed.

The production package ID is `com.knzscent.admin`. The checked-in Android Firebase file belongs to the previous template ID, so regenerate Firebase configuration for the new package before expecting Firebase-backed features or Crashlytics to work. Credential-free CI builds intentionally skip the Firebase Gradle plugins when no matching configuration is available.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔐 **Authentication** | Firebase email/password login, email verification, controlled registration approval, password reset, and persistent brute-force lockout (5 attempts → 30s lockout, survives app restarts) |
| 📦 **Inventory Management** | Add, edit, soft-delete, and restore stock items; low-stock alerts with push notifications |
| 🛒 **Order Management** | Create and track orders with statuses: Pending, Processing, Shipped, Delivered, Cancelled, Utang |
| 💸 **Utang (Credit) System** | Record customer debts, accept partial payments, and print Bluetooth debt receipts |
| 🏪 **Reseller Management** | Track resellers with a fixed peso deduction per item; dedicated reseller accounting view |
| 📋 **Custom Orders** | Create and manage custom/bespoke orders separate from standard orders |
| 💰 **Sales & Accounting** | Sales records screen and a dedicated accounting screen for financial reconciliation |
| 📊 **Analytics Dashboard** | Visual sales reports, revenue trends, and product performance charts |
| 🗂️ **Product Catalog** | Manage fragrance products with categories, pricing, image support, and minimum stock levels |
| 📋 **Activity Logs** | Full audit trail of all admin actions |
| 🗑️ **Recycle Bin** | Soft-deleted records are stored and can be restored or permanently deleted |
| 📤 **Export** | Export inventory, orders, and debt records as PDF or CSV and share them |
| 🖨️ **Bluetooth Printing** | Print receipts and debt agreements wirelessly to ESC/POS Bluetooth thermal printers |
| 🔄 **Offline-First Sync** | Works without internet; auto-syncs to Firebase Firestore when back online via a persistent sync queue |
| ⏱️ **Session Timeout** | Automatically logs out after a period of inactivity for security |
| 🔔 **Local Notifications** | On-device notifications for low-stock and overdue-debt reminders |

---

## 🏗️ Architecture

This project follows a **layered architecture** with clear separation of concerns:

```
lib/
├── core/                              # App-wide constants, colors, text styles, and state management
│   ├── app_constants.dart             # AppColors, AppStrings — single source of truth for design tokens
│   ├── app_state.dart                 # Singleton ChangeNotifier — central app state
│   └── app_state_builder.dart
│
├── models/                            # Data entities (all extend BaseModel)
│   ├── base_model.dart
│   ├── product_model.dart             # ProductCategory enum (EDP, EDT, Body Mist, Perfume Oil, Gift Set)
│   ├── order_model.dart               # OrderStatus enum + OrderItem
│   ├── payment_method_model.dart      # PaymentMethod enum (GCash, Maya, COD, Card, Utang)
│   ├── debt_model.dart                # CustomerDebt + PaymentRecord
│   ├── reseller_model.dart            # Reseller with deductionPerItem
│   ├── custom_order_model.dart
│   ├── sales_record_model.dart
│   ├── reseller_accounting_summary.dart
│   └── user_model.dart
│
├── repositories/                      # Data access layer (local SQLite + Firestore sync)
│   ├── base_repository.dart
│   ├── product_repository.dart        # Abstract interface
│   ├── order_repository.dart          # Abstract interface
│   ├── debt_repository.dart           # Abstract interface
│   ├── user_repository.dart           # Abstract interface
│   ├── local_product_repository.dart
│   ├── local_order_repository.dart
│   ├── local_debt_repository.dart
│   ├── local_user_repository.dart
│   ├── local_reseller_repository.dart
│   ├── local_custom_order_repository.dart
│   ├── activity_log_repository.dart
│   ├── i_activity_log_repository.dart
│   ├── firestore_sync.dart            # Syncs local data to Firebase Firestore
│   └── sync_queue.dart               # Processes durable SQLite outbox writes and retries
│
├── services/                          # Business logic layer (interface + implementation)
│   ├── auth_service.dart
│   ├── product_service.dart
│   ├── order_service.dart
│   ├── debt_service.dart
│   ├── accounting_service.dart
│   ├── agreement_pdf_service.dart     # Generates Bluetooth-printable debt agreement PDFs
│   ├── export_service.dart            # PDF and CSV export logic
│   ├── notification_service.dart      # Local push notifications (low-stock alerts)
│   ├── login_rate_limiter.dart        # Persistent brute-force lockout (SharedPreferences-backed)
│   ├── otp_service.dart                # Calls the secured Firebase OTP backend
│   └── session_timeout_service.dart
│
├── screens/                           # UI screens (one per feature)
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── otp_screen.dart
│   ├── forgot_password_screen.dart
│   ├── main_shell.dart               # Navigation shell with sidebar
│   ├── overview_screen.dart
│   ├── inventory_screen.dart
│   ├── products_screen.dart
│   ├── orders_screen.dart
│   ├── utang_screen.dart
│   ├── sales_screen.dart
│   ├── reports_screen.dart
│   ├── analytics_screen.dart
│   ├── accounting_screen.dart
│   ├── reseller_screen.dart
│   ├── reseller_accounting_screen.dart
│   ├── custom_orders_screen.dart
│   ├── receipt_screen.dart
│   └── recycle_bin_screen.dart
│
├── dialogs/                           # Reusable dialog components
│   ├── order_dialog.dart
│   ├── custom_order_dialog.dart
│   ├── product_dialog.dart
│   ├── edit_stock_dialog.dart
│   ├── reseller_dialog.dart
│   ├── mark_as_utang_dialog.dart
│   ├── utang_payment_dialog.dart
│   ├── utang_receipt_printer.dart
│   └── export_dialog.dart            # Export format selection (PDF / CSV)
│
├── widgets/                           # Shared reusable UI widgets
│   ├── shared_widgets.dart
│   └── receipt_shared_widgets.dart
│
├── database/
│   └── database_helper.dart          # SQLite setup and schema migrations (current version: 12)
│
├── firebase_options.dart
└── main.dart
```

---

## 🧠 OOP Concepts Applied

This project was built with core **Object-Oriented Programming** principles in mind:

### 1. 🔒 Encapsulation
All model classes (`Product`, `Order`, `CustomerDebt`, etc.) use **private fields** with public **getters** to protect data integrity. Mutable properties like `stockQty` and `amountPaid` have **validated setters** that prevent invalid states.

```dart
// Example from product_model.dart
int get stockQty => _stockQty;
set stockQty(int value) {
  if (value < 0) throw ArgumentError('Stock cannot be negative');
  _stockQty = value;
}
```

### 2. 🧬 Inheritance
All models extend `BaseModel`, which provides a shared `id` field and an abstract `toMap()` method enforced on every subclass.

```
BaseModel
├── Product
├── Order
│   └── OrderItem
├── CustomerDebt
│   └── PaymentRecord
├── Reseller
├── CustomOrder
└── AppUser
```

### 3. 🎭 Abstraction & Polymorphism
Services and repositories are defined as **abstract interfaces** and implemented by concrete classes. This allows easy mocking in unit tests and swapping implementations without changing business logic.

```dart
// AppState depends on interfaces, not concrete classes
IProductService _productService;
IOrderService   _orderService;
IDebtService    _debtService;
IAuthService    _authService;
```

`OrderStatus` and `PaymentMethod` both use **map-based dispatch** instead of switch statements for polymorphic behavior (display names, colors, icons).

### 4. ⚙️ Dependency Inversion Principle (DIP)
`AppState` receives its dependencies through a `configure()` method, making the app testable and modular. Concrete repositories and services are only wired up in `main.dart`, keeping the rest of the codebase decoupled.

---

## 🗄️ Database

- **Local:** SQLite via `sqflite` (primary, offline-first)
- **Cloud:** Firebase Firestore (backup, synced when back online)
- **Schema Version:** 12, with tested upgrades from every historical version

### Tables

| Table | Description |
|---|---|
| `users` | Admin accounts |
| `products` | Fragrance product inventory |
| `orders` | Customer orders |
| `order_items` | Line items per order (includes `srp_price` for sales accuracy) |
| `debts` | Customer credit/utang records |
| `payments` | Payment records against debts |
| `activity_logs` | Audit trail of all admin actions |
| `sync_queue` | Pending Firestore operations queued for retry when offline |
| `order_sequences` | Per-user source for unique human-readable order numbers |
| `resellers` | Reseller accounts with per-item deduction amounts |
| `custom_orders` | Custom/bespoke order records |
| `custom_order_payments` | Immutable custom-order receipt history |

---

## 🎨 UI Design

- **Theme:** Dark mode with a luxury gold accent
- **Color Palette:**

| Role | Hex | Token |
|---|---|---|
| Background | `#0D0D0D` | `AppColors.background` |
| Surface | `#1A1A1A` | `AppColors.surface` |
| Surface Elevated | `#222222` | `AppColors.surfaceElevated` |
| Sidebar | `#111111` | `AppColors.sidebar` |
| Gold (main) | `#D4AF37` | `AppColors.gold` |
| Gold (light) | `#E8C547` | `AppColors.goldLight` |
| Gold (dark) | `#B8960C` | `AppColors.goldDark` |
| Error | `#E53935` | `AppColors.error` |
| Success | `#43A047` | `AppColors.success` |
| Warning | `#FFA726` | `AppColors.warning` |

- **Typography:** Roboto with wide letter-spacing for a premium feel
- **Component library:** Material Design 3 with a custom dark `ColorScheme`
- **Gradients:** Horizontal gold sweep (`goldGradient`) for headings/buttons; vertical dark fade (`sidebarGradient`) for the nav rail

---

## 📋 Order Statuses

| Status | Color | Description |
|---|---|---|
| Pending | 🟠 Orange `#FFA726` | Order placed, not yet processed |
| Processing | 🔵 Blue `#29B6F6` | Order is being prepared |
| Shipped | 🟣 Purple `#AB47BC` | Order is on its way |
| Delivered | 🟢 Green `#43A047` | Order successfully delivered |
| Cancelled | 🔴 Red `#E53935` | Order was cancelled |
| Utang | 🟡 Gold `#D4AF37` | Order marked as credit/debt |

---

## 💳 Payment Methods

| Method | Description |
|---|---|
| GCash | GCash e-wallet |
| Maya | Maya (formerly PayMaya) e-wallet |
| Credit / Debit Card | Visa / Mastercard / etc. |
| Cash on Delivery | COD — no digital reference |
| Utang (Credit) | Customer owes payment |

---

## 📂 Product Categories

The app supports the following fragrance product categories:

- Eau de Parfum
- Eau de Toilette
- Body Mist
- Perfume Oil
- Gift Set

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter `3.38.4` repository/CI pin, Dart `>=3.10.3 <4.0.0` |
| Local Database | SQLite (`sqflite ^2.4.1`) |
| Cloud Database | Firebase Firestore (`cloud_firestore ^5.6.5`) |
| Authentication | Firebase Authentication with Firestore-rules-enforced approval and UID ownership |
| State Management | `ChangeNotifier` — singleton `AppState` |
| Optional Email Delivery | Brevo through Firebase callable Functions; secrets stored in Google Cloud Secret Manager |
| Password Handling | Managed by Firebase Authentication; no client or Firestore password verifier |
| Login Protection | Persistent rate limiter via `shared_preferences ^2.3.2` |
| Analytics Charts | `fl_chart ^0.70.2` |
| Bluetooth Printing | `flutter_blue_plus ^1.35.5` + `esc_pos_utils_plus ^2.0.4` |
| Export (PDF) | `pdf ^3.11.1` + `printing ^5.13.1` + `share_plus ^10.0.0` |
| Export (CSV) | `csv ^6.0.0` + `share_plus ^10.0.0` |
| Local Notifications | `flutter_local_notifications ^18.0.1` |
| Crash Reporting | Firebase Crashlytics `^4.3.3` (disabled in debug mode) |
| Image Handling | `image_picker ^1.1.2` + `path_provider ^2.1.5` |
| Connectivity | `connectivity_plus ^6.1.4` |
| Animations | `animate_do ^3.3.4` + `flutter_staggered_animations ^1.1.1` |

Package versions above are the direct compatibility constraints declared in
`pubspec.yaml`, not claims that every resolved package has that exact version.
Reproducible installs use the exact resolutions in `pubspec.lock`.

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `3.38.4` from `.fvmrc` with Dart SDK `3.10.3` (the project constraint is `>=3.10.3 <4.0.0`)
- Node.js 20
- Java 17 and the Android SDK
- Firebase CLI `14.27.0` and FlutterFire CLI
- Android Studio or VS Code with Flutter plugin
- Spark-plan Firebase project with Firestore, Email/Password Authentication, and Crashlytics enabled
- Node.js tooling for local Functions and Firestore emulator tests; no production Functions deployment is required
- A Bluetooth ESC/POS thermal printer (optional, for receipt printing)

### Setup

1. **Open the repository root and install dependencies**

   ```bash
   flutter pub get
   ```

2. **Register the Android application with Firebase**

   Register package `com.knzscent.admin`, then regenerate the FlutterFire files:

   ```bash
   flutterfire configure --project=knz-scent --platforms=android
   ```

   Confirm that `android/app/google-services.json` contains `"package_name": "com.knzscent.admin"`. The Gradle build deliberately does not apply Google Services or Crashlytics when this does not match.

3. **Deploy the Spark-compatible Firestore configuration**

   Firebase Authentication email verification and password reset are the active production authentication flows. Registration and account review use Firebase Auth plus atomic Firestore batches protected by rules. They do not call deployed Cloud Functions or Brevo.

   Keep the Functions source for emulator coverage or a future owner-approved Blaze migration, but do not deploy it for the Spark production path:

   ```bash
   cd functions
   npm ci
   npm run lint
   npm test
   npm run deploy:spark
   cd ..
   ```

   Never place Firebase Admin credentials, Brevo keys, OTP secrets, or sender credentials in Flutter source, assets, logs, or crash reports.

4. **Run the Android app**

   ```bash
   flutter run -d android
   ```

Apple, web, and desktop targets require separate Firebase registrations and platform verification before use.

---

## 🧪 Tests and CI

The automated suite covers authentication and registration decisions, sessions and rate limiting, domain validation, products, atomic order/stock/debt transactions, interest and payment allocation, accounting, CSV/PDF exports, DTO restore into a fresh database, migrations, durable outbox retries, Functions policies/endpoints, and Firestore authorization rules. Bluetooth hardware, platform permissions, production Firebase configuration, and signed-release behavior still require device or owner-controlled verification.

Run Flutter checks with:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test --coverage
dart run tool/check_coverage.dart coverage/lcov.info 30
```

Run backend checks with:

```bash
cd functions
npm ci
npm run lint
npm test
npm run test:emulator
npm audit --omit=dev --audit-level=high
```

The GitHub Actions workflow is configured to run formatting, analysis, Flutter tests with a 30% line-coverage floor, an Android debug build, Functions unit/emulator tests, Firestore rule tests, and a production dependency audit. These CI-equivalent checks pass locally; a clean-clone remote workflow run still requires owner validation. The Phase 7 baseline measured 55.45% line coverage; the lower gate allows normal compiler and platform variation while preventing a major regression, and should increase as additional UI and platform seams become deterministic.

---

## 🔐 Security, privacy, and releases

- [Security policy](SECURITY.md)
- [Privacy disclosure template](PRIVACY.md)
- [Android release checklist](RELEASE_CHECKLIST.md)

---

## 👤 Author

**Kennith** — Built as a school project demonstrating the application of **Object-Oriented Programming** principles in a real-world Flutter mobile application.

---

*KNZ Scent — Luxury Fragrance House* 🌸
