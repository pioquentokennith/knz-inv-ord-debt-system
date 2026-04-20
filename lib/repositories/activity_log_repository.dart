// ─────────────────────────────────────────────────────────────────────────────
// activity_log_repository.dart — FIXED: Offline-first with SyncQueue
//
// FIXES:
//   1. add()  — now enqueues 'save_log' via SyncQueue instead of calling
//               _cloud.saveLog() directly. Logs are saved to SQLite first,
//               then auto-synced to Firestore when internet is available.
//               Before: offline = logs never reached Firestore, lost on logout.
//   2. getAll() — reads SQLite first. Falls back to Firestore only if empty
//               AND online, then caches locally — same pattern as products/
//               orders/debts. Logs now survive sign-out + sign-in.
//   3. No more direct FirestoreSync calls in add() — everything via queue.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';
import 'base_repository.dart';
import 'i_activity_log_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class ActivityLogRepository extends BaseRepository
    implements IActivityLogRepository {
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  // ── getAll ────────────────────────────────────────────────────────────────
  @override
  Future<List<ActivityLog>> getAll(String userId) => safeCall(() async {
    final database = await db.database;

    final maps = await database.query(
      'activity_logs',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 50,
    );

    // Local cache hit → return immediately (works offline too)
    if (maps.isNotEmpty) return maps.map(_fromMap).toList();

    // Empty local + online → restore from Firestore and cache locally
    if (_queue.isOnline) {
      final cloudLogs = await _cloud.getLogs(userId);
      for (final l in cloudLogs) {
        try {
          // Avoid duplicates on partial sync
          final existing = await database.query(
            'activity_logs',
            where: 'user_id = ? AND timestamp = ? AND message = ?',
            whereArgs: [userId, l['timestamp'], l['message']],
          );
          if (existing.isNotEmpty) continue;
          await database.insert('activity_logs', {
            'message':   l['message'],
            'type':      l['type'],
            'timestamp': l['timestamp'],
            'user_id':   userId,
          });
        } catch (_) {}
      }
      final restored = await database.query(
        'activity_logs',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
        limit: 50,
      );
      return restored.map(_fromMap).toList();
    }

    return [];
  }, []);

  // ── add ───────────────────────────────────────────────────────────────────
  @override
  Future<void> add(ActivityLog log, String userId) =>
      safeVoidCall(() async {
    final database = await db.database;

    // 1. Save to SQLite immediately — always works offline
    await database.insert('activity_logs', {
      'message':   log.message,
      'type':      log.type,
      'timestamp': log.timestamp.toIso8601String(),
      'user_id':   userId,
    });

    // 2. Keep only the 50 most-recent logs per user
    await database.rawDelete('''
      DELETE FROM activity_logs
      WHERE user_id = ? AND id NOT IN (
        SELECT id FROM activity_logs
        WHERE user_id = ?
        ORDER BY timestamp DESC
        LIMIT 50
      )
    ''', [userId, userId]);

    // 3. Enqueue Firestore sync — fires now if online, auto-retried if offline
    await _queue.enqueue(
      operation:  'save_log',
      collection: 'activity_logs',
      userId:     userId,
      docId:      log.id,
      data: {
        'id':        log.id,
        'message':   log.message,
        'type':      log.type,
        'timestamp': log.timestamp.toIso8601String(),
        'user_id':   userId,
      },
    );

    // 4. Flush queue right away if we're online so it syncs immediately
    if (_queue.isOnline) _queue.syncPending();
  });

  // ── helpers ───────────────────────────────────────────────────────────────
  ActivityLog _fromMap(Map<String, Object?> m) => ActivityLog(
    id:        m['id'].toString(),
    message:   m['message'] as String,
    timestamp: DateTime.parse(m['timestamp'] as String),
    type:      m['type'] as String,
  );
}
