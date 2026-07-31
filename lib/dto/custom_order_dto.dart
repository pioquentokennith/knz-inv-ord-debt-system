import '../core/money.dart';
import '../models/custom_order_model.dart';
import 'dto_reader.dart';

class CustomOrderPaymentDto {
  static const currentVersion = 1;

  CustomOrderPaymentDto({
    required this.id,
    required this.customOrderId,
    required this.amountCentavos,
    required this.paidAt,
    required this.note,
  }) {
    if (amountCentavos <= 0) {
      throw const FormatException('Custom-order payment must be positive.');
    }
  }

  final String id;
  final String customOrderId;
  final int amountCentavos;
  final DateTime paidAt;
  final String? note;

  factory CustomOrderPaymentDto.fromDomain(CustomOrderPayment payment) =>
      CustomOrderPaymentDto(
        id: payment.id,
        customOrderId: payment.customOrderId,
        amountCentavos: payment.amount.centavos,
        paidAt: payment.paidAt.toUtc(),
        note: payment.note,
      );

  factory CustomOrderPaymentDto.fromLocal(Map<String, dynamic> map) =>
      _fromMap(map);

  factory CustomOrderPaymentDto.fromCloud(
    Map<String, dynamic> map, {
    required String customOrderId,
  }) => _fromMap(map, customOrderId: customOrderId);

  static CustomOrderPaymentDto _fromMap(
    Map<String, dynamic> map, {
    String? customOrderId,
  }) {
    final r = DtoReader(map, 'CustomOrderPayment');
    r.version(currentVersion);
    return CustomOrderPaymentDto(
      id: r.string(const ['id']),
      customOrderId:
          customOrderId ?? r.string(const ['custom_order_id', 'customOrderId']),
      amountCentavos: r.centavos(
        const ['amount_centavos', 'amountCentavos'],
        legacyMoneyKeys: const ['amount'],
      ),
      paidAt: r.date(const ['paid_at', 'paidAt']),
      note: r.optionalString(const ['note', 'notes']),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'custom_order_id': customOrderId,
    'amount_centavos': amountCentavos,
    'paid_at': paidAt.toIso8601String(),
    'note': note,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  CustomOrderPayment toDomain() => CustomOrderPayment(
    id: id,
    customOrderId: customOrderId,
    amount: Money.fromCentavos(amountCentavos),
    paidAt: paidAt,
    note: note,
  );
}

class CustomOrderDto {
  static const currentVersion = 1;

  CustomOrderDto({
    required this.id,
    required this.customerName,
    required this.contact,
    required this.fragranceSpecs,
    required this.agreedPriceCentavos,
    required this.depositPaidCentavos,
    required this.deliveryDate,
    required this.status,
    required this.terms,
    required this.userId,
    required this.createdAt,
    required this.isDeleted,
    required this.deletedAt,
    required this.payments,
  }) {
    if (agreedPriceCentavos < 0 ||
        depositPaidCentavos < 0 ||
        depositPaidCentavos > agreedPriceCentavos) {
      throw const FormatException('Custom-order balances are invalid.');
    }
    final ledgerTotal = payments.fold<int>(
      0,
      (sum, payment) => sum + payment.amountCentavos,
    );
    if (payments.isNotEmpty && ledgerTotal != depositPaidCentavos) {
      throw const FormatException(
        'Custom-order payment ledger does not match the deposit total.',
      );
    }
    if (!CustomOrderStatus.values
        .map((value) => value.storageKey)
        .contains(status)) {
      throw FormatException('Custom-order status is invalid: $status');
    }
  }

  final String id;
  final String customerName;
  final String? contact;
  final String fragranceSpecs;
  final int agreedPriceCentavos;
  final int depositPaidCentavos;
  final DateTime deliveryDate;
  final String status;
  final String? terms;
  final String userId;
  final DateTime createdAt;
  final bool isDeleted;
  final DateTime? deletedAt;
  final List<CustomOrderPaymentDto> payments;

  factory CustomOrderDto.fromDomain(
    CustomOrder order, {
    bool isDeleted = false,
    DateTime? deletedAt,
  }) => CustomOrderDto(
    id: order.id,
    customerName: order.customerName,
    contact: order.contact,
    fragranceSpecs: order.fragranceSpecs,
    agreedPriceCentavos: order.agreedPrice.centavos,
    depositPaidCentavos: order.depositPaid.centavos,
    deliveryDate: order.deliveryDate.toUtc(),
    status: order.status.storageKey,
    terms: order.terms,
    userId: order.userId,
    createdAt: order.createdAt.toUtc(),
    isDeleted: isDeleted,
    deletedAt: deletedAt?.toUtc(),
    payments: order.payments
        .map(CustomOrderPaymentDto.fromDomain)
        .toList(growable: false),
  );

  factory CustomOrderDto.fromLocal(
    Map<String, dynamic> map,
    List<Map<String, dynamic>> paymentRows,
  ) => _fromMap(map, paymentRows: paymentRows);

  factory CustomOrderDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static CustomOrderDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
    List<Map<String, dynamic>>? paymentRows,
  }) {
    final r = DtoReader(map, 'CustomOrder');
    r.version(currentVersion);
    final id = r.string(const ['id']);
    final rows = paymentRows ?? r.maps(const ['payments', '_payments']);
    final payments = rows
        .map(
          (payment) => paymentRows == null
              ? CustomOrderPaymentDto.fromCloud(payment, customOrderId: id)
              : CustomOrderPaymentDto.fromLocal(payment),
        )
        .toList(growable: false);
    return CustomOrderDto(
      id: id,
      customerName: r.string(const ['customer_name', 'customerName']),
      contact: r.optionalString(const ['contact']),
      fragranceSpecs: r.string(const ['fragrance_specs', 'fragranceSpecs']),
      agreedPriceCentavos: r.centavos(
        const ['agreed_price_centavos', 'agreedPriceCentavos'],
        legacyMoneyKeys: const ['agreed_price', 'agreedPrice'],
      ),
      depositPaidCentavos: r.centavos(
        const ['deposit_paid_centavos', 'depositPaidCentavos'],
        legacyMoneyKeys: const ['deposit_paid', 'depositPaid'],
        defaultValue: 0,
      ),
      deliveryDate: r.date(const ['delivery_date', 'deliveryDate']),
      status: r.string(const ['status'], defaultValue: 'Pending'),
      terms: r.optionalString(const ['terms']),
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
      createdAt: r.date(const ['created_at', 'createdAt']),
      isDeleted: r.boolean(const ['is_deleted', 'isDeleted']),
      deletedAt: r.optionalDate(const ['deleted_at', 'deletedAt']),
      payments: List.unmodifiable(payments),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'customer_name': customerName,
    'contact': contact,
    'fragrance_specs': fragranceSpecs,
    'agreed_price_centavos': agreedPriceCentavos,
    'deposit_paid_centavos': depositPaidCentavos,
    'delivery_date': deliveryDate.toIso8601String(),
    'status': status,
    'terms': terms,
    'user_id': userId,
    'created_at': createdAt.toIso8601String(),
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => {
    ...toLocal(),
    'payments': payments
        .map((payment) => payment.toCloud())
        .toList(growable: false),
  };

  CustomOrder toDomain() => CustomOrder(
    id: id,
    customerName: customerName,
    contact: contact,
    fragranceSpecs: fragranceSpecs,
    agreedPrice: Money.fromCentavos(agreedPriceCentavos),
    depositPaid: Money.fromCentavos(depositPaidCentavos),
    payments: payments.map((payment) => payment.toDomain()).toList(),
    deliveryDate: deliveryDate,
    status: CustomOrderStatusExtension.fromString(status),
    terms: terms,
    userId: userId,
    createdAt: createdAt,
  );
}
