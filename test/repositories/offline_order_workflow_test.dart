import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/repositories/firestore_sync.dart';
import 'package:knz_scent_admin/repositories/local_debt_repository.dart';
import 'package:knz_scent_admin/repositories/local_order_repository.dart';
import 'package:knz_scent_admin/repositories/local_product_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/revision_firestore_fake.dart';

void main() {
  sqfliteFfiInit();
  const uid = 'demo-owner';
  const productPath = 'users/$uid/products/p';
  const debtPath = 'users/$uid/debts/d';
  final date = DateTime.utc(2026, 1, 1);
  late Database db;
  late RevisionFirestoreFake remote;
  late SyncQueue queue;
  late LocalOrderRepository orders;
  late LocalDebtRepository debts;
  late LocalProductRepository products;

  Order order({OrderStatus status = OrderStatus.pending, String id = 'o'}) =>
      Order(
        id: id,
        orderId: 'PENDING',
        customerName: 'Demo customer',
        items: [
          OrderItem(
            id: 'item-$id',
            productId: 'p',
            productName: 'Rose',
            quantity: 1,
            unitPrice: const Money.fromCentavos(10000),
          ),
        ],
        totalAmount: const Money.fromCentavos(10000),
        status: status,
        orderDate: date,
        commandId: 'create-$id',
      );
  CustomerDebt debt() => CustomerDebt(
    id: 'd',
    customerName: 'Demo customer',
    orderId: 'PENDING',
    principalOriginal: const Money.fromCentavos(10000),
    principalOutstanding: const Money.fromCentavos(10000),
    createdAt: date,
  );

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(db);
    final product = <String, dynamic>{
      'id': 'p',
      'user_id': uid,
      'name': 'Rose',
      'description': '',
      'category': 'Perfume',
      'price_centavos': 10000,
      'stock_qty': 10,
      'min_stock_level': 1,
      'created_at': date.toIso8601String(),
      'is_deleted': 0,
      'revision': 1,
      'base_revision': 0,
      'writer_device_id': 'ORIGINAL',
      'updated_at': date.toIso8601String(),
    };
    await db.insert('products', product);
    remote = RevisionFirestoreFake()..documents[productPath] = {...product};
    queue = SyncQueue.forTesting(
      databaseProvider: () async => db,
      currentUid: () => uid,
      cloud: FirestoreSync.forTesting(firestore: remote, currentUid: () => uid),
    )..setAuthorizationGate((_) async => true);
    orders = LocalOrderRepository(
      databaseProvider: () async => db,
      queue: queue,
    );
    debts = LocalDebtRepository(
      databaseProvider: () async => db,
      queue: queue,
      now: () => date,
    );
    products = LocalProductRepository(
      databaseProvider: () async => db,
      queue: queue,
    );
  });
  tearDown(() async {
    await queue.stopMonitoring();
    await db.close();
  });

  test(
    'offline Utang creation followed by partial and full payments syncs completely',
    () async {
      await orders.addWithInventory(
        order(status: OrderStatus.utang),
        uid,
        debt: debt(),
      );
      for (var i = 1; i <= 2; i++) {
        await debts.addPayment(
          'd',
          PaymentRecord(
            id: 'pay-$i',
            amount: const Money.fromCentavos(5000),
            paidAt: date,
          ),
        );
      }
      final result = await queue.syncPending();
      expect(result.error, isNull);
      expect(await db.query('sync_queue'), isEmpty);
      expect(remote.documents[debtPath]!['order_id'], 'KNZ-000001');
      expect(remote.documents[debtPath]!['principal_outstanding_centavos'], 0);
      expect(remote.documents[debtPath]!['revision'], 3);
      expect(remote.documents[debtPath]!['payments'], hasLength(2));
      expect(remote.documents[productPath]!['stock_qty'], 9);
    },
  );

  test(
    'restock queued after an offline order accounts for the stock revision',
    () async {
      await orders.addWithInventory(order(), uid);
      await products.updateStock('p', 15);
      final result = await queue.syncPending();
      expect(result.error, isNull);
      expect(await db.query('sync_queue'), isEmpty);
      expect(remote.documents[productPath]!['stock_qty'], 15);
      expect(remote.documents[productPath]!['revision'], 3);
    },
  );

  test(
    'restock after finalized order works without an inbound refresh',
    () async {
      await orders.addWithInventory(order(), uid);
      expect((await queue.syncPending()).error, isNull);
      await products.updateStock('p', 15);
      expect((await queue.syncPending()).error, isNull);
      expect(remote.documents[productPath]!['stock_qty'], 15);
    },
  );

  test('a newly cancelled order never deducts cloud stock', () async {
    await orders.addWithInventory(order(status: OrderStatus.cancelled), uid);
    expect((await queue.syncPending()).error, isNull);
    expect((await products.getAll(uid)).single.stockQty, 10);
    expect(remote.documents[productPath]!['stock_qty'], 10);
    expect(remote.documents[productPath]!['revision'], 1);
  });

  test(
    'initial Utang payment is present in the cloud parent and its accounting event',
    () async {
      final initial = debt()
          .allocatePayment(
            PaymentRecord(
              id: 'initial',
              amount: const Money.fromCentavos(2500),
              paidAt: date,
            ),
          )
          .debt;
      await orders.addWithInventory(
        order(status: OrderStatus.utang),
        uid,
        debt: initial,
      );
      expect((await queue.syncPending()).error, isNull);
      expect(remote.documents[debtPath]!['payments'], hasLength(1));
      expect(
        remote.documents['users/$uid/business_events/debt-collection-initial'],
        isNotNull,
      );
    },
  );

  test('payment after finalization keeps the queued writer metadata', () async {
    await orders.addWithInventory(
      order(status: OrderStatus.utang),
      uid,
      debt: debt(),
    );
    expect((await queue.syncPending()).error, isNull);
    await db.update('device_identity', {'device_id': 'NEW-WRITER'});
    await debts.addPayment(
      'd',
      PaymentRecord(
        id: 'payment',
        amount: const Money.fromCentavos(1000),
        paidAt: date,
      ),
    );
    final queued =
        jsonDecode((await db.query('sync_queue')).single['data'] as String)
            as Map;
    expect((await queue.syncPending()).error, isNull);
    expect(
      remote.documents[debtPath]!['writer_device_id'],
      queued['writer_device_id'],
    );
    expect(remote.documents[debtPath]!['updated_at'], queued['updated_at']);
  });

  test(
    'offline conversion to Utang creates a debt with the canonical order reference',
    () async {
      final created = await orders.addWithInventory(order(), uid);
      await orders.markAsUtang(
        'o',
        CustomerDebt(
          id: 'd',
          customerName: 'Demo customer',
          orderId: created.order.orderId,
          principalOriginal: const Money.fromCentavos(10000),
          principalOutstanding: const Money.fromCentavos(10000),
          createdAt: date,
        ),
      );
      expect((await queue.syncPending()).error, isNull);
      expect(remote.documents[debtPath]!['order_id'], 'KNZ-000001');
    },
  );

  test(
    'multiple pending orders reserve distinct stock revisions before restocking',
    () async {
      await orders.addWithInventory(order(id: 'first'), uid);
      await orders.addWithInventory(order(id: 'second'), uid);
      await products.updateStock('p', 20);
      expect((await queue.syncPending()).error, isNull);
      expect(remote.documents[productPath]!['stock_qty'], 20);
      expect(remote.documents[productPath]!['revision'], 4);
    },
  );

  test(
    'a stock edit during finalization keeps its value and syncs on the next pass',
    () async {
      await orders.addWithInventory(order(), uid);
      final drained = queue.statusStream.firstWhere(
        (status) => status.pendingCount == 0 && status.failedCount == 0,
      );
      remote.afterCommit = () async {
        remote.afterCommit = null;
        await products.updateStock('p', 20);
      };
      expect((await queue.syncPending()).error, isNull);
      expect((await products.getAll(uid)).single.stockQty, 20);
      expect((await queue.syncPending()).error, isNull);
      await drained.timeout(const Duration(seconds: 5));
      expect(remote.documents[productPath]!['stock_qty'], 20);
      expect(remote.documents[productPath]!['revision'], 3);
    },
  );

  test(
    'an unseen remote stock edit remains a conflict rather than being overwritten',
    () async {
      await orders.addWithInventory(order(), uid);
      await products.updateStock('p', 20);
      remote.documents[productPath]!.addAll({
        'stock_qty': 7,
        'revision': 2,
        'base_revision': 1,
      });
      final result = await queue.syncPending();
      expect(result.error, isNotNull);
      expect(remote.documents[productPath]!['stock_qty'], 6);
      expect((await products.getAll(uid)).single.stockQty, 20);
      expect(await db.query('sync_conflicts'), isNotEmpty);
    },
  );

  test(
    'legacy offline creation and dependent stock/payment commands remain recoverable',
    () async {
      await orders.addWithInventory(
        order(status: OrderStatus.utang),
        uid,
        debt: debt(),
      );
      await products.updateStock('p', 20);
      await debts.addPayment(
        'd',
        PaymentRecord(
          id: 'legacy-pay',
          amount: const Money.fromCentavos(5000),
          paidAt: date,
        ),
      );
      // Recreate the persisted queue format written before implicit revisions
      // were tracked, without replacing the local business records.
      for (final row in await db.query('sync_queue')) {
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        if (row['operation'] == 'create_order') {
          data.remove('_stock_revisions');
          await db.update(
            'sync_queue',
            {'data': jsonEncode(data)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        } else {
          data['base_revision'] = (data['base_revision'] as int) - 1;
          data['revision'] = (data['revision'] as int) - 1;
          await db.update(
            'sync_queue',
            {
              'data': jsonEncode(data),
              'expected_revision': data['base_revision'],
              'resulting_revision': data['revision'],
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      expect((await queue.syncPending()).error, isNull);
      expect(await db.query('sync_queue'), isEmpty);
      expect(remote.documents[debtPath]!['order_id'], 'KNZ-000001');
      expect(
        remote.documents[debtPath]!['principal_outstanding_centavos'],
        5000,
      );
      expect(remote.documents[productPath]!['stock_qty'], 20);
    },
  );
}
