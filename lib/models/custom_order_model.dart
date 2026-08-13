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
import '../core/money.dart';

/// Status lifecycle for a custom perfume order agreement.
enum CustomOrderStatus { pending, inProgress, ready, delivered, cancelled }

extension CustomOrderStatusExtension on CustomOrderStatus {
  static const _labels = {
    CustomOrderStatus.pending: 'Pending',
    CustomOrderStatus.inProgress: 'In Progress',
    CustomOrderStatus.ready: 'Ready',
    CustomOrderStatus.delivered: 'Delivered',
    CustomOrderStatus.cancelled: 'Cancelled',
  };

  static const _storageKeys = {
    CustomOrderStatus.pending: 'Pending',
    CustomOrderStatus.inProgress: 'In Progress',
    CustomOrderStatus.ready: 'Ready',
    CustomOrderStatus.delivered: 'Delivered',
    CustomOrderStatus.cancelled: 'Cancelled',
  };

  String get displayName => _labels[this] ?? name;
  String get storageKey => _storageKeys[this] ?? name;

  static CustomOrderStatus fromString(String? v) {
    return CustomOrderStatus.values.firstWhere(
      (e) => e.storageKey == v,
      orElse: () => CustomOrderStatus.pending,
    );
  }
}

/// One immutable receipt in a custom order's payment ledger.
///
/// Payments are intentionally separate from [CustomOrder] so the editable
/// agreement cannot rewrite how much a customer has already paid.
class CustomOrderPayment {
  final String id;
  final String customOrderId;
  final Money amount;
  final DateTime paidAt;
  final String? note;

  CustomOrderPayment({
    required this.id,
    required this.customOrderId,
    required this.amount,
    required this.paidAt,
    String? note,
  }) : note = note == null || note.trim().isEmpty ? null : note.trim() {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Payment id cannot be blank.');
    }
    if (customOrderId.trim().isEmpty) {
      throw ArgumentError.value(
        customOrderId,
        'customOrderId',
        'Custom order id cannot be blank.',
      );
    }
    if (!amount.isPositive) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Payment amount must be greater than zero.',
      );
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'custom_order_id': customOrderId,
    'amount_centavos': amount.centavos,
    'paid_at': paidAt.toIso8601String(),
    'note': note,
  };

  factory CustomOrderPayment.fromMap(Map<String, dynamic> map) =>
      CustomOrderPayment(
        id: map['id'] as String? ?? '',
        customOrderId: map['custom_order_id'] as String? ?? '',
        amount: Money.fromCentavos(map['amount_centavos'] as int? ?? 0),
        paidAt: map['paid_at'] != null
            ? DateTime.tryParse(map['paid_at'] as String) ?? DateTime.now()
            : DateTime.now(),
        note: map['note'] as String?,
      );
}

class CustomOrder extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _customerName;
  final String? _contact;
  final String _fragranceSpecs;
  final Money _agreedPrice;
  final Money _depositPaid;
  final List<CustomOrderPayment> _payments;
  final DateTime _deliveryDate;
  CustomOrderStatus status; // Public mutable — changes over lifecycle
  final String? _terms;
  final String _userId;
  final DateTime _createdAt;

  CustomOrder({
    required super.id,
    required String customerName,
    String? contact,
    required String fragranceSpecs,
    required Money agreedPrice,
    Money depositPaid = Money.zero,
    List<CustomOrderPayment> payments = const [],
    required DateTime deliveryDate,
    this.status = CustomOrderStatus.pending,
    String? terms,
    required String userId,
    required DateTime createdAt,
  }) : _customerName = customerName,
       _contact = contact,
       _fragranceSpecs = fragranceSpecs,
       _agreedPrice = agreedPrice,
       _depositPaid = depositPaid,
       _payments = List.unmodifiable(payments),
       _deliveryDate = deliveryDate,
       _terms = terms,
       _userId = userId,
       _createdAt = createdAt {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Custom order id cannot be blank.');
    }
    if (_customerName.trim().isEmpty) {
      throw ArgumentError.value(
        customerName,
        'customerName',
        'Customer name cannot be blank.',
      );
    }
    if (_fragranceSpecs.trim().isEmpty) {
      throw ArgumentError.value(
        fragranceSpecs,
        'fragranceSpecs',
        'Fragrance specifications cannot be blank.',
      );
    }
    if (_userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id cannot be blank.');
    }
    if (_agreedPrice.isNegative) {
      throw ArgumentError.value(
        agreedPrice,
        'agreedPrice',
        'Agreed price must be non-negative.',
      );
    }
    if (_depositPaid.isNegative) {
      throw ArgumentError.value(
        depositPaid,
        'depositPaid',
        'Deposit must be non-negative.',
      );
    }
    final paymentIds = <String>{};
    final recordedTotal = _payments.fold<Money>(Money.zero, (total, payment) {
      if (payment.customOrderId != id) {
        throw ArgumentError.value(
          payment.customOrderId,
          'payments',
          'Every payment must belong to this custom order.',
        );
      }
      if (!paymentIds.add(payment.id)) {
        throw ArgumentError.value(
          payment.id,
          'payments',
          'Payment ids must be unique.',
        );
      }
      return total + payment.amount;
    });
    if (recordedTotal > _depositPaid) {
      throw ArgumentError.value(
        depositPaid,
        'depositPaid',
        'Payment ledger cannot exceed the stored amount paid.',
      );
    }
    if (depositPaid.compareTo(_agreedPrice) > 0) {
      throw ArgumentError.value(
        depositPaid,
        'depositPaid',
        'Deposit cannot exceed the agreed price.',
      );
    }
  }

  // ── Public read-only getters ──────────────────────────────────────────────
  String get customerName => _customerName;
  String? get contact => _contact;
  String get fragranceSpecs => _fragranceSpecs;
  Money get agreedPrice => _agreedPrice;

  Money get depositPaid => _depositPaid;
  Money get unattributedPaymentAmount =>
      _depositPaid -
      _payments.fold<Money>(
        Money.zero,
        (total, payment) => total + payment.amount,
      );
  List<CustomOrderPayment> get payments => _payments;
  DateTime get deliveryDate => _deliveryDate;
  // status is a public field — no getter/setter wrapper needed
  String? get terms => _terms;
  String get userId => _userId;
  DateTime get createdAt => _createdAt;

  // ── Computed properties ───────────────────────────────────────────────────

  /// Amount the customer still owes after deposit.
  Money get balanceDue => _agreedPrice - depositPaid;

  /// Whether the delivery date has passed and the order is not yet delivered.
  bool get isOverdue =>
      status != CustomOrderStatus.delivered &&
      DateTime.now().isAfter(_deliveryDate);

  // ── Serialization ─────────────────────────────────────────────────────────

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_name': _customerName,
    'contact': _contact,
    'fragrance_specs': _fragranceSpecs,
    'agreed_price_centavos': _agreedPrice.centavos,
    'deposit_paid_centavos': depositPaid.centavos,
    'delivery_date': _deliveryDate.toIso8601String(),
    'status': status.storageKey,
    'terms': _terms,
    'user_id': _userId,
    'created_at': _createdAt.toIso8601String(),
    'is_deleted': 0,
  };

  factory CustomOrder.fromMap(Map<String, dynamic> map) => CustomOrder(
    id: map['id'] as String? ?? '',
    customerName: map['customer_name'] as String? ?? '',
    contact: map['contact'] as String?,
    fragranceSpecs: map['fragrance_specs'] as String? ?? '',
    agreedPrice: Money.fromCentavos(map['agreed_price_centavos'] as int? ?? 0),
    depositPaid: Money.fromCentavos(map['deposit_paid_centavos'] as int? ?? 0),
    deliveryDate: map['delivery_date'] != null
        ? DateTime.tryParse(map['delivery_date'] as String) ?? DateTime.now()
        : DateTime.now(),
    status: CustomOrderStatusExtension.fromString(map['status'] as String?),
    terms: map['terms'] as String?,
    userId: map['user_id'] as String? ?? '',
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  /// Returns a new CustomOrder with only the specified fields changed.
  CustomOrder copyWith({
    String? customerName,
    String? contact,
    String? fragranceSpecs,
    Money? agreedPrice,
    Money? depositPaid,
    List<CustomOrderPayment>? payments,
    DateTime? deliveryDate,
    CustomOrderStatus? status,
    String? terms,
  }) => CustomOrder(
    id: id,
    customerName: customerName ?? _customerName,
    contact: contact ?? _contact,
    fragranceSpecs: fragranceSpecs ?? _fragranceSpecs,
    agreedPrice: agreedPrice ?? _agreedPrice,
    depositPaid: depositPaid ?? _depositPaid,
    payments: payments ?? _payments,
    deliveryDate: deliveryDate ?? _deliveryDate,
    status: status ?? this.status,
    terms: terms ?? _terms,
    userId: _userId,
    createdAt: _createdAt,
  );
}
