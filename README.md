# KNZ Scent — Admin Portal

> A Flutter-based mobile admin application for managing a luxury fragrance business.
> Built with an offline-first architecture, real-time Firebase cloud sync, Bluetooth receipt printing, and a clean dark/gold UI theme.

---

## 📱 Overview

**KNZ Scent Admin** is a business management system designed for a small fragrance business. It allows administrators to manage products, track orders, monitor inventory, handle customer debts (*utang*), export reports, and view sales analytics — all from a mobile device, even without an internet connection.

> Built as a school project demonstrating the practical application of **Object-Oriented Programming (OOP)** principles in a real-world Flutter mobile application.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔐 **Authentication** | Secure login, registration, OTP email verification, and password reset |
| 📦 **Inventory Management** | Add, edit, soft-delete, and restore stock items; low-stock alerts included |
| 🛒 **Order Management** | Create and track orders with statuses: Pending, Processing, Shipped, Delivered, Cancelled, Utang |
| 💸 **Utang (Credit) System** | Record customer debts, accept partial payments, and print Bluetooth debt receipts |
| 📊 **Analytics Dashboard** | Visual sales reports, revenue trends, and product performance charts |
| 🗂️ **Product Catalog** | Manage fragrance products with categories, pricing, and images |
| 📋 **Activity Logs** | Full audit trail of all admin actions |
| 🗑️ **Recycle Bin** | Soft-deleted records are stored and can be restored or permanently deleted |
| 📤 **Export** | Export inventory, orders, and debt records as PDF or CSV and share them |
| 🖨️ **Bluetooth Printing** | Print receipts wirelessly to ESC/POS Bluetooth thermal printers |
| 🔄 **Offline-First Sync** | Works without internet; auto-syncs to Firebase Firestore when back online |
| ⏱️ **Session Timeout** | Automatically logs out after a period of inactivity for security |

---

## 🏗️ Architecture

This project follows a **layered architecture** with clear separation of concerns:

```
lib/
├── core/                          # App-wide constants, colors, text styles, and state management
│   ├── app_constants.dart
│   ├── app_state.dart             # Singleton ChangeNotifier — central app state
│   └── app_state_builder.dart
│
├── models/                        # Data entities (all extend BaseModel)
│   ├── base_model.dart
│   ├── product_model.dart
│   ├── order_model.dart
│   ├── debt_model.dart
│   └── user_model.dart
│
├── repositories/                  # Data access layer (local SQLite + Firestore sync)
│   ├── base_repository.dart
│   ├── product_repository.dart    # Abstract interface
│   ├── order_repository.dart      # Abstract interface
│   ├── debt_repository.dart       # Abstract interface
│   ├── user_repository.dart       # Abstract interface
│   ├── local_product_repository.dart
│   ├── local_order_repository.dart
│   ├── local_debt_repository.dart
│   ├── local_user_repository.dart
│   ├── activity_log_repository.dart
│   ├── i_activity_log_repository.dart
│   ├── firestore_sync.dart        # Syncs local data to Firebase Firestore
│   └── sync_queue.dart            # Queues offline writes for retry when online
│
├── services/                      # Business logic layer (interface + implementation)
│   ├── auth_service.dart
│   ├── product_service.dart
│   ├── order_service.dart
│   ├── debt_service.dart
│   ├── export_service.dart        # PDF and CSV export logic
│   └── session_timeout_service.dart
│
├── screens/                       # UI screens (one per feature)
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── otp_screen.dart
│   ├── forgot_password_screen.dart
│   ├── main_shell.dart            # Navigation shell with sidebar
│   ├── overview_screen.dart
│   ├── inventory_screen.dart
│   ├── products_screen.dart
│   ├── orders_screen.dart
│   ├── utang_screen.dart
│   ├── analytics_screen.dart
│   ├── receipt_screen.dart
│   └── recycle_bin_screen.dart    # Soft-deleted items management
│
├── dialogs/                       # Reusable dialog components
│   ├── order_dialog.dart
│   ├── product_dialog.dart
│   ├── edit_stock_dialog.dart
│   ├── mark_as_utang_dialog.dart
│   ├── utang_payment_dialog.dart
│   ├── utang_receipt_printer.dart
│   └── export_dialog.dart         # Export format selection (PDF / CSV)
│
├── widgets/                       # Shared reusable UI widgets
│   ├── shared_widgets.dart
│   └── receipt_shared_widgets.dart
│
├── database/
│   └── database_helper.dart       # SQLite setup and schema migrations
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

`OrderStatus` also uses a **map-based dispatch** instead of switch statements for polymorphic behavior (display names, colors, icons).

### 4. ⚙️ Dependency Inversion Principle (DIP)
`AppState` receives its dependencies through a `configure()` method, making the app testable and modular. Concrete repositories and services are only wired up in `main.dart`, keeping the rest of the codebase decoupled.

---

## 🗄️ Database

- **Local:** SQLite via `sqflite` (primary, offline-first)
- **Cloud:** Firebase Firestore (backup, synced when back online)
- **Schema Version:** 3

### Tables

| Table | Description |
|---|---|
| `users` | Admin accounts |
| `products` | Fragrance product inventory |
| `orders` | Customer orders and order line items |
| `debts` | Customer credit/utang records and payment history |
| `activity_logs` | Audit trail of all admin actions |
| `sync_queue` | Pending Firestore operations queued for retry when offline |

---

## 🎨 UI Design

- **Theme:** Dark mode with a luxury gold accent
- **Color Palette:**

| Role | Hex | Preview |
|---|---|---|
| Background | `#0D0D0D` | ⬛ |
| Surface | `#1A1A1A` | 🟫 |
| Gold (base) | `#B8960C` | 🟡 |
| Gold (main) | `#D4AF37` | 🟡 |
| Gold (light) | `#E8C547` | 🟡 |

- **Typography:** Roboto with wide letter-spacing for a premium feel
- **Component library:** Material Design 3 with a custom dark `ColorScheme`

---

## 📋 Order Statuses

| Status | Color | Description |
|---|---|---|
| Pending | 🟠 Orange | Order placed, not yet processed |
| Processing | 🔵 Blue | Order is being prepared |
| Shipped | 🟣 Purple | Order is on its way |
| Delivered | 🟢 Green | Order successfully delivered |
| Cancelled | 🔴 Red | Order was cancelled |
| Utang | 🟡 Gold | Order marked as credit/debt |

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
| Framework | Flutter (Dart) `>=3.4.0` |
| Local Database | SQLite (`sqflite`) |
| Cloud Database | Firebase Firestore |
| Authentication | Custom + Firebase |
| State Management | `ChangeNotifier` — singleton `AppState` |
| Email / OTP | Brevo API (via `.env`) |
| Environment Config | `flutter_dotenv` |
| Password Hashing | SHA-256 via `crypto` |
| Analytics Charts | `fl_chart` |
| Bluetooth Printing | `flutter_blue_plus` + `esc_pos_utils_plus` |
| Export (PDF) | `pdf` + `printing` + `share_plus` |
| Export (CSV) | `csv` + `share_plus` |
| Crash Reporting | Firebase Crashlytics |

---

## 🧪 Unit Tests

The project includes unit tests covering core business logic:

| Test File | Coverage |
|---|---|
| `app_state_test.dart` | Central state management |
| `auth_appstate_test.dart` | Authentication flows |
| `product_service_test.dart` | Product CRUD and validation |
| `order_service_test.dart` | Order creation and status transitions |
| `debt_service_test.dart` | Utang recording and payment handling |
| `activity_log_test.dart` | Audit log creation |
| `session_timeout_service_test.dart` | Auto-logout after inactivity |

Run all tests with:

```bash
flutter test
```

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `>=3.4.0`
- Android Studio or VS Code with Flutter plugin
- Firebase project with Firestore enabled
- Brevo account (for OTP email verification)
- A Bluetooth ESC/POS thermal printer (optional, for receipt printing)

### Setup

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd knz_scent_admin
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up environment variables**

   Create a `.env` file in the root of the project (see `.env.example`):
   ```env
   BREVO_API_KEY=your_brevo_api_key
   BREVO_SENDER_EMAIL=your_sender_email
   BREVO_SENDER_NAME=KNZ Scent
   ```

4. **Configure Firebase**

   Place your `google-services.json` (Android) and/or `GoogleService-Info.plist` (iOS) in the appropriate platform folders. The `firebase_options.dart` is already generated.

5. **Run the app**
   ```bash
   flutter run
   ```

---

## 👤 Author

**Kennith** — Built as a school project demonstrating the application of **Object-Oriented Programming** principles in a real-world Flutter mobile application.

---

*KNZ Scent — Luxury Fragrance House* 🌸
