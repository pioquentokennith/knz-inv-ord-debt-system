import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/domain_exceptions.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/repositories/local_order_repository.dart';
import 'package:knz_scent_admin/repositories/order_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:path/path.dart' as path;
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

class _FailingOutbox extends _TestOutbox {
  @override
  Future<int> enqueue({
    required String operation,
    required String collection,
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
    DatabaseExecutor? executor,
  }) => throw StateError('simulated event outbox failure');
}

Order _order({
  required String id,
  String? commandId,
  int quantity = 1,
  OrderStatus status = OrderStatus.pending,
  int unitPriceCentavos = 10000,
  int? srpPriceCentavos,
  int? totalCentavos,
  int? srpTotalCentavos,
  int? discountedTotalCentavos,
  bool isReseller = false,
  int deductionPerItemCentavos = 0,
}) => Order(
  id: id,
  orderId: 'PENDING',
  customerName: 'Customer',
  items: [
    OrderItem(
      id: 'item-$id',
      productId: 'product-1',
      productName: 'Rose',
      unitPrice: Money.fromCentavos(unitPriceCentavos),
      srpPrice: srpPriceCentavos == null
          ? null
          : Money.fromCentavos(srpPriceCentavos),
      quantity: quantity,
    ),
  ],
  totalAmount: Money.fromCentavos(
    totalCentavos ?? unitPriceCentavos * quantity,
  ),
  srpTotal: srpTotalCentavos == null
      ? null
      : Money.fromCentavos(srpTotalCentavos),
  status: status,
  orderDate: DateTime.utc(2026),
  isReseller: isReseller,
  deductionPerItem: Money.fromCentavos(deductionPerItemCentavos),
  discountedTotal: discountedTotalCentavos == null
      ? null
      : Money.fromCentavos(discountedTotalCentavos),
  commandId: commandId ?? 'command-$id',
);

BusinessEvent _delivery(String orderId, {String? id}) {
  final eventId = id ?? 'delivery-$orderId';
  return BusinessEvent(
    id: eventId,
    userId: 'user-1',
    subject: BusinessEventSubject.order,
    subjectId: orderId,
    type: BusinessEventType.delivery,
    occurredAt: DateTime.utc(2026, 1, 2),
    recordedAt: DateTime.utc(2026, 1, 2),
    commandId: eventId,
  );
}

BusinessEvent _financialEvent({
  required String id,
  required String orderId,
  required BusinessEventType type,
  required int amountCentavos,
  String? relatedEventId,
  String? reason,
}) => BusinessEvent(
  id: id,
  userId: 'user-1',
  subject: BusinessEventSubject.order,
  subjectId: orderId,
  type: type,
  amount: Money.fromCentavos(amountCentavos),
  occurredAt: DateTime.utc(2026, 1, 2),
  recordedAt: DateTime.utc(2026, 1, 2),
  paymentMethod: type == BusinessEventType.payment ? 'cash_on_delivery' : null,
  relatedEventId: relatedEventId,
  reason: reason,
  commandId: id,
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

  Future<Object> capture(Future<OrderCreationResult> operation) async {
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

    expect(saved.order.orderId, matches(r'^TMP-[A-F0-9]{4}-000001$'));
    expect(saved.created, isTrue);
    expect(await database.query('orders'), hasLength(1));
    expect(await database.query('order_items'), hasLength(1));
    expect(await database.query('debts'), hasLength(1));
    expect(await stock(), 4);
    await _expectSingleCommandEffects(
      database,
      expectedStock: 4,
      expectedDebtCount: 1,
    );
  });

  test(
    'persists reconciled discounted headers, lines, and outbox data',
    () async {
      final repo = repository();

      await repo.addWithInventory(
        _order(
          id: 'discounted-order',
          quantity: 2,
          unitPriceCentavos: 17000,
          srpPriceCentavos: 20000,
          totalCentavos: 34000,
          srpTotalCentavos: 40000,
          discountedTotalCentavos: 34000,
          isReseller: true,
          deductionPerItemCentavos: 3000,
        ),
        'user-1',
      );

      final orderRow = (await database.query('orders')).single;
      expect(orderRow['total_amount_centavos'], 34000);
      expect(orderRow['srp_total_centavos'], 40000);
      expect(orderRow['customer_pay_amount_centavos'], 34000);
      expect(orderRow['discounted_total_centavos'], 34000);

      final itemRow = (await database.query('order_items')).single;
      expect(itemRow['unit_price_centavos'], 17000);
      expect(itemRow['srp_price_centavos'], 20000);
      expect(itemRow['quantity'], 2);

      final queueRow = (await database.query('sync_queue')).single;
      final payload =
          jsonDecode(queueRow['data'] as String) as Map<String, dynamic>;
      final cloudOrder = payload['_order'] as Map<String, dynamic>;
      expect(cloudOrder['total_amount_centavos'], 34000);
      expect(cloudOrder['srp_total_centavos'], 40000);
      expect(cloudOrder['customer_pay_amount_centavos'], 34000);
      final cloudItem =
          (cloudOrder['_items'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(cloudItem['unit_price_centavos'], 17000);
      expect(cloudItem['srp_price_centavos'], 20000);
    },
  );

  test('rejects an SRP header mismatch before writing anything', () async {
    final repo = repository();

    await expectLater(
      repo.addWithInventory(
        _order(
          id: 'bad-srp',
          unitPriceCentavos: 9000,
          srpPriceCentavos: 10000,
          totalCentavos: 9000,
          srpTotalCentavos: 9999,
        ),
        'user-1',
      ),
      throwsArgumentError,
    );

    await _expectRejectedOrderLeavesNoWrites(database);
  });

  test('rejects a net header mismatch before writing anything', () async {
    final repo = repository();

    await expectLater(
      repo.addWithInventory(
        _order(
          id: 'bad-net',
          unitPriceCentavos: 9000,
          srpPriceCentavos: 10000,
          totalCentavos: 8999,
          srpTotalCentavos: 10000,
        ),
        'user-1',
      ),
      throwsArgumentError,
    );

    await _expectRejectedOrderLeavesNoWrites(database);
  });

  test('rejects a discounted customer-pay mismatch before writing', () async {
    final repo = repository();

    await expectLater(
      repo.addWithInventory(
        _order(
          id: 'bad-discounted-net',
          unitPriceCentavos: 9000,
          srpPriceCentavos: 10000,
          totalCentavos: 9000,
          srpTotalCentavos: 10000,
          discountedTotalCentavos: 8999,
          isReseller: true,
        ),
        'user-1',
      ),
      throwsArgumentError,
    );

    await _expectRejectedOrderLeavesNoWrites(database);
  });

  test('a new cancelled order does not consume inventory', () async {
    final repo = repository();

    final saved = await repo.addWithInventory(
      _order(id: 'order-1', status: OrderStatus.cancelled),
      'user-1',
    );

    expect(saved.order.status, OrderStatus.cancelled);
    expect(await stock(), 5);
    final orderRow = (await database.query('orders')).single;
    expect(orderRow['stock_deducted'], 0);

    final outboxRow = (await database.query('sync_queue')).single;
    final payload = jsonDecode(outboxRow['data'] as String);
    expect(payload['_products'], isEmpty);
    expect(payload['_order']['stock_deducted'], 0);
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

      expect(results.whereType<OrderCreationResult>(), hasLength(1));
      expect(results.whereType<StockShortageException>(), hasLength(1));
      expect(await database.query('orders'), hasLength(1));
      expect(await stock(), 0);
      expect(
        (await database.query('orders')).single['order_id'],
        matches(r'^TMP-[A-F0-9]{4}-000001$'),
      );
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
      repo.recordDelivery('order-1', _delivery('order-1')),
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
      await repo.recordDelivery('order-1', _delivery('order-1'));
      expect(await stock(), 4);

      await repo.deleteWithInventory('order-1', 'user-1');
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
      await repo.restoreWithInventory('order-1', 'user-1');
      expect(await stock(), 4);
      expect((await database.query('orders')).single['status'], 'Delivered');
    },
  );

  test(
    'payment refund and reversal append exact immutable cash facts',
    () async {
      final repo = repository();
      await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
      final payment = _financialEvent(
        id: 'payment-event',
        orderId: 'order-1',
        type: BusinessEventType.payment,
        amountCentavos: 6000,
      );
      final refund = _financialEvent(
        id: 'refund-event',
        orderId: 'order-1',
        type: BusinessEventType.refund,
        amountCentavos: 1000,
        reason: 'Returned item',
      );
      final reversal = _financialEvent(
        id: 'reversal-event',
        orderId: 'order-1',
        type: BusinessEventType.reversal,
        amountCentavos: 1000,
        relatedEventId: refund.id,
        reason: 'Refund entered in error',
      );

      await repo.recordPayment('order-1', payment);
      await repo.issueRefund('order-1', refund);
      await repo.reverseEvent('order-1', reversal);

      final rows = await database.query(
        'business_events',
        orderBy: 'recorded_at',
      );
      expect(rows, hasLength(3));
      expect(rows.map((row) => row['event_type']), [
        'payment',
        'refund',
        'reversal',
      ]);
      final events = rows
          .map((row) => BusinessEventDto.fromLocal(row).toDomain())
          .toList();
      expect(BusinessEventLedger.netCash(events).centavos, 6000);
      expect(
        await database.query(
          'sync_queue',
          where: 'operation = ?',
          whereArgs: ['save_business_event'],
        ),
        hasLength(3),
      );

      await expectLater(
        database.update(
          'business_events',
          {'amount_centavos': 1},
          where: 'id = ?',
          whereArgs: [payment.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        database.delete(
          'business_events',
          where: 'id = ?',
          whereArgs: [payment.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test('event command replay is idempotent and payload changes fail', () async {
    final repo = repository();
    await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
    final event = _financialEvent(
      id: 'payment-event',
      orderId: 'order-1',
      type: BusinessEventType.payment,
      amountCentavos: 6000,
    );

    final first = await repo.recordPayment('order-1', event);
    final replay = await repo.recordPayment('order-1', event);
    expect(replay.id, first.id);
    expect(await database.query('business_events'), hasLength(1));

    await expectLater(
      repo.recordPayment(
        'order-1',
        _financialEvent(
          id: event.id,
          orderId: 'order-1',
          type: BusinessEventType.payment,
          amountCentavos: 5000,
        ),
      ),
      throwsStateError,
    );
    expect(await database.query('business_events'), hasLength(1));
  });

  test(
    'overpayments and excessive refunds leave no event or outbox row',
    () async {
      final repo = repository();
      await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
      final baselineOutbox = (await database.query('sync_queue')).length;

      await expectLater(
        repo.recordPayment(
          'order-1',
          _financialEvent(
            id: 'overpayment',
            orderId: 'order-1',
            type: BusinessEventType.payment,
            amountCentavos: 10001,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.issueRefund(
          'order-1',
          _financialEvent(
            id: 'excess-refund',
            orderId: 'order-1',
            type: BusinessEventType.refund,
            amountCentavos: 1,
            reason: 'No payment exists',
          ),
        ),
        throwsArgumentError,
      );

      expect(await database.query('business_events'), isEmpty);
      expect((await database.query('sync_queue')).length, baselineOutbox);
    },
  );

  test('event and outbox roll back together when enqueue fails', () async {
    final base = repository();
    await base.addWithInventory(_order(id: 'order-1'), 'user-1');
    final failing = LocalOrderRepository(
      databaseProvider: () async => database,
      queue: _FailingOutbox(),
    );

    await expectLater(
      failing.recordPayment(
        'order-1',
        _financialEvent(
          id: 'payment-event',
          orderId: 'order-1',
          type: BusinessEventType.payment,
          amountCentavos: 5000,
        ),
      ),
      throwsStateError,
    );

    expect(await database.query('business_events'), isEmpty);
  });

  test(
    'collected direct cash blocks cancellation and Utang conversion',
    () async {
      final repo = repository();
      final created = await repo.addWithInventory(
        _order(id: 'order-1'),
        'user-1',
      );
      await repo.recordPayment(
        'order-1',
        _financialEvent(
          id: 'payment-event',
          orderId: 'order-1',
          type: BusinessEventType.payment,
          amountCentavos: 5000,
        ),
      );

      await expectLater(
        repo.updateStatus('order-1', OrderStatus.cancelled),
        throwsStateError,
      );
      await expectLater(
        repo.markAsUtang(
          'order-1',
          CustomerDebt(
            id: 'debt-cash-conflict',
            customerName: 'Customer',
            orderId: created.order.orderId,
            principalOriginal: const Money.fromCentavos(10000),
            principalOutstanding: const Money.fromCentavos(10000),
            createdAt: DateTime.utc(2026, 1, 2),
          ),
        ),
        throwsStateError,
      );

      expect((await database.query('orders')).single['status'], 'Pending');
      expect(await database.query('debts'), isEmpty);
    },
  );

  test(
    'restore with insufficient stock preserves tombstone and exact stock',
    () async {
      final repo = repository();
      await repo.addWithInventory(_order(id: 'order-1', quantity: 2), 'user-1');
      await repo.deleteWithInventory('order-1', 'user-1');
      expect(await stock(), 5);
      await database.update('products', {'stock_qty': 1});
      final beforeOutbox = (await database.query('sync_queue')).length;

      await expectLater(
        repo.restoreWithInventory('order-1', 'user-1'),
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
      repo.recordDelivery('order-1', _delivery('order-1')),
      throwsA(isA<OpenDebtException>()),
    );
    await expectLater(
      repo.deleteWithInventory('order-1', 'user-1'),
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

      await repo.recordDelivery('order-1', _delivery('order-1'));

      expect((await database.query('orders')).single['status'], 'Delivered');
      expect(await stock(), 4);
    },
  );

  test('readable sequence is not reused after permanent purge', () async {
    final repo = repository();
    final first = await repo.addWithInventory(_order(id: 'order-1'), 'user-1');
    await repo.deleteWithInventory('order-1', 'user-1');
    await repo.hardDelete('order-1', 'user-1');
    final second = await repo.addWithInventory(_order(id: 'order-2'), 'user-1');

    final firstPrefix = first.order.orderId.substring(0, 8);
    expect(first.order.orderId, matches(r'^TMP-[A-F0-9]{4}-000001$'));
    expect(second.order.orderId, '$firstPrefix-000002');
  });

  test('rapid double submission replays one committed command', () async {
    final repo = repository();
    final results = await Future.wait([
      repo.addWithInventory(
        _order(id: 'order-1', commandId: 'same-command'),
        'user-1',
      ),
      repo.addWithInventory(
        _order(id: 'order-2', commandId: 'same-command'),
        'user-1',
      ),
    ]);

    expect(results.where((result) => result.created), hasLength(1));
    expect(results.map((result) => result.order.id).toSet(), {'order-1'});
    await _expectSingleCommandEffects(database, expectedStock: 4);
  });

  test(
    'three repeated submissions change every business record once',
    () async {
      final repo = repository();
      final results = await Future.wait([
        for (var attempt = 1; attempt <= 3; attempt++)
          repo.addWithInventory(
            _order(
              id: 'order-$attempt',
              commandId: 'triple-command',
              status: OrderStatus.utang,
            ),
            'user-1',
            debt: _debt('debt-$attempt'),
          ),
      ]);

      expect(results.where((result) => result.created), hasLength(1));
      expect(results.map((result) => result.order.id).toSet(), {'order-1'});
      await _expectSingleCommandEffects(
        database,
        expectedStock: 4,
        expectedDebtCount: 1,
      );
    },
  );

  test(
    'slow save rejects concurrent repeats at the repository boundary',
    () async {
      final enteredTransaction = Completer<void>();
      final releaseTransaction = Completer<void>();
      final repo = repository(
        hook: (stage) async {
          if (stage == OrderCommitStage.orderAndItemsInserted &&
              !enteredTransaction.isCompleted) {
            enteredTransaction.complete();
            await releaseTransaction.future;
          }
        },
      );

      final first = repo.addWithInventory(
        _order(id: 'order-1', commandId: 'slow-command'),
        'user-1',
      );
      await enteredTransaction.future;
      final repeats = [
        repo.addWithInventory(
          _order(id: 'order-2', commandId: 'slow-command'),
          'user-1',
        ),
        repo.addWithInventory(
          _order(id: 'order-3', commandId: 'slow-command'),
          'user-1',
        ),
      ];
      releaseTransaction.complete();
      final results = await Future.wait([first, ...repeats]);

      expect(results.where((result) => result.created), hasLength(1));
      await _expectSingleCommandEffects(database, expectedStock: 4);
    },
  );

  test(
    'retry after a committed response timeout returns the original order',
    () async {
      final repo = repository();

      Future<void> commitThenTimeout() async {
        await repo.addWithInventory(
          _order(id: 'order-1', commandId: 'timeout-command'),
          'user-1',
        );
        throw TimeoutException('response lost after commit');
      }

      await expectLater(commitThenTimeout(), throwsA(isA<TimeoutException>()));
      final replay = await repo.addWithInventory(
        _order(id: 'order-retry', commandId: 'timeout-command'),
        'user-1',
      );

      expect(replay.created, isFalse);
      expect(replay.order.id, 'order-1');
      await _expectSingleCommandEffects(database, expectedStock: 4);
    },
  );

  test('retry after database restart returns the original order', () async {
    final directory = await Directory.systemTemp.createTemp('knz_order_retry_');
    final databasePath = path.join(directory.path, 'orders.db');
    var reopened = await DatabaseHelper.openDatabaseForTesting(
      databasePath,
      factory: databaseFactoryFfi,
    );
    await _insertProduct(reopened);
    final firstRepo = LocalOrderRepository(
      databaseProvider: () async => reopened,
      queue: _TestOutbox(),
    );
    final first = await firstRepo.addWithInventory(
      _order(id: 'persisted-order', commandId: 'restart-command'),
      'user-1',
    );
    expect(first.created, isTrue);
    await reopened.close();

    reopened = await DatabaseHelper.openDatabaseForTesting(
      databasePath,
      factory: databaseFactoryFfi,
    );
    final restartedRepo = LocalOrderRepository(
      databaseProvider: () async => reopened,
      queue: _TestOutbox(),
    );
    final replay = await restartedRepo.addWithInventory(
      _order(id: 'retry-order', commandId: 'restart-command'),
      'user-1',
    );

    expect(replay.created, isFalse);
    expect(replay.order.id, 'persisted-order');
    await _expectSingleCommandEffects(reopened, expectedStock: 4);
    await reopened.close();
    await directory.delete(recursive: true);
  });

  test('a genuinely new command creates a new order', () async {
    final repo = repository();
    final first = await repo.addWithInventory(
      _order(id: 'order-1', commandId: 'command-1'),
      'user-1',
    );
    final second = await repo.addWithInventory(
      _order(id: 'order-2', commandId: 'command-2'),
      'user-1',
    );

    expect(first.created, isTrue);
    expect(second.created, isTrue);
    expect(second.order.orderId, matches(r'^TMP-[A-F0-9]{4}-000002$'));
    expect(await database.query('orders'), hasLength(2));
    expect(await stock(), 3);
  });
}

Future<void> _insertProduct(Database database) => database.insert('products', {
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

Future<void> _expectSingleCommandEffects(
  Database database, {
  required int expectedStock,
  int expectedDebtCount = 0,
}) async {
  expect(await database.query('orders'), hasLength(1));
  expect(await database.query('order_items'), hasLength(1));
  expect(await database.query('debts'), hasLength(expectedDebtCount));
  expect((await database.query('products')).single['stock_qty'], expectedStock);
  final outbox = await database.query('sync_queue');
  expect(outbox, hasLength(1));
  final row = outbox.single;
  expect(row['operation'], 'create_order');
  expect(row['collection'], 'orders');

  final payload = jsonDecode(row['data'] as String) as Map<String, dynamic>;
  expect(payload['command_id'], isNotEmpty);
  final order = payload['_order'] as Map<String, dynamic>;
  expect(order['id'], row['doc_id']);
  expect(order['command_id'], payload['command_id']);
  expect(order['_items'], hasLength(1));

  final products = payload['_products'] as List<dynamic>;
  expect(products, hasLength(1));
  expect((products.single as Map<String, dynamic>)['stock_qty'], expectedStock);

  if (expectedDebtCount == 0) {
    expect(payload, isNot(contains('_debt')));
  } else {
    final debt = payload['_debt'] as Map<String, dynamic>;
    expect(debt['order_id'], order['order_id']);
    expect(debt['_payments'], isEmpty);
  }
}

Future<void> _expectRejectedOrderLeavesNoWrites(Database database) async {
  expect(await database.query('orders'), isEmpty);
  expect(await database.query('order_items'), isEmpty);
  expect(await database.query('debts'), isEmpty);
  expect(await database.query('sync_queue'), isEmpty);
  expect((await database.query('products')).single['stock_qty'], 5);
}
