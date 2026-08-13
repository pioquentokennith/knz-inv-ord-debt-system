// ─────────────────────────────────────────────────────────────────────────────
// payment_method_model.dart — PaymentMethod enum and extension
// Purpose : Defines the supported payment methods for an order.
//           Extension adds display name, icon, and serialization helpers
//           so switch blocks are replaced with map-based dispatch (Polymorphism).
// OOP Pillars:
//   • Encapsulation — internal maps are private; only getters are public
//   • Polymorphism  — map-based dispatch instead of switch blocks
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// All supported payment methods for a KNZ Scent order.
enum PaymentMethod {
  creditDebitCard, // Visa / Mastercard / etc.
  gcash, // GCash e-wallet
  maya, // Maya (formerly PayMaya) e-wallet
  cashOnDelivery, // COD — no digital reference
  utang, // Utang / Credit — customer owes payment
}

extension PaymentMethodExtension on PaymentMethod {
  // ── Map-based dispatch (Polymorphism) ────────────────────────────────────
  static const _displayNames = {
    PaymentMethod.creditDebitCard: 'Credit / Debit Card',
    PaymentMethod.gcash: 'GCash',
    PaymentMethod.maya: 'Maya',
    PaymentMethod.cashOnDelivery: 'Cash on Delivery',
    PaymentMethod.utang: 'Utang (Credit)',
  };

  static const _icons = {
    PaymentMethod.creditDebitCard: Icons.credit_card_outlined,
    PaymentMethod.gcash: Icons.account_balance_wallet_outlined,
    PaymentMethod.maya: Icons.payment_outlined,
    PaymentMethod.cashOnDelivery: Icons.local_shipping_outlined,
    PaymentMethod.utang: Icons.receipt_long_outlined,
  };

  // Stored value in SQLite / Firestore — stable snake_case string
  static const _storageKeys = {
    PaymentMethod.creditDebitCard: 'credit_debit_card',
    PaymentMethod.gcash: 'gcash',
    PaymentMethod.maya: 'maya',
    PaymentMethod.cashOnDelivery: 'cash_on_delivery',
    PaymentMethod.utang: 'utang',
  };

  /// Human-readable name for display in UI widgets.
  String get displayName => _displayNames[this] ?? name;

  /// Icon used in receipts, order cards, and the payment selector.
  IconData get icon => _icons[this] ?? Icons.payments_outlined;

  /// Stable string key used when persisting to SQLite or Firestore.
  String get storageKey => _storageKeys[this] ?? name;

  /// Whether this payment method collects a reference number / masked account.
  bool get requiresReference =>
      this == PaymentMethod.creditDebitCard ||
      this == PaymentMethod.gcash ||
      this == PaymentMethod.maya;

  /// Placeholder hint text for the reference field.
  String get referenceHint {
    switch (this) {
      case PaymentMethod.creditDebitCard:
        return 'Last 4 digits (e.g. 4321)';
      case PaymentMethod.gcash:
        return 'Masked number (e.g. 0917***890)';
      case PaymentMethod.maya:
        return 'Masked number (e.g. 0998***012)';
      default:
        return '';
    }
  }

  /// Parses a stored string back to the enum; defaults to cashOnDelivery on unknown.
  static PaymentMethod fromString(String? value) {
    if (value == null) return PaymentMethod.cashOnDelivery;
    return PaymentMethod.values.firstWhere(
      (e) => e.storageKey == value,
      orElse: () => PaymentMethod.cashOnDelivery,
    );
  }
}
