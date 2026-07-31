import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        name TEXT NOT NULL,
        email TEXT,
        role TEXT NOT NULL DEFAULT 'Administrator',
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        collection TEXT NOT NULL,
        user_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL
      )
    ''');
  });

  tearDown(() => database.close());

  test(
    'removes verifiers while quarantining legacy ownership unchanged',
    () async {
      await database.insert('users', {
        'id': 'local-id',
        'username': 'LegacyAdmin',
        'password': 'legacy-verifier',
        'name': 'Legacy Admin',
        'email': 'ADMIN@EXAMPLE.COM',
        'role': 'Administrator',
        'is_synced': 1,
        'created_at': '2025-01-01T00:00:00.000Z',
      });
      await database.insert('products', {
        'id': 'product-1',
        'user_id': 'legacyadmin',
        'name': 'Preserved product',
      });
      await database.insert('sync_queue', {
        'operation': 'save_user',
        'collection': 'users',
        'user_id': 'legacyadmin',
        'doc_id': 'local-id',
        'data': jsonEncode({
          'username': 'legacyadmin',
          'password': 'legacy-verifier',
          'nested': {'verifier': 'secret', 'name': 'Preserved'},
        }),
        'created_at': '2025-01-01T00:00:00.000Z',
      });

      await database.transaction(DatabaseHelper.migrateUsersToV9);

      final columns = await database.rawQuery('PRAGMA table_info(users)');
      expect(columns.map((row) => row['name']), isNot(contains('password')));
      final user = (await database.query('users')).single;
      expect(user['firebase_uid'], isNull);
      expect(user['username'], 'legacyadmin');
      expect(user['legacy_owner_key'], 'legacyadmin');
      expect(user['migration_state'], 'unmapped');
      expect(user['account_status'], 'pending');
      expect(user['is_active'], 0);
      expect(
        (await database.query('products')).single['user_id'],
        'legacyadmin',
      );

      final payload =
          jsonDecode(
                (await database.query('sync_queue')).single['data'] as String,
              )
              as Map<String, dynamic>;
      expect(payload, isNot(contains('password')));
      expect(payload['nested'], {'name': 'Preserved'});
    },
  );

  test('invalid outbox JSON rolls the identity migration back', () async {
    await database.insert('users', {
      'id': 'local-id',
      'username': 'legacy',
      'password': 'legacy-verifier',
      'name': 'Legacy User',
      'email': 'legacy@example.com',
      'role': 'Administrator',
      'is_synced': 0,
      'created_at': '2025-01-01T00:00:00.000Z',
    });
    await database.insert('sync_queue', {
      'operation': 'save_user',
      'collection': 'users',
      'user_id': 'legacy',
      'doc_id': 'local-id',
      'data': '{invalid',
      'created_at': '2025-01-01T00:00:00.000Z',
    });

    await expectLater(
      database.transaction(DatabaseHelper.migrateUsersToV9),
      throwsStateError,
    );
    final columns = await database.rawQuery('PRAGMA table_info(users)');
    expect(columns.map((row) => row['name']), contains('password'));
    expect(
      (await database.query('users')).single['password'],
      'legacy-verifier',
    );
  });
}
