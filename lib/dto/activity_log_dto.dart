import '../models/user_model.dart';
import 'dto_reader.dart';

class ActivityLogDto {
  static const currentVersion = 1;

  ActivityLogDto({
    required this.id,
    required this.message,
    required this.type,
    required this.timestamp,
    required this.userId,
  });

  final String id;
  final String message;
  final String type;
  final DateTime timestamp;
  final String userId;

  factory ActivityLogDto.fromDomain(ActivityLog log, String userId) =>
      ActivityLogDto(
        id: log.id,
        message: log.message,
        type: log.type,
        timestamp: log.timestamp.toUtc(),
        userId: userId,
      );

  factory ActivityLogDto.fromLocal(Map<String, dynamic> map) => _fromMap(map);

  factory ActivityLogDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static ActivityLogDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
  }) {
    final r = DtoReader(map, 'ActivityLog');
    r.version(currentVersion);
    return ActivityLogDto(
      id: r.string(const ['id']),
      message: r.string(const ['message']),
      type: r.string(const ['type']),
      timestamp: r.date(const ['timestamp']),
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'message': message,
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'user_id': userId,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  ActivityLog toDomain() =>
      ActivityLog(id: id, message: message, timestamp: timestamp, type: type);
}
