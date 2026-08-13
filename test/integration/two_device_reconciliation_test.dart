import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/repositories/inbound_sync_coordinator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> _product({
  required int stock,
  required int revision,
  required String device,
}) => {
  'id': 'product-1',
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
  'base_revision': revision == 0 ? 0 : revision - 1,
  'updated_at': DateTime.utc(2026, 1, revision + 1).toIso8601String(),
  'writer_device_id': device,
};

Future<List<List<Map<String, dynamic>>>> _snapshot(
  Map<String, dynamic> product,
) async => [
  [product],
  const [],
  const [],
  const [],
  const [],
  const [],
  const [],
];

void main() {
  sqfliteFfiInit();

  test(
    'two independent devices converge and preserve divergent local work',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'knz-two-device-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final deviceA = await databaseFactoryFfi.openDatabase(
        '${directory.path}${Platform.pathSeparator}device-a.db',
      );
      final deviceB = await databaseFactoryFfi.openDatabase(
        '${directory.path}${Platform.pathSeparator}device-b.db',
      );
      addTearDown(deviceA.close);
      addTearDown(deviceB.close);
      await DatabaseHelper.createSchemaForTesting(deviceA);
      await DatabaseHelper.createSchemaForTesting(deviceB);

      final remoteRevisionOne = _product(
        stock: 10,
        revision: 1,
        device: 'DEVICE-A',
      );
      final coordinatorA = InboundSyncCoordinator(
        databaseProvider: () async => deviceA,
        remoteLoader: (_) => _snapshot(remoteRevisionOne),
      );
      final coordinatorB = InboundSyncCoordinator(
        databaseProvider: () async => deviceB,
        remoteLoader: (_) => _snapshot(remoteRevisionOne),
      );
      await coordinatorA.reconcile('user-1');
      await coordinatorB.reconcile('user-1');
      expect((await deviceA.query('products')).single['stock_qty'], 10);
      expect((await deviceB.query('products')).single['stock_qty'], 10);

      final now = DateTime.utc(2026, 1, 3).toIso8601String();
      await deviceB.update(
        'products',
        {'stock_qty': 8},
        where: 'id = ? AND user_id = ?',
        whereArgs: ['product-1', 'user-1'],
      );
      await deviceB.insert('sync_queue', {
        'operation': 'save_product',
        'collection': 'products',
        'user_id': 'user-1',
        'doc_id': 'product-1',
        'data': '{}',
        'created_at': now,
        'status': 'pending',
        'idempotency_key': 'device-b-edit',
        'updated_at': now,
        'aggregate_key': 'products:product-1',
        'expected_revision': 1,
        'resulting_revision': 2,
      });

      final remoteRevisionTwo = _product(
        stock: 9,
        revision: 2,
        device: 'DEVICE-A',
      );
      final changedA = InboundSyncCoordinator(
        databaseProvider: () async => deviceA,
        remoteLoader: (_) => _snapshot(remoteRevisionTwo),
      );
      final conflictedB = InboundSyncCoordinator(
        databaseProvider: () async => deviceB,
        remoteLoader: (_) => _snapshot(remoteRevisionTwo),
      );

      expect((await changedA.reconcile('user-1')).appliedCount, 1);
      expect((await conflictedB.reconcile('user-1')).conflictCount, 1);
      expect((await deviceA.query('products')).single['stock_qty'], 9);
      expect((await deviceB.query('products')).single['stock_qty'], 8);
      expect(await deviceB.query('sync_conflicts'), hasLength(1));
      expect(await deviceB.query('sync_queue'), hasLength(1));
    },
  );
}
