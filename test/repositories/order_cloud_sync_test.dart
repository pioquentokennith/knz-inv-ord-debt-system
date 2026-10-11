import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/domain_exceptions.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/repositories/firestore_sync.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/revision_firestore_fake.dart';

void main() {
  sqfliteFfiInit();
  const uid = 'user-a';
  const stamp = '2026-01-01T00:00:00.000Z';
  const orderPath = 'users/$uid/orders/order-a';
  const productPath = 'users/$uid/products/product-a';
  late Database db;
  late RevisionFirestoreFake remote;
  late FirestoreSync cloud;
  late SyncQueue queue;
  late OrderDto order;
  late Map<String, dynamic> event;

  Map<String, dynamic> metadata(int base) => {
    'base_revision': base,
    'revision': base + 1,
    'writer_device_id': 'DEVICE-A',
    'updated_at': stamp,
  };
  Map<String, dynamic> snapshot(String status) => {
    ...order.toLocal(),
    'status': status,
    '_items': order.items.map((i) => i.toCloud()).toList(),
  };
  Future<void> enqueue(String operation, int base, Map<String, dynamic> data) =>
      db.insert('sync_queue', {
        'operation': operation,
        'collection': 'orders',
        'doc_id': 'order-a',
        'user_id': uid,
        'aggregate_key': 'orders:order-a',
        'data': jsonEncode({...data, ...metadata(base)}),
        'expected_revision': base,
        'resulting_revision': base + 1,
        'created_at': stamp,
        'updated_at': stamp,
        'status': 'pending',
        'idempotency_key': 'operation-$base',
      });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(db);
    remote = RevisionFirestoreFake();
    cloud = FirestoreSync.forTesting(firestore: remote, currentUid: () => uid);
    queue = SyncQueue.forTesting(
      databaseProvider: () async => db,
      currentUid: () => uid,
      cloud: cloud,
    );
    queue.setAuthorizationGate((_) async => true);
    order = OrderDto.fromDomain(
      Order(
        id: 'order-a',
        orderId: 'LOCAL-DEVICE-A-001',
        customerName: 'Test',
        items: [
          OrderItem(
            id: 'item-a',
            productId: 'product-a',
            productName: 'Rose',
            quantity: 2,
            unitPrice: const Money.fromCentavos(22000),
          ),
        ],
        totalAmount: const Money.fromCentavos(44000),
        status: OrderStatus.pending,
        orderDate: DateTime.utc(2026),
        commandId: 'command-a',
      ),
      userId: uid,
    );
    await db.insert('orders', order.toLocal());
    remote.documents[productPath] = {
      'id': 'product-a',
      'user_id': uid,
      'stock_qty': 100,
      ...metadata(0),
    };
    event = BusinessEventDto.fromDomain(
      BusinessEvent(
        id: 'delivery-a',
        userId: uid,
        subject: BusinessEventSubject.order,
        subjectId: 'order-a',
        type: BusinessEventType.delivery,
        occurredAt: DateTime.utc(2026),
        recordedAt: DateTime.utc(2026),
        commandId: 'delivery-a',
      ),
    ).toCloud();
  });
  tearDown(() async {
    await queue.stopMonitoring();
    await db.close();
  });

  test(
    'queued creation carries revision identity to order and stock; command retry is read-only',
    () async {
      await enqueue('create_order', 0, {
        'command_id': 'command-a',
        '_order': snapshot('Pending'),
      });
      expect((await queue.syncPending()).completedCount, 1);
      final created = remote.documents[orderPath]!;
      expect(created['writer_device_id'], 'DEVICE-A');
      expect(created['updated_at'], stamp);
      expect(created['revision'], 1);
      expect(created['base_revision'], 0);
      expect(remote.documents[productPath]!['stock_qty'], 98);
      expect(remote.documents[productPath]!['base_revision'], 1);
      expect(remote.documents[productPath]!['revision'], 2);
      final writes = remote.writes;
      await cloud.finalizeOrder(
        uid,
        'command-a',
        {...order.toLocal(), ...metadata(0)},
        order.items.map((i) => i.toCloud()).toList(),
        {'product-a': 2},
        null,
      );
      expect(remote.writes, writes);
      expect(remote.documents[productPath]!['stock_qty'], 98);
    },
  );

  test(
    'offline creation/status/delivery queue drains with correct revisions and canonical ID',
    () async {
      await enqueue('create_order', 0, {
        'command_id': 'command-a',
        '_order': snapshot('Pending'),
      });
      await enqueue('save_order', 1, snapshot('Processing'));
      await enqueue('save_order', 2, snapshot('Shipped'));
      await enqueue('save_order_with_event', 3, {
        '_order': snapshot('Delivered'),
        '_event': event,
      });
      final result = await queue.syncPending();
      expect(result.error, isNull);
      expect(result.completedCount, 4);
      expect(await db.query('sync_queue'), isEmpty);
      final saved = remote.documents[orderPath]!;
      expect(saved['order_id'], 'KNZ-000001');
      expect(saved['revision'], 4);
      expect(saved['base_revision'], 3);
      expect(saved['writer_device_id'], 'DEVICE-A');
      expect(saved['status'], 'Delivered');
      expect(remote.documents['users/$uid/business_events/delivery-a'], event);
      expect(remote.documents[productPath]!['stock_qty'], 98);
      final writes = remote.writes;
      await cloud.saveOrderWithEvent(
        uid,
        {...order.toLocal(), 'status': 'Delivered', ...metadata(3)},
        order.items.map((i) => i.toCloud()).toList(),
        event,
      );
      expect(remote.writes, writes);
    },
  );

  test(
    'stale event parent is rejected without changing order or recording event',
    () async {
      remote.documents[orderPath] = {...order.toCloud(), ...metadata(4)};
      await expectLater(
        cloud.saveOrderWithEvent(
          uid,
          {...order.toLocal(), 'status': 'Delivered', ...metadata(3)},
          order.items.map((i) => i.toCloud()).toList(),
          event,
        ),
        throwsA(isA<SyncConflictException>()),
      );
      expect(remote.writes, 0);
      expect(
        remote.documents.containsKey('users/$uid/business_events/delivery-a'),
        isFalse,
      );
    },
  );

  test(
    'activity log retry reads an existing immutable log instead of updating it',
    () async {
      final log = {
        'id': 'log-a',
        'user_id': uid,
        'message': 'Order saved',
        'type': 'info',
        'timestamp': stamp,
        'schema_version': 1,
      };
      await cloud.saveLog(uid, log);
      final writes = remote.writes;
      await cloud.saveLog(uid, log);
      expect(remote.writes, writes);
      await expectLater(
        cloud.saveLog(uid, {...log, 'message': 'Changed'}),
        throwsStateError,
      );
      expect(remote.writes, writes);
    },
  );
}
