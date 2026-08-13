// ─────────────────────────────────────────────────────────────────────────────
// local_reseller_repository.dart — SQLite-backed reseller repository
// Purpose : CRUD operations for the resellers table. Follows the same patterns
//           as LocalProductRepository (safeCall wrapper, soft-delete, user_id
//           partitioning) so the rest of the codebase stays consistent.
// OOP Pillars:
//   • Inheritance  — extends BaseRepository (safeCall, db getter)
//   • Encapsulation— all SQL is encapsulated here; callers use model objects
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../dto/reseller_dto.dart';
import '../models/reseller_model.dart';
import 'base_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class LocalResellerRepository extends BaseRepository {
  LocalResellerRepository({
    Future<Database> Function()? databaseProvider,
    SyncOutbox? queue,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _queue = queue ?? SyncQueue.instance;

  final Future<Database> Function() _databaseProvider;
  final SyncOutbox _queue;
  final _cloud = FirestoreSync.instance;

  /// Returns all active (non-deleted) resellers for a given user.
  Future<List<Reseller>> getAll(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    final partition = await database.query(
      'resellers',
      columns: const ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (partition.isEmpty && _queue.isOnline) {
      final cloudRows = await _cloud.getResellers(userId);
      await database.transaction((txn) async {
        for (final cloudRow in cloudRows) {
          final dto = ResellerDto.fromCloud(cloudRow, userId: userId);
          await txn.insert(
            'resellers',
            dto.toLocal(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });
    }
    final rows = await database.query(
      'resellers',
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
      orderBy: 'name ASC',
    );
    return rows.map((row) => ResellerDto.fromLocal(row).toDomain()).toList();
  });

  /// Returns resellers currently held in this user's recycle bin.
  Future<List<Reseller>> getDeleted(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'resellers',
      where: 'user_id = ? AND is_deleted = 1',
      whereArgs: [userId],
      orderBy: 'name ASC',
    );
    return rows.map((row) => ResellerDto.fromLocal(row).toDomain()).toList();
  });

  /// Inserts a new reseller. Generates a UUID if [reseller.id] is empty.
  Future<void> save(Reseller reseller) => safeVoidCall(() async {
    final database = await _databaseProvider();
    final dto = ResellerDto.fromDomain(reseller);
    final map = dto.toLocal();
    await database.transaction((txn) async {
      final inserted = await txn.insert('resellers', map);
      if (inserted <= 0) throw StateError('Reseller was not inserted.');
      await _queue.enqueue(
        operation: 'save_reseller',
        collection: 'resellers',
        userId: reseller.userId,
        docId: reseller.id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Replaces an existing reseller row with updated values.
  Future<void> update(Reseller reseller) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final dto = ResellerDto.fromDomain(reseller);
      final data = dto.toLocal();
      final changed = await txn.update(
        'resellers',
        data,
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [reseller.id, reseller.userId],
      );
      if (changed != 1) {
        throw StateError('Active reseller not found: ${reseller.id}');
      }
      await _queue.enqueue(
        operation: 'save_reseller',
        collection: 'resellers',
        userId: reseller.userId,
        docId: reseller.id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Soft-deletes a reseller (sets is_deleted = 1).
  Future<void> delete(String id, String userId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'resellers',
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Active reseller not found: $id');
      final tombstone = Map<String, dynamic>.from(rows.single)
        ..['is_deleted'] = 1
        ..['deleted_at'] = deletedAt;
      final dto = ResellerDto.fromLocal(tombstone);
      final changed = await txn.update(
        'resellers',
        {'is_deleted': 1, 'deleted_at': deletedAt},
        where: 'id = ? AND user_id = ? AND is_deleted = 0',
        whereArgs: [id, userId],
      );
      if (changed != 1) throw StateError('Active reseller not found: $id');
      await _queue.enqueue(
        operation: 'soft_delete_reseller',
        collection: 'resellers',
        userId: userId,
        docId: id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Restores one reseller owned by [userId] from the recycle bin.
  Future<void> restore(String id, String userId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'resellers',
        where: 'id = ? AND user_id = ? AND is_deleted = 1',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Deleted reseller not found: $id');
      final data = Map<String, dynamic>.from(rows.single)
        ..['is_deleted'] = 0
        ..['deleted_at'] = null;
      final dto = ResellerDto.fromLocal(data);
      final changed = await txn.update(
        'resellers',
        {'is_deleted': 0, 'deleted_at': null},
        where: 'id = ? AND user_id = ? AND is_deleted = 1',
        whereArgs: [id, userId],
      );
      if (changed != 1) throw StateError('Deleted reseller not found: $id');
      await _queue.enqueue(
        operation: 'save_reseller',
        collection: 'resellers',
        userId: userId,
        docId: id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  /// Permanently removes one already-deleted reseller owned by [userId].
  Future<void> hardDelete(String id, String userId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      await _queue.enqueue(
        operation: 'delete_reseller',
        collection: 'resellers',
        userId: userId,
        docId: id,
        data: {'id': id, 'user_id': userId},
        executor: txn,
      );
      final changed = await txn.update(
        'resellers',
        {'purge_state': 'pending'},
        where: 'id = ? AND user_id = ? AND is_deleted = 1 AND purge_state = ?',
        whereArgs: [id, userId, 'none'],
      );
      if (changed != 1) {
        throw StateError('Reseller purge could not be queued: $id');
      }
    });
    _queue.requestSync();
  });
}
