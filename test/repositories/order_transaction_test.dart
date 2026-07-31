import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/domain_exceptions.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/repositories/local_order_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestOutbox implements SyncOutbox {
  int _nextKey = 0;

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
    if (executor == null) throw StateError('A transaction is required.');
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
      'idempotency_key': 'test-${_nextKey++}',
      'updated_at': now,
    });
  }

  @override
  void requestSync() {}
}

Order _order({
  required String id,
  int quantity = 1,
  OrderStatus status = OrderStatus.pending,
}) => Order(
  id: id,
  orderId: 'PENDING',
  customerName: 'Customer',
  items: [
    OrderItem(
      id: 'item-$id',
      productId: 'product-1',
      productName: 'Rose',
      unitPrice: const Money.fromCentavos(10000),
      quantity: quantity,
    ),
  ],
  totalAmount: Money.fromCentavos(10000 * quantity),
  status: status,
  orderDate: DateTime.utc(2026),
);

CustomerDebt _debt(String id) => CustomerDebt(
  id: id,
  customerName: 'Customer',
  orderId: 'PENDING',
  principalOriginal: const Money.fromCentavos(10000),
  principalOutstanding: const Money.fromCentavos(10000),
  createdAt: DateTime.utc(2026),
);

void main() {
  sqfliteFfiInit();

  late Database database;
  late _TestOutbox outbox;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createSchemaForTesting(database);
    await database.insert('products', {
      'id': 'product-1',
      'name': 'Rose',
      'description': '',
      'category': 'Perfume',
      'price_centavos': 10000,
      'stock_qty': 5,
      'min_stock_level': 1,
      'image_path': null,
      'created_at': DateTime.utc(2026).toIso8601String(),
      'user_id': 'user-1',
      'is_deleted': 0,
      'deleted_at': null,
    });
    outbox = _TestOutbox();
  });

  tearDown(() => database.close());

  LocalOrderRepository repository({
    Future<void> Function(OrderCommitStage)? hook,
  }) => LocalOrderRepository(
    databaseProvider: () async => database,
    queue: outbox,
    commitHook: hook,
  );

  Future<int> stock() async =>
      (await database.query('products')).single['stock_qty'] as int;

  Future<Object> capture(Future<Order> operation) async {
    try {
      return await operation;
    } catch (error) {
      return error;
    }
  }

  test(
    'app interruption during order creation rolls back every record',
    () async {
      final repo = repository(
        hook: (stage) async {
          if (stage == OrderCommitStage.orderAndItemsInserted) {
            throw StateError('simulated process interruption');
          }
        },
      );

      await expectLater(
        repo.addWithInventory(_order(id: 'order-1'), 'user-1'),
        throwsStateError,
      );

      expect(await database.query('orders'), isEmpty);
      expect(await database.query('order_items'), isEmpty);
      expect(await database.query('sync_queue'), isEmpty);
      expect(await stock(), 5);
    },
  );

  test(
    'partial failure after inventory adjustment rolls back debt and stock',
    () async {
      final repo = repository(
        hook: (stage) async {
          if (stage == OrderCommitStage.inventoryAdjusted) {
            throw StateError('forced failure after stock update');
          }
        },
      );

      await expectLater(
        repo.addWithInventory(
          _order(id: 'order-1', status: OrderStatus.utang),
          'user-1',
          debt: _debt('debt-1'),
        ),
        throwsStateError,
      );

      expect(await database.query('orders'), isEmpty);
      expect(await database.query('debts'), isEmpty);
      expect(await database.query('payments'), isEmpty);
      expect(await database.query('sync_queue'), isEmpty);
      expect(await stock(), 5);
    },
  );

  test('automatic debt and every cloud intent commit with the order', () async {
    final repo = repository();

    final saved = await repo.addWithInventory(
      _order(id: 'order-1', status: OrderStatus.utang),
      'user-1',
      debt: _debt('debt-1'),
    );

    expect(saved.orderId, 'KNZ-001');
    expect(await database.query('orders'), hasLength(1));
    expect(await database.query('order_items'), hasLength(1));
    expect(await database.query('debts'), hasLength(1));
    expect(await stock(), 4);
    expect(
      (await database.query(
        'sync_queue',
      )).map((row) => row['operation']).toList(),
      ['save_product', 'save_debt', 'save_order'],
    );
  });

  test(
    'two concurrent attempts cannot oversell stock or duplicate IDs',
    () async {
      await database.update('products', {'stock_qty': 1});
      final repo = repository();
      final results = await Future.wait<Object>([
        capture(repo.addWithInventory(_order(id: 'order-1'), 'user-1')),
        capture(repo.addWithInventory(_order(id: 'order-2'), 'user-1')),
      ]);

      expect(results.whereType<Order>(), hasLength(1));
      expect(results.whereType<StockShortageException>(), hasLength(1));
      expect(await database.query('orders'), hasLength(1));
      expect(await stock(), 0);
      expect((await database.query('orders')).single['order_id'], 'KNZ-001');
    },
  );

  test('database rejects a duplicate readable order ID for one user', () async {
    final repo = repository();
    await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
    final first = (await database.query('orders')).single;

    await expectLater(
      database.insert('orders', {...first, 'id': 'order-duplicate'}),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('invalid order transition is rejected without changing stock', () async {
    final repo = repository();
    await repo.addWithInventory(_order(id: 'order-1'), 'user-1');

    await expectLater(
      repo.updateStatus('order-1', OrderStatus.delivered),
      throwsA(isA<InvalidOrderTransitionException>()),
    );
    expect(await stock(), 4);
    expect((await database.query('orders')).single['status'], 'Pending');
  });

  test(
    'cancellation releases stock and reactivation conditionally reserves it',
    () async {
      final repo = repository();
      await repo.addWithInventory(_order(id: 'order-1', quantity: 2), 'user-1');
      await repo.updateStatus('order-1', OrderStatus.processing);
      await repo.updateStatus('order-1', OrderStatus.cancelled);
      expect(await stock(), 5);

      await repo.updateStatus('order-1', OrderStatus.pending);
      expect(await stock(), 3);
      final row = (await database.query('orders')).single;
      expect(row['status'], 'Pending');
      expect(row['stock_deducted'], 1);
    },
  );

  test(
    'delivery keeps stock consumed while delete and restore remain neutral',
    () async {
      final repo = repository();
      await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
      await repo.updateStatus('order-1', OrderStatus.processing);
      await repo.updateStatus('order-1', OrderStatus.shipped);
      await repo.updateStatus('order-1', OrderStatus.delivered);
      expect(await stock(), 4);

      await repo.deleteWithInventory('order-1');
      expect(await stock(), 5);
      final tombstoneRow = (await database.query(
        'sync_queue',
        where: 'operation = ?',
        whereArgs: ['soft_delete_order'],
      )).single;
      final tombstone = jsonDecode(tombstoneRow['data'] as String);
      expect(tombstone['customer_name'], 'Customer');
      expect(tombstone['_items'], hasLength(1));
      expect(tombstone['stock_released_on_delete'], 1);
      await repo.restoreWithInventory('order-1');
      expect(await stock(), 4);
      expect((await database.query('orders')).single['status'], 'Delivered');
    },
  );

  test(
    'restore with insufficient stock preserves tombstone and exact stock',
    () async {
      final repo = repository();
      await repo.addWithInventory(_order(id: 'order-1', quantity: 2), 'user-1');
      await repo.deleteWithInventory('order-1');
      expect(await stock(), 5);
      await database.update('products', {'stock_qty': 1});
      final beforeOutbox = (await database.query('sync_queue')).length;

      await expectLater(
        repo.restoreWithInventory('order-1'),
        throwsA(
          isA<StockShortageException>().having(
            (error) => error.message,
            'message',
            'Insufficient stock for Rose: need 2, have 1.',
          ),
        ),
      );

      expect(await stock(), 1);
      expect((await database.query('orders')).single['is_deleted'], 1);
      expect((await database.query('sync_queue')).length, beforeOutbox);
    },
  );

  test('open debt blocks order cancellation and deletion', () async {
    final repo = repository();
    await repo.addWithInventory(
      _order(id: 'order-1', status: OrderStatus.utang),
      'user-1',
      debt: _debt('debt-1'),
    );

    await expectLater(
      repo.updateStatus('order-1', OrderStatus.delivered),
      throwsA(isA<OpenDebtException>()),
    );
    await expectLater(
      repo.deleteWithInventory('order-1'),
      throwsA(isA<OpenDebtException>()),
    );
    expect(await stock(), 4);
  });

  test(
    'settled utang may advance to delivered without changing stock',
    () async {
      final repo = repository();
      await repo.addWithInventory(
        _order(id: 'order-1', status: OrderStatus.utang),
        'user-1',
        debt: _debt('debt-1'),
      );
      await database.update(
        'debts',
        {
          'principal_outstanding_centavos': 0,
          'interest_outstanding_centavos': 0,
          'status': 'paid',
        },
        where: 'id = ?',
        whereArgs: ['debt-1'],
      );
      await database.insert('payments', {
        'id': 'payment-1',
        'debt_id': 'debt-1',
        'amount_centavos': 10000,
        'interest_applied_centavos': 0,
        'principal_applied_centavos': 10000,
        'paid_at': DateTime.utc(2026).toIso8601String(),
        'payment_method': 'Cash',
        'reference': null,
        'note': null,
      });

      await repo.updateStatus('order-1', OrderStatus.delivered);

      expect((await database.query('orders')).single['status'], 'Delivered');
      expect(await stock(), 4);
    },
  );

  test('readable sequence is not reused after permanent purge', () async {
    final repo = repository();
    final first = await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
    await repo.deleteWithInventory('order-1');
    await repo.hardDelete('order-1');
    final second = await repo.addWithInventory(_order(id: 'order-2'), 'user-1');

    expect(first.orderId, 'KNZ-001');
    expect(second.orderId, 'KNZ-002');
  });
}
