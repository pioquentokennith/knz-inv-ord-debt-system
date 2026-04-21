// ─────────────────────────────────────────────────────────────────────────────
// i_activity_log_repository.dart — Abstract IActivityLogRepository interface
// Purpose : Defines the minimal contract for reading and writing activity logs.
//           AppState depends on this interface so tests can inject a stub
//           without touching SQLite or Firestore.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/user_model.dart';

abstract class IActivityLogRepository {
  // Fetches the most recent activity log entries for a given user
  Future<List<ActivityLog>> getAll(String userId);

  // Persists a single activity log entry (SQLite + async Firestore sync)
  Future<void> add(ActivityLog log, String userId);
}
