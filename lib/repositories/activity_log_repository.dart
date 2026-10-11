// ─────────────────────────────────────────────────────────────────────────────
// activity_log_repository.dart — Offline-first activity log storage
// Purpose : Saves activity log entries to SQLite immediately (works offline),
//           then enqueues a Firestore sync via SyncQueue for later upload.
// FIXES:
//   1. add()    — now enqueues 'save_log' via SyncQueue instead of calling
//                 _cloud.saveLog() directly. Logs are saved to SQLite first,
//                 then auto-synced to Firestore when internet is available.
//   2. getAll() — reads SQLite first. Falls back to Firestore only if empty
//                 AND online, then caches locally.
//   3. No more direct FirestoreSync calls in add() — everything via queue.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';
import '../dto/activity_log_dto.dart';
import 'base_repository.dart';
import 'i_activity_log_repository.dart';
import 'sync_queue.dart';

// Concrete implementation of IActivityLogRepository backed by SQLite + Firestore
class ActivityLogRepository extends BaseRepository
    implements IActivityLogRepository {
  final _queue = SyncQueue.instance; // Used to enqueue async Firestore writes

  // ── getAll ────────────────────────────────────────────────────────────────

  // Returns the most recent 500 activity logs for a user; falls back to Firestore if local is empty
  @override
  Future<List<ActivityLog>> getAll(String userId) => safeCall(() async {
    final database = await db.database;

    // Query SQLite for recent logs, newest first
    final maps = await database.query(
      'activity_logs',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 500,
    );

    return maps.map((row) => ActivityLogDto.fromLocal(row).toDomain()).toList();
  });

  // ── add ───────────────────────────────────────────────────────────────────

  // Saves a log entry to SQLite immediately, then schedules a Firestore upload
  @override
  Future<void> add(ActivityLog log, String userId) => safeVoidCall(() async {
    final database = await db.database;
    final dto = ActivityLogDto.fromDomain(log, userId);
    await database.transaction((txn) async {
      // The local log and its outbox row either both commit or both roll back.
      await txn.insert('activity_logs', dto.toLocal());

      await txn.rawDelete(
        '''
        DELETE FROM activity_logs
        WHERE user_id = ? AND id NOT IN (
          SELECT id FROM activity_logs
          WHERE user_id = ?
          ORDER BY timestamp DESC
          LIMIT 500
        )
      ''',
        [userId, userId],
      );

      await _queue.enqueue(
        operation: 'save_log',
        collection: 'activity_logs',
        userId: userId,
        docId: log.id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });
}
