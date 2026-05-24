// ─────────────────────────────────────────────────────────────────────────────
// debt_model.dart — Utang / credit system data models  (v6: interest fields)
// OOP Pillars: Inheritance, Encapsulation, validated setter.
// v6 additions:
//   • interestRate       — annual-equivalent percentage stored on the debt
//   • interestType       — 'none' | 'daily' | 'monthly'
//   • interestStartDate  — when accrual begins (defaults to createdAt)
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

/// A single payment installment made by a customer toward their debt.
class PaymentRecord extends BaseModel {
  final double   _amount;
  final DateTime _paidAt;
  final String?  _note;

  PaymentRecord({
    required super.id,
    required double   amount,
    required DateTime paidAt,
    String?           note,
  })  : _amount = amount,
        _paidAt = paidAt,
        _note   = note;

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
/// v6: adds interest rate, type, and start-date fields.
class CustomerDebt extends BaseModel {
  final String              _customerName;
  final String              _orderId;
  final double              _totalAmount;
  double                    _amountPaid;
  final DateTime            _createdAt;
  final List<PaymentRecord> _payments;

  // ── v6: interest fields ────────────────────────────────────────────────────
  final double    _interestRate;       // e.g. 2 = 2% per period
  final String    _interestType;       // 'none' | 'daily' | 'monthly'
  final DateTime? _interestStartDate;  // null = use createdAt

  CustomerDebt({
    required super.id,
    required String               customerName,
    required String               orderId,
    required double               totalAmount,
    required double               amountPaid,
    required DateTime             createdAt,
    List<PaymentRecord>?          payments,
    // v6 interest fields — all optional for backward compat with old rows
    double                        interestRate      = 0,
    String                        interestType      = 'none',
    DateTime?                     interestStartDate,
  })  : _customerName      = customerName,
        _orderId           = orderId,
        _totalAmount       = totalAmount,
        _amountPaid        = amountPaid,
        _createdAt         = createdAt,
        _payments          = payments ?? [],
        _interestRate      = interestRate,
        _interestType      = interestType,
        _interestStartDate = interestStartDate;

  // ── Public read-only getters ──────────────────────────────────────────────
  String              get customerName      => _customerName;
  String              get orderId           => _orderId;
  double              get totalAmount       => _totalAmount;
  double              get amountPaid        => _amountPaid;
  DateTime            get createdAt         => _createdAt;
  List<PaymentRecord> get payments          => List.unmodifiable(_payments);

  // v6 interest getters
  double    get interestRate      => _interestRate;
  String    get interestType      => _interestType;
  DateTime? get interestStartDate => _interestStartDate;
  bool      get hasInterest       => _interestType != 'none' && _interestRate > 0;

  // ── Validated setter ──────────────────────────────────────────────────────
  set amountPaid(double value) {
    if (value < 0) throw ArgumentError('Amount paid cannot be negative.');
    _amountPaid = value;
  }

  // ── Computed properties ───────────────────────────────────────────────────

  double get remainingBalance => _totalAmount - _amountPaid;
  bool   get isPaid           => remainingBalance <= 0;
  bool   get isOverdue        => !isPaid && DateTime.now().difference(_createdAt).inDays >= 7;
  int    get daysOld          => DateTime.now().difference(_createdAt).inDays;

  /// Days since interest accrual started (uses interestStartDate if set).
  int get interestDaysOld {
    final start = _interestStartDate ?? _createdAt;
    return DateTime.now().difference(start).inDays;
  }

  /// Accrued interest based on remaining principal balance.
  /// Daily:   balance × (rate/100) × days
  /// Monthly: balance × (rate/100) × (days/30)
  double get accruedInterest {
    if (!hasInterest || remainingBalance <= 0) return 0;
    final days = interestDaysOld;
    switch (_interestType) {
      case 'daily':
        return remainingBalance * (_interestRate / 100) * days;
      case 'monthly':
        return remainingBalance * (_interestRate / 100) * (days / 30);
      default:
        return 0;
    }
  }

  /// Total amount owed including accrued interest.
  double get totalWithInterest => remainingBalance + accruedInterest;

  // ── Serialization ─────────────────────────────────────────────────────────

  @override
  Map<String, dynamic> toMap() => {
    'id':                   id,
    'customerName':         _customerName,
    'orderId':              _orderId,
    'totalAmount':          _totalAmount,
    'amountPaid':           _amountPaid,
    'createdAt':            _createdAt.toIso8601String(),
    'payments':             _payments.map((p) => p.toMap()).toList(),
    // v6
    'interestRate':         _interestRate,
    'interestType':         _interestType,
    'interestStartDate':    _interestStartDate?.toIso8601String(),
  };

  factory CustomerDebt.fromMap(Map<String, dynamic> map) => CustomerDebt(
    id:                  map['id']           as String? ?? '',
    customerName:        map['customerName'] as String? ?? '',
    orderId:             map['orderId']      as String? ?? '',
    totalAmount:         (map['totalAmount'] as num?)?.toDouble() ?? 0,
    amountPaid:          (map['amountPaid']  as num?)?.toDouble() ?? 0,
    createdAt:           DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    payments:            (map['payments'] as List? ?? [])
        .map((p) => PaymentRecord.fromMap(p as Map<String, dynamic>))
        .toList(),
    // v6 — safe defaults for old rows that have no interest columns
    interestRate:        (map['interestRate']    as num?)?.toDouble() ?? 0,
    interestType:        map['interestType']      as String? ?? 'none',
    interestStartDate:   map['interestStartDate'] != null
        ? DateTime.tryParse(map['interestStartDate'] as String)
        : null,
  );

  /// Returns a copy with only the specified fields changed (immutable update).
  CustomerDebt copyWith({
    double?    interestRate,
    String?    interestType,
    DateTime?  interestStartDate,
    double?    amountPaid,
  }) => CustomerDebt(
    id:                 id,
    customerName:       _customerName,
    orderId:            _orderId,
    totalAmount:        _totalAmount,
    amountPaid:         amountPaid ?? _amountPaid,
    createdAt:          _createdAt,
    payments:           _payments,
    interestRate:       interestRate      ?? _interestRate,
    interestType:       interestType      ?? _interestType,
    interestStartDate:  interestStartDate ?? _interestStartDate,
  );
}
