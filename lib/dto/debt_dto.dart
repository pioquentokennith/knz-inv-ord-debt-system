import '../core/money.dart';
import '../models/debt_model.dart';
import 'dto_reader.dart';

class PaymentDto {
  static const currentVersion = 1;

  PaymentDto({
    required this.id,
    required this.debtId,
    required this.amountCentavos,
    required this.interestAppliedCentavos,
    required this.principalAppliedCentavos,
    required this.paidAt,
    required this.paymentMethod,
    required this.reference,
    required this.note,
  }) {
    if (amountCentavos <= 0 ||
        interestAppliedCentavos < 0 ||
        principalAppliedCentavos < 0 ||
        interestAppliedCentavos + principalAppliedCentavos != amountCentavos) {
      throw const FormatException('Payment allocation is invalid.');
    }
  }

  final String id;
  final String debtId;
  final int amountCentavos;
  final int interestAppliedCentavos;
  final int principalAppliedCentavos;
  final DateTime paidAt;
  final String? paymentMethod;
  final String? reference;
  final String? note;

  factory PaymentDto.fromDomain(PaymentRecord payment, String debtId) =>
      PaymentDto(
        id: payment.id,
        debtId: debtId,
        amountCentavos: payment.amount.centavos,
        interestAppliedCentavos: payment.interestApplied.centavos,
        principalAppliedCentavos: payment.principalApplied.centavos,
        paidAt: payment.paidAt.toUtc(),
        paymentMethod: payment.paymentMethod,
        reference: payment.reference,
        note: payment.note,
      );

  factory PaymentDto.fromLocal(Map<String, dynamic> map) => _fromMap(map);

  factory PaymentDto.fromCloud(
    Map<String, dynamic> map, {
    required String debtId,
  }) => _fromMap(map, debtId: debtId);

  static PaymentDto _fromMap(Map<String, dynamic> map, {String? debtId}) {
    final r = DtoReader(map, 'Payment');
    r.version(currentVersion);
    final amount = r.centavos(
      const ['amount_centavos', 'amountCentavos'],
      legacyMoneyKeys: const ['amount'],
    );
    final interest = r.integer(const [
      'interest_applied_centavos',
      'interestAppliedCentavos',
    ], defaultValue: 0);
    return PaymentDto(
      id: r.string(const ['id']),
      debtId: debtId ?? r.string(const ['debt_id', 'debtId']),
      amountCentavos: amount,
      interestAppliedCentavos: interest,
      principalAppliedCentavos: r.integer(const [
        'principal_applied_centavos',
        'principalAppliedCentavos',
      ], defaultValue: amount - interest),
      paidAt: r.date(const ['paid_at', 'paidAt']),
      paymentMethod: r.optionalString(const [
        'payment_method',
        'paymentMethod',
      ]),
      reference: r.optionalString(const ['reference']),
      note: r.optionalString(const ['note', 'notes']),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'debt_id': debtId,
    'amount_centavos': amountCentavos,
    'interest_applied_centavos': interestAppliedCentavos,
    'principal_applied_centavos': principalAppliedCentavos,
    'paid_at': paidAt.toIso8601String(),
    'payment_method': paymentMethod,
    'reference': reference,
    'note': note,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  PaymentRecord toDomain() => PaymentRecord(
    id: id,
    amount: Money.fromCentavos(amountCentavos),
    interestApplied: Money.fromCentavos(interestAppliedCentavos),
    principalApplied: Money.fromCentavos(principalAppliedCentavos),
    paidAt: paidAt,
    paymentMethod: paymentMethod,
    reference: reference,
    note: note,
  );
}

class DebtDto {
  static const currentVersion = 1;

  DebtDto({
    required this.id,
    required this.customerName,
    required this.orderId,
    required this.principalOriginalCentavos,
    required this.principalOutstandingCentavos,
    required this.interestOutstandingCentavos,
    required this.createdAt,
    required this.userId,
    required this.isDeleted,
    required this.deletedAt,
    required this.interestRateBasisPoints,
    required this.interestType,
    required this.interestStartTimestamp,
    required this.lastAccrualTimestamp,
    required this.status,
    required this.payments,
  }) {
    if (principalOriginalCentavos < 0 ||
        principalOutstandingCentavos < 0 ||
        interestOutstandingCentavos < 0 ||
        interestRateBasisPoints < 0 ||
        principalOutstandingCentavos > principalOriginalCentavos) {
      throw const FormatException('Debt balances are invalid.');
    }
    if (!const {'none', 'daily', 'monthly'}.contains(interestType)) {
      throw FormatException('Debt interest type is invalid: $interestType');
    }
    if (lastAccrualTimestamp.isBefore(interestStartTimestamp)) {
      throw const FormatException(
        'Debt accrual timestamp precedes interest start.',
      );
    }
    final expectedStatus =
        principalOutstandingCentavos + interestOutstandingCentavos == 0
        ? 'paid'
        : 'open';
    if (status != expectedStatus) {
      throw const FormatException('Debt status does not match its balances.');
    }
  }

  final String id;
  final String customerName;
  final String orderId;
  final int principalOriginalCentavos;
  final int principalOutstandingCentavos;
  final int interestOutstandingCentavos;
  final DateTime createdAt;
  final String userId;
  final bool isDeleted;
  final DateTime? deletedAt;
  final int interestRateBasisPoints;
  final String interestType;
  final DateTime interestStartTimestamp;
  final DateTime lastAccrualTimestamp;
  final String status;
  final List<PaymentDto> payments;

  factory DebtDto.fromDomain(
    CustomerDebt debt, {
    required String userId,
    bool isDeleted = false,
    DateTime? deletedAt,
  }) => DebtDto(
    id: debt.id,
    customerName: debt.customerName,
    orderId: debt.orderId,
    principalOriginalCentavos: debt.principalOriginal.centavos,
    principalOutstandingCentavos: debt.principalOutstanding.centavos,
    interestOutstandingCentavos: debt.interestOutstanding.centavos,
    createdAt: debt.createdAt.toUtc(),
    userId: userId,
    isDeleted: isDeleted,
    deletedAt: deletedAt?.toUtc(),
    interestRateBasisPoints: debt.interestRateBasisPoints,
    interestType: debt.interestType,
    interestStartTimestamp: debt.interestStartTimestamp.toUtc(),
    lastAccrualTimestamp: debt.lastAccrualTimestamp.toUtc(),
    status: debt.status.storageKey,
    payments: debt.payments
        .map((payment) => PaymentDto.fromDomain(payment, debt.id))
        .toList(growable: false),
  );

  factory DebtDto.fromLocal(
    Map<String, dynamic> map,
    List<Map<String, dynamic>> paymentRows,
  ) => _fromMap(map, paymentRows: paymentRows);

  factory DebtDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static DebtDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
    List<Map<String, dynamic>>? paymentRows,
  }) {
    final r = DtoReader(map, 'Debt');
    r.version(currentVersion);
    if (!map.containsKey('principal_original_centavos') &&
        !map.containsKey('principalOriginalCentavos')) {
      throw FormatException(
        'Cloud debt ${map['id']} uses an ambiguous pre-centavo contract. '
        'Synchronize an upgraded source device first.',
      );
    }
    final id = r.string(const ['id']);
    final rows = paymentRows ?? r.maps(const ['payments', '_payments']);
    final payments = rows
        .map(
          (payment) => paymentRows == null
              ? PaymentDto.fromCloud(payment, debtId: id)
              : PaymentDto.fromLocal(payment),
        )
        .toList(growable: false);
    final createdAt = r.date(const ['created_at', 'createdAt']);
    final interestStart = r.date(const [
      'interest_start_timestamp',
      'interestStartTimestamp',
    ], defaultValue: createdAt);
    final principal = r.integer(const [
      'principal_outstanding_centavos',
      'principalOutstandingCentavos',
    ]);
    final interest = r.integer(const [
      'interest_outstanding_centavos',
      'interestOutstandingCentavos',
    ], defaultValue: 0);
    return DebtDto(
      id: id,
      customerName: r.string(const ['customer_name', 'customerName']),
      orderId: r.string(const ['order_id', 'orderId']),
      principalOriginalCentavos: r.integer(const [
        'principal_original_centavos',
        'principalOriginalCentavos',
      ]),
      principalOutstandingCentavos: principal,
      interestOutstandingCentavos: interest,
      createdAt: createdAt,
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
      isDeleted: r.boolean(const ['is_deleted', 'isDeleted']),
      deletedAt: r.optionalDate(const ['deleted_at', 'deletedAt']),
      interestRateBasisPoints: r.integer(const [
        'interest_rate_basis_points',
        'interestRateBasisPoints',
      ], defaultValue: 0),
      interestType: r.string(const [
        'interest_type',
        'interestType',
      ], defaultValue: 'none'),
      interestStartTimestamp: interestStart,
      lastAccrualTimestamp: r.date(const [
        'last_accrual_timestamp',
        'lastAccrualTimestamp',
      ], defaultValue: interestStart),
      status: r.string(const [
        'status',
      ], defaultValue: principal + interest == 0 ? 'paid' : 'open'),
      payments: List.unmodifiable(payments),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'customer_name': customerName,
    'order_id': orderId,
    'principal_original_centavos': principalOriginalCentavos,
    'principal_outstanding_centavos': principalOutstandingCentavos,
    'interest_outstanding_centavos': interestOutstandingCentavos,
    'created_at': createdAt.toIso8601String(),
    'user_id': userId,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
    'interest_rate_basis_points': interestRateBasisPoints,
    'interest_type': interestType,
    'interest_start_timestamp': interestStartTimestamp.toIso8601String(),
    'last_accrual_timestamp': lastAccrualTimestamp.toIso8601String(),
    'status': status,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => {
    ...toLocal(),
    'payments': payments
        .map((payment) => payment.toCloud())
        .toList(growable: false),
  };

  CustomerDebt toDomain() => CustomerDebt(
    id: id,
    customerName: customerName,
    orderId: orderId,
    principalOriginal: Money.fromCentavos(principalOriginalCentavos),
    principalOutstanding: Money.fromCentavos(principalOutstandingCentavos),
    interestOutstanding: Money.fromCentavos(interestOutstandingCentavos),
    createdAt: createdAt,
    payments: payments.map((payment) => payment.toDomain()).toList(),
    interestRateBasisPoints: interestRateBasisPoints,
    interestType: interestType,
    interestStartTimestamp: interestStartTimestamp,
    lastAccrualTimestamp: lastAccrualTimestamp,
    status: DebtStatusExtension.fromString(status),
  );
}
