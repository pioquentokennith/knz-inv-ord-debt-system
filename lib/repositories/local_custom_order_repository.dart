// ─────────────────────────────────────────────────────────────────────────────
// local_custom_order_repository.dart — SQLite CRUD for custom_orders
// OOP: Inheritance (BaseRepository), Encapsulation (SQL hidden from callers)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../dto/business_event_dto.dart';
import '../dto/custom_order_dto.dart';
import '../models/business_event_model.dart';
import '../models/custom_order_model.dart';
import 'base_repository.dart';
import 'firestore_sync.dart';
import 'local_business_event_repository.dart';
import 'sync_queue.dart';

class LocalCustomOrderRepository extends BaseRepository {
  LocalCustomOrderRepository({
    Future<Database> Function()? databaseProvider,
    SyncOutbox? queue,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _queue = queue ?? SyncQueue.instance;

  final Future<Database> Function() _databaseProvider;
  final SyncOutbox _queue;
  final _cloud = FirestoreSync.instance;

  /// Returns all active (non-deleted) custom orders for the given user.
  Future<List<CustomOrder>> getAll(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    final partition = await database.query(
      'custom_orders',
      columns: const ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (partition.isEmpty && _queue.isOnline) {
      final cloudRows = await _cloud.getCustomOrders(userId);
      await database.transaction((txn) async {
        for (final cloudRow in cloudRows) {
          final dto = CustomOrderDto.fromCloud(cloudRow, userId: userId);
          await txn.insert(
            'custom_orders',
            dto.toLocal(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          for (final payment in dto.payments) {
            await txn.insert(
              'custom_order_payments',
              payment.toLocal(),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
      });
    }
    final rows = await database.query(
      'custom_orders',
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return _toDomainList(database, rows);
  });

  /// Returns custom orders currently held in this user's recycle bin.
  Future<List<CustomOrder>> getDeleted(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'custom_orders',
      where: 'user_id = ? AND is_deleted = 1',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return _toDomainList(database, rows);
  });

  /// Inserts a new custom order.
  Future<void> save(CustomOrder order) => safeVoidCall(() async {
    final database = await _databaseProvider();
    final dto = CustomOrderDto.fromDomain(order);
    final map = dto.toLocal();
    await database.transaction((txn) async {
      final inserted = await txn.insert('custom_orders', map);
      if (inserted <= 0) throw StateError('Custom order was not inserted.');
      for (final payment in dto.payments) {
        await txn.insert('custom_order_payments', payment.toLocal());
      }
      final events = <BusinessEvent>[];
      for (final payment in order.payments) {
        final event = _collectionEvent(order.userId, order.id, payment);
        await insertBusinessEvent(txn, event);
        events.add(event);
      }
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      await _queue.enqueue(
        operation: events.isEmpty
            ? 'save_custom_order'
            : 'save_custom_order_with_events',
        collection: 'custom_orders',
        userId: order.userId,
        docId: order.id,
        data: events.isEmpty
            ? cloud
            : {
                '_custom_order': cloud,
                '_events': events
                    .map(
                      (event) => BusinessEventDto.fromDomain(event).toCloud(),
                    )
                    .toList(growable: false),
              },
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Updates an existing custom order row.
  Future<void> update(CustomOrder order) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final dto = CustomOrderDto.fromDomain(order);
      final data = dto.toLocal();
      final changed = await txn.update(
        'custom_orders',
        data,
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [order.id, order.userId],
      );
      if (changed != 1) {
        throw StateError('Active custom order not found: ${order.id}');
      }
      final events = await _persistPayments(txn, dto, order.userId);
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      if (events.isEmpty) {
        await _queue.enqueue(
          operation: 'save_custom_order',
          collection: 'custom_orders',
          userId: order.userId,
          docId: order.id,
          data: cloud,
          executor: txn,
        );
      } else {
        for (final event in events) {
          final payment = dto.payments.singleWhere(
            (candidate) => candidate.id == event.sourceId,
          );
          await _queue.enqueue(
            operation: 'apply_custom_order_payment',
            collection: 'custom_orders',
            userId: order.userId,
            docId: order.id,
            data: {
              '_custom_order': cloud,
              '_payment': payment.toCloud(),
              '_event': BusinessEventDto.fromDomain(event).toCloud(),
            },
            executor: txn,
          );
        }
      }
    });
    _queue.requestSync();
  });

  /// Updates only the status column (avoids full row rewrite on status change).
  Future<void> updateStatus(
    String id,
    String userId,
    String status,
  ) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'custom_orders',
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Active custom order not found: $id');
      final changed = await txn.update(
        'custom_orders',
        {'status': status},
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [id, userId],
      );
      if (changed != 1) throw StateError('Active custom order not found: $id');
      final data = Map<String, dynamic>.from(rows.single)..['status'] = status;
      final dto = await _dtoFromRow(txn, data);
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      await _queue.enqueue(
        operation: 'save_custom_order',
        collection: 'custom_orders',
        userId: userId,
        docId: id,
        data: cloud,
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Soft-deletes a custom order.
  Future<void> delete(String id, String userId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'custom_orders',
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Active custom order not found: $id');
      }
      final tombstone = Map<String, dynamic>.from(rows.single)
        ..['is_deleted'] = 1
        ..['deleted_at'] = deletedAt;
      final dto = await _dtoFromRow(txn, tombstone);
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      final changed = await txn.update(
        'custom_orders',
        {'is_deleted': 1, 'deleted_at': deletedAt},
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [id, userId],
      );
      if (changed != 1) throw StateError('Active custom order not found: $id');
      await _queue.enqueue(
        operation: 'soft_delete_custom_order',
        collection: 'custom_orders',
        userId: userId,
        docId: id,
        data: cloud,
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Restores one custom order owned by [userId] from the recycle bin.
  Future<void> restore(String id, String userId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'custom_orders',
        where: 'id = ? AND user_id = ? AND is_deleted = 1',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Deleted custom order not found: $id');
      final data = Map<String, dynamic>.from(rows.single)
        ..['is_deleted'] = 0
        ..['deleted_at'] = null;
      final dto = await _dtoFromRow(txn, data);
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      final changed = await txn.update(
        'custom_orders',
        {'is_deleted': 0, 'deleted_at': null},
        where: 'id = ? AND user_id = ? AND is_deleted = 1',
        whereArgs: [id, userId],
      );
      if (changed != 1) throw StateError('Deleted custom order not found: $id');
      await _queue.enqueue(
        operation: 'save_custom_order',
        collection: 'custom_orders',
        userId: userId,
        docId: id,
        data: cloud,
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Permanently removes one already-deleted custom order owned by [userId].
  Future<void> hardDelete(String id, String userId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      await _queue.enqueue(
        operation: 'delete_custom_order',
        collection: 'custom_orders',
        userId: userId,
        docId: id,
        data: {'id': id, 'user_id': userId},
        executor: txn,
      );
      final changed = await txn.update(
        'custom_orders',
        {'purge_state': 'pending'},
        where: 'id = ? AND user_id = ? AND is_deleted = 1 AND purge_state = ?',
        whereArgs: [id, userId, 'none'],
      );
      if (changed != 1) {
        throw StateError('Custom-order purge could not be queued: $id');
      }
    });
    _queue.requestSync();
  });

  Future<List<CustomOrder>> _toDomainList(
    DatabaseExecutor database,
    List<Map<String, Object?>> rows,
  ) async {
    final result = <CustomOrder>[];
    for (final row in rows) {
      result.add(
        (await _dtoFromRow(
          database,
          Map<String, dynamic>.from(row),
        )).toDomain(),
      );
    }
    return result;
  }

  Future<CustomOrderDto> _dtoFromRow(
    DatabaseExecutor database,
    Map<String, dynamic> row,
  ) async {
    final payments = await database.query(
      'custom_order_payments',
      where: 'custom_order_id = ?',
      whereArgs: [row['id']],
      orderBy: 'paid_at ASC, id ASC',
    );
    return CustomOrderDto.fromLocal(
      row,
      payments.map(Map<String, dynamic>.from).toList(),
    );
  }

  Future<List<BusinessEvent>> _persistPayments(
    DatabaseExecutor database,
    CustomOrderDto dto,
    String userId,
  ) async {
    final existing = await database.query(
      'custom_order_payments',
      where: 'custom_order_id = ?',
      whereArgs: [dto.id],
    );
    final desired = {for (final payment in dto.payments) payment.id: payment};
    for (final row in existing) {
      final current = CustomOrderPaymentDto.fromLocal(
        Map<String, dynamic>.from(row),
      );
      final replacement = desired.remove(current.id);
      if (replacement == null ||
          replacement.toLocal().toString() != current.toLocal().toString()) {
        throw StateError('Custom-order payment history is immutable.');
      }
    }
    final events = <BusinessEvent>[];
    for (final payment in desired.values) {
      await database.insert('custom_order_payments', payment.toLocal());
      final event = _collectionEvent(userId, dto.id, payment.toDomain());
      await insertBusinessEvent(database, event);
      events.add(event);
    }
    return events;
  }

  BusinessEvent _collectionEvent(
    String userId,
    String customOrderId,
    CustomOrderPayment payment,
  ) => BusinessEvent(
    id: 'custom-collection-${payment.id}',
    userId: userId,
    subject: BusinessEventSubject.customOrder,
    subjectId: customOrderId,
    type: BusinessEventType.collection,
    amount: payment.amount,
    occurredAt: payment.paidAt,
    recordedAt: payment.paidAt,
    reason: payment.note,
    commandId: 'custom-collection-${payment.id}',
    sourceType: 'custom_payment',
    sourceId: payment.id,
  );
}
