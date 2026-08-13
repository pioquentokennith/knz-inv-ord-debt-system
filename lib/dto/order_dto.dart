import '../core/money.dart';
import '../models/order_model.dart';
import '../models/payment_method_model.dart';
import 'dto_reader.dart';

class OrderItemDto {
  static const currentVersion = 1;

  OrderItemDto({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.unitPriceCentavos,
    required this.srpPriceCentavos,
    required this.quantity,
  }) {
    if (unitPriceCentavos < 0 || srpPriceCentavos < 0 || quantity <= 0) {
      throw const FormatException('Order item values are invalid.');
    }
  }

  final String id;
  final String orderId;
  final String productId;
  final String productName;
  final int unitPriceCentavos;
  final int srpPriceCentavos;
  final int quantity;

  factory OrderItemDto.fromDomain(OrderItem item, String orderId) =>
      OrderItemDto(
        id: item.id,
        orderId: orderId,
        productId: item.productId,
        productName: item.productName,
        unitPriceCentavos: item.unitPrice.centavos,
        srpPriceCentavos: item.srpPrice.centavos,
        quantity: item.quantity,
      );

  factory OrderItemDto.fromLocal(Map<String, dynamic> map) => _fromMap(map);

  factory OrderItemDto.fromCloud(
    Map<String, dynamic> map, {
    required String orderId,
    required int legacyIndex,
  }) => _fromMap(map, orderId: orderId, legacyIndex: legacyIndex);

  static OrderItemDto _fromMap(
    Map<String, dynamic> map, {
    String? orderId,
    int legacyIndex = 0,
  }) {
    final r = DtoReader(map, 'OrderItem');
    r.version(currentVersion);
    final owner = orderId ?? r.string(const ['order_id', 'orderId']);
    final productId = r.string(const [
      'product_id',
      'productId',
    ], defaultValue: 'legacy-product-$legacyIndex');
    final unit = r.centavos(
      const ['unit_price_centavos', 'unitPriceCentavos'],
      legacyMoneyKeys: const ['unit_price', 'unitPrice'],
    );
    return OrderItemDto(
      id: r.string(const ['id'], defaultValue: 'legacy-$owner-$legacyIndex'),
      orderId: owner,
      productId: productId,
      productName: r.string(const ['product_name', 'productName']),
      unitPriceCentavos: unit,
      srpPriceCentavos: r.centavos(
        const ['srp_price_centavos', 'srpPriceCentavos'],
        legacyMoneyKeys: const ['srp_price', 'srpPrice'],
        defaultValue: unit,
      ),
      quantity: r.integer(const ['quantity'], defaultValue: 1),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'order_id': orderId,
    'product_id': productId,
    'product_name': productName,
    'unit_price_centavos': unitPriceCentavos,
    'srp_price_centavos': srpPriceCentavos,
    'quantity': quantity,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  OrderItem toDomain() => OrderItem(
    id: id,
    productId: productId,
    productName: productName,
    unitPrice: Money.fromCentavos(unitPriceCentavos),
    srpPrice: Money.fromCentavos(srpPriceCentavos),
    quantity: quantity,
  );
}

class OrderDto {
  static const currentVersion = 2;

  OrderDto({
    required this.id,
    required this.orderId,
    required this.customerName,
    required this.totalAmountCentavos,
    required this.srpTotalCentavos,
    required this.customerPayAmountCentavos,
    required this.status,
    required this.orderDate,
    required this.notes,
    required this.userId,
    required this.isDeleted,
    required this.deletedAt,
    required this.paymentMethod,
    required this.paymentReference,
    required this.isReseller,
    required this.deductionPerItemCentavos,
    required this.discountedTotalCentavos,
    required this.orderType,
    required this.stockDeducted,
    required this.stockReleasedOnDelete,
    required this.commandId,
    required this.items,
  }) {
    if (totalAmountCentavos < 0 ||
        srpTotalCentavos < 0 ||
        customerPayAmountCentavos < 0 ||
        deductionPerItemCentavos < 0 ||
        (discountedTotalCentavos != null && discountedTotalCentavos! < 0)) {
      throw const FormatException('Order money fields cannot be negative.');
    }
    final expectedPay = discountedTotalCentavos ?? totalAmountCentavos;
    if (customerPayAmountCentavos != expectedPay) {
      throw const FormatException(
        'Order customer-pay amount must match its authoritative total.',
      );
    }
    if (items.isEmpty) {
      throw const FormatException('Order must contain at least one line item.');
    }
    final lineSrpTotal = items.fold<int>(
      0,
      (sum, item) => sum + item.srpPriceCentavos * item.quantity,
    );
    final lineCustomerPayTotal = items.fold<int>(
      0,
      (sum, item) => sum + item.unitPriceCentavos * item.quantity,
    );
    if (srpTotalCentavos != lineSrpTotal) {
      throw const FormatException(
        'Order SRP total does not match its line items.',
      );
    }
    if (totalAmountCentavos != lineCustomerPayTotal) {
      throw const FormatException('Order total does not match its line items.');
    }
    if (customerPayAmountCentavos != lineCustomerPayTotal) {
      throw const FormatException(
        'Order customer-pay total does not match its line items.',
      );
    }
    if (!OrderStatus.values
        .map((value) => value.displayName)
        .contains(status)) {
      throw FormatException('Order status is invalid: $status');
    }
    if (paymentMethod != null &&
        !PaymentMethod.values
            .map((value) => value.storageKey)
            .contains(paymentMethod)) {
      throw FormatException('Order payment method is invalid: $paymentMethod');
    }
    if (!const {'regular', 'customized'}.contains(orderType)) {
      throw FormatException('Order type is invalid: $orderType');
    }
    if (commandId != null && commandId!.trim().isEmpty) {
      throw const FormatException('Order command id cannot be blank.');
    }
  }

  final String id;
  final String orderId;
  final String customerName;
  final int totalAmountCentavos;
  final int srpTotalCentavos;
  final int customerPayAmountCentavos;
  final String status;
  final DateTime orderDate;
  final String? notes;
  final String userId;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? paymentMethod;
  final String? paymentReference;
  final bool isReseller;
  final int deductionPerItemCentavos;
  final int? discountedTotalCentavos;
  final String orderType;
  final bool stockDeducted;
  final bool stockReleasedOnDelete;
  final String? commandId;
  final List<OrderItemDto> items;

  factory OrderDto.fromDomain(
    Order order, {
    required String userId,
    bool isDeleted = false,
    DateTime? deletedAt,
    bool stockDeducted = true,
    bool stockReleasedOnDelete = false,
  }) => OrderDto(
    id: order.id,
    orderId: order.orderId,
    customerName: order.customerName,
    totalAmountCentavos: order.customerPayAmount.centavos,
    srpTotalCentavos: order.srpTotal.centavos,
    customerPayAmountCentavos: order.customerPayAmount.centavos,
    status: order.status.displayName,
    orderDate: order.orderDate.toUtc(),
    notes: order.notes,
    userId: userId,
    isDeleted: isDeleted,
    deletedAt: deletedAt?.toUtc(),
    paymentMethod: order.paymentMethod?.storageKey,
    paymentReference: order.paymentReference,
    isReseller: order.isReseller,
    deductionPerItemCentavos: order.deductionPerItem.centavos,
    discountedTotalCentavos: order.storedDiscountedTotal?.centavos,
    orderType: order.orderType,
    stockDeducted: stockDeducted,
    stockReleasedOnDelete: stockReleasedOnDelete,
    commandId: order.commandId,
    items: order.items
        .map((item) => OrderItemDto.fromDomain(item, order.id))
        .toList(growable: false),
  );

  factory OrderDto.fromLocal(
    Map<String, dynamic> map,
    List<Map<String, dynamic>> itemRows,
  ) => _fromMap(map, itemRows: itemRows);

  factory OrderDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static OrderDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
    List<Map<String, dynamic>>? itemRows,
  }) {
    final r = DtoReader(map, 'Order');
    r.version(currentVersion);
    final id = r.string(const ['id']);
    final rows = itemRows ?? r.maps(const ['items', '_items']);
    final items = <OrderItemDto>[];
    for (var index = 0; index < rows.length; index++) {
      items.add(
        itemRows == null
            ? OrderItemDto.fromCloud(
                rows[index],
                orderId: id,
                legacyIndex: index,
              )
            : OrderItemDto.fromLocal(rows[index]),
      );
    }
    final total = r.centavos(
      const ['total_amount_centavos', 'totalAmountCentavos'],
      legacyMoneyKeys: const ['total_amount', 'totalAmount'],
    );
    final discounted = r.optionalInteger(const [
      'discounted_total_centavos',
      'discountedTotalCentavos',
    ]);
    final legacyDiscounted = discounted == null
        ? r.data['discounted_total'] ?? r.data['discountedTotal']
        : null;
    final normalizedDiscounted =
        discounted ??
        (legacyDiscounted is num
            ? Money.fromLegacyNumber(legacyDiscounted).centavos
            : null);
    final srpFromItems = items.fold<int>(
      0,
      (sum, item) => sum + item.srpPriceCentavos * item.quantity,
    );
    final rawPaymentMethod = r.optionalString(const [
      'payment_method',
      'paymentMethod',
    ]);
    final paymentMethod = rawPaymentMethod?.toLowerCase() == 'cash'
        ? PaymentMethod.cashOnDelivery.storageKey
        : rawPaymentMethod;
    return OrderDto(
      id: id,
      orderId: r.string(const ['order_id', 'orderId']),
      customerName: r.string(const ['customer_name', 'customerName']),
      totalAmountCentavos: total,
      srpTotalCentavos: r.centavos(const [
        'srp_total_centavos',
        'srpTotalCentavos',
      ], defaultValue: srpFromItems == 0 ? total : srpFromItems),
      customerPayAmountCentavos: r.centavos(const [
        'customer_pay_amount_centavos',
        'customerPayAmountCentavos',
      ], defaultValue: normalizedDiscounted ?? total),
      status: r.string(const ['status'], defaultValue: 'Pending'),
      orderDate: r.date(const ['order_date', 'orderDate']),
      notes: r.optionalString(const ['notes']),
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
      isDeleted: r.boolean(const ['is_deleted', 'isDeleted']),
      deletedAt: r.optionalDate(const ['deleted_at', 'deletedAt']),
      paymentMethod: paymentMethod,
      paymentReference: r.optionalString(const [
        'payment_reference',
        'paymentReference',
      ]),
      isReseller: r.boolean(const ['is_reseller', 'isReseller']),
      deductionPerItemCentavos: r.centavos(
        const ['deduction_per_item_centavos', 'deductionPerItemCentavos'],
        legacyMoneyKeys: const ['discount_percent'],
        defaultValue: 0,
      ),
      discountedTotalCentavos: normalizedDiscounted,
      orderType: r.string(const [
        'order_type',
        'orderType',
      ], defaultValue: 'regular'),
      stockDeducted: r.boolean(const [
        'stock_deducted',
        'stockDeducted',
      ], defaultValue: true),
      stockReleasedOnDelete: r.boolean(const [
        'stock_released_on_delete',
        'stockReleasedOnDelete',
      ]),
      commandId: r.optionalString(const ['command_id', 'commandId']),
      items: List.unmodifiable(items),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'order_id': orderId,
    'customer_name': customerName,
    'total_amount_centavos': totalAmountCentavos,
    'srp_total_centavos': srpTotalCentavos,
    'customer_pay_amount_centavos': customerPayAmountCentavos,
    'status': status,
    'order_date': orderDate.toIso8601String(),
    'notes': notes,
    'user_id': userId,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
    'payment_method': paymentMethod,
    'payment_reference': paymentReference,
    'is_reseller': isReseller ? 1 : 0,
    'deduction_per_item_centavos': deductionPerItemCentavos,
    'discounted_total_centavos': discountedTotalCentavos,
    'order_type': orderType,
    'stock_deducted': stockDeducted ? 1 : 0,
    'stock_released_on_delete': stockReleasedOnDelete ? 1 : 0,
    'command_id': commandId,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => {
    ...toLocal(),
    'items': items.map((item) => item.toCloud()).toList(growable: false),
  };

  Order toDomain() => Order(
    id: id,
    orderId: orderId,
    customerName: customerName,
    items: items.map((item) => item.toDomain()).toList(growable: false),
    totalAmount: Money.fromCentavos(totalAmountCentavos),
    srpTotal: Money.fromCentavos(srpTotalCentavos),
    status: OrderStatusExtension.fromString(status),
    orderDate: orderDate,
    notes: notes,
    paymentMethod: PaymentMethodExtension.fromString(paymentMethod),
    paymentReference: paymentReference,
    isReseller: isReseller,
    deductionPerItem: Money.fromCentavos(deductionPerItemCentavos),
    discountedTotal: discountedTotalCentavos == null
        ? null
        : Money.fromCentavos(discountedTotalCentavos!),
    orderType: orderType,
    commandId: commandId,
  );

  static void validateDomain(Order order) {
    OrderDto.fromDomain(order, userId: 'validation-owner');
  }
}
