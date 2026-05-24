// ─────────────────────────────────────────────────────────────────────────────
// custom_order_model.dart — CustomOrder entity (Feature 5)
// Purpose : Represents a bespoke / custom-perfume agreement between the owner
//           and a customer. Follows the same OOP pattern as other models.
// OOP Pillars:
//   • Inheritance  — extends BaseModel
//   • Encapsulation— private fields, public read-only getters
//   • Polymorphism — toMap() / fromMap() override
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

/// Status lifecycle for a custom perfume order agreement.
enum CustomOrderStatus { pending, inProgress, ready, delivered }

extension CustomOrderStatusExtension on CustomOrderStatus {
  static const _labels = {
    CustomOrderStatus.pending:    'Pending',
    CustomOrderStatus.inProgress: 'In Progress',
    CustomOrderStatus.ready:      'Ready',
    CustomOrderStatus.delivered:  'Delivered',
  };

  static const _storageKeys = {
    CustomOrderStatus.pending:    'Pending',
    CustomOrderStatus.inProgress: 'In Progress',
    CustomOrderStatus.ready:      'Ready',
    CustomOrderStatus.delivered:  'Delivered',
  };

  String get displayName => _labels[this] ?? name;
  String get storageKey  => _storageKeys[this] ?? name;

  static CustomOrderStatus fromString(String? v) {
    return CustomOrderStatus.values.firstWhere(
      (e) => e.storageKey == v,
      orElse: () => CustomOrderStatus.pending,
    );
  }
}

class CustomOrder extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String            _customerName;
  final String?           _contact;
  final String            _fragranceSpecs;
  final double            _agreedPrice;
  final double            _depositPaid;
  final DateTime          _deliveryDate;
  CustomOrderStatus       status;          // Public mutable — changes over lifecycle
  final String?           _terms;
  final String            _userId;
  final DateTime          _createdAt;

  CustomOrder({
    required super.id,
    required String             customerName,
    String?                     contact,
    required String             fragranceSpecs,
    required double             agreedPrice,
    double                      depositPaid    = 0,
    required DateTime           deliveryDate,
    this.status                                = CustomOrderStatus.pending,
    String?                     terms,
    required String             userId,
    required DateTime           createdAt,
  })  : _customerName   = customerName,
        _contact        = contact,
        _fragranceSpecs = fragranceSpecs,
        _agreedPrice    = agreedPrice,
        _depositPaid    = depositPaid,
        _deliveryDate   = deliveryDate,
        _terms          = terms,
        _userId         = userId,
        _createdAt      = createdAt;

  // ── Public read-only getters ──────────────────────────────────────────────
  String            get customerName   => _customerName;
  String?           get contact        => _contact;
  String            get fragranceSpecs => _fragranceSpecs;
  double            get agreedPrice    => _agreedPrice;
  double            get depositPaid    => _depositPaid;
  DateTime          get deliveryDate   => _deliveryDate;
  // status is a public field — no getter/setter wrapper needed
  String?           get terms          => _terms;
  String            get userId         => _userId;
  DateTime          get createdAt      => _createdAt;

  // ── Computed properties ───────────────────────────────────────────────────

  /// Amount the customer still owes after deposit.
  double get balanceDue => _agreedPrice - _depositPaid;

  /// Whether the delivery date has passed and the order is not yet delivered.
  bool get isOverdue =>
      status != CustomOrderStatus.delivered &&
      DateTime.now().isAfter(_deliveryDate);

  // ── Serialization ─────────────────────────────────────────────────────────

  @override
  Map<String, dynamic> toMap() => {
    'id':              id,
    'customer_name':   _customerName,
    'contact':         _contact,
    'fragrance_specs': _fragranceSpecs,
    'agreed_price':    _agreedPrice,
    'deposit_paid':    _depositPaid,
    'delivery_date':   _deliveryDate.toIso8601String(),
    'status':          status.storageKey,
    'terms':           _terms,
    'user_id':         _userId,
    'created_at':      _createdAt.toIso8601String(),
    'is_deleted':      0,
  };

  factory CustomOrder.fromMap(Map<String, dynamic> map) => CustomOrder(
    id:              map['id']              as String? ?? '',
    customerName:    map['customer_name']   as String? ?? '',
    contact:         map['contact']         as String?,
    fragranceSpecs:  map['fragrance_specs'] as String? ?? '',
    agreedPrice:     (map['agreed_price']   as num?)?.toDouble() ?? 0,
    depositPaid:     (map['deposit_paid']   as num?)?.toDouble() ?? 0,
    deliveryDate:    map['delivery_date'] != null
        ? DateTime.tryParse(map['delivery_date'] as String) ?? DateTime.now()
        : DateTime.now(),
    status:          CustomOrderStatusExtension.fromString(map['status'] as String?),
    terms:           map['terms']           as String?,
    userId:          map['user_id']         as String? ?? '',
    createdAt:       map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  /// Returns a new CustomOrder with only the specified fields changed.
  CustomOrder copyWith({
    String?            customerName,
    String?            contact,
    String?            fragranceSpecs,
    double?            agreedPrice,
    double?            depositPaid,
    DateTime?          deliveryDate,
    CustomOrderStatus? status,
    String?            terms,
  }) => CustomOrder(
    id:             id,
    customerName:   customerName   ?? _customerName,
    contact:        contact        ?? _contact,
    fragranceSpecs: fragranceSpecs ?? _fragranceSpecs,
    agreedPrice:    agreedPrice    ?? _agreedPrice,
    depositPaid:    depositPaid    ?? _depositPaid,
    deliveryDate:   deliveryDate   ?? _deliveryDate,
    status:         status         ?? this.status,
    terms:          terms          ?? _terms,
    userId:         _userId,
    createdAt:      _createdAt,
  );
}