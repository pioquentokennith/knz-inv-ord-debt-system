import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<int> _insertOutbox(
  Database database, {
  required String key,
  String documentId = 'document-1',
}) {
  final now = DateTime.utc(2026).toIso8601String();
  return database.insert('sync_queue', {
    'operation': 'save_product',
    'collection': 'products',
    'user_id': 'user-1',
    'doc_id': documentId,
    'data': '{"id":"$documentId","user_id":"user-1"}',
    'created_at': now,
    'attempt_count': 0,
    'next_attempt_at': null,
    'last_attempt_at': null,
    'last_error': null,
    'status': 'pending',
    'idempotency_key': key,
    'updated_at': now,
  });
}

void main() {
  sqfliteFfiInit();

  group('SyncQueue retryDelayForAttempt', () {
    test('starts at five seconds and grows exponentially', () {
      expect(SyncQueue.retryDelayForAttempt(1), const Duration(seconds: 5));
      expect(SyncQueue.retryDelayForAttempt(2), const Duration(seconds: 10));
      expect(SyncQueue.retryDelayForAttempt(3), const Duration(seconds: 20));
    });

    test('caps durable retries at one hour', () {
      expect(SyncQueue.retryDelayForAttempt(11), const Duration(hours: 1));
      expect(SyncQueue.retryDelayForAttempt(100), const Duration(hours: 1));
    });
  });

  group('OutboxProcessor', () {
    late Database database;

    setUp(() async {
      database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await DatabaseHelper.createSchemaForTesting(database);
    });

    tearDown(() => database.close());

    test('Firestore write failure remains durable and visible', () async {
      await _insertOutbox(database, key: 'failure');
      final processor = OutboxProcessor(
        databaseProvider: () async => database,
        dispatch: (_) => throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'Firestore is unavailable',
        ),
        now: () => DateTime.utc(2026),
      );

      final result = await processor.processUser('user-1');

      expect(result.succeeded, isFalse);
      expect(result.error, isA<FirebaseException>());
      final row = (await database.query('sync_queue')).single;
      expect(row['status'], 'failed');
      expect(row['attempt_count'], 1);
      expect(row['last_attempt_at'], isNotNull);
      expect(row['last_error'], contains('Firestore is unavailable'));
    });

    test('retry after reconnection completes the failed row', () async {
      await _insertOutbox(database, key: 'retry');
      var now = DateTime.utc(2026);
      var online = false;
      final processor = OutboxProcessor(
        databaseProvider: () async => database,
        dispatch: (_) async {
          if (!online) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
            );
          }
        },
        now: () => now,
      );

      expect((await processor.processUser('user-1')).succeeded, isFalse);
      online = true;
      now = now.add(const Duration(seconds: 5));
      final retry = await processor.processUser('user-1');

      expect(retry.succeeded, isTrue);
      expect(retry.completedCount, 1);
      expect(await database.query('sync_queue'), isEmpty);
    });

    test('successful processing completes only the confirmed row', () async {
      await _insertOutbox(database, key: 'first', documentId: 'document-1');
      await _insertOutbox(database, key: 'second', documentId: 'document-2');
      final processor = OutboxProcessor(
        databaseProvider: () async => database,
        dispatch: (row) async {
          if (row['doc_id'] == 'document-2') {
            throw StateError('second row failed');
          }
        },
        now: () => DateTime.utc(2026),
      );

      final result = await processor.processUser('user-1');

      expect(result.completedCount, 1);
      expect(result.failedRowId, 2);
      final remaining = (await database.query('sync_queue')).single;
      expect(remaining['doc_id'], 'document-2');
      expect(remaining['status'], 'failed');
    });

    test('idempotency keys are unique durable records', () async {
      await _insertOutbox(database, key: 'same-key');

      await expectLater(
        _insertOutbox(database, key: 'same-key', documentId: 'document-2'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  test('outbox survives database restart', () async {
    final directory = await Directory.systemTemp.createTemp('knz-outbox-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}outbox.db';
    var database = await databaseFactoryFfi.openDatabase(path);
    await DatabaseHelper.createSchemaForTesting(database);
    await _insertOutbox(database, key: 'restart');
    await database.close();

    database = await databaseFactoryFfi.openDatabase(path);
    addTearDown(database.close);
    expect(await database.query('sync_queue'), hasLength(1));
    final processor = OutboxProcessor(
      databaseProvider: () async => database,
      dispatch: (_) async {},
      now: () => DateTime.utc(2026),
    );

    final result = await processor.processUser('user-1');

    expect(result.completedCount, 1);
    expect(await database.query('sync_queue'), isEmpty);
  });
}
