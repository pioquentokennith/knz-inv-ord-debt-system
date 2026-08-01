// ─────────────────────────────────────────────────────────────────────────────
// local_product_repository.dart — SQLite-backed product repository
// Purpose : Manages product CRUD against the local SQLite 'products' table
//           with automatic Firestore sync via SyncQueue (offline-first).
// Changes:
//   • getAll()     — filters WHERE is_deleted = 0 (active only)
//   • delete()     — soft-delete: sets is_deleted=1, deleted_at=now
//   • getDeleted() — returns all soft-deleted products (Recycle Bin)
//   • restore()    — un-deletes a product (is_deleted=0, deleted_at=NULL)
//   • hardDelete() — permanently removes a product (admin purge only)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/product_model.dart';
import '../dto/product_dto.dart';
import 'base_repository.dart';
import 'product_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

// Concrete SQLite + Firestore implementation of ProductRepository
class LocalProductRepository extends BaseRepository
    implements ProductRepository {
  LocalProductRepository({
    Future<Database> Function()? databaseProvider,
    SyncOutbox? queue,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _queue = queue ?? SyncQueue.instance;

  final Future<Database> Function() _databaseProvider;
  final _cloud = FirestoreSync.instance; // Firestore adapter for cloud sync
  final SyncOutbox _queue;

  // Returns all active (non-deleted) products for a user, newest first
  @override
  Future<List<Product>> getAll(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    // Only fetch rows where is_deleted = 0 (soft-deleted rows are excluded)
    final maps = await database.query(
      'products',
      where: 'user_id = ? AND is_deleted = 0',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );

    final partitionRows = await database.query(
      'products',
      columns: const ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    // Restore both active records and tombstones only into an empty partition.
    if (partitionRows.isEmpty && _queue.isOnline) {
      final cloud = await _cloud.getProducts(userId);
      await database.transaction((txn) async {
        for (final p in cloud) {
          final dto = ProductDto.fromCloud(p, userId: userId);
          // Avoid inserting duplicates if a partial sync already ran
          final exists = await txn.query(
            'products',
            where: 'id = ?',
            whereArgs: [dto.id],
          );
          if (exists.isNotEmpty) continue;
          await txn.insert('products', dto.toLocal());
        }
      });
      // Re-query after caching cloud products
      final restored = await database.query(
        'products',
        where: 'user_id = ? AND is_deleted = 0',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
      );
      return restored
          .map((row) => ProductDto.fromLocal(row).toDomain())
          .toList();
    }

    return maps.map((row) => ProductDto.fromLocal(row).toDomain()).toList();
  });

  // Returns all soft-deleted products for the Recycle Bin screen
  @override
  Future<List<Product>> getDeleted(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    // Only fetch rows where is_deleted = 1
    final maps = await database.query(
      'products',
      where: 'user_id = ? AND is_deleted = 1',
      whereArgs: [userId],
      orderBy: 'deleted_at DESC',
    ); // Most recently deleted appears first
    return maps.map((row) => ProductDto.fromLocal(row).toDomain()).toList();
  });

  // Restores a soft-deleted product back to the active list and re-syncs to Firestore
  @override
  Future<void> restore(String productId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [productId],
      );
      if (rows.isEmpty) {
        throw StateError('Deleted product $productId was not found.');
      }
      final data = Map<String, dynamic>.from(rows.first)
        ..['is_deleted'] = 0
        ..['deleted_at'] = null;
      final dto = ProductDto.fromLocal(data);
      final changed = await txn.update(
        'products',
        {'is_deleted': 0, 'deleted_at': null},
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [productId],
      );
      if (changed != 1) {
        throw StateError('Product $productId was not restored.');
      }
      await _queue.enqueue(
        operation: 'save_product',
        collection: 'products',
        userId: data['user_id'] as String,
        docId: productId,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  // Inserts a new product into SQLite and syncs to Firestore
  @override
  Future<void> add(Product product, String userId) => safeVoidCall(() async {
    if (userId.isEmpty) throw ArgumentError('User id is required.');
    _validateProduct(product);
    final database = await _databaseProvider();
    final dto = ProductDto.fromDomain(product, userId: userId);
    final data = dto.toLocal();
    await database.transaction((txn) async {
      final inserted = await txn.insert('products', data);
      if (inserted <= 0) throw StateError('Product was not inserted.');
      await _queue.enqueue(
        operation: 'save_product',
        collection: 'products',
        userId: userId,
        docId: product.id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  // Updates all fields of an existing product in SQLite and Firestore
  @override
  Future<void> update(Product product) => safeVoidCall(() async {
    _validateProduct(product);
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [product.id],
      );
      if (rows.isEmpty) {
        throw StateError('Product ${product.id} was not found.');
      }
      final userId = rows.first['user_id'] as String;
      final dto = ProductDto.fromDomain(product, userId: userId);
      final data = dto.toLocal();
      final changed = await txn.update(
        'products',
        data,
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [product.id],
      );
      if (changed != 1) {
        throw StateError('Product ${product.id} was not updated.');
      }
      await _queue.enqueue(
        operation: 'save_product',
        collection: 'products',
        userId: userId,
        docId: product.id,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  // Updates only the stock_qty column for a single product (called after order creation)
  @override
  Future<void> updateStock(String productId, int newQty) => safeVoidCall(
    () async {
      if (newQty < 0) throw ArgumentError.value(newQty, 'newQty');
      final database = await _databaseProvider();
      await database.transaction((txn) async {
        final rows = await txn.query(
          'products',
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [productId],
        );
        if (rows.isEmpty) throw StateError('Product $productId was not found.');
        final changed = await txn.update(
          'products',
          {'stock_qty': newQty},
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [productId],
        );
        if (changed != 1) {
          throw StateError('Stock for $productId was not updated.');
        }
        final data = Map<String, dynamic>.from(rows.first)
          ..['stock_qty'] = newQty;
        final dto = ProductDto.fromLocal(data);
        await _queue.enqueue(
          operation: 'save_product',
          collection: 'products',
          userId: data['user_id'] as String,
          docId: productId,
          data: dto.toCloud(),
          executor: txn,
        );
      });
      _queue.requestSync();
    },
  );

  // Soft-deletes a product: sets is_deleted=1 and records deleted_at timestamp
  @override
  Future<void> delete(String productId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [productId],
      );
      if (rows.isEmpty) throw StateError('Product $productId was not found.');
      final tombstone = Map<String, dynamic>.from(rows.first)
        ..['is_deleted'] = 1
        ..['deleted_at'] = now;
      final dto = ProductDto.fromLocal(tombstone);
      final changed = await txn.update(
        'products',
        {'is_deleted': 1, 'deleted_at': now},
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [productId],
      );
      if (changed != 1) throw StateError('Product $productId was not deleted.');
      await _queue.enqueue(
        operation: 'soft_delete_product',
        collection: 'products',
        userId: rows.first['user_id'] as String,
        docId: productId,
        data: dto.toCloud(),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  // Permanently removes a product from SQLite and Firestore — no recovery possible
  @override
  Future<void> hardDelete(String productId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [productId],
      );
      if (rows.isEmpty) {
        throw StateError('Deleted product $productId was not found.');
      }
      final changed = await txn.delete(
        'products',
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [productId],
      );
      if (changed != 1) {
        throw StateError('Product $productId was not permanently deleted.');
      }
      await _queue.enqueue(
        operation: 'delete_product',
        collection: 'products',
        userId: rows.first['user_id'] as String,
        docId: productId,
        data: {'id': productId},
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  // Converts a Product model into a SQLite-compatible column map
  void _validateProduct(Product product) {
    if (product.id.isEmpty) throw ArgumentError('Product id is required.');
    if (product.price.isNegative) {
      throw ArgumentError.value(product.price, 'product.price');
    }
    if (product.stockQty < 0) {
      throw ArgumentError.value(product.stockQty, 'product.stockQty');
    }
    if (product.minStockLevel < 0) {
      throw ArgumentError.value(product.minStockLevel, 'product.minStockLevel');
    }
  }
}
