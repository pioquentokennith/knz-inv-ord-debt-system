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

class Reseller extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String  _name;
  final String? _contact;         // Phone / address — optional
  final double  _deductionPerItem; // Fixed peso minus per item (e.g. 20 = −₱20 per item)
  final String  _userId;           // Owner partition key (multi-user support)
  final DateTime _createdAt;

  Reseller({
    required super.id,
    required String  name,
    String?          contact,
    required double  deductionPerItem,
    required String  userId,
    required DateTime createdAt,
  })  : _name            = name,
        _contact         = contact,
        _deductionPerItem = deductionPerItem,
        _userId          = userId,
        _createdAt       = createdAt;

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String   get name             => _name;
  String?  get contact          => _contact;
  double   get deductionPerItem => _deductionPerItem;
  String   get userId           => _userId;
  DateTime get createdAt        => _createdAt;

  /// Computes the selling price for a given SRP by subtracting the fixed peso deduction.
  double discountedPrice(double srp) => (srp - _deductionPerItem).clamp(0.0, srp);

  /// User-friendly label shown in dropdown / receipt.
  String get label =>
      '$_name (−₱${_deductionPerItem.toStringAsFixed(0)}/item)';

  // Returns a new Reseller with only specified fields changed (immutable update)
  Reseller copyWith({
    String?  name,
    String?  contact,
    double?  deductionPerItem,
  }) {
    return Reseller(
      id:               id,
      name:             name             ?? _name,
      contact:          contact          ?? _contact,
      deductionPerItem: deductionPerItem ?? _deductionPerItem,
      userId:           _userId,
      createdAt:        _createdAt,
    );
  }

  // Serializes to SQLite column map + Firestore payload
  // DB column stays 'discount_percent' for backward compat with existing rows
  @override
  Map<String, dynamic> toMap() => {
    'id':               id,
    'name':             _name,
    'contact':          _contact,
    'discount_percent': _deductionPerItem,  // DB column unchanged for compat
    'user_id':          _userId,
    'created_at':       _createdAt.toIso8601String(),
    'is_deleted':       0,
  };

  // Deserializes from SQLite query row or Firestore document
  factory Reseller.fromMap(Map<String, dynamic> map) => Reseller(
    id:               map['id']               as String? ?? '',
    name:             map['name']             as String? ?? '',
    contact:          map['contact']          as String?,
    deductionPerItem: (map['discount_percent'] as num?)?.toDouble() ?? 0,
    userId:           map['user_id']          as String? ?? '',
    createdAt:        map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
