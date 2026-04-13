# 🌸 KNZ Scent — Admin Portal

> A Flutter-based mobile admin application for managing a luxury fragrance business. Built with an offline-first architecture, real-time cloud sync, and a clean dark/gold UI theme.

---

## 📱 Overview

**KNZ Scent Admin** is a business management system designed for a small fragrance business. It allows administrators to manage products, track orders, monitor inventory, handle customer debts (*utang*), and view sales analytics — all from a mobile device, even without an internet connection.

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔐 **Authentication** | Secure login, registration, OTP verification, and password reset |
| 📦 **Inventory Management** | Add, edit, and track stock levels with low-stock alerts |
| 🛒 **Order Management** | Create and track orders with statuses: Pending, Processing, Shipped, Delivered, Cancelled |
| 💸 **Utang (Credit) System** | Record customer debts, accept partial payments, and print debt receipts |
| 📊 **Analytics Dashboard** | Visual sales reports, revenue trends, and product performance |
| 🗂️ **Product Catalog** | Manage fragrance products with categories, pricing, and images |
| 📋 **Activity Logs** | Track all admin actions for auditing |
| 🔄 **Offline-First Sync** | Works without internet; auto-syncs to Firebase Firestore when online |

---

## 🏗️ Architecture

This project follows a **layered architecture** with clear separation of concerns:

```
lib/
├── core/               # App-wide constants, colors, text styles, and state management
│   ├── app_constants.dart
│   ├── app_state.dart          # Singleton ChangeNotifier — central state
│   └── app_state_builder.dart
│
├── models/             # Data entities (all extend BaseModel)
│   ├── base_model.dart
│   ├── product_model.dart
│   ├── order_model.dart
│   ├── debt_model.dart
│   └── user_model.dart
│
├── repositories/       # Data access layer (local SQLite + Firestore sync)
│   ├── local_product_repository.dart
│   ├── local_order_repository.dart
│   ├── local_debt_repository.dart
│   ├── local_user_repository.dart
│   ├── firestore_sync.dart
│   ├── sync_queue.dart         # Queues offline writes for retry
│   └── activity_log_repository.dart
│
├── services/           # Business logic layer (interface + implementation)
│   ├── auth_service.dart
│   ├── product_service.dart
│   ├── order_service.dart
│   └── debt_service.dart
│
├── screens/            # UI screens (one per feature)
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── otp_screen.dart
│   ├── forgot_password_screen.dart
│   ├── main_shell.dart         # Navigation shell (sidebar)
│   ├── overview_screen.dart
│   ├── inventory_screen.dart
│   ├── products_screen.dart
│   ├── orders_screen.dart
│   ├── utang_screen.dart
│   ├── analytics_screen.dart
│   └── receipt_screen.dart
│
├── dialogs/            # Reusable dialog components
│   ├── order_dialog.dart
│   ├── product_dialog.dart
│   ├── edit_stock_dialog.dart
│   ├── mark_as_utang_dialog.dart
│   ├── utang_payment_dialog.dart
│   └── utang_receipt_printer.dart
│
├── widgets/            # Shared reusable UI widgets
│   └── shared_widgets.dart
│
├── database/
│   └── database_helper.dart    # SQLite setup and migrations
│
├── firebase_options.dart
└── main.dart
```

---

## 🧠 OOP Concepts Applied

This project was built with core **Object-Oriented Programming** principles in mind:

### 1. 🔒 Encapsulation
All model classes (`Product`, `Order`, `CustomerDebt`, etc.) use **private fields** with public **getters** to protect data integrity. Mutable properties like `stockQty` and `amountPaid` have **validated setters**.

```dart
// Example from product_model.dart
int get stockQty => _stockQty;
set stockQty(int value) {
  if (value < 0) throw ArgumentError('Stock cannot be negative');
  _stockQty = value;
}
```

### 2. 🧬 Inheritance
All models extend `BaseModel`, which provides a shared `id` field and an abstract `toMap()` method.

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
Services are defined as **abstract interfaces** (`IAuthService`, `IProductService`, etc.) and implemented by concrete classes. This allows easy **mocking for testing** and swapping of implementations.

```dart
// AppState depends on interfaces, not concrete classes
IProductService _productService;
IOrderService   _orderService;
IDebtService    _debtService;
IAuthService    _authService;
```

`OrderStatus` also uses a **map-based dispatch** instead of switch statements for polymorphic behavior (display names, colors, icons).

### 4. ⚙️ Dependency Inversion Principle (DIP)
`AppState` receives its dependencies through `configure()`, making the app testable and modular. Concrete repos and services are only wired up in `main.dart`.

---

## 🗄️ Database

- **Local:** SQLite via `sqflite` (primary, offline-first)
- **Cloud:** Firebase Firestore (backup, synced when online)
- **Schema Version:** 3 (includes `sync_queue` table for offline write retries)

### Tables
- `users` — Admin accounts
- `products` — Fragrance inventory
- `orders` — Customer orders and order items
- `debts` — Customer credit/utang records and payment history
- `activity_logs` — Audit trail of all admin actions
- `sync_queue` — Pending Firestore sync operations

---

## 🎨 UI Design

- **Theme:** Dark mode with a luxury gold (`#D4AF37`) accent
- **Color Palette:**
  - Background: `#0D0D0D`
  - Surface: `#1A1A1A`
  - Gold Gradient: `#B8960C → #D4AF37 → #E8C547`
- **Typography:** Roboto with wide letter-spacing for a premium feel
- **Material Design 3** with custom dark `ColorScheme`

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Local Database | SQLite (`sqflite`) |
| Cloud Database | Firebase Firestore |
| Authentication | Custom + Firebase |
| State Management | `ChangeNotifier` (singleton `AppState`) |
| Email (OTP) | Brevo API (via `.env`) |
| Environment Config | `flutter_dotenv` |

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (≥ 3.x)
- Firebase project set up with Firestore enabled
- Brevo account (for OTP email verification)

### Setup

1. **Clone the repository**
   ```bash
   git clone <your-repo-url>
   cd knz_scent
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Set up environment variables**

   Create a `.env` file in the root of the project:
   ```env
   BREVO_API_KEY=your_brevo_api_key
   BREVO_SENDER_EMAIL=your_sender_email
   BREVO_SENDER_NAME=KNZ Scent
   ```

4. **Configure Firebase**

   Place your `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) in the appropriate platform folders. The `firebase_options.dart` is already generated.

5. **Run the app**
   ```bash
   flutter run
   ```

---

## 📂 Product Categories

The app supports the following fragrance product categories:
- Eau de Parfum
- Eau de Toilette
- Body Mist
- Perfume Oil
- Gift Set

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

## 👤 Author

Built as a school project demonstrating the application of **Object-Oriented Programming** principles in a real-world Flutter mobile application.

---

> *"KNZ Scent — Luxury Fragrance House"* 🌸
