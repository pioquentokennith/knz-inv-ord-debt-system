// stub_activity_log_repository.dart — In-memory stub, no SQLite
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/repositories/i_activity_log_repository.dart';

class StubActivityLogRepository implements IActivityLogRepository {
  final List<ActivityLog> _logs = [];

  @override
  Future<List<ActivityLog>> getAll(String userId) async => List.of(_logs);

  @override
  Future<void> add(ActivityLog log, String userId) async {
    _logs.insert(0, log);
    if (_logs.length > 50) _logs.removeLast();
  }
}
