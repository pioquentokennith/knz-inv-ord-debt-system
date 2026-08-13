import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/repositories/sync_issue_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database database;
  late SyncIssueRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(database);
    repository = SyncIssueRepository(databaseProvider: () async => database);
  });

  tearDown(() => database.close());

  test('lists and resolves only the active user sync issue', () async {
    final now = DateTime.utc(2026).toIso8601String();
    await database.insert('sync_conflicts', {
      'user_id': 'user-1',
      'collection': 'products',
      'doc_id': 'product-1',
      'aggregate_key': 'products:product-1',
      'local_revision': 1,
      'remote_revision': 2,
      'local_data': '{}',
      'remote_data': '{}',
      'reason': 'stale revision',
      'status': 'open',
      'created_at': now,
    });
    await database.insert('dead_letters', {
      'user_id': 'user-2',
      'operation': 'save_product',
      'aggregate_key': 'products:other',
      'payload': '{}',
      'error_class': 'permanent',
      'last_error': 'invalid',
      'attempt_count': 1,
      'created_at': now,
    });

    final issues = await repository.getOpen('user-1');
    expect(issues, hasLength(1));
    await repository.resolve(issues.single, 'user-1');

    expect(await repository.getOpen('user-1'), isEmpty);
    expect(await repository.getOpen('user-2'), hasLength(1));
  });

  test('explicit dead-letter retry recreates one pending outbox row', () async {
    final now = DateTime.utc(2026).toIso8601String();
    await database.insert('dead_letters', {
      'user_id': 'user-1',
      'operation': 'save_product',
      'aggregate_key': 'products:product-1',
      'payload': '{"id":"product-1","revision":1,"base_revision":0}',
      'error_class': 'permanent',
      'last_error': 'old client contract',
      'attempt_count': 1,
      'created_at': now,
    });
    final issue = (await repository.getOpen('user-1')).single;

    await repository.retryDeadLetter(issue, 'user-1');

    final outbox = (await database.query('sync_queue')).single;
    expect(outbox['operation'], 'save_product');
    expect(outbox['doc_id'], 'product-1');
    expect(outbox['status'], 'pending');
    expect(await repository.getOpen('user-1'), isEmpty);
  });
}
