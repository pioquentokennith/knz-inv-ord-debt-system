# KNZ Scent Admin — Fix Checklist

All 6 fixes from the guide are applied. Follow the steps below to drop the files into your project.

---

## Step 1 — Copy Files Into Your Project

Replace/create each file in your project with the version in this folder:

| File in this folder | Destination in your project | Fix |
|---|---|---|
| `pubspec.yaml` | `pubspec.yaml` (project root) | 1 & 2 |
| `.env` | `.env` (project root) | 1 |
| `.env.example` | `.env.example` (project root) | 1 |
| `.gitignore` | `.gitignore` (project root) | 1 |
| `lib/main.dart` | `lib/main.dart` | 1 |
| `lib/screens/otp_screen.dart` | `lib/screens/otp_screen.dart` | 1 |
| `lib/repositories/local_user_repository.dart` | `lib/repositories/local_user_repository.dart` | 2 |
| `lib/repositories/local_product_repository.dart` | `lib/repositories/local_product_repository.dart` | 3 |
| `lib/core/app_state.dart` | `lib/core/app_state.dart` | 4 |
| `lib/core/app_state_builder.dart` | `lib/core/app_state_builder.dart` (NEW FILE) | 6 |
| `lib/screens/orders_screen.dart` | `lib/screens/orders_screen.dart` | 6 |
| `lib/dialogs/utang_payment_dialog.dart` | `lib/dialogs/utang_payment_dialog.dart` (NEW FILE) | 5 |
| `lib/dialogs/mark_as_utang_dialog.dart` | `lib/dialogs/mark_as_utang_dialog.dart` (NEW FILE) | 5 |
| `lib/dialogs/utang_receipt_printer.dart` | `lib/dialogs/utang_receipt_printer.dart` (NEW FILE) | 5 |

---

## Step 2 — Run pub get

```bash
flutter pub get
```

---

## Step 3 — Regenerate Your Brevo API Key (CRITICAL)

The old key was exposed in source code. Go to:
> https://app.brevo.com → Settings → API Keys → Delete old key → Create new key

Then update `.env` with your new key:
```
BREVO_API_KEY=your_new_key_here
```

---

## Step 4 — Fix 5: Update utang_screen.dart

After copying the 3 new dialog files, open `lib/screens/utang_screen.dart` and:

1. Add these imports at the top:
```dart
import '../dialogs/utang_payment_dialog.dart';
import '../dialogs/mark_as_utang_dialog.dart';
import '../dialogs/utang_receipt_printer.dart';
```

2. Remove the old class definitions: `_PaymentDialog`, `_MethodBtn`, `MarkAsUtangDialog`, `_UtangPrintScreen`, `_UtangReceiptPreview`, `_UtangInfoRow`, `_UtangBtPrintPanel`, `_BtState`

3. Update calls:
```dart
// In _showPaymentDialog:
showDialog(context: context, builder: (_) => UtangPaymentDialog(debt: debt));

// In _showUtangReceipt:
UtangReceiptScreen.show(context, debt);
```

---

## Step 5 — Fix 6: Apply AppStateBuilder to Remaining Screens

Apply the `AppStateBuilder` pattern (see `orders_screen.dart` as the example) to:
- `inventory_screen.dart`
- `products_screen.dart`
- `analytics_screen.dart`
- `overview_screen.dart`
- `utang_screen.dart`

In each: remove `_state`, `addListener`, `removeListener`, and `_onStateChange`. Wrap the list/chart widgets with `AppStateBuilder`.

---

## Fix 4 — Wire Up onError in OrderDialog

In `lib/dialogs/order_dialog.dart`, update the `addOrder` call:

```dart
final ok = await AppState().addOrder(order, onError: (msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.error,
      content: Text(msg, style: const TextStyle(color: AppColors.white)),
    ),
  );
});

if (!ok || !mounted) return;
Navigator.pop(context);
```

---

## Warning — Password Migration

Fix 2 hashes all passwords. **Existing users cannot log in** with the old plain-text password.
Ask them to use **Forgot Password** to reset — that will save the new hashed version.
