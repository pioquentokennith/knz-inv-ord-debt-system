// ─────────────────────────────────────────────────────────────────────────────
// local_custom_order_repository.dart — SQLite CRUD for custom_orders
// OOP: Inheritance (BaseRepository), Encapsulation (SQL hidden from callers)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../dto/custom_order_dto.dart';
import '../models/custom_order_model.dart';
import 'base_repository.dart';
import 'firestore_sync.dart';
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
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      await _queue.enqueue(
        operation: 'save_custom_order',
        collection: 'custom_orders',
        userId: order.userId,
        docId: order.id,
        data: cloud,
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
      await _persistPayments(txn, dto);
      final cloud = dto.toCloud();
      cloud['_payments'] = cloud.remove('payments');
      await _queue.enqueue(
        operation: 'save_custom_order',
        collection: 'custom_orders',
        userId: order.userId,
        docId: order.id,
        data: cloud,
        executor: txn,
      );
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
      final changed = await txn.delete(
        'custom_orders',
        where: 'id = ? AND user_id = ? AND is_deleted = 1',
        whereArgs: [id, userId],
      );
      if (changed != 1) throw StateError('Deleted custom order not found: $id');
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

  Future<void> _persistPayments(
    DatabaseExecutor database,
    CustomOrderDto dto,
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
    for (final payment in desired.values) {
      await database.insert('custom_order_payments', payment.toLocal());
    }
  }
}
