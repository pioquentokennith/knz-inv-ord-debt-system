import '../models/user_model.dart';
import 'base_repository.dart';
import 'firestore_sync.dart';
import 'i_activity_log_repository.dart';

class ActivityLogRepository extends BaseRepository implements IActivityLogRepository {
  FirestoreSync get _cloud => FirestoreSync.instance;

  @override
  Future<List<ActivityLog>> getAll(String userId) => safeCall(() async {
    final database = await db.database;
    final maps = await database.query('activity_logs',
        where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'timestamp DESC', limit: 50);

    if (maps.isEmpty) {
      final cloudLogs = await _cloud.getLogs(userId);
      for (final l in cloudLogs) {
        try {
          await database.insert('activity_logs', {
            'message':   l['message'],
            'type':      l['type'],
            'timestamp': l['timestamp'],
            'user_id':   userId,
          });
        } catch (_) {}
      }
      final restored = await database.query('activity_logs',
          where: 'user_id = ?', whereArgs: [userId],
          orderBy: 'timestamp DESC', limit: 50);
      return restored.map((m) => ActivityLog(
        id:        m['id'].toString(),
        message:   m['message'] as String,
        timestamp: DateTime.parse(m['timestamp'] as String),
        type:      m['type'] as String,
      )).toList();
    }

    return maps.map((m) => ActivityLog(
      id:        m['id'].toString(),
      message:   m['message'] as String,
      timestamp: DateTime.parse(m['timestamp'] as String),
      type:      m['type'] as String,
    )).toList();
  }, []);

  @override
  Future<void> add(ActivityLog log, String userId) => safeVoidCall(() async {
    final database = await db.database;

    await database.insert('activity_logs', {
      'message':   log.message,
      'type':      log.type,
      'timestamp': log.timestamp.toIso8601String(),
      'user_id':   userId,
    });

    await database.rawDelete('''
      DELETE FROM activity_logs
      WHERE user_id = ? AND id NOT IN (
        SELECT id FROM activity_logs
        WHERE user_id = ?
        ORDER BY timestamp DESC
        LIMIT 50
      )
    ''', [userId, userId]);

    await _cloud.saveLog(userId, {
      'id':        log.id,
      'message':   log.message,
      'type':      log.type,
      'timestamp': log.timestamp.toIso8601String(),
      'user_id':   userId,
    });
  });
}
