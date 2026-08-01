import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/repositories/local_product_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Outbox implements SyncOutbox {
  var nextKey = 0;

  @override
  bool get isOnline => false;

  @override
  Future<int> enqueue({
    required String operation,
    required String collection,
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
    DatabaseExecutor? executor,
  }) {
    if (executor == null) throw StateError('Transaction required.');
    final now = DateTime.utc(2026).toIso8601String();
    return executor.insert('sync_queue', {
      'operation': operation,
      'collection': collection,
      'user_id': userId,
      'doc_id': docId,
      'data': jsonEncode(data),
      'created_at': now,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_attempt_at': null,
      'last_error': null,
      'status': 'pending',
      'idempotency_key': 'product-${nextKey++}',
      'updated_at': now,
    });
  }

  @override
  void requestSync() {}
}

Product _product({String name = 'Rose', int stock = 5}) => Product(
  id: 'product-1',
  name: name,
  description: 'Floral',
  category: ProductCategory.eauDeParfum,
  price: const Money.fromCentavos(12500),
  stockQty: stock,
  minStockLevel: 1,
  createdAt: DateTime.utc(2026),
);

void main() {
  sqfliteFfiInit();
  late Database database;
  late LocalProductRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(database);
    repository = LocalProductRepository(
      databaseProvider: () async => database,
      queue: _Outbox(),
    );
  });

  tearDown(() => database.close());

  test(
    'CRUD, stock, soft delete, restore, and hard delete remain owner-scoped',
    () async {
      await repository.add(_product(), 'owner-1');
      expect((await repository.getAll('owner-1')).single.name, 'Rose');
      expect(await repository.getAll('owner-2'), isEmpty);

      await repository.update(_product(name: 'Rose Oud'));
      await repository.updateStock('product-1', 3);
      expect((await repository.getAll('owner-1')).single.stockQty, 3);

      await repository.delete('product-1');
      expect(await repository.getAll('owner-1'), isEmpty);
      expect((await repository.getDeleted('owner-1')).single.name, 'Rose Oud');

      await repository.restore('product-1');
      expect(await repository.getAll('owner-1'), hasLength(1));
      await repository.delete('product-1');
      await repository.hardDelete('product-1');

      expect(await database.query('products'), isEmpty);
      expect(
        (await database.query('sync_queue')).map((row) => row['operation']),
        [
          'save_product',
          'save_product',
          'save_product',
          'soft_delete_product',
          'save_product',
          'soft_delete_product',
          'delete_product',
        ],
      );
    },
  );

  test('missing rows and invalid stock propagate failures', () async {
    await expectLater(
      repository.updateStock('missing', 1),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.updateStock('missing', -1),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      repository.restore('missing'),
      throwsA(isA<StateError>()),
    );
    expect(await database.query('sync_queue'), isEmpty);
  });
}
