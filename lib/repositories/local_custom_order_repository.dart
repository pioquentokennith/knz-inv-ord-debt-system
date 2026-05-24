// ─────────────────────────────────────────────────────────────────────────────
// local_custom_order_repository.dart — SQLite CRUD for custom_orders
// OOP: Inheritance (BaseRepository), Encapsulation (SQL hidden from callers)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:uuid/uuid.dart';
import '../models/custom_order_model.dart';
import 'base_repository.dart';

class LocalCustomOrderRepository extends BaseRepository {
  final _uuid = const Uuid();

  /// Returns all active (non-deleted) custom orders for the given user.
  Future<List<CustomOrder>> getAll(String userId) =>
      safeCall(() async {
        final database = await db.database;
        final rows = await database.query(
          'custom_orders',
          where: 'user_id = ? AND is_deleted = 0',
          whereArgs: [userId],
          orderBy: 'created_at DESC',
        );
        return rows.map(CustomOrder.fromMap).toList();
      }, <CustomOrder>[]);

  /// Inserts a new custom order.
  Future<void> save(CustomOrder order) =>
      safeVoidCall(() async {
        final database = await db.database;
        final map = order.toMap();
        if ((map['id'] as String).isEmpty) map['id'] = _uuid.v4();
        await database.insert('custom_orders', map);
      });

  /// Updates an existing custom order row.
  Future<void> update(CustomOrder order) =>
      safeVoidCall(() async {
        final database = await db.database;
        await database.update(
          'custom_orders',
          order.toMap(),
          where: 'id = ?',
          whereArgs: [order.id],
        );
      });

  /// Updates only the status column (avoids full row rewrite on status change).
  Future<void> updateStatus(String id, String status) =>
      safeVoidCall(() async {
        final database = await db.database;
        await database.update(
          'custom_orders',
          {'status': status},
          where: 'id = ?',
          whereArgs: [id],
        );
      });

  /// Soft-deletes a custom order.
  Future<void> delete(String id) =>
      safeVoidCall(() async {
        final database = await db.database;
        await database.update(
          'custom_orders',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      });
}
