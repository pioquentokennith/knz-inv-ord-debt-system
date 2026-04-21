// ─────────────────────────────────────────────────────────────────────────────
// debt_model.dart — Utang / credit system data models
// Purpose : Represents a customer's outstanding debt (utang) and the individual
//           payment installments made toward that debt.
// Demonstrates: Inheritance (extends BaseModel), Encapsulation (private fields
// with getters), validated setter for amountPaid.
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

/// A single payment installment made by a customer toward their debt.
class PaymentRecord extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final double   _amount;
  final DateTime _paidAt;
  final String?  _note; // Optional note from the collector (e.g. "GCash transfer")

  PaymentRecord({
    required super.id,
    required double   amount,
    required DateTime paidAt,
    String?           note,
  })  : _amount = amount,
        _paidAt = paidAt,
        _note   = note;

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  double   get amount => _amount;
  DateTime get paidAt => _paidAt;
  String?  get note   => _note;

  // Serializes to a map for the SQLite payments table or Firestore array element
  @override
  Map<String, dynamic> toMap() => {
    'id':     id,
    'amount': _amount,
    'paidAt': _paidAt.toIso8601String(),
    'note':   _note,
  };

  // Deserializes a map back into a PaymentRecord
  factory PaymentRecord.fromMap(Map<String, dynamic> map) => PaymentRecord(
    id:     map['id']     as String? ?? '',
    amount: (map['amount'] as num?)?.toDouble() ?? 0,
    paidAt: DateTime.tryParse(map['paidAt'] as String? ?? '') ?? DateTime.now(),
    note:   map['note']   as String?,
  );
}

/// Tracks one customer's total debt linked to a specific order.
/// Accumulates payment installments via [amountPaid] until the balance is zero.
class CustomerDebt extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String              _customerName;
  final String              _orderId;      // Links the debt back to the originating order
  final double              _totalAmount;  // Fixed — the original debt amount
  double                    _amountPaid;   // Running total of all payments received
  final DateTime            _createdAt;
  final List<PaymentRecord> _payments;     // History of all installment payments

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

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String              get customerName => _customerName;
  String              get orderId      => _orderId;
  double              get totalAmount  => _totalAmount;
  double              get amountPaid   => _amountPaid;
  DateTime            get createdAt    => _createdAt;
  // Unmodifiable view — external code cannot add/remove payments directly
  List<PaymentRecord> get payments     => List.unmodifiable(_payments);

  // ── Validated setter — prevents amountPaid from going negative ────────────
  set amountPaid(double value) {
    if (value < 0) throw ArgumentError('Amount paid cannot be negative.');
    _amountPaid = value;
  }

  // ── Computed properties ───────────────────────────────────────────────────

  // How much the customer still owes (totalAmount minus all payments made)
  double get remainingBalance => _totalAmount - _amountPaid;

  // True when the debt is fully settled
  bool   get isPaid           => remainingBalance <= 0;

  // True when unpaid and more than 7 days old — triggers overdue badge in UI
  bool   get isOverdue        => !isPaid && DateTime.now().difference(_createdAt).inDays >= 7;

  // Number of calendar days since the debt was created
  int    get daysOld          => DateTime.now().difference(_createdAt).inDays;

  // Serializes to a map with a nested payments list for Firestore
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

  // Deserializes a map back into a CustomerDebt with its full payment history
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
