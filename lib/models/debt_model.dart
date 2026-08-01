import 'dart:math' as math;

import '../core/money.dart';
import 'base_model.dart';

enum DebtStatus { open, paid }

extension DebtStatusExtension on DebtStatus {
  String get storageKey => name;

  static DebtStatus fromString(String? value) => DebtStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => DebtStatus.open,
  );
}

/// One immutable payment and its explicit interest-first allocation.
class PaymentRecord extends BaseModel {
  PaymentRecord({
    required super.id,
    required this.amount,
    required this.paidAt,
    this.interestApplied = Money.zero,
    this.principalApplied = Money.zero,
    this.paymentMethod,
    this.reference,
    String? note,
  }) : note = note == null || note.trim().isEmpty ? null : note.trim() {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Payment id cannot be blank.');
    }
    if (!amount.isPositive) {
      throw ArgumentError.value(amount, 'amount', 'Payment must be positive.');
    }
    if (interestApplied.isNegative || principalApplied.isNegative) {
      throw ArgumentError('Payment allocations cannot be negative.');
    }
    final allocated = interestApplied + principalApplied;
    if (!allocated.isZero && allocated != amount) {
      throw ArgumentError('Payment allocations must equal the payment amount.');
    }
  }

  final Money amount;
  final Money interestApplied;
  final Money principalApplied;
  final DateTime paidAt;
  final String? paymentMethod;
  final String? reference;
  final String? note;

  bool get isAllocated => interestApplied + principalApplied == amount;

  PaymentRecord withAllocation({
    required Money interest,
    required Money principal,
  }) => PaymentRecord(
    id: id,
    amount: amount,
    paidAt: paidAt,
    interestApplied: interest,
    principalApplied: principal,
    paymentMethod: paymentMethod,
    reference: reference,
    note: note,
  );

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'amountCentavos': amount.centavos,
    'interestAppliedCentavos': interestApplied.centavos,
    'principalAppliedCentavos': principalApplied.centavos,
    'paidAt': paidAt.toUtc().toIso8601String(),
    'paymentMethod': paymentMethod,
    'reference': reference,
    'note': note,
  };

  factory PaymentRecord.fromMap(Map<String, dynamic> map) => PaymentRecord(
    id: map['id'] as String? ?? '',
    amount: Money.fromCentavos(map['amountCentavos'] as int? ?? 0),
    interestApplied: Money.fromCentavos(
      map['interestAppliedCentavos'] as int? ?? 0,
    ),
    principalApplied: Money.fromCentavos(
      map['principalAppliedCentavos'] as int? ?? 0,
    ),
    paidAt:
        DateTime.tryParse(map['paidAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    paymentMethod: map['paymentMethod'] as String?,
    reference: map['reference'] as String?,
    note: map['note'] as String?,
  );
}

/// Persisted debt state. Accrual advances only from [lastAccrualTimestamp].
class CustomerDebt extends BaseModel {
  CustomerDebt({
    required super.id,
    required String customerName,
    required String orderId,
    required Money principalOriginal,
    required Money principalOutstanding,
    Money interestOutstanding = Money.zero,
    required DateTime createdAt,
    List<PaymentRecord> payments = const [],
    int interestRateBasisPoints = 0,
    String interestType = 'none',
    DateTime? interestStartTimestamp,
    DateTime? lastAccrualTimestamp,
    DateTime? dueDate,
    DebtStatus? status,
  }) : _customerName = customerName.trim(),
       _orderId = orderId.trim(),
       _principalOriginal = principalOriginal,
       _principalOutstanding = principalOutstanding,
       _interestOutstanding = interestOutstanding,
       _createdAt = createdAt.toUtc(),
       _payments = List<PaymentRecord>.unmodifiable(payments),
       _interestRateBasisPoints = interestRateBasisPoints,
       _interestType = _validInterestType(interestType),
       _interestStartTimestamp = (interestStartTimestamp ?? createdAt).toUtc(),
       _lastAccrualTimestamp =
           (lastAccrualTimestamp ?? interestStartTimestamp ?? createdAt)
               .toUtc(),
       _dueDate = dueDate == null
           ? null
           : DateTime.utc(dueDate.year, dueDate.month, dueDate.day),
       _status =
           status ??
           ((principalOutstanding + interestOutstanding).isZero
               ? DebtStatus.paid
               : DebtStatus.open) {
    if (id.trim().isEmpty || _customerName.isEmpty || _orderId.isEmpty) {
      throw ArgumentError('Debt identity, customer, and order are required.');
    }
    if (_principalOriginal.isNegative ||
        _principalOutstanding.isNegative ||
        _interestOutstanding.isNegative ||
        _principalOutstanding.compareTo(_principalOriginal) > 0) {
      throw ArgumentError('Debt balances are invalid.');
    }
    if (_interestRateBasisPoints < 0) {
      throw ArgumentError.value(
        interestRateBasisPoints,
        'interestRateBasisPoints',
      );
    }
    if (_lastAccrualTimestamp.isBefore(_interestStartTimestamp)) {
      throw ArgumentError('Last accrual cannot precede interest start.');
    }
    final expectedStatus = totalOutstanding.isZero
        ? DebtStatus.paid
        : DebtStatus.open;
    if (_status != expectedStatus) {
      throw ArgumentError(
        'Debt status does not match its outstanding balance.',
      );
    }
    final paymentIds = <String>{};
    for (final payment in _payments) {
      if (!payment.isAllocated || !paymentIds.add(payment.id)) {
        throw ArgumentError('Persisted payments must be allocated and unique.');
      }
    }
  }

  final String _customerName;
  final String _orderId;
  final Money _principalOriginal;
  final Money _principalOutstanding;
  final Money _interestOutstanding;
  final DateTime _createdAt;
  final List<PaymentRecord> _payments;
  final int _interestRateBasisPoints;
  final String _interestType;
  final DateTime _interestStartTimestamp;
  final DateTime _lastAccrualTimestamp;
  final DateTime? _dueDate;
  final DebtStatus _status;

  String get customerName => _customerName;
  String get orderId => _orderId;
  Money get principalOriginal => _principalOriginal;
  Money get principalOutstanding => _principalOutstanding;
  Money get interestOutstanding => _interestOutstanding;
  Money get totalAmount => _principalOriginal;
  Money get amountPaid =>
      _payments.fold(Money.zero, (total, payment) => total + payment.amount);
  DateTime get createdAt => _createdAt;
  List<PaymentRecord> get payments => _payments;
  int get interestRateBasisPoints => _interestRateBasisPoints;
  String get interestType => _interestType;
  DateTime get interestStartTimestamp => _interestStartTimestamp;
  DateTime get lastAccrualTimestamp => _lastAccrualTimestamp;
  DateTime? get dueDate => _dueDate;
  DebtStatus get status => _status;
  bool get hasInterest =>
      _interestType != 'none' && _interestRateBasisPoints > 0;
  bool get isPaid =>
      _principalOutstanding.isZero && _interestOutstanding.isZero;
  bool get isDue => isDueAt(DateTime.now());
  bool get isOverdue => isOverdueAt(DateTime.now());
  bool isDueAt(DateTime timestamp) {
    if (isPaid || _dueDate == null) return false;
    final local = timestamp.toLocal();
    final today = DateTime.utc(local.year, local.month, local.day);
    return !today.isBefore(_dueDate);
  }

  bool isOverdueAt(DateTime timestamp) {
    if (isPaid || _dueDate == null) return false;
    final local = timestamp.toLocal();
    final today = DateTime.utc(local.year, local.month, local.day);
    return today.isAfter(_dueDate);
  }

  int get daysOverdue {
    if (!isOverdue || _dueDate == null) return 0;
    final now = DateTime.now().toLocal();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(_dueDate).inDays;
  }

  int get daysOld =>
      math.max(0, DateTime.now().toUtc().difference(_createdAt).inDays);
  int get interestDaysOld => math.max(
    0,
    DateTime.now().toUtc().difference(_interestStartTimestamp).inDays,
  );
  Money get remainingBalance => _principalOutstanding;
  Money get accruedInterest => _interestOutstanding;
  Money get totalWithInterest => totalOutstanding;
  Money get totalOutstanding => _principalOutstanding + _interestOutstanding;
  DebtBalance get currentBalance => DebtBalance(
    principalOutstanding: _principalOutstanding,
    interestOutstanding: _interestOutstanding,
  );

  CustomerDebt accrueTo(DateTime timestamp) {
    final target = timestamp.toUtc();
    if (target.isBefore(_lastAccrualTimestamp)) {
      throw ArgumentError('Accrual timestamp cannot move backwards.');
    }
    if (!hasInterest || _principalOutstanding.isZero) {
      return copyWith(lastAccrualTimestamp: target);
    }
    final period = _interestType == 'daily'
        ? const Duration(days: 1)
        : const Duration(days: 30);
    final elapsed = target.difference(_lastAccrualTimestamp);
    final periods = elapsed.inSeconds ~/ period.inSeconds;
    if (periods == 0) return this;
    final perPeriod = Money.fromCentavos(
      roundRatioHalfUp(
        _principalOutstanding.centavos * _interestRateBasisPoints,
        10000,
      ),
    );
    return copyWith(
      interestOutstanding: _interestOutstanding + perPeriod * periods,
      lastAccrualTimestamp: _lastAccrualTimestamp.add(period * periods),
    );
  }

  DebtBalance balanceAt(DateTime timestamp) =>
      accrueTo(timestamp).currentBalance;

  DebtPaymentResult allocatePayment(PaymentRecord payment) {
    if (_payments.any((existing) => existing.id == payment.id)) {
      throw StateError('Payment already exists: ${payment.id}');
    }
    final accrued = accrueTo(payment.paidAt);
    if (payment.amount.compareTo(accrued.totalOutstanding) > 0) {
      throw StateError('Payment exceeds the total debt outstanding.');
    }
    final interestApplied = payment.amount.min(accrued.interestOutstanding);
    final principalApplied = payment.amount - interestApplied;
    final allocated = payment.withAllocation(
      interest: interestApplied,
      principal: principalApplied,
    );
    final updated = accrued.copyWith(
      principalOutstanding: accrued.principalOutstanding - principalApplied,
      interestOutstanding: accrued.interestOutstanding - interestApplied,
      payments: [...accrued.payments, allocated],
    );
    return DebtPaymentResult(debt: updated, payment: allocated);
  }

  CustomerDebt copyWith({
    Money? principalOutstanding,
    Money? interestOutstanding,
    List<PaymentRecord>? payments,
    int? interestRateBasisPoints,
    String? interestType,
    DateTime? interestStartTimestamp,
    DateTime? lastAccrualTimestamp,
    DateTime? dueDate,
  }) => CustomerDebt(
    id: id,
    customerName: _customerName,
    orderId: _orderId,
    principalOriginal: _principalOriginal,
    principalOutstanding: principalOutstanding ?? _principalOutstanding,
    interestOutstanding: interestOutstanding ?? _interestOutstanding,
    createdAt: _createdAt,
    payments: payments ?? _payments,
    interestRateBasisPoints:
        interestRateBasisPoints ?? _interestRateBasisPoints,
    interestType: interestType ?? _interestType,
    interestStartTimestamp: interestStartTimestamp ?? _interestStartTimestamp,
    lastAccrualTimestamp: lastAccrualTimestamp ?? _lastAccrualTimestamp,
    dueDate: dueDate ?? _dueDate,
  );

  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'customerName': _customerName,
    'orderId': _orderId,
    'principalOriginalCentavos': _principalOriginal.centavos,
    'principalOutstandingCentavos': _principalOutstanding.centavos,
    'interestOutstandingCentavos': _interestOutstanding.centavos,
    'createdAt': _createdAt.toIso8601String(),
    'payments': _payments.map((payment) => payment.toMap()).toList(),
    'interestRateBasisPoints': _interestRateBasisPoints,
    'interestType': _interestType,
    'interestStartTimestamp': _interestStartTimestamp.toIso8601String(),
    'lastAccrualTimestamp': _lastAccrualTimestamp.toIso8601String(),
    'dueDate': _dueDate?.toIso8601String(),
    'status': _status.storageKey,
  };

  factory CustomerDebt.fromMap(Map<String, dynamic> map) => CustomerDebt(
    id: map['id'] as String? ?? '',
    customerName: map['customerName'] as String? ?? '',
    orderId: map['orderId'] as String? ?? '',
    principalOriginal: Money.fromCentavos(
      map['principalOriginalCentavos'] as int? ?? 0,
    ),
    principalOutstanding: Money.fromCentavos(
      map['principalOutstandingCentavos'] as int? ?? 0,
    ),
    interestOutstanding: Money.fromCentavos(
      map['interestOutstandingCentavos'] as int? ?? 0,
    ),
    createdAt:
        DateTime.tryParse(map['createdAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    payments: (map['payments'] as List? ?? const [])
        .map(
          (payment) => PaymentRecord.fromMap(payment as Map<String, dynamic>),
        )
        .toList(),
    interestRateBasisPoints: map['interestRateBasisPoints'] as int? ?? 0,
    interestType: map['interestType'] as String? ?? 'none',
    interestStartTimestamp: DateTime.tryParse(
      map['interestStartTimestamp'] as String? ?? '',
    ),
    lastAccrualTimestamp: DateTime.tryParse(
      map['lastAccrualTimestamp'] as String? ?? '',
    ),
    dueDate: DateTime.tryParse(map['dueDate'] as String? ?? ''),
    status: DebtStatusExtension.fromString(map['status'] as String?),
  );
}

class DebtBalance {
  const DebtBalance({
    required this.principalOutstanding,
    required this.interestOutstanding,
  });

  final Money principalOutstanding;
  final Money interestOutstanding;
  Money get totalOutstanding => principalOutstanding + interestOutstanding;
}

class DebtPaymentResult {
  const DebtPaymentResult({required this.debt, required this.payment});

  final CustomerDebt debt;
  final PaymentRecord payment;
}

String _validInterestType(String value) {
  if (!const {'none', 'daily', 'monthly'}.contains(value)) {
    throw ArgumentError.value(
      value,
      'interestType',
      'Must be none, daily, or monthly.',
    );
  }
  return value;
}
