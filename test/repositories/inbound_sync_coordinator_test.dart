import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/repositories/inbound_sync_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _product({
  String id = 'product-1',
  int stock = 5,
  int revision = 1,
}) => {
  'id': id,
  'name': 'Rose',
  'description': '',
  'category': 'Eau de Parfum',
  'price_centavos': 10000,
  'stock_qty': stock,
  'min_stock_level': 1,
  'image_path': null,
  'created_at': DateTime.utc(2026).toIso8601String(),
  'user_id': 'user-1',
  'is_deleted': 0,
  'deleted_at': null,
  'schema_version': 1,
  'revision': revision,
  'base_revision': revision - 1,
  'updated_at': DateTime.utc(2026, 1, revision + 1).toIso8601String(),
  'writer_device_id': 'REMOTE01',
};

Future<List<List<Map<String, dynamic>>>> _snapshot({
  List<Map<String, dynamic>> products = const [],
  List<Map<String, dynamic>> events = const [],
}) async => [
  products,
  const [],
  const [],
  const [],
  const [],
  events,
  const [],
];

void main() {
  sqfliteFfiInit();
  late Database database;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(database);
  });

  tearDown(() => database.close());

  test('newer clean remote revision replaces the local entity', () async {
    await database.insert('products', _product(stock: 2, revision: 1));
    final coordinator = InboundSyncCoordinator(
      databaseProvider: () async => database,
      remoteLoader: (_) =>
          _snapshot(products: [_product(stock: 8, revision: 2)]),
    );

    final result = await coordinator.reconcile('user-1');

    expect(result.appliedCount, 1);
    final row = (await database.query('products')).single;
    expect(row['stock_qty'], 8);
    expect(row['revision'], 2);
  });

  test('newer remote revision preserves the device-local image path', () async {
    final local = _product(stock: 2, revision: 1)
      ..['image_path'] = 'C:/device/rose.jpg';
    await database.insert('products', local);
    final remote = _product(stock: 8, revision: 2)..['image_path'] = null;
    final coordinator = InboundSyncCoordinator(
      databaseProvider: () async => database,
      remoteLoader: (_) => _snapshot(products: [remote]),
    );

    await coordinator.reconcile('user-1');

    final row = (await database.query('products')).single;
    expect(row['stock_qty'], 8);
    expect(row['image_path'], 'C:/device/rose.jpg');
  });

  test(
    'pending local aggregate is preserved and remote change conflicts',
    () async {
      await database.insert('products', _product(stock: 2, revision: 1));
      final now = DateTime.utc(2026).toIso8601String();
      await database.insert('sync_queue', {
        'operation': 'save_product',
        'collection': 'products',
        'user_id': 'user-1',
        'doc_id': 'product-1',
        'data': jsonEncode(_product(stock: 3, revision: 2)),
        'created_at': now,
        'status': 'pending',
        'idempotency_key': 'local-change',
        'updated_at': now,
        'aggregate_key': 'products:product-1',
        'expected_revision': 1,
        'resulting_revision': 2,
      });
      final coordinator = InboundSyncCoordinator(
        databaseProvider: () async => database,
        remoteLoader: (_) =>
            _snapshot(products: [_product(stock: 9, revision: 2)]),
      );

      final result = await coordinator.reconcile('user-1');

      expect(result.conflictCount, 1);
      expect((await database.query('products')).single['stock_qty'], 2);
      expect(await database.query('sync_conflicts'), hasLength(1));
    },
  );

  test(
    'malformed remote snapshot applies no earlier valid documents',
    () async {
      final coordinator = InboundSyncCoordinator(
        databaseProvider: () async => database,
        remoteLoader: (_) => _snapshot(
          products: [
            _product(),
            {..._product(id: 'bad'), 'stock_qty': -1},
          ],
        ),
      );

      await expectLater(
        coordinator.reconcile('user-1'),
        throwsA(isA<FormatException>()),
      );

      expect(await database.query('products'), isEmpty);
      expect(await database.query('sync_cursors'), isEmpty);
    },
  );
}
