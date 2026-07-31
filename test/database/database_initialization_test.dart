import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'database initialization enables secure delete and preserves rows',
    () async {
      final directory = await Directory.systemTemp.createTemp('knz_db_init_');
      final databasePath = path.join(directory.path, 'existing.db');
      Database? database;

      try {
        database = await DatabaseHelper.openDatabaseForTesting(
          databasePath,
          factory: databaseFactoryFfi,
        );
        await database.insert('users', {
          'id': 'existing-user',
          'firebase_uid': 'firebase-user',
          'username': 'existing',
          'name': 'Existing User',
          'email': 'existing@example.com',
          'role': 'Staff',
          'account_status': 'active',
          'is_active': 1,
          'legacy_owner_key': null,
          'migration_state': 'mapped',
          'is_synced': 0,
          'created_at': '2026-01-01T00:00:00.000Z',
        });
        await database.close();
        database = null;

        database = await DatabaseHelper.openDatabaseForTesting(
          databasePath,
          factory: databaseFactoryFfi,
        );

        final secureDelete = await database.rawQuery('PRAGMA secure_delete');
        expect(secureDelete.single.values.single, 1);
        expect(
          await database.query(
            'users',
            where: 'id = ?',
            whereArgs: ['existing-user'],
          ),
          hasLength(1),
        );
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
