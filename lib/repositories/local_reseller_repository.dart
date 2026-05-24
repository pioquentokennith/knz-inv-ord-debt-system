// ─────────────────────────────────────────────────────────────────────────────
// local_reseller_repository.dart — SQLite-backed reseller repository
// Purpose : CRUD operations for the resellers table. Follows the same patterns
//           as LocalProductRepository (safeCall wrapper, soft-delete, user_id
//           partitioning) so the rest of the codebase stays consistent.
// OOP Pillars:
//   • Inheritance  — extends BaseRepository (safeCall, db getter)
//   • Encapsulation— all SQL is encapsulated here; callers use model objects
// ─────────────────────────────────────────────────────────────────────────────

import 'package:uuid/uuid.dart';
import '../models/reseller_model.dart';
import 'base_repository.dart';

class LocalResellerRepository extends BaseRepository {
  final _uuid = const Uuid();

  /// Returns all active (non-deleted) resellers for a given user.
  Future<List<Reseller>> getAll(String userId) =>
      safeCall(() async {
        final database = await db.database;
        final rows = await database.query(
          'resellers',
          where: 'user_id = ? AND is_deleted = 0',
          whereArgs: [userId],
          orderBy: 'name ASC',
        );
        return rows.map(Reseller.fromMap).toList();
      }, <Reseller>[]); // fallback = empty list

  /// Inserts a new reseller. Generates a UUID if [reseller.id] is empty.
  Future<void> save(Reseller reseller) =>
      safeVoidCall(() async {
        final database = await db.database;
        final map = reseller.toMap();
        if ((map['id'] as String).isEmpty) map['id'] = _uuid.v4();
        await database.insert('resellers', map);
      });

  /// Replaces an existing reseller row with updated values.
  Future<void> update(Reseller reseller) =>
      safeVoidCall(() async {
        final database = await db.database;
        await database.update(
          'resellers',
          reseller.toMap(),
          where: 'id = ?',
          whereArgs: [reseller.id],
        );
      });

  /// Soft-deletes a reseller (sets is_deleted = 1).
  Future<void> delete(String id) =>
      safeVoidCall(() async {
        final database = await db.database;
        await database.update(
          'resellers',
          {'is_deleted': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      });

  /// Finds a reseller by name (case-insensitive, active only). Returns null if not found.
  Future<Reseller?> findByName(String userId, String name) =>
      safeCall(() async {
        final database = await db.database;
        final rows = await database.query(
          'resellers',
          where: 'user_id = ? AND is_deleted = 0 AND LOWER(name) = LOWER(?)',
          whereArgs: [userId, name],
          limit: 1,
        );
        return rows.isEmpty ? null : Reseller.fromMap(rows.first);
      }, null); // fallback = null
}
