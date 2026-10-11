import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/domain_exceptions.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/repositories/firestore_sync.dart';
import 'package:knz_scent_admin/repositories/revisioned_replay.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/revision_firestore_fake.dart';

const uid = 'user-a';
const stamp = '2026-09-21T10:57:24.837158Z';
const path = 'users/$uid/products/product-a';

Map<String, dynamic> product({int base = 0, int stock = 100}) => {
  'id': 'product-a',
  'user_id': uid,
  'name': 'Rose',
  'description': 'Floral',
  'category': 'Eau de Parfum',
  'price_centavos': 22000,
  'stock_qty': stock,
  'min_stock_level': 5,
  'image_path': null,
  'created_at': stamp,
  'is_deleted': 0,
  'deleted_at': null,
  'schema_version': 1,
  'base_revision': base,
  'revision': base + 1,
  'writer_device_id': 'DEVICE-A',
  'updated_at': stamp,
};

Future<int> enqueue(
  Database db,
  Map<String, dynamic> data, {
  String collection = 'products',
  String? owner,
  String? status,
}) => db.insert('sync_queue', {
  'operation': collection == 'products' ? 'save_product' : 'save_reseller',
  'collection': collection,
  'user_id': owner ?? data['user_id'],
  'doc_id': data['id'],
  'data': jsonEncode(data),
  'created_at': stamp,
  'status': status ?? 'pending',
  'attempt_count': 0,
  'idempotency_key':
      '${owner ?? data['user_id']}:$collection:${data['id']}:${data['revision']}',
  'operation_id': 'operation-${data['revision']}',
  'aggregate_key': '$collection:${data['id']}',
  'updated_at': stamp,
  'expected_revision': data['base_revision'],
  'resulting_revision': data['revision'],
  'device_id': data['writer_device_id'],
});

Future<int> conflict(
  Database db,
  Map<String, dynamic> data, {
  String collection = 'products',
  String? owner,
  String? status,
}) => db.insert('sync_conflicts', {
  'user_id': owner ?? data['user_id'],
  'collection': collection,
  'doc_id': data['id'],
  'aggregate_key': '$collection:${data['id']}',
  'local_revision': data['base_revision'],
  'remote_revision': data['revision'],
  'local_data': jsonEncode(Map.fromEntries(data.entries.toList().reversed)),
  'remote_data': jsonEncode(data),
  'reason': 'revision mismatch',
  'status': status ?? 'open',
  'created_at': stamp,
});

void main() {
  sqfliteFfiInit();
  late Database db;
  late RevisionFirestoreFake remote;
  late FirestoreSync cloud;
  late String? principal;
  late SyncQueue queue;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(db);
    principal = uid;
    remote = RevisionFirestoreFake();
    cloud = FirestoreSync.forTesting(
      firestore: remote,
      currentUid: () => principal,
    );
    queue = SyncQueue.forTesting(
      databaseProvider: () async => db,
      currentUid: () => principal,
      cloud: cloud,
    );
    queue.setAuthorizationGate((_) async => true);
  });
  tearDown(() async {
    await queue.stopMonitoring();
    await db.close();
  });

  test(
    'normal write, lost acknowledgment, then replay completes without another write',
    () async {
      final data = product();
      await enqueue(db, data);
      await cloud.saveProduct(
        uid,
        data,
      ); // Remote commit; outbox still durable.
      expect(remote.writes, 1);
      final result = await queue.syncPending();
      expect(result.completedCount, 1);
      expect(remote.writes, 1);
      expect(await db.query('sync_queue'), isEmpty);
      expect(await db.query('sync_conflicts'), isEmpty);
    },
  );

  test(
    'reseller replay ignores map ordering and resolves its existing false conflict',
    () async {
      final data = <String, dynamic>{
        'id': 'reseller-a',
        'user_id': uid,
        'name': 'Test reseller',
        'contact': null,
        'deduction_per_item_centavos': 5000,
        'created_at': stamp,
        'is_deleted': 0,
        'deleted_at': null,
        'schema_version': 1,
        'base_revision': 0,
        'revision': 1,
        'writer_device_id': 'DEVICE-A',
        'updated_at': stamp,
      };
      remote.documents['users/$uid/resellers/reseller-a'] = Map.fromEntries(
        data.entries.toList().reversed,
      );
      await enqueue(db, data, collection: 'resellers', status: 'conflict');
      await conflict(db, data, collection: 'resellers');
      final result = await queue.syncPending();
      expect(result.completedCount, 1);
      expect(remote.writes, 0);
      expect(await db.query('sync_queue'), isEmpty);
      expect(await db.query('sync_conflicts'), isEmpty);
    },
  );

  test(
    'same resulting revision but different stock remains a real conflict',
    () async {
      await enqueue(db, product());
      remote.documents[path] = product(stock: 90);
      final result = await queue.syncPending();
      expect(result.error, isA<SyncConflictException>());
      expect(remote.writes, 0);
      expect((await db.query('sync_queue')).single['status'], 'conflict');
      expect(await db.query('sync_conflicts'), hasLength(1));
      expect(remote.documents[path]!['stock_qty'], 90);
    },
  );

  test(
    'detached false conflict is recovered from a current read without an outbox row',
    () async {
      final a = product();
      remote.documents[path] = a;
      await db.insert('products', {...a, 'stock_qty': 94, 'revision': 2});
      final before = (await db.query('products')).single;
      await conflict(db, a);
      final otherUid = await conflict(db, {...a, 'user_id': 'user-b'});
      final otherRecord = await conflict(db, {...a, 'id': 'other-document'});
      expect((await queue.syncPending()).succeeded, isTrue);
      expect(remote.writes, 0);
      expect((await db.query('products')).single, before);
      expect(
        (await db.query('sync_conflicts')).map((r) => r['id']),
        unorderedEquals([otherUid, otherRecord]),
      );
    },
  );

  test(
    'detached conflict is preserved if current remote differs from stored snapshot',
    () async {
      await conflict(db, product());
      remote.documents[path] = product(base: 1, stock: 90);
      await queue.syncPending();
      expect(await db.query('sync_conflicts'), hasLength(1));
      expect(remote.writes, 0);
    },
  );

  test(
    'detached recovery leaves a new local edit and its conflict intact',
    () async {
      final a = product();
      await conflict(db, a);
      remote.documents[path] = a;
      remote.beforeRead = () async {
        remote.beforeRead = null;
        final bId = await enqueue(db, product(base: 1, stock: 94));
        await db.update(
          'sync_queue',
          {'next_attempt_at': '2099-01-01T00:00:00Z'},
          where: 'id = ?',
          whereArgs: [bId],
        );
      };
      await queue.syncPending();
      expect(await db.query('sync_queue'), hasLength(1));
      expect(await db.query('sync_conflicts'), hasLength(1));
      expect(remote.writes, 0);
    },
  );

  test(
    'conflict retries use backoff and retain the exact conflict link',
    () async {
      final a = product();
      await enqueue(db, a, status: 'conflict');
      final id = await conflict(db, a);
      remote.documents[path] = product(stock: 90);
      await queue.syncPending();
      final row = (await db.query('sync_queue')).single;
      expect(row['conflict_id'], id);
      expect(
        DateTime.parse(
          row['next_attempt_at'] as String,
        ).isAfter(DateTime.parse(row['last_attempt_at'] as String)),
        isTrue,
      );
      final reads = remote.transactions;
      await queue.syncPending();
      expect(remote.transactions, reads);
      expect(await db.query('sync_conflicts'), hasLength(1));
    },
  );

  test('guard stays acquired while Firestore dispatch awaits', () async {
    await enqueue(db, product());
    final started = Completer<void>();
    final release = Completer<void>();
    remote.beforeRead = () async {
      started.complete();
      await release.future;
    };
    final first = queue.syncPending();
    await started.future;
    expect((await queue.syncPending()).completedCount, 0);
    release.complete();
    expect((await first).completedCount, 1);
    expect(remote.transactions, 1);
    expect(remote.writes, 1);
  });

  test('guard releases after processing exception', () async {
    await enqueue(db, product());
    // Keep the automatic retry timer out of this explicit guard-release test.
    await db.update('sync_queue', {'next_attempt_at': '2099-01-01T00:00:00Z'});
    await db.execute(
      'ALTER TABLE sync_conflicts RENAME TO unavailable_conflicts',
    );
    await expectLater(queue.syncPending(), throwsA(isA<DatabaseException>()));
    await db.execute(
      'ALTER TABLE unavailable_conflicts RENAME TO sync_conflicts',
    );
    await db.update('sync_queue', {'next_attempt_at': null});
    expect((await queue.syncPending()).completedCount, 1);
  });

  for (final field in ['writer_device_id', 'updated_at', 'base_revision']) {
    test('matching data without $field cannot prove replay', () async {
      final data = product()..remove(field);
      remote.documents[path] = {...data};
      await expectLater(
        cloud.saveProduct(uid, data),
        throwsA(isA<SyncConflictException>()),
      );
      expect(remote.writes, 0);
    });
  }

  test('same business data from another device is not replay', () async {
    remote.documents[path] = product()..['writer_device_id'] = 'DEVICE-B';
    await expectLater(
      cloud.saveProduct(uid, product()),
      throwsA(isA<SyncConflictException>()),
    );
    expect(remote.writes, 0);
  });

  test(
    'stored matching snapshot is insufficient when current Firebase differs',
    () async {
      final data = product();
      await enqueue(db, data, status: 'conflict');
      final conflictId = await conflict(db, data);
      remote.documents[path] = product(base: 1, stock: 70);
      final result = await queue.syncPending();
      expect(result.error, isA<SyncConflictException>());
      expect((await db.query('sync_conflicts')).single['id'], conflictId);
      expect((await db.query('sync_queue')).single['conflict_id'], conflictId);
      expect(remote.writes, 0);
    },
  );

  test(
    'existing conflict recovery never recreates a missing cloud record',
    () async {
      await enqueue(db, product(), status: 'conflict');
      await conflict(db, product());
      final result = await queue.syncPending();
      expect(result.error, isA<SyncConflictException>());
      expect(remote.writes, 0);
      expect(await db.query('sync_conflicts'), hasLength(1));
    },
  );

  test(
    'acknowledges A without overwriting latest local stock or removing pending B',
    () async {
      final a = product();
      final b = product(base: 1, stock: 94);
      await db.insert('products', {
        ...b,
        'revision': 3,
        'base_revision': 2,
        'image_path': '/device/photo.jpg',
      });
      final before = (await db.query('products')).single;
      await enqueue(db, a, status: 'conflict');
      final bId = await enqueue(db, b);
      await db.update(
        'sync_queue',
        {'next_attempt_at': '2099-01-01T00:00:00Z'},
        where: 'id = ?',
        whereArgs: [bId],
      );
      await conflict(db, a);
      await conflict(db, {...a, 'id': 'other-document'});
      await conflict(db, {...a, 'user_id': 'user-b'});
      remote.documents[path] = a;
      final result = await queue.syncPending();
      expect(result.completedCount, 1);
      expect((await db.query('sync_queue')).single['id'], bId);
      expect((await db.query('products')).single, before);
      final remaining = await db.query('sync_conflicts');
      expect(remaining, hasLength(2));
      expect(remaining.any((row) => row['user_id'] == 'user-b'), isTrue);
      expect(remaining.any((row) => row['doc_id'] == 'other-document'), isTrue);
      expect(remote.writes, 0);
    },
  );

  test('acknowledging A preserves B conflict for the same document', () async {
    final a = product();
    final b = product(base: 1, stock: 94);
    await enqueue(db, a, status: 'conflict');
    final bId = await enqueue(db, b, status: 'conflict');
    await db.update(
      'sync_queue',
      {'next_attempt_at': '2099-01-01T00:00:00Z'},
      where: 'id = ?',
      whereArgs: [bId],
    );
    final bConflict = await conflict(db, b);
    remote.documents[path] = a;
    expect((await queue.syncPending()).completedCount, 1);
    expect((await db.query('sync_conflicts')).single['id'], bConflict);
    expect((await db.query('sync_queue')).single['id'], bId);
  });

  test(
    'later dependent B can sync normally after replay A is acknowledged',
    () async {
      await enqueue(db, product(), status: 'conflict');
      await enqueue(db, product(base: 1, stock: 94));
      await conflict(db, product());
      remote.documents[path] = product();
      expect((await queue.syncPending()).completedCount, 2);
      expect(remote.writes, 1);
      expect(remote.documents[path]!['revision'], 2);
      expect(remote.documents[path]!['stock_qty'], 94);
      expect(await db.query('sync_queue'), isEmpty);
    },
  );

  test('another UID payload cannot acknowledge this user operation', () async {
    final other = product()..['user_id'] = 'user-b';
    remote.documents['users/user-b/products/product-a'] = other;
    await enqueue(db, other, owner: uid);
    expect((await queue.syncPending()).succeeded, isFalse);
    expect(await db.query('sync_queue'), hasLength(1));
    expect(remote.transactions, 0);
    await expectLater(cloud.saveProduct(uid, other), throwsStateError);
  });

  test('remote record with different owner does not prove replay', () async {
    remote.documents[path] = product()..['user_id'] = 'user-b';
    await expectLater(
      cloud.saveProduct(uid, product()),
      throwsA(isA<SyncConflictException>()),
    );
    expect(remote.writes, 0);
  });

  test(
    'Firebase commits then SQLite acknowledgment fails; retry recovers atomically',
    () async {
      await db.insert('products', {...product(), 'revision': 0});
      await enqueue(db, product());
      await db.execute(
        '''CREATE TRIGGER fail_ack BEFORE DELETE ON sync_queue
      BEGIN SELECT RAISE(ABORT, 'simulated local acknowledgment failure'); END''',
      );
      final first = await queue.syncPending();
      expect(first.succeeded, isFalse);
      expect(remote.writes, 1);
      expect((await db.query('products')).single['revision'], 0);
      expect(await db.query('sync_queue'), hasLength(1));
      await db.execute('DROP TRIGGER fail_ack');
      await db.update('sync_queue', {'next_attempt_at': null});
      final retry = await queue.syncPending();
      expect(retry.completedCount, 1);
      expect(remote.writes, 1);
      expect((await db.query('products')).single['revision'], 1);
      expect(await db.query('sync_queue'), isEmpty);
      expect(await db.query('sync_conflicts'), isEmpty);
    },
  );

  test('failed acknowledgment rolls back conflict removal as well', () async {
    await enqueue(db, product(), status: 'conflict');
    final id = await conflict(db, product());
    remote.documents[path] = product();
    await db.execute('''CREATE TRIGGER fail_ack BEFORE DELETE ON sync_queue
      BEGIN SELECT RAISE(ABORT, 'ack failure'); END''');
    expect((await queue.syncPending()).succeeded, isFalse);
    expect((await db.query('sync_conflicts')).single['id'], id);
    await db.execute('DROP TRIGGER fail_ack');
    await db.update('sync_queue', {'next_attempt_at': null});
    expect((await queue.syncPending()).completedCount, 1);
    expect(await db.query('sync_conflicts'), isEmpty);
  });

  test(
    'two syncPending calls cannot enter while authorization awaits',
    () async {
      final authorization = Completer<bool>();
      var gates = 0;
      queue.setAuthorizationGate((_) {
        gates++;
        return authorization.future;
      });
      await enqueue(db, product());
      final first = queue.syncPending();
      final second = await queue.syncPending();
      expect(second.completedCount, 0);
      expect(gates, 1);
      expect(remote.transactions, 0);
      authorization.complete(true);
      expect((await first).completedCount, 1);
      expect(remote.transactions, 1);
      expect(remote.writes, 1);
      expect(await db.query('sync_conflicts'), isEmpty);
    },
  );

  test(
    'sync guard releases after rejection and after authorization exception',
    () async {
      await enqueue(db, product());
      queue.setAuthorizationGate((_) async => false);
      expect((await queue.syncPending()).completedCount, 0);
      queue.setAuthorizationGate((_) => throw StateError('temporary'));
      await expectLater(queue.syncPending(), throwsStateError);
      queue.setAuthorizationGate((_) async => true);
      expect((await queue.syncPending()).completedCount, 1);
    },
  );

  test(
    'UID changes during authorization: old user does not dispatch',
    () async {
      final authorization = Completer<bool>();
      queue.setAuthorizationGate((_) => authorization.future);
      await enqueue(db, product());
      final running = queue.syncPending();
      principal = 'user-b';
      authorization.complete(true);
      expect((await running).completedCount, 0);
      expect(remote.transactions, 0);
      expect(await db.query('sync_queue'), hasLength(1));
      principal = uid;
      queue.setAuthorizationGate((_) async => true);
      expect((await queue.syncPending()).completedCount, 1);
    },
  );

  test('session stop during authorization prevents delayed dispatch', () async {
    final authorization = Completer<bool>();
    queue.setAuthorizationGate((_) => authorization.future);
    await enqueue(db, product());
    final running = queue.syncPending();
    await queue.stopMonitoring();
    authorization.complete(true);
    expect((await running).completedCount, 0);
    expect(remote.transactions, 0);
    expect(await db.query('sync_queue'), hasLength(1));
  });

  test(
    'UID change after remote commit preserves durable operation for original session',
    () async {
      await enqueue(db, product());
      remote.afterCommit = () async {
        principal = 'user-b';
      };
      expect((await queue.syncPending()).completedCount, 0);
      expect(await db.query('sync_queue'), hasLength(1));
      principal = uid;
      remote.afterCommit = null;
      expect((await queue.syncPending()).completedCount, 1);
      expect(remote.writes, 1);
    },
  );

  test(
    'map key order is ignored; lists, missing values and metadata remain meaningful',
    () {
      final a = product()
        ..['nested'] = {
          'a': 1,
          'b': [1, 2],
        };
      final b = Map<String, dynamic>.fromEntries(a.entries.toList().reversed)
        ..['nested'] = {
          'b': [1, 2],
          'a': 1,
        };
      expect(RevisionedReplay.isExact(a, b), isTrue);
      b['nested'] = {
        'b': [2, 1],
        'a': 1,
      };
      expect(RevisionedReplay.isExact(a, b), isFalse);
      expect(
        RevisionedReplay.isExact(product(), product()..remove('image_path')),
        isFalse,
      );
      expect(
        RevisionedReplay.isExact(product(), product()..['extra'] = true),
        isFalse,
      );
    },
  );

  test(
    'replay compares DTO cloud payload, preserving a device-local photo',
    () async {
      final data = product()..['image_path'] = '/local/photo.jpg';
      remote.documents[path] = product();
      await cloud.saveProduct(uid, data);
      expect(remote.writes, 0);
      expect(data['image_path'], '/local/photo.jpg');
    },
  );

  test(
    'exact replay survives SQLite close/reopen and adapter recreation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'replay-restart-',
      );
      final filename = '${directory.path}${Platform.pathSeparator}outbox.db';
      var persistent = await databaseFactoryFfi.openDatabase(filename);
      await DatabaseHelper.createSchemaForTesting(persistent);
      await enqueue(persistent, product());
      await cloud.saveProduct(uid, product());
      await persistent.close();
      persistent = await databaseFactoryFfi.openDatabase(filename);
      final restoredCloud = FirestoreSync.forTesting(
        firestore: remote,
        currentUid: () => uid,
      );
      final restarted = SyncQueue.forTesting(
        databaseProvider: () async => persistent,
        currentUid: () => uid,
        cloud: restoredCloud,
      );
      restarted.setAuthorizationGate((_) async => true);
      try {
        expect((await restarted.syncPending()).completedCount, 1);
        expect(remote.writes, 1);
        expect(await persistent.query('sync_queue'), isEmpty);
        expect(await persistent.query('sync_conflicts'), isEmpty);
      } finally {
        await restarted.stopMonitoring();
        await persistent.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
