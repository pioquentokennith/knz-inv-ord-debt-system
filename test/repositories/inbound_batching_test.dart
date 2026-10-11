import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/dto/custom_order_dto.dart';
import 'package:knz_scent_admin/dto/debt_dto.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/dto/product_dto.dart';
import 'package:knz_scent_admin/dto/reseller_dto.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/repositories/firestore_sync.dart';
import 'package:knz_scent_admin/repositories/inbound_change_buffer.dart';
import 'package:knz_scent_admin/repositories/inbound_sync_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Counts {
  final selects = <String, int>{};
  final inserts = <String, int>{};
  final updates = <String, int>{};
  final selectArgs = <String, List<List<Object?>>>{};
  int changeQueries = 0;
  bool committed = false;
  void reset() {
    selects.clear();
    inserts.clear();
    updates.clear();
    selectArgs.clear();
    changeQueries = 0;
    committed = false;
  }
}

class _Executor extends Fake implements DatabaseExecutor {
  _Executor(this.delegate, this.counts);
  final DatabaseExecutor delegate;
  final _Counts counts;
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    counts.selects[table] = (counts.selects[table] ?? 0) + 1;
    (counts.selectArgs[table] ??= []).add(List.of(whereArgs ?? []));
    return delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    counts.inserts[table] = (counts.inserts[table] ?? 0) + 1;
    return delegate.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    counts.updates[table] = (counts.updates[table] ?? 0) + 1;
    return delegate.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      delegate.delete(table, where: where, whereArgs: whereArgs);
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    if (sql == 'SELECT changes()') counts.changeQueries++;
    return delegate.rawQuery(sql, arguments);
  }
}

class _Txn extends _Executor implements Transaction {
  _Txn(super.delegate, super.counts);
}

class _Db extends _Executor implements Database {
  _Db(Database super.delegate, super.counts);
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) async {
    counts.committed = false;
    final result = await (delegate as Database).transaction(
      (txn) => action(_Txn(txn, counts)),
      exclusive: exclusive,
    );
    counts.committed = true;
    return result;
  }
}

final _date = DateTime.utc(2026);
Map<String, dynamic> _event(
  String id, {
  String owner = 'u',
  String? command,
  int amount = 100,
}) => BusinessEventDto.fromDomain(
  BusinessEvent(
    id: id,
    userId: owner,
    subject: BusinessEventSubject.order,
    subjectId: 'o',
    type: BusinessEventType.payment,
    amount: Money.fromCentavos(amount),
    occurredAt: _date,
    recordedAt: _date,
    commandId: command ?? id,
  ),
).toCloud();
Map<String, dynamic> _product(String id, {int revision = 1, int stock = 10}) =>
    {
      ...ProductDto.fromDomain(
        Product(
          id: id,
          name: 'Rose',
          description: '',
          category: ProductCategory.eauDeParfum,
          price: const Money.fromCentavos(100),
          stockQty: stock,
          minStockLevel: 1,
          createdAt: _date,
        ),
        userId: 'u',
      ).toCloud(),
      'revision': revision,
    };
Map<String, dynamic> _order({int revision = 1, int quantity = 1}) => {
  ...OrderDto.fromDomain(
    Order(
      id: 'o',
      orderId: 'KNZ-000001',
      customerName: 'Fixture',
      items: [
        OrderItem(
          id: 'i',
          productId: 'p',
          productName: 'Rose',
          quantity: quantity,
          unitPrice: const Money.fromCentavos(100),
        ),
      ],
      totalAmount: Money.fromCentavos(100 * quantity),
      status: OrderStatus.pending,
      orderDate: _date,
    ),
    userId: 'u',
  ).toCloud(),
  'revision': revision,
};
Map<String, dynamic> _debt({int revision = 1, int paid = 200}) => {
  ...DebtDto.fromDomain(
    CustomerDebt(
      id: 'd',
      customerName: 'Fixture',
      orderId: 'KNZ-000001',
      principalOriginal: const Money.fromCentavos(1000),
      principalOutstanding: Money.fromCentavos(1000 - paid),
      createdAt: _date,
      payments: [
        PaymentRecord(
          id: 'dp',
          amount: Money.fromCentavos(paid),
          principalApplied: Money.fromCentavos(paid),
          paidAt: _date,
        ),
      ],
    ),
    userId: 'u',
  ).toCloud(),
  'revision': revision,
};
Map<String, dynamic> _custom({int revision = 1, int paid = 200}) => {
  ...CustomOrderDto.fromDomain(
    CustomOrder(
      id: 'c',
      customerName: 'Fixture',
      fragranceSpecs: 'Rose',
      agreedPrice: const Money.fromCentavos(1000),
      depositPaid: Money.fromCentavos(paid),
      deliveryDate: DateTime.utc(2027),
      userId: 'u',
      createdAt: _date,
      payments: [
        CustomOrderPayment(
          id: 'cp',
          customOrderId: 'c',
          amount: Money.fromCentavos(paid),
          paidAt: _date,
        ),
      ],
    ),
  ).toCloud(),
  'revision': revision,
};
List<List<Map<String, dynamic>>> _snapshot({
  List<Map<String, dynamic>> products = const [],
  List<Map<String, dynamic>> orders = const [],
  List<Map<String, dynamic>> debts = const [],
  List<Map<String, dynamic>> customs = const [],
  List<Map<String, dynamic>> resellers = const [],
  List<Map<String, dynamic>> events = const [],
}) => [products, orders, debts, resellers, customs, events, []];

void main() {
  sqfliteFfiInit();
  late Database db;
  late _Db observed;
  final counts = _Counts();
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.createSchemaForTesting(db);
    counts.reset();
    observed = _Db(db, counts);
  });
  tearDown(() => db.close());
  Future<InboundSyncResult> reconcile(
    List<List<Map<String, dynamic>>> snapshot, {
    String owner = 'u',
  }) => InboundSyncCoordinator(
    databaseProvider: () async => observed,
    remoteLoader: (_) async => snapshot,
  ).reconcile(owner);

  test(
    '801 existing events use three owner-scoped queries and no insert/change calls',
    () async {
      final events = [for (var i = 0; i < 801; i++) _event('e$i')];
      final batch = db.batch();
      for (final event in events) {
        batch.insert('business_events', event);
      }
      await batch.commit(noResult: true);
      final result = await reconcile(_snapshot(events: events));
      expect(result.appliedCount, 0);
      expect(result.changedCollections, isEmpty);
      expect(counts.selects['business_events'], 3);
      expect(counts.inserts['business_events'] ?? 0, 0);
      expect(counts.changeQueries, 0);
      for (final args in counts.selectArgs['business_events']!) {
        expect(args.first, 'u');
        expect(args.length, lessThanOrEqualTo(401));
      }
    },
  );
  test(
    'mixed and new events report only actual inserts, keeping exact stored content',
    () async {
      final existing = _event('old');
      await db.insert('business_events', existing);
      final newEvents = [_event('new1'), _event('new2')];
      final result = await reconcile(
        _snapshot(
          events: [
            _event('old', amount: 900),
            ...newEvents,
            _event('new1', amount: 800),
          ],
        ),
      );
      expect(result.appliedCount, 2);
      expect(result.changedCollections, {'business_events'});
      expect(counts.inserts['business_events'], 2);
      expect(counts.changeQueries, 2);
      final rows = await db.query('business_events', orderBy: 'id');
      expect(rows, [newEvents[0], newEvents[1], existing]);
    },
  );
  test(
    'all new events insert once, and successful IDs are deduplicated within the batch',
    () async {
      final result = await reconcile(
        _snapshot(events: [_event('a'), _event('b'), _event('a'), _event('c')]),
      );
      expect(result.appliedCount, 3);
      expect(counts.inserts['business_events'], 3);
      expect(counts.changeQueries, 3);
      expect(await db.query('business_events'), hasLength(3));
      counts.reset();
      expect(
        (await reconcile(
          _snapshot(events: [_event('a'), _event('b'), _event('c')]),
        )).changed,
        isFalse,
      );
      expect(counts.changeQueries, 0);
    },
  );
  test(
    'another owner does not satisfy the current owner existence check',
    () async {
      final other = _event('collision', owner: 'other');
      await db.insert('business_events', other);
      final result = await reconcile(_snapshot(events: [_event('collision')]));
      // Global ID collision still follows existing INSERT OR IGNORE semantics.
      // The other owner must not be treated as an existing current-owner event.
      expect(counts.inserts['business_events'], 1);
      expect(counts.changeQueries, 1);
      expect(result.appliedCount, 0);
      expect((await db.query('business_events')).single, other);
      expect(
        await db.query(
          'business_events',
          where: 'user_id = ?',
          whereArgs: ['u'],
        ),
        isEmpty,
      );
    },
  );
  test(
    'command/source uniqueness counts actual inserts, not attempted missing IDs',
    () async {
      await db.insert(
        'business_events',
        _event('existing', command: 'same-command'),
      );
      await db.insert('business_events', {
        ..._event('source'),
        'source_type': 'payment',
        'source_id': 'p',
      });
      final result = await reconcile(
        _snapshot(
          events: [
            _event('candidate', command: 'same-command'), // ignored
            _event(
              'candidate',
              command: 'different-command',
            ), // must still insert
            {
              ..._event('source-duplicate'),
              'source_type': 'payment',
              'source_id': 'p',
            }, // ignored
          ],
        ),
      );
      expect(result.appliedCount, 1);
      expect(counts.inserts['business_events'], 3);
      expect(counts.changeQueries, 3);
      expect(
        (await db.query(
          'business_events',
          where: 'id = ?',
          whereArgs: ['candidate'],
        )).single['command_id'],
        'different-command',
      );
    },
  );
  test(
    'payment then reversal order is preserved with foreign keys enabled',
    () async {
      final payment = _event('payment');
      final reversal = {
        ..._event('reversal'),
        'event_type': 'reversal',
        'related_event_id': 'payment',
        'reason': 'Correction',
      };
      expect(
        (await reconcile(
          _snapshot(events: [payment, reversal, payment]),
        )).appliedCount,
        2,
      );
      expect(
        (await db.query(
          'business_events',
          where: 'id = ?',
          whereArgs: ['reversal'],
        )).single,
        reversal,
      );
    },
  );
  test(
    'late transaction failure rolls back parents/events and leaves buffer unacknowledged',
    () async {
      await reconcile(_snapshot(products: [_product('p')]));
      final original = (await db.query('products')).single;
      final originalCursors = await db.query('sync_cursors');
      final batch = _snapshot(
        products: [_product('p', revision: 2, stock: 7)],
        events: [_event('ok'), _event('fail')],
      );
      final buffer = InboundChangeBuffer(() {});
      for (var i = 0; i < batch.length; i++) {
        final collection = FirestoreSync.inboundCollections[i];
        buffer.expect(collection);
        buffer.add(collection, batch[i]);
      }
      var acknowledgments = 0;
      final coordinator = InboundSyncCoordinator(
        databaseProvider: () async => observed,
        remoteLoader: (_) => buffer.snapshot(FirestoreSync.inboundCollections),
        acknowledge: (_, incoming) async {
          expect(counts.committed, isTrue);
          expect((await db.query('products')).single['stock_qty'], 7);
          expect(await db.query('business_events'), hasLength(2));
          acknowledgments++;
          buffer.acknowledge(FirestoreSync.inboundCollections, incoming);
        },
      );
      await db.execute(
        "CREATE TRIGGER fail_event BEFORE INSERT ON business_events WHEN NEW.id = 'fail' BEGIN SELECT RAISE(ABORT, 'disk failure'); END",
      );
      await expectLater(
        coordinator.reconcile('u'),
        throwsA(isA<DatabaseException>()),
      );
      expect(acknowledgments, 0);
      expect(counts.committed, isFalse);
      expect((await db.query('products')).single, original);
      expect(await db.query('business_events'), isEmpty);
      expect(await db.query('sync_cursors'), originalCursors);
      expect(
        (await buffer.snapshot(FirestoreSync.inboundCollections))[5],
        hasLength(2),
      );
      await db.execute('DROP TRIGGER fail_event');
      expect((await coordinator.reconcile('u')).appliedCount, 3);
      expect(acknowledgments, 1);
      expect(
        (await buffer.snapshot(
          FirestoreSync.inboundCollections,
        )).every((rows) => rows.isEmpty),
        isTrue,
      );
    },
  );
  test(
    'parent prefetch chunks full rows and skips all unchanged writes',
    () async {
      final products = [for (var i = 0; i < 801; i++) _product('p$i')];
      await reconcile(_snapshot(products: products));
      counts.reset();
      final result = await reconcile(_snapshot(products: products));
      expect(result.appliedCount, 0);
      expect(counts.selects['products'], 3);
      expect(counts.inserts['products'] ?? 0, 0);
      expect(counts.updates['products'] ?? 0, 0);
      expect(
        counts.selects['business_events'],
        isNull,
      ); // Empty collections need no lookup.
    },
  );
  test(
    'duplicate parent IDs see writes from earlier records, including child replacements',
    () async {
      await reconcile(_snapshot(orders: [_order()]));
      counts.reset();
      final result = await reconcile(
        _snapshot(
          orders: [
            _order(revision: 3, quantity: 3),
            _order(revision: 2, quantity: 2),
            _order(revision: 4, quantity: 4),
            _order(revision: 4, quantity: 9),
          ],
        ),
      );
      expect(result.appliedCount, 2);
      expect((await db.query('orders')).single['revision'], 4);
      expect((await db.query('order_items')).single['quantity'], 4);
      expect(
        counts.selects['orders'],
        3,
      ); // Prefetch and two post-write re-reads.
    },
  );
  test(
    'parent lookup cache cannot leak across owners or reconciliation passes',
    () async {
      await reconcile(_snapshot(products: [_product('p')]), owner: 'other');
      await expectLater(
        reconcile(_snapshot(products: [_product('p')])),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.query('products')).single['user_id'], 'other');
      await reconcile(
        _snapshot(products: [_product('own')], events: [_event('own-event')]),
      );
      await db.update(
        'products',
        {'stock_qty': 33, 'revision': 5},
        where: 'id = ?',
        whereArgs: ['own'],
      );
      expect(
        (await reconcile(
          _snapshot(products: [_product('own', revision: 2)]),
        )).changed,
        isFalse,
      );
      expect(
        (await db.query(
          'products',
          where: 'id = ?',
          whereArgs: ['own'],
        )).single['stock_qty'],
        33,
      );
    },
  );
  test(
    'pending composite intent protects order/product/debt and payment children',
    () async {
      await reconcile(
        _snapshot(
          products: [_product('p', stock: 3)],
          orders: [_order()],
          debts: [_debt()],
          customs: [_custom()],
        ),
      );
      final originals = {
        for (final table in [
          'products',
          'orders',
          'order_items',
          'debts',
          'payments',
          'custom_orders',
          'custom_order_payments',
        ])
          table: await db.query(table),
      };
      await db.insert('sync_queue', {
        'operation': 'create_order',
        'collection': 'orders',
        'user_id': 'u',
        'doc_id': 'o',
        'aggregate_key': 'orders:o',
        'data': jsonEncode({
          '_order': {
            'order_id': 'KNZ-000001',
            '_items': [
              {'product_id': 'p'},
            ],
          },
          '_debt': {'id': 'd', 'order_id': 'KNZ-000001'},
        }),
        'created_at': _date.toIso8601String(),
        'updated_at': _date.toIso8601String(),
        'idempotency_key': 'pending-o',
        'status': 'pending',
      });
      await db.insert('sync_queue', {
        'operation': 'save_custom_order',
        'collection': 'custom_orders',
        'user_id': 'u',
        'doc_id': 'c',
        'aggregate_key': 'custom_orders:c',
        'data': '{}',
        'created_at': _date.toIso8601String(),
        'updated_at': _date.toIso8601String(),
        'idempotency_key': 'pending-c',
        'status': 'pending',
      });
      final result = await reconcile(
        _snapshot(
          products: [_product('p', revision: 2)],
          orders: [_order(revision: 2, quantity: 5)],
          debts: [_debt(revision: 2, paid: 500)],
          customs: [_custom(revision: 2, paid: 500)],
        ),
      );
      expect(result.appliedCount, 0);
      expect(result.conflictCount, 4);
      for (final entry in originals.entries) {
        expect(await db.query(entry.key), entry.value);
      }
      expect(await db.query('sync_conflicts'), hasLength(4));
    },
  );
  test(
    'clean changed debt/custom/reseller records still update, unchanged replay does not',
    () async {
      Map<String, dynamic> reseller(int revision, String name) => {
        ...ResellerDto.fromDomain(
          Reseller(
            id: 'r',
            name: name,
            deductionPerItem: Money.zero,
            userId: 'u',
            createdAt: _date,
          ),
        ).toCloud(),
        'revision': revision,
      };
      await reconcile(
        _snapshot(
          debts: [_debt()],
          customs: [_custom()],
          resellers: [reseller(1, 'Old')],
        ),
      );
      final next = _snapshot(
        debts: [_debt(revision: 2, paid: 500)],
        customs: [_custom(revision: 2, paid: 500)],
        resellers: [reseller(2, 'New')],
      );
      expect((await reconcile(next)).changedCollections, {
        'debts',
        'custom_orders',
        'resellers',
      });
      expect((await db.query('payments')).single['amount_centavos'], 500);
      expect(
        (await db.query('custom_order_payments')).single['amount_centavos'],
        500,
      );
      counts.reset();
      expect((await reconcile(next)).changed, isFalse);
      expect(counts.updates, isEmpty);
      expect(counts.selects['debts'], 1);
      expect(counts.selects['custom_orders'], 1);
      expect(counts.selects['resellers'], 1);
    },
  );
  test(
    'legacy divergent values still conflict using complete prefetched rows',
    () async {
      await reconcile(
        _snapshot(products: [_product('p', revision: 0, stock: 3)]),
      );
      final result = await reconcile(
        _snapshot(products: [_product('p', revision: 0, stock: 9)]),
      );
      expect(result.conflictCount, 1);
      expect(result.appliedCount, 0);
      final conflict = (await db.query('sync_conflicts')).single;
      expect(conflict['reason'], 'legacy_divergence');
      expect(
        (jsonDecode(conflict['local_data'] as String) as Map)['stock_qty'],
        3,
      );
    },
  );
}
