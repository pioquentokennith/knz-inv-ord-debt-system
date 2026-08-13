import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../dto/business_event_dto.dart';
import '../models/business_event_model.dart';
import 'base_repository.dart';
import 'business_event_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class LocalBusinessEventRepository extends BaseRepository
    implements BusinessEventRepository {
  LocalBusinessEventRepository({
    Future<Database> Function()? databaseProvider,
    SyncOutbox? queue,
    FirestoreSync? cloud,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _queue = queue ?? SyncQueue.instance,
       _cloud = cloud ?? FirestoreSync.instance;

  final Future<Database> Function() _databaseProvider;
  final SyncOutbox _queue;
  final FirestoreSync _cloud;

  @override
  Future<List<BusinessEvent>> getAll(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    final local = await database.query(
      'business_events',
      columns: const ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (local.isEmpty && _queue.isOnline) {
      final cloudEvents = await _cloud.getBusinessEvents(userId);
      final dtos =
          cloudEvents
              .map((data) => BusinessEventDto.fromCloud(data, userId: userId))
              .toList()
            ..sort((left, right) {
              final leftReversal = left.eventType == 'reversal' ? 1 : 0;
              final rightReversal = right.eventType == 'reversal' ? 1 : 0;
              if (leftReversal != rightReversal) {
                return leftReversal.compareTo(rightReversal);
              }
              return left.recordedAt.compareTo(right.recordedAt);
            });
      await database.transaction((txn) async {
        for (final dto in dtos) {
          await txn.insert(
            'business_events',
            dto.toLocal(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });
    }
    final rows = await database.query(
      'business_events',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'COALESCE(occurred_at, recorded_at) DESC, id DESC',
    );
    return rows
        .map((row) => BusinessEventDto.fromLocal(row).toDomain())
        .toList(growable: false);
  });

  @override
  Future<List<BusinessEvent>> getForSubject(
    String userId,
    BusinessEventSubject subject,
    String subjectId,
  ) => safeCall(() async {
    final database = await _databaseProvider();
    final rows = await database.query(
      'business_events',
      where: 'user_id = ? AND subject_type = ? AND subject_id = ?',
      whereArgs: [userId, subject.storageKey, subjectId],
      orderBy: 'COALESCE(occurred_at, recorded_at) ASC, id ASC',
    );
    return rows
        .map((row) => BusinessEventDto.fromLocal(row).toDomain())
        .toList(growable: false);
  });
}

Future<void> insertBusinessEvent(
  DatabaseExecutor executor,
  BusinessEvent event,
) async {
  await executor.insert(
    'business_events',
    BusinessEventDto.fromDomain(event).toLocal(),
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
}
