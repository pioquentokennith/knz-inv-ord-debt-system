import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/activity_log_dto.dart';
import 'package:knz_scent_admin/dto/custom_order_dto.dart';
import 'package:knz_scent_admin/dto/debt_dto.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/dto/product_dto.dart';
import 'package:knz_scent_admin/dto/reseller_dto.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/payment_method_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
  const userId = 'user-1';
  late Database source;
  late Database restored;
  late Directory testDirectory;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'knz_dto_round_trip_',
    );
    source = await databaseFactoryFfi.openDatabase(
      path.join(testDirectory.path, 'source.db'),
    );
    restored = await databaseFactoryFfi.openDatabase(
      path.join(testDirectory.path, 'restored.db'),
    );
    await DatabaseHelper.createSchemaForTesting(source);
    await DatabaseHelper.createSchemaForTesting(restored);
  });

  tearDown(() async {
    await source.close();
    await restored.close();
    await testDirectory.delete(recursive: true);
  });

  test('Product local to DTO to cloud to fresh database round trip', () async {
    final original = ProductDto.fromDomain(
      Product(
        id: 'product-1',
        name: 'Rose',
        description: 'Floral',
        category: ProductCategory.eauDeParfum,
        price: const Money.fromCentavos(12345),
        stockQty: 8,
        minStockLevel: 2,
        imagePath: 'https://example.test/rose.png',
        createdAt: createdAt,
      ),
      userId: userId,
      isDeleted: true,
      deletedAt: createdAt.add(const Duration(days: 1)),
    );
    await source.insert('products', original.toLocal());

    final dto = ProductDto.fromLocal((await source.query('products')).single);
    final cloud = dto.toCloud();
    expect(cloud['image_path'], isNull);
    final incoming = ProductDto.fromCloud(cloud, userId: userId);
    await restored.insert('products', incoming.toLocal());

    expect(
      (await restored.query('products')).single,
      _withSyncDefaults({...dto.toLocal(), 'image_path': null}),
    );
    expect(incoming.toDomain().price.centavos, 12345);
  });

  test('Order local to DTO to cloud to fresh database round trip', () async {
    final order = Order(
      id: 'order-1',
      orderId: 'KNZ-007',
      customerName: 'Customer',
      items: [
        OrderItem(
          id: 'item-1',
          productId: 'product-1',
          productName: 'Rose',
          unitPrice: const Money.fromCentavos(17000),
          srpPrice: const Money.fromCentavos(20000),
          quantity: 2,
        ),
      ],
      totalAmount: const Money.fromCentavos(34000),
      srpTotal: const Money.fromCentavos(40000),
      status: OrderStatus.shipped,
      orderDate: createdAt,
      notes: 'Handle carefully',
      paymentMethod: PaymentMethod.gcash,
      paymentReference: 'GC-123',
      isReseller: true,
      deductionPerItem: const Money.fromCentavos(3000),
      discountedTotal: const Money.fromCentavos(34000),
      orderType: 'customized',
      commandId: 'command-7',
    );
    final original = OrderDto.fromDomain(order, userId: userId);
    await source.insert('orders', original.toLocal());
    for (final item in original.items) {
      await source.insert('order_items', item.toLocal());
    }

    final dto = OrderDto.fromLocal(
      (await source.query('orders')).single,
      await source.query('order_items'),
    );
    final incoming = OrderDto.fromCloud(dto.toCloud(), userId: userId);
    await restored.insert('orders', incoming.toLocal());
    for (final item in incoming.items) {
      await restored.insert('order_items', item.toLocal());
    }

    expect(
      (await restored.query('orders')).single,
      _withSyncDefaults(dto.toLocal(), order: true),
    );
    expect(await restored.query('order_items'), [dto.items.single.toLocal()]);
    final domain = incoming.toDomain();
    expect(domain.paymentMethod, PaymentMethod.gcash);
    expect(domain.paymentReference, 'GC-123');
    expect(domain.customerPayAmount.centavos, 34000);
    expect(domain.items.single.srpPrice.centavos, 20000);
    expect(domain.commandId, 'command-7');
  });

  test(
    'Order Item local to DTO to cloud to fresh database round trip',
    () async {
      await _insertOrderParent(source);
      await _insertOrderParent(restored);
      final original = OrderItemDto(
        id: 'item-1',
        orderId: 'order-1',
        productId: 'product-1',
        productName: 'Rose',
        unitPriceCentavos: 17000,
        srpPriceCentavos: 20000,
        quantity: 3,
      );
      await source.insert('order_items', original.toLocal());
      final dto = OrderItemDto.fromLocal(
        (await source.query('order_items')).single,
      );
      final incoming = OrderItemDto.fromCloud(
        dto.toCloud(),
        orderId: 'order-1',
        legacyIndex: 0,
      );
      await restored.insert('order_items', incoming.toLocal());
      expect((await restored.query('order_items')).single, dto.toLocal());
    },
  );

  test('Debt local to DTO to cloud to fresh database round trip', () async {
    final payment = PaymentRecord(
      id: 'payment-1',
      amount: const Money.fromCentavos(10000),
      interestApplied: const Money.fromCentavos(1000),
      principalApplied: const Money.fromCentavos(9000),
      paidAt: createdAt.add(const Duration(days: 1)),
      paymentMethod: 'Cash',
      reference: 'OR-1',
      note: 'First payment',
    );
    final debt = CustomerDebt(
      id: 'debt-1',
      customerName: 'Customer',
      orderId: 'KNZ-007',
      principalOriginal: const Money.fromCentavos(10000),
      principalOutstanding: const Money.fromCentavos(1000),
      createdAt: createdAt,
      payments: [payment],
      interestRateBasisPoints: 1000,
      interestType: 'daily',
      interestStartTimestamp: createdAt,
      lastAccrualTimestamp: createdAt.add(const Duration(days: 1)),
      dueDate: DateTime.utc(2026, 1, 15),
    );
    final original = DebtDto.fromDomain(debt, userId: userId);
    await source.insert('debts', original.toLocal());
    await source.insert('payments', original.payments.single.toLocal());

    final dto = DebtDto.fromLocal(
      (await source.query('debts')).single,
      await source.query('payments'),
    );
    final incoming = DebtDto.fromCloud(dto.toCloud(), userId: userId);
    await restored.insert('debts', incoming.toLocal());
    for (final row in incoming.payments) {
      await restored.insert('payments', row.toLocal());
    }

    expect(
      (await restored.query('debts')).single,
      _withSyncDefaults(dto.toLocal()),
    );
    expect(await restored.query('payments'), [dto.payments.single.toLocal()]);
    expect(incoming.toDomain().interestRateBasisPoints, 1000);
    expect(incoming.toDomain().dueDate, DateTime.utc(2026, 1, 15));
  });

  test('Payment local to DTO to cloud to fresh database round trip', () async {
    await _insertDebtParent(source);
    await _insertDebtParent(restored);
    final original = PaymentDto(
      id: 'payment-1',
      debtId: 'debt-1',
      amountCentavos: 2500,
      interestAppliedCentavos: 500,
      principalAppliedCentavos: 2000,
      paidAt: createdAt,
      paymentMethod: 'Cash',
      reference: 'OR-1',
      note: 'Partial',
    );
    await source.insert('payments', original.toLocal());
    final dto = PaymentDto.fromLocal((await source.query('payments')).single);
    final incoming = PaymentDto.fromCloud(dto.toCloud(), debtId: 'debt-1');
    await restored.insert('payments', incoming.toLocal());
    expect((await restored.query('payments')).single, dto.toLocal());
  });

  test('Reseller local to DTO to cloud to fresh database round trip', () async {
    final original = ResellerDto.fromDomain(
      Reseller(
        id: 'reseller-1',
        name: 'Partner',
        contact: '0917',
        deductionPerItem: const Money.fromCentavos(3000),
        userId: userId,
        createdAt: createdAt,
      ),
      isDeleted: true,
      deletedAt: createdAt,
    );
    await source.insert('resellers', original.toLocal());
    final dto = ResellerDto.fromLocal((await source.query('resellers')).single);
    final incoming = ResellerDto.fromCloud(dto.toCloud(), userId: userId);
    await restored.insert('resellers', incoming.toLocal());
    expect(
      (await restored.query('resellers')).single,
      _withSyncDefaults(dto.toLocal()),
    );
  });

  test(
    'Custom Order local to DTO to cloud to fresh database round trip',
    () async {
      final payment = CustomOrderPayment(
        id: 'custom-payment-1',
        customOrderId: 'custom-1',
        amount: const Money.fromCentavos(12550),
        paidAt: createdAt,
        note: 'Deposit',
      );
      final order = CustomOrder(
        id: 'custom-1',
        customerName: 'Customer',
        contact: '0917',
        fragranceSpecs: 'Rose and oud',
        agreedPrice: const Money.fromCentavos(50000),
        depositPaid: const Money.fromCentavos(12550),
        payments: [payment],
        deliveryDate: createdAt.add(const Duration(days: 30)),
        status: CustomOrderStatus.cancelled,
        terms: 'Non-refundable deposit',
        userId: userId,
        createdAt: createdAt,
      );
      final original = CustomOrderDto.fromDomain(order);
      await source.insert('custom_orders', original.toLocal());
      await source.insert(
        'custom_order_payments',
        original.payments.single.toLocal(),
      );

      final dto = CustomOrderDto.fromLocal(
        (await source.query('custom_orders')).single,
        await source.query('custom_order_payments'),
      );
      final incoming = CustomOrderDto.fromCloud(dto.toCloud(), userId: userId);
      await restored.insert('custom_orders', incoming.toLocal());
      for (final row in incoming.payments) {
        await restored.insert('custom_order_payments', row.toLocal());
      }

      expect(
        (await restored.query('custom_orders')).single,
        _withSyncDefaults(dto.toLocal()),
      );
      expect(await restored.query('custom_order_payments'), [
        dto.payments.single.toLocal(),
      ]);
      expect(incoming.toDomain().status, CustomOrderStatus.cancelled);
    },
  );

  test(
    'Custom Order Payment local to DTO to cloud to fresh database round trip',
    () async {
      await _insertCustomOrderParent(source);
      await _insertCustomOrderParent(restored);
      final original = CustomOrderPaymentDto(
        id: 'custom-payment-1',
        customOrderId: 'custom-1',
        amountCentavos: 12550,
        paidAt: createdAt,
        note: 'Deposit',
      );
      await source.insert('custom_order_payments', original.toLocal());
      final dto = CustomOrderPaymentDto.fromLocal(
        (await source.query('custom_order_payments')).single,
      );
      final incoming = CustomOrderPaymentDto.fromCloud(
        dto.toCloud(),
        customOrderId: 'custom-1',
      );
      await restored.insert('custom_order_payments', incoming.toLocal());
      expect(
        (await restored.query('custom_order_payments')).single,
        dto.toLocal(),
      );
    },
  );

  test(
    'Activity Log local to DTO to cloud to fresh database round trip',
    () async {
      final original = ActivityLogDto.fromDomain(
        ActivityLog(
          id: 'log-uuid-1',
          message: 'Order created',
          timestamp: createdAt,
          type: 'order',
        ),
        userId,
      );
      await source.insert('activity_logs', original.toLocal());
      final dto = ActivityLogDto.fromLocal(
        (await source.query('activity_logs')).single,
      );
      final incoming = ActivityLogDto.fromCloud(dto.toCloud(), userId: userId);
      await restored.insert('activity_logs', incoming.toLocal());
      expect((await restored.query('activity_logs')).single, dto.toLocal());
      expect(incoming.toDomain().id, 'log-uuid-1');
    },
  );

  test('older cloud defaults are explicit and future versions fail', () {
    final legacyProduct = ProductDto.fromCloud({
      'id': 'product-legacy',
      'name': 'Legacy Rose',
      'category': 'Perfume',
      'price': 100,
      'created_at': createdAt.toIso8601String(),
    }, userId: userId);
    expect(legacyProduct.category, 'Eau de Parfum');

    final legacyOrder = OrderDto.fromCloud({
      'id': 'order-1',
      'order_id': 'KNZ-001',
      'customer_name': 'Customer',
      'total_amount': 100,
      'status': 'Pending',
      'order_date': createdAt.toIso8601String(),
      'items': [
        {
          'product_id': 'product-1',
          'product_name': 'Rose',
          'unit_price': 100,
          'quantity': 1,
        },
      ],
    }, userId: userId);
    expect(legacyOrder.customerPayAmountCentavos, 10000);
    expect(legacyOrder.items.single.srpPriceCentavos, 10000);
    expect(legacyOrder.orderType, 'regular');

    expect(
      () => ProductDto.fromCloud({
        'schema_version': 2,
        'id': 'product-1',
      }, userId: userId),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _withSyncDefaults(
  Map<String, dynamic> data, {
  bool order = false,
}) => {
  ...data,
  'revision': 0,
  'base_revision': 0,
  'updated_at': null,
  'writer_device_id': null,
  'tombstone_revision': 0,
  'purge_state': 'none',
  if (order) 'number_state': 'legacy',
  if (order) 'provisional_order_id': null,
};

Future<void> _insertOrderParent(Database database) =>
    database.insert('orders', {
      'id': 'order-1',
      'order_id': 'KNZ-001',
      'customer_name': 'Customer',
      'total_amount_centavos': 10000,
      'srp_total_centavos': 10000,
      'customer_pay_amount_centavos': 10000,
      'status': 'Pending',
      'order_date': '2026-01-01T00:00:00.000Z',
      'user_id': 'user-1',
    });

Future<void> _insertDebtParent(Database database) => database.insert('debts', {
  'id': 'debt-1',
  'customer_name': 'Customer',
  'order_id': 'KNZ-001',
  'principal_original_centavos': 10000,
  'principal_outstanding_centavos': 10000,
  'interest_outstanding_centavos': 0,
  'created_at': '2026-01-01T00:00:00.000Z',
  'user_id': 'user-1',
  'interest_start_timestamp': '2026-01-01T00:00:00.000Z',
  'last_accrual_timestamp': '2026-01-01T00:00:00.000Z',
});

Future<void> _insertCustomOrderParent(Database database) =>
    database.insert('custom_orders', {
      'id': 'custom-1',
      'customer_name': 'Customer',
      'fragrance_specs': 'Rose',
      'agreed_price_centavos': 50000,
      'deposit_paid_centavos': 12550,
      'delivery_date': '2026-02-01T00:00:00.000Z',
      'user_id': 'user-1',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
