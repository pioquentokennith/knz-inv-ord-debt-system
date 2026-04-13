// ─────────────────────────────────────────────────────────────────────────────
// debt_model.dart — Utang / Credit system data models
// Demonstrates: Inheritance (extends BaseModel), Encapsulation (private fields
// with getters), Setter with validation for amountPaid.
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

/// A single payment made by a customer toward their debt.
class PaymentRecord extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final double   _amount;
  final DateTime _paidAt;
  final String?  _note;

  // super.id — Dart super-parameter syntax (fixes use_super_parameters lint)
  PaymentRecord({
    required super.id,
    required double   amount,
    required DateTime paidAt,
    String?           note,
  })  : _amount = amount,
        _paidAt = paidAt,
        _note   = note;

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  double   get amount => _amount;
  DateTime get paidAt => _paidAt;
  String?  get note   => _note;

  @override
  Map<String, dynamic> toMap() => {
    'id':     id,
    'amount': _amount,
    'paidAt': _paidAt.toIso8601String(),
    'note':   _note,
  };

  factory PaymentRecord.fromMap(Map<String, dynamic> map) => PaymentRecord(
    id:     map['id']     as String? ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0,
    paidAt: DateTime.tryParse(map['paidAt'] as String? ?? '') ?? DateTime.now(),
    note:   map['note']   as String?,
  );
}

/// Tracks one customer's total debt linked to a specific order.
class CustomerDebt extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String              _customerName;
  final String              _orderId;
  final double              _totalAmount;
  double                    _amountPaid;
  final DateTime            _createdAt;
  final List<PaymentRecord> _payments;

  // super.id — Dart super-parameter syntax (fixes use_super_parameters lint)
  CustomerDebt({
    required super.id,
    required String               customerName,
    required String               orderId,
    required double               totalAmount,
    required double               amountPaid,
    required DateTime             createdAt,
    List<PaymentRecord>?          payments,
  })  : _customerName = customerName,
        _orderId      = orderId,
        _totalAmount  = totalAmount,
        _amountPaid   = amountPaid,
        _createdAt    = createdAt,
        _payments     = payments ?? [];

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  String              get customerName => _customerName;
  String              get orderId      => _orderId;
  double              get totalAmount  => _totalAmount;
  double              get amountPaid   => _amountPaid;
  DateTime            get createdAt    => _createdAt;
  List<PaymentRecord> get payments     => List.unmodifiable(_payments);

  // ── Validated setter (Encapsulation) ─────────────────────────────────────
  set amountPaid(double value) {
    if (value < 0) throw ArgumentError('Amount paid cannot be negative.');
    _amountPaid = value;
  }

  // ── Computed getters ──────────────────────────────────────────────────────
  double get remainingBalance => _totalAmount - _amountPaid;
  bool   get isPaid           => remainingBalance <= 0;
  bool   get isOverdue        => !isPaid && DateTime.now().difference(_createdAt).inDays >= 7;
  int    get daysOld          => DateTime.now().difference(_createdAt).inDays;

  @override
  Map<String, dynamic> toMap() => {
    'id':           id,
    'customerName': _customerName,
    'orderId':      _orderId,
    'totalAmount':  _totalAmount,
    'amountPaid':   _amountPaid,
    'createdAt':    _createdAt.toIso8601String(),
    'payments':     _payments.map((p) => p.toMap()).toList(),
  };

  factory CustomerDebt.fromMap(Map<String, dynamic> map) => CustomerDebt(
    id:           map['id']           as String? ?? '',
    customerName: map['customerName'] as String? ?? '',
    orderId:      map['orderId']      as String? ?? '',
    totalAmount:  (map['totalAmount'] as num?)?.toDouble() ?? 0,
    amountPaid:   (map['amountPaid']  as num?)?.toDouble() ?? 0,
    createdAt:    DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    payments:     (map['payments'] as List? ?? [])
        .map((p) => PaymentRecord.fromMap(p as Map<String, dynamic>))
        .toList(),
  );
}
