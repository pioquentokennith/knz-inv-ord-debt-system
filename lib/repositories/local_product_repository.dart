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

import '../models/product_model.dart';
import 'base_repository.dart';
import 'product_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

// Concrete SQLite + Firestore implementation of ProductRepository
class LocalProductRepository extends BaseRepository implements ProductRepository {
  final _cloud = FirestoreSync.instance; // Firestore adapter for cloud sync
  final _queue = SyncQueue.instance;     // Offline queue for deferred Firestore writes

  // Returns all active (non-deleted) products for a user, newest first
  @override
  Future<List<Product>> getAll(String userId) => safeCall(() async {
    final database = await db.database;
    // Only fetch rows where is_deleted = 0 (soft-deleted rows are excluded)
    final maps = await database.query('products',
        where: 'user_id = ? AND is_deleted = 0', whereArgs: [userId],
        orderBy: 'created_at DESC');

    // Local is empty and device is online — restore products from Firestore
    if (maps.isEmpty && _queue.isOnline) {
      final cloud = await _cloud.getProducts(userId);
      for (final p in cloud) {
        try {
          // Avoid inserting duplicates if a partial sync already ran
          final exists = await database.query('products',
              where: 'id = ?', whereArgs: [p['id']]);
          if (exists.isNotEmpty) continue;
          await database.insert('products', {
            'id':              p['id'],
            'name':            p['name'],
            'description':     p['description'] ?? '',
            'category':        p['category'],
            'price':           p['price'],
            'stock_qty':       p['stock_qty'],
            'min_stock_level': p['min_stock_level'],
            'image_path':      p['image_path'],
            'created_at':      p['created_at'],
            'user_id':         userId,
            'is_deleted':      0,
            'deleted_at':      null,
          });
        } catch (_) {}
      }
      // Re-query after caching cloud products
      final restored = await database.query('products',
          where: 'user_id = ? AND is_deleted = 0', whereArgs: [userId],
          orderBy: 'created_at DESC');
      return restored.map(_fromMap).toList();
    }

    return maps.map(_fromMap).toList();
  }, []);

  // Returns all soft-deleted products for the Recycle Bin screen
  @override
  Future<List<Product>> getDeleted(String userId) => safeCall(() async {
    final database = await db.database;
    // Only fetch rows where is_deleted = 1
    final maps = await database.query('products',
        where: 'user_id = ? AND is_deleted = 1', whereArgs: [userId],
        orderBy: 'deleted_at DESC'); // Most recently deleted appears first
    return maps.map(_fromMap).toList();
  }, []);

  // Restores a soft-deleted product back to the active list and re-syncs to Firestore
  @override
  Future<void> restore(String productId) => safeVoidCall(() async {
    final database = await db.database;
    // Clear the soft-delete flags to make the product active again
    await database.update(
      'products',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ?',
      whereArgs: [productId],
    );

    // Re-sync the restored product to Firestore so cloud reflects the un-delete
    final rows = await database.query('products',
        where: 'id = ?', whereArgs: [productId]);
    if (rows.isNotEmpty) {
      final userId = rows.first['user_id'] as String;
      final data = Map<String, dynamic>.from(rows.first);
      if (_queue.isOnline) {
        await _cloud.saveProduct(userId, data);
      } else {
        await _queue.enqueue(
          operation: 'save_product', collection: 'products',
          userId: userId, docId: productId, data: data,
        );
      }
    }
  });

  // Inserts a new product into SQLite and syncs to Firestore
  @override
  Future<void> add(Product product, String userId) => safeVoidCall(() async {
    final database = await db.database;
    final data = _toMap(product, userId);
    await database.insert('products', data);

    // Sync immediately if online; otherwise queue for later
    if (_queue.isOnline) {
      await _cloud.saveProduct(userId, data);
    } else {
      await _queue.enqueue(
        operation: 'save_product', collection: 'products',
        userId: userId, docId: product.id, data: data,
      );
    }
  });

  // Updates all fields of an existing product in SQLite and Firestore
  @override
  Future<void> update(Product product) => safeVoidCall(() async {
    final database = await db.database;
    // Retrieve the userId from the existing row (not available on the model)
    final rows = await database.query('products',
        where: 'id = ?', whereArgs: [product.id]);
    final userId = rows.isNotEmpty ? rows.first['user_id'] as String : '';
    final data = _toMap(product, userId);

    await database.update('products', data,
        where: 'id = ?', whereArgs: [product.id]);

    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.saveProduct(userId, data);
      } else {
        await _queue.enqueue(
          operation: 'save_product', collection: 'products',
          userId: userId, docId: product.id, data: data,
        );
      }
    }
  });

  // Updates only the stock_qty column for a single product (called after order creation)
  @override
  Future<void> updateStock(String productId, int newQty) => safeVoidCall(() async {
    final database = await db.database;
    await database.update('products', {'stock_qty': newQty},
        where: 'id = ?', whereArgs: [productId]);

    // Fetch the full row so we can sync the complete product data to Firestore
    final rows = await database.query('products',
        where: 'id = ?', whereArgs: [productId]);
    if (rows.isNotEmpty) {
      final userId = rows.first['user_id'] as String;
      final data = Map<String, dynamic>.from(rows.first);
      data['stock_qty'] = newQty; // Ensure updated value is in sync payload

      if (_queue.isOnline) {
        await _cloud.saveProduct(userId, data);
      } else {
        await _queue.enqueue(
          operation: 'save_product', collection: 'products',
          userId: userId, docId: productId, data: data,
        );
      }
    }
  });

  // Soft-deletes a product: sets is_deleted=1 and records deleted_at timestamp
  @override
  Future<void> delete(String productId) => safeVoidCall(() async {
    final database = await db.database;
    final rows = await database.query('products',
        where: 'id = ?', whereArgs: [productId]);
    final userId = rows.isNotEmpty ? rows.first['user_id'] as String : '';
    final now = DateTime.now().toIso8601String();

    // Mark as deleted — data is preserved for Recycle Bin recovery
    await database.update(
      'products',
      {'is_deleted': 1, 'deleted_at': now},
      where: 'id = ?',
      whereArgs: [productId],
    );

    // Sync the soft-delete flag to Firestore
    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.softDeleteProduct(userId, productId, now);
      } else {
        await _queue.enqueue(
          operation: 'soft_delete_product', collection: 'products',
          userId: userId, docId: productId,
          data: {'id': productId, 'is_deleted': 1, 'deleted_at': now},
        );
      }
    }
  });

  // Permanently removes a product from SQLite and Firestore — no recovery possible
  @override
  Future<void> hardDelete(String productId) => safeVoidCall(() async {
    final database = await db.database;
    final rows = await database.query('products',
        where: 'id = ?', whereArgs: [productId]);
    final userId = rows.isNotEmpty ? rows.first['user_id'] as String : '';

    await database.delete('products', where: 'id = ?', whereArgs: [productId]);

    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.deleteProduct(userId, productId);
      } else {
        await _queue.enqueue(
          operation: 'delete_product', collection: 'products',
          userId: userId, docId: productId, data: {'id': productId},
        );
      }
    }
  });

  // Converts a Product model into a SQLite-compatible column map
  Map<String, dynamic> _toMap(Product p, String? userId) {
    final m = <String, dynamic>{
      'id':              p.id,
      'name':            p.name,
      'description':     p.description,
      'category':        p.category.displayName, // Store display name string
      'price':           p.price,
      'stock_qty':       p.stockQty,
      'min_stock_level': p.minStockLevel,
      'image_path':      p.imagePath,
      'created_at':      p.createdAt.toIso8601String(),
      'is_deleted':      0,   // New products are always active
      'deleted_at':      null,
    };
    if (userId != null && userId.isNotEmpty) m['user_id'] = userId;
    return m;
  }

  // Converts a raw SQLite row map into a typed Product model instance
  Product _fromMap(Map<String, dynamic> m) => Product(
    id:            m['id']              as String,
    name:          m['name']            as String,
    description:   m['description']     as String? ?? '',
    category:      ProductCategoryExtension.fromString(m['category'] as String),
    price:         (m['price']          as num).toDouble(),
    stockQty:      m['stock_qty']       as int,
    minStockLevel: m['min_stock_level'] as int,
    imagePath:     m['image_path']      as String?,
    createdAt:     DateTime.parse(m['created_at'] as String),
  );
}
