import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/repositories/local_custom_order_repository.dart';
import 'package:knz_scent_admin/repositories/local_reseller_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Outbox implements SyncOutbox {
  var key = 0;

  @override
  bool get isOnline => false;

  @override
  Future<int> enqueue({
    required String operation,
    required String collection,
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
    DatabaseExecutor? executor,
  }) {
    if (executor == null) throw StateError('Transaction required.');
    final now = DateTime.utc(2026).toIso8601String();
    return executor.insert('sync_queue', {
      'operation': operation,
      'collection': collection,
      'user_id': userId,
      'doc_id': docId,
      'data': jsonEncode(data),
      'created_at': now,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_attempt_at': null,
      'last_error': null,
      'status': 'pending',
      'idempotency_key': 'entity-${key++}',
      'updated_at': now,
    });
  }

  @override
  void requestSync() {}
}

void main() {
  sqfliteFfiInit();

  late Database database;
  late _Outbox outbox;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(database);
    outbox = _Outbox();
  });

  tearDown(() => database.close());

  test(
    'reseller mutations commit with durable upserts and tombstones',
    () async {
      final repository = LocalResellerRepository(
        databaseProvider: () async => database,
        queue: outbox,
      );
      final reseller = Reseller(
        id: 'reseller-1',
        name: 'Partner',
        deductionPerItem: const Money.fromCentavos(1000),
        userId: 'user-1',
        createdAt: DateTime.utc(2026),
      );

      await repository.save(reseller);
      await repository.delete(reseller.id, reseller.userId);
      await repository.restore(reseller.id, reseller.userId);

      final queuedRows = await database.query('sync_queue');
      final operations = queuedRows.map((row) => row['operation']).toList();
      expect(operations, [
        'save_reseller',
        'soft_delete_reseller',
        'save_reseller',
      ]);
      final tombstone = jsonDecode(queuedRows[1]['data'] as String);
      expect(tombstone['name'], 'Partner');
      expect(tombstone['deduction_per_item_centavos'], 1000);
      expect(tombstone['is_deleted'], 1);
      expect(tombstone['deleted_at'], isNotNull);
      expect((await database.query('resellers')).single['is_deleted'], 0);
    },
  );

  test(
    'custom-order mutations commit with durable upserts and tombstones',
    () async {
      final repository = LocalCustomOrderRepository(
        databaseProvider: () async => database,
        queue: outbox,
      );
      final payment = CustomOrderPayment(
        id: 'custom-payment-1',
        customOrderId: 'custom-1',
        amount: const Money.fromCentavos(10000),
        paidAt: DateTime.utc(2026, 1, 2),
        note: 'Deposit',
      );
      final order = CustomOrder(
        id: 'custom-1',
        customerName: 'Customer',
        fragranceSpecs: 'Rose',
        agreedPrice: const Money.fromCentavos(50000),
        depositPaid: const Money.fromCentavos(10000),
        payments: [payment],
        deliveryDate: DateTime.utc(2026, 2),
        userId: 'user-1',
        createdAt: DateTime.utc(2026),
      );

      await repository.save(order);
      final laterPayment = CustomOrderPayment(
        id: 'custom-payment-2',
        customOrderId: order.id,
        amount: const Money.fromCentavos(5000),
        paidAt: DateTime.utc(2026, 1, 15),
        note: 'Later payment',
      );
      await repository.update(
        order.copyWith(
          depositPaid: const Money.fromCentavos(15000),
          payments: [payment, laterPayment],
        ),
      );
      await repository.delete(order.id, order.userId);
      await repository.restore(order.id, order.userId);

      final queuedRows = await database.query('sync_queue');
      final operations = queuedRows.map((row) => row['operation']).toList();
      expect(operations, [
        'save_custom_order_with_events',
        'apply_custom_order_payment',
        'soft_delete_custom_order',
        'save_custom_order',
      ]);
      final tombstone = jsonDecode(queuedRows[2]['data'] as String);
      expect(tombstone['customer_name'], 'Customer');
      expect(tombstone['fragrance_specs'], 'Rose');
      expect(tombstone['is_deleted'], 1);
      expect(tombstone['deleted_at'], isNotNull);
      expect(tombstone['schema_version'], 1);
      expect(tombstone['_payments'], hasLength(2));
      expect(tombstone['_payments'][0]['amount_centavos'], 10000);
      expect(tombstone['_payments'][1]['amount_centavos'], 5000);
      expect((await database.query('custom_orders')).single['is_deleted'], 0);
      expect(await database.query('custom_order_payments'), hasLength(2));
      final events = await database.query(
        'business_events',
        orderBy: 'occurred_at',
      );
      expect(events, hasLength(2));
      expect(events.first['event_type'], 'collection');
      expect(events.last['amount_centavos'], 5000);
    },
  );

  test('custom-order payment history cannot be removed or rewritten', () async {
    final repository = LocalCustomOrderRepository(
      databaseProvider: () async => database,
      queue: outbox,
    );
    final payment = CustomOrderPayment(
      id: 'immutable-payment',
      customOrderId: 'custom-immutable',
      amount: const Money.fromCentavos(10000),
      paidAt: DateTime.utc(2026, 1, 2),
      note: 'Deposit',
    );
    final order = CustomOrder(
      id: 'custom-immutable',
      customerName: 'Customer',
      fragranceSpecs: 'Rose',
      agreedPrice: const Money.fromCentavos(50000),
      depositPaid: const Money.fromCentavos(10000),
      payments: [payment],
      deliveryDate: DateTime.utc(2026, 2),
      userId: 'user-1',
      createdAt: DateTime.utc(2026),
    );
    await repository.save(order);

    await expectLater(
      repository.update(order.copyWith(payments: const [])),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Custom-order payment history is immutable.',
        ),
      ),
    );
    final rewritten = CustomOrderPayment(
      id: payment.id,
      customOrderId: payment.customOrderId,
      amount: const Money.fromCentavos(9000),
      paidAt: payment.paidAt,
      note: payment.note,
    );
    await expectLater(
      repository.update(
        order.copyWith(
          depositPaid: const Money.fromCentavos(9000),
          payments: [rewritten],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final stored = await database.query('custom_order_payments');
    expect(stored, hasLength(1));
    expect(stored.single['amount_centavos'], 10000);
    expect(await database.query('sync_queue'), hasLength(1));
  });
}
