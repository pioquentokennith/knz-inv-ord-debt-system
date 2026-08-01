// ─────────────────────────────────────────────────────────────────────────────
// reseller_model.dart — Reseller entity
// Purpose : Represents a reseller customer who receives a fixed peso deduction
//           (minus per item) on all their orders.
// OOP Pillars:
//   • Inheritance   — extends BaseModel for id equality + serialization contract
//   • Encapsulation — private fields; public read-only getters
//   • Polymorphism  — toMap() overrides BaseModel's abstract method
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';
import '../core/money.dart';

class Reseller extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _name;
  final String? _contact; // Phone / address — optional
  final Money
  _deductionPerItem; // Fixed peso minus per item (e.g. 20 = −₱20 per item)
  final String _userId; // Owner partition key (multi-user support)
  final DateTime _createdAt;

  Reseller({
    required super.id,
    required String name,
    String? contact,
    required Money deductionPerItem,
    required String userId,
    required DateTime createdAt,
  }) : _name = name,
       _contact = contact,
       _deductionPerItem = deductionPerItem,
       _userId = userId,
       _createdAt = createdAt {
    if (this.id.trim().isEmpty) {
      throw ArgumentError.value(this.id, 'id', 'Reseller id cannot be blank.');
    }
    if (_name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Reseller name cannot be blank.');
    }
    if (_userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id cannot be blank.');
    }
    if (_deductionPerItem.isNegative) {
      throw ArgumentError.value(
        deductionPerItem,
        'deductionPerItem',
        'Deduction must be non-negative.',
      );
    }
  }

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get name => _name;
  String? get contact => _contact;
  Money get deductionPerItem => _deductionPerItem;
  String get userId => _userId;
  DateTime get createdAt => _createdAt;

  /// Computes the selling price for a given SRP by subtracting the fixed peso deduction.
  Money discountedPrice(Money srp) {
    if (srp.isNegative) throw ArgumentError.value(srp, 'srp');
    return (srp - _deductionPerItem).max(Money.zero).min(srp);
  }

  /// User-friendly label shown in dropdown / receipt.
  String get label => '$_name (−₱${_deductionPerItem.toStringAsFixed(0)}/item)';

  // Returns a new Reseller with only specified fields changed (immutable update)
  Reseller copyWith({String? name, String? contact, Money? deductionPerItem}) {
    return Reseller(
      id: id,
      name: name ?? _name,
      contact: contact ?? _contact,
      deductionPerItem: deductionPerItem ?? _deductionPerItem,
      userId: _userId,
      createdAt: _createdAt,
    );
  }

  // Serializes to the centavo SQLite and Firestore contract.
  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': _name,
    'contact': _contact,
    'deduction_per_item_centavos': _deductionPerItem.centavos,
    'user_id': _userId,
    'created_at': _createdAt.toIso8601String(),
    'is_deleted': 0,
  };

  // Deserializes from SQLite query row or Firestore document
  factory Reseller.fromMap(Map<String, dynamic> map) => Reseller(
    id: map['id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    contact: map['contact'] as String?,
    deductionPerItem: Money.fromCentavos(
      map['deduction_per_item_centavos'] as int? ?? 0,
    ),
    userId: map['user_id'] as String? ?? '',
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
