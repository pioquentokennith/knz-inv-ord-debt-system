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

import 'dart:async';

import '../models/user_model.dart';
import 'base_repository.dart';
import 'i_activity_log_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

// Concrete implementation of IActivityLogRepository backed by SQLite + Firestore
class ActivityLogRepository extends BaseRepository
    implements IActivityLogRepository {
  final _cloud = FirestoreSync.instance; // Used for Firestore fallback in getAll()
  final _queue = SyncQueue.instance;     // Used to enqueue async Firestore writes

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

    // Local cache hit — return immediately without any network call (works offline too)
    if (maps.isNotEmpty) return maps.map(_fromMap).toList();

    // Local is empty and device is online — restore from Firestore and cache locally
    if (_queue.isOnline) {
      final cloudLogs = await _cloud.getLogs(userId);
      for (final l in cloudLogs) {
        try {
          // Check for duplicates before inserting to avoid double entries on partial sync
          final existing = await database.query(
            'activity_logs',
            where: 'user_id = ? AND timestamp = ? AND message = ?',
            whereArgs: [userId, l['timestamp'], l['message']],
          );
          if (existing.isNotEmpty) continue; // Skip if already cached
          await database.insert('activity_logs', {
            'message':   l['message'],
            'type':      l['type'],
            'timestamp': l['timestamp'],
            'user_id':   userId,
          });
        } catch (_) {}
      }
      // Re-query SQLite after caching cloud logs
      final restored = await database.query(
        'activity_logs',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'timestamp DESC',
        limit: 500,
      );
      return restored.map(_fromMap).toList();
    }

    return []; // Offline and no local data — return empty list
  }, []);

  // ── add ───────────────────────────────────────────────────────────────────

  // Saves a log entry to SQLite immediately, then schedules a Firestore upload
  @override
  Future<void> add(ActivityLog log, String userId) =>
      safeVoidCall(() async {
    final database = await db.database;

    // Step 1: Write to SQLite right away — always succeeds regardless of connectivity
    await database.insert('activity_logs', {
      'message':   log.message,
      'type':      log.type,
      'timestamp': log.timestamp.toIso8601String(),
      'user_id':   userId,
    });

    // Step 2: Trim the table to the 500 most recent logs to control DB size
    await database.rawDelete('''
      DELETE FROM activity_logs
      WHERE user_id = ? AND id NOT IN (
        SELECT id FROM activity_logs
        WHERE user_id = ?
        ORDER BY timestamp DESC
        LIMIT 500
      )
    ''', [userId, userId]);

    // Step 3: Enqueue the Firestore write — SyncQueue handles online/offline logic
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

    // Step 4: Flush the queue immediately if online so the log reaches Firestore now
    // unawaited intentionally — fire-and-forget, don't block the caller
    if (_queue.isOnline) unawaited(_queue.syncPending());
  });

  // ── helpers ───────────────────────────────────────────────────────────────

  // Converts a raw SQLite row map into an ActivityLog model instance
  ActivityLog _fromMap(Map<String, Object?> m) => ActivityLog(
    id:        m['id'].toString(),                        // AUTOINCREMENT int cast to String
    message:   m['message'] as String,
    timestamp: DateTime.parse(m['timestamp'] as String),
    type:      m['type'] as String,
  );
}
