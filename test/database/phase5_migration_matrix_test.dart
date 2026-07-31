import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory testDirectory;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('knz_migrations_');
  });

  tearDown(() async {
    await testDirectory.delete(recursive: true);
  });

  for (var version = 1; version <= DatabaseHelper.schemaVersion; version++) {
    test(
      'fixture version $version upgrades to the complete current schema',
      () async {
        final databasePath = path.join(testDirectory.path, 'v$version.db');
        final fixture = await databaseFactoryFfi.openDatabase(databasePath);
        if (version >= 11) {
          await _createRecentFixture(fixture, version);
        } else {
          await _createLegacyFixture(fixture, version);
        }
        await fixture.execute('PRAGMA user_version = $version');
        await fixture.close();

        final upgraded = await DatabaseHelper.openDatabaseForTesting(
          databasePath,
          factory: databaseFactoryFfi,
        );
        addTearDown(upgraded.close);

        expect(await upgraded.getVersion(), DatabaseHelper.schemaVersion);
        await _expectCompleteSchema(upgraded);
        final products = await upgraded.query('products');
        expect(products, hasLength(1));
        expect(products.single['price_centavos'], 10000);
        final orders = await upgraded.query('orders');
        expect(orders, hasLength(1));
        expect(orders.single['customer_pay_amount_centavos'], 10000);
        expect(await upgraded.query('order_items'), hasLength(1));
        expect(await upgraded.query('debts'), hasLength(1));
        expect(await upgraded.query('activity_logs'), hasLength(1));
        if (version >= 6) {
          expect(await upgraded.query('resellers'), hasLength(1));
          final custom = (await upgraded.query('custom_orders')).single;
          expect(custom['status'], 'Cancelled');
        }
      },
    );
  }

  test('failed v11 upgrade rolls back schema and user_version', () async {
    final databasePath = path.join(testDirectory.path, 'rollback.db');
    final fixture = await databaseFactoryFfi.openDatabase(databasePath);
    await _createRecentFixture(fixture, 11, duplicateDebt: true);
    await fixture.execute('PRAGMA user_version = 11');
    await fixture.close();

    await expectLater(
      DatabaseHelper.openDatabaseForTesting(
        databasePath,
        factory: databaseFactoryFfi,
      ),
      throwsA(isA<StateError>()),
    );

    final unchanged = await databaseFactoryFfi.openDatabase(databasePath);
    addTearDown(unchanged.close);
    expect(await unchanged.getVersion(), 11);
    expect(
      await _columns(unchanged, 'orders'),
      isNot(contains('schema_version')),
    );
    expect(
      await _columns(unchanged, 'orders'),
      isNot(contains('customer_pay_amount_centavos')),
    );
    expect(await _tableExists(unchanged, 'custom_order_payments'), isFalse);
    expect(await unchanged.query('debts'), hasLength(2));
  });

  test('incomplete schema cannot advance database version', () async {
    final databasePath = path.join(testDirectory.path, 'incomplete.db');
    final fixture = await databaseFactoryFfi.openDatabase(databasePath);
    await _createRecentFixture(fixture, 11);
    await fixture.execute('DROP TABLE activity_logs');
    await fixture.execute('PRAGMA user_version = 11');
    await fixture.close();

    await expectLater(
      DatabaseHelper.openDatabaseForTesting(
        databasePath,
        factory: databaseFactoryFfi,
      ),
      throwsA(isA<StateError>()),
    );

    final unchanged = await databaseFactoryFfi.openDatabase(databasePath);
    addTearDown(unchanged.close);
    expect(await unchanged.getVersion(), 11);
    expect(await _tableExists(unchanged, 'activity_logs'), isFalse);
    expect(await _tableExists(unchanged, 'custom_order_payments'), isFalse);
  });
}

Future<void> _createLegacyFixture(Database db, int version) async {
  final modernUser = version >= 9;
  await _createTable(
    db,
    'users',
    modernUser
        ? [
            'id TEXT PRIMARY KEY',
            'firebase_uid TEXT UNIQUE',
            'username TEXT NOT NULL UNIQUE COLLATE NOCASE',
            'name TEXT NOT NULL',
            'email TEXT NOT NULL',
            "role TEXT NOT NULL DEFAULT 'Staff'",
            "account_status TEXT NOT NULL DEFAULT 'pending'",
            'is_active INTEGER NOT NULL DEFAULT 0',
            'legacy_owner_key TEXT',
            "migration_state TEXT NOT NULL DEFAULT 'unmapped'",
            'is_synced INTEGER NOT NULL DEFAULT 0',
            'created_at TEXT NOT NULL',
          ]
        : [
            'id TEXT PRIMARY KEY',
            'username TEXT NOT NULL UNIQUE COLLATE NOCASE',
            'password TEXT NOT NULL',
            'name TEXT NOT NULL',
            if (version >= 2) 'email TEXT',
            "role TEXT NOT NULL DEFAULT 'Staff'",
            if (version >= 2) 'is_synced INTEGER NOT NULL DEFAULT 0',
            'created_at TEXT NOT NULL',
          ],
  );
  await _createTable(db, 'products', [
    'id TEXT PRIMARY KEY',
    'name TEXT NOT NULL',
    'description TEXT',
    'category TEXT NOT NULL',
    'price REAL NOT NULL',
    'stock_qty INTEGER NOT NULL DEFAULT 0',
    'min_stock_level INTEGER NOT NULL DEFAULT 5',
    'image_path TEXT',
    'created_at TEXT NOT NULL',
    'user_id TEXT NOT NULL',
    if (version >= 4) 'is_deleted INTEGER NOT NULL DEFAULT 0',
    if (version >= 4) 'deleted_at TEXT',
  ]);
  await _createTable(db, 'orders', [
    'id TEXT PRIMARY KEY',
    'order_id TEXT NOT NULL',
    'customer_name TEXT NOT NULL',
    'total_amount REAL NOT NULL',
    'status TEXT NOT NULL',
    'order_date TEXT NOT NULL',
    'notes TEXT',
    'user_id TEXT NOT NULL',
    if (version >= 4) 'is_deleted INTEGER NOT NULL DEFAULT 0',
    if (version >= 4) 'deleted_at TEXT',
    if (version >= 6) 'payment_method TEXT',
    if (version >= 6) 'payment_reference TEXT',
    if (version >= 6) 'is_reseller INTEGER NOT NULL DEFAULT 0',
    if (version >= 6) 'discount_percent REAL NOT NULL DEFAULT 0',
    if (version >= 6) 'discounted_total REAL',
    if (version >= 6) "order_type TEXT NOT NULL DEFAULT 'regular'",
    if (version >= 10) 'stock_deducted INTEGER NOT NULL DEFAULT 1',
    if (version >= 10) 'stock_released_on_delete INTEGER NOT NULL DEFAULT 0',
  ]);
  await _createTable(db, 'order_items', [
    'id TEXT PRIMARY KEY',
    'order_id TEXT NOT NULL',
    'product_id TEXT NOT NULL',
    'product_name TEXT NOT NULL',
    'unit_price REAL NOT NULL',
    if (version >= 7) 'srp_price REAL',
    'quantity INTEGER NOT NULL',
    'FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE',
  ]);
  await _createTable(db, 'debts', [
    'id TEXT PRIMARY KEY',
    'customer_name TEXT NOT NULL',
    'order_id TEXT NOT NULL',
    'total_amount REAL NOT NULL',
    'amount_paid REAL NOT NULL DEFAULT 0',
    'created_at TEXT NOT NULL',
    'user_id TEXT NOT NULL',
    if (version >= 4) 'is_deleted INTEGER NOT NULL DEFAULT 0',
    if (version >= 4) 'deleted_at TEXT',
    if (version >= 6) 'interest_rate REAL NOT NULL DEFAULT 0',
    if (version >= 6) "interest_type TEXT DEFAULT 'none'",
    if (version >= 6) 'interest_start_date TEXT',
  ]);
  await _createTable(db, 'payments', [
    'id TEXT PRIMARY KEY',
    'debt_id TEXT NOT NULL',
    'amount REAL NOT NULL',
    'paid_at TEXT NOT NULL',
    'note TEXT',
    'FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE',
  ]);
  await _createTable(db, 'activity_logs', [
    'id INTEGER PRIMARY KEY AUTOINCREMENT',
    'message TEXT NOT NULL',
    'type TEXT NOT NULL',
    'timestamp TEXT NOT NULL',
    'user_id TEXT NOT NULL',
  ]);
  if (version >= 3) {
    await _createTable(db, 'sync_queue', [
      'id INTEGER PRIMARY KEY AUTOINCREMENT',
      'operation TEXT NOT NULL',
      'collection TEXT NOT NULL',
      'user_id TEXT NOT NULL',
      'doc_id TEXT NOT NULL',
      'data TEXT NOT NULL',
      'created_at TEXT NOT NULL',
      if (version >= 8) 'attempt_count INTEGER NOT NULL DEFAULT 0',
      if (version >= 8) 'next_attempt_at TEXT',
      if (version >= 8) 'last_attempt_at TEXT',
      if (version >= 8) 'last_error TEXT',
      if (version >= 8) "status TEXT NOT NULL DEFAULT 'pending'",
      if (version >= 8) 'idempotency_key TEXT',
      if (version >= 8) 'updated_at TEXT',
    ]);
  }
  if (version >= 6) {
    await _createTable(db, 'resellers', [
      'id TEXT PRIMARY KEY',
      'name TEXT NOT NULL',
      'contact TEXT',
      'discount_percent REAL NOT NULL DEFAULT 0',
      'user_id TEXT NOT NULL',
      'created_at TEXT NOT NULL',
      'is_deleted INTEGER NOT NULL DEFAULT 0',
      if (version >= 10) 'deleted_at TEXT',
    ]);
    await _createTable(db, 'custom_orders', [
      'id TEXT PRIMARY KEY',
      'customer_name TEXT NOT NULL',
      'contact TEXT',
      'fragrance_specs TEXT NOT NULL',
      'agreed_price REAL NOT NULL',
      'deposit_paid REAL NOT NULL DEFAULT 0',
      'delivery_date TEXT NOT NULL',
      "status TEXT NOT NULL DEFAULT 'Pending'",
      'terms TEXT',
      'user_id TEXT NOT NULL',
      'created_at TEXT NOT NULL',
      'is_deleted INTEGER NOT NULL DEFAULT 0',
      if (version >= 10) 'deleted_at TEXT',
    ]);
  }
  if (version >= 10) {
    await _createTable(db, 'order_sequences', [
      'user_id TEXT PRIMARY KEY',
      'last_value INTEGER NOT NULL DEFAULT 0',
    ]);
  }

  await db.insert(
    'users',
    modernUser
        ? {
            'id': 'user-row-1',
            'firebase_uid': 'user-1',
            'username': 'admin',
            'name': 'Administrator',
            'email': 'admin@example.test',
            'role': 'Administrator',
            'account_status': 'active',
            'is_active': 1,
            'legacy_owner_key': null,
            'migration_state': 'mapped',
            'is_synced': 1,
            'created_at': '2026-01-01T00:00:00.000Z',
          }
        : {
            'id': 'user-row-1',
            'username': 'admin',
            'password': 'legacy-verifier',
            'name': 'Administrator',
            if (version >= 2) 'email': 'admin@example.test',
            'role': 'Administrator',
            if (version >= 2) 'is_synced': 1,
            'created_at': '2026-01-01T00:00:00.000Z',
          },
  );
  await db.insert('products', {
    'id': 'product-1',
    'name': 'Rose',
    'description': 'Floral',
    'category': 'Eau de Parfum',
    'price': 100,
    'stock_qty': 5,
    'min_stock_level': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
    if (version >= 4) 'is_deleted': 0,
    if (version >= 4) 'deleted_at': null,
  });
  await db.insert('orders', {
    'id': 'order-1',
    'order_id': 'KNZ-001',
    'customer_name': 'Customer',
    'total_amount': 100,
    'status': 'Pending',
    'order_date': '2026-01-01T00:00:00.000Z',
    'notes': 'Fixture',
    'user_id': 'user-1',
    if (version >= 4) 'is_deleted': 0,
    if (version >= 4) 'deleted_at': null,
    if (version >= 6) 'payment_method': 'cash',
    if (version >= 6) 'payment_reference': 'REF-1',
    if (version >= 6) 'is_reseller': 0,
    if (version >= 6) 'discount_percent': 0,
    if (version >= 6) 'discounted_total': null,
    if (version >= 6) 'order_type': 'regular',
    if (version >= 10) 'stock_deducted': 1,
    if (version >= 10) 'stock_released_on_delete': 0,
  });
  await db.insert('order_items', {
    'id': 'item-1',
    'order_id': 'order-1',
    'product_id': 'product-1',
    'product_name': 'Rose',
    'unit_price': 100,
    if (version >= 7) 'srp_price': 100,
    'quantity': 1,
  });
  await db.insert('debts', {
    'id': 'debt-1',
    'customer_name': 'Customer',
    'order_id': 'KNZ-001',
    'total_amount': 100,
    'amount_paid': 0,
    'created_at': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
    if (version >= 4) 'is_deleted': 0,
    if (version >= 4) 'deleted_at': null,
    if (version >= 6) 'interest_rate': 0,
    if (version >= 6) 'interest_type': 'none',
    if (version >= 6) 'interest_start_date': null,
  });
  await db.insert('activity_logs', {
    'message': 'Fixture created',
    'type': 'test',
    'timestamp': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
  });
  if (version >= 6) {
    await db.insert('resellers', {
      'id': 'reseller-1',
      'name': 'Partner',
      'discount_percent': 10,
      'user_id': 'user-1',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_deleted': 0,
      if (version >= 10) 'deleted_at': null,
    });
    await db.insert('custom_orders', {
      'id': 'custom-1',
      'customer_name': 'Customer',
      'fragrance_specs': 'Rose',
      'agreed_price': 500,
      'deposit_paid': 100,
      'delivery_date': '2026-02-01T00:00:00.000Z',
      'status': 'Cancelled',
      'user_id': 'user-1',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_deleted': 0,
      if (version >= 10) 'deleted_at': null,
    });
  }
}

Future<void> _createRecentFixture(
  Database db,
  int version, {
  bool duplicateDebt = false,
}) async {
  await DatabaseHelper.createSchemaForTesting(db);
  if (version == 11) {
    await db.execute('DROP INDEX idx_debts_user_order_id');
    await db.execute('DROP INDEX idx_custom_orders_user');
    await db.execute('DROP INDEX idx_custom_order_payments_order');
    await db.execute('DROP TABLE custom_order_payments');
    for (final table in [
      'products',
      'orders',
      'order_items',
      'debts',
      'payments',
      'resellers',
      'custom_orders',
    ]) {
      await db.execute('ALTER TABLE $table DROP COLUMN schema_version');
    }
    await db.execute(
      'ALTER TABLE orders DROP COLUMN customer_pay_amount_centavos',
    );
    await db.execute('DROP INDEX idx_logs_user');
    await db.execute('''
      CREATE TABLE activity_logs_v11 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        user_id TEXT NOT NULL
      )
    ''');
    await db.execute('DROP TABLE activity_logs');
    await db.execute('ALTER TABLE activity_logs_v11 RENAME TO activity_logs');
  }
  await db.insert('products', {
    'id': 'product-1',
    'name': 'Rose',
    'description': 'Floral',
    'category': 'Eau de Parfum',
    'price_centavos': 10000,
    'stock_qty': 5,
    'min_stock_level': 1,
    'created_at': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
  });
  await db.insert('orders', {
    'id': 'order-1',
    'order_id': 'KNZ-001',
    'customer_name': 'Customer',
    'total_amount_centavos': 10000,
    'srp_total_centavos': 10000,
    if (version == 12) 'customer_pay_amount_centavos': 10000,
    'status': 'Pending',
    'order_date': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
  });
  await db.insert('order_items', {
    'id': 'item-1',
    'order_id': 'order-1',
    'product_id': 'product-1',
    'product_name': 'Rose',
    'unit_price_centavos': 10000,
    'srp_price_centavos': 10000,
    'quantity': 1,
  });
  await db.insert('debts', {
    'id': 'debt-1',
    'customer_name': 'Customer',
    'order_id': 'KNZ-001',
    'principal_original_centavos': 10000,
    'principal_outstanding_centavos': 10000,
    'interest_outstanding_centavos': 0,
    'created_at': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
    'interest_rate_basis_points': 0,
    'interest_type': 'none',
    'interest_start_timestamp': '2026-01-01T00:00:00.000Z',
    'last_accrual_timestamp': '2026-01-01T00:00:00.000Z',
    'status': 'open',
  });
  if (duplicateDebt) {
    await db.insert('debts', {
      'id': 'debt-2',
      'customer_name': 'Customer',
      'order_id': 'KNZ-001',
      'principal_original_centavos': 5000,
      'principal_outstanding_centavos': 5000,
      'interest_outstanding_centavos': 0,
      'created_at': '2026-01-02T00:00:00.000Z',
      'user_id': 'user-1',
      'interest_rate_basis_points': 0,
      'interest_type': 'none',
      'interest_start_timestamp': '2026-01-02T00:00:00.000Z',
      'last_accrual_timestamp': '2026-01-02T00:00:00.000Z',
      'status': 'open',
    });
  }
  await db.insert('resellers', {
    'id': 'reseller-1',
    'name': 'Partner',
    'deduction_per_item_centavos': 1000,
    'user_id': 'user-1',
    'created_at': '2026-01-01T00:00:00.000Z',
  });
  await db.insert('custom_orders', {
    'id': 'custom-1',
    'customer_name': 'Customer',
    'fragrance_specs': 'Rose',
    'agreed_price_centavos': 50000,
    'deposit_paid_centavos': 10000,
    'delivery_date': '2026-02-01T00:00:00.000Z',
    'status': 'Cancelled',
    'user_id': 'user-1',
    'created_at': '2026-01-01T00:00:00.000Z',
  });
  await db.insert('activity_logs', {
    if (version == 12) 'id': 'log-1',
    'message': 'Fixture created',
    'type': 'test',
    'timestamp': '2026-01-01T00:00:00.000Z',
    'user_id': 'user-1',
  });
}

Future<void> _createTable(Database db, String name, List<String> columns) =>
    db.execute('CREATE TABLE $name (${columns.join(', ')})');

Future<Set<String>> _columns(Database db, String table) async =>
    (await db.rawQuery(
      'PRAGMA table_info($table)',
    )).map((row) => row['name'] as String).toSet();

Future<bool> _tableExists(Database db, String table) async => (await db.query(
  'sqlite_master',
  columns: const ['name'],
  where: 'type = ? AND name = ?',
  whereArgs: ['table', table],
)).isNotEmpty;

Future<void> _expectCompleteSchema(Database db) async {
  for (final entry in {
    'orders': {'customer_pay_amount_centavos', 'schema_version'},
    'debts': {
      'principal_original_centavos',
      'interest_outstanding_centavos',
      'last_accrual_timestamp',
      'schema_version',
    },
    'payments': {
      'interest_applied_centavos',
      'principal_applied_centavos',
      'schema_version',
    },
    'resellers': {'deleted_at', 'schema_version'},
    'custom_orders': {'deleted_at', 'schema_version'},
    'custom_order_payments': {
      'custom_order_id',
      'amount_centavos',
      'schema_version',
    },
  }.entries) {
    expect(await _columns(db, entry.key), containsAll(entry.value));
  }
  expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  for (final entry in {
    'order_items': ['orders', 'order_id'],
    'payments': ['debts', 'debt_id'],
    'custom_order_payments': ['custom_orders', 'custom_order_id'],
  }.entries) {
    final foreignKeys = await db.rawQuery(
      'PRAGMA foreign_key_list(${entry.key})',
    );
    expect(
      foreignKeys,
      contains(
        predicate<Map<String, Object?>>(
          (row) =>
              row['table'] == entry.value[0] &&
              row['from'] == entry.value[1] &&
              row['on_delete'] == 'CASCADE',
        ),
      ),
    );
  }
  final orderIndexes = await db.rawQuery('PRAGMA index_list(orders)');
  expect(
    orderIndexes,
    contains(
      predicate<Map<String, Object?>>(
        (row) =>
            row['name'] == 'idx_orders_user_order_id' && row['unique'] == 1,
      ),
    ),
  );
  final debtIndexes = await db.rawQuery('PRAGMA index_list(debts)');
  expect(
    debtIndexes,
    contains(
      predicate<Map<String, Object?>>(
        (row) => row['name'] == 'idx_debts_user_order_id' && row['unique'] == 1,
      ),
    ),
  );
  final queueColumns = await db.rawQuery('PRAGMA table_info(sync_queue)');
  for (final column in const ['idempotency_key', 'updated_at', 'status']) {
    expect(
      queueColumns.singleWhere((row) => row['name'] == column)['notnull'],
      1,
    );
  }
  final queueIndexes = await db.rawQuery('PRAGMA index_list(sync_queue)');
  expect(
    queueIndexes,
    contains(
      predicate<Map<String, Object?>>(
        (row) =>
            row['name'] == 'idx_sync_queue_idempotency' && row['unique'] == 1,
      ),
    ),
  );
}
