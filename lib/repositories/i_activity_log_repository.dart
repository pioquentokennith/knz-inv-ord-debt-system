import '../models/user_model.dart';

abstract class IActivityLogRepository {
  Future<List<ActivityLog>> getAll(String userId);
  Future<void> add(ActivityLog log, String userId);
}
