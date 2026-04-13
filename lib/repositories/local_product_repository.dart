import '../models/product_model.dart';
import 'base_repository.dart';
import 'product_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class LocalProductRepository extends BaseRepository implements ProductRepository {
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  @override
  Future<List<Product>> getAll(String userId) => safeCall(() async {
    final database = await db.database;
    final maps = await database.query('products',
        where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'created_at DESC');

    // Kung walang local data at online, restore mula Firestore
    if (maps.isEmpty && _queue.isOnline) {
      final cloud = await _cloud.getProducts(userId);
      for (final p in cloud) {
        try {
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
          });
        } catch (_) {}
      }
      final restored = await database.query('products',
          where: 'user_id = ?', whereArgs: [userId],
          orderBy: 'created_at DESC');
      return restored.map(_fromMap).toList();
    }

    return maps.map(_fromMap).toList();
  }, []);

  @override
  Future<void> add(Product product, String userId) => safeVoidCall(() async {
    final database = await db.database;
    final data = _toMap(product, userId);
    await database.insert('products', data);

    if (_queue.isOnline) {
      await _cloud.saveProduct(userId, data);
    } else {
      await _queue.enqueue(
        operation: 'save_product', collection: 'products',
        userId: userId, docId: product.id, data: data,
      );
    }
  });

  @override
  Future<void> update(Product product) => safeVoidCall(() async {
    final database = await db.database;
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

  @override
  Future<void> updateStock(String productId, int newQty) => safeVoidCall(() async {
    final database = await db.database;

    // 1. Update SQLite first
    await database.update('products', {'stock_qty': newQty},
        where: 'id = ?', whereArgs: [productId]);

    // 2. Fetch the updated row to build the full cloud payload
    final rows = await database.query('products',
        where: 'id = ?', whereArgs: [productId]);

    if (rows.isNotEmpty) {
      final userId = rows.first['user_id'] as String;

      // ── FIX 3: ..[] cascade on Map does NOT mutate — it returns void.
      // The old code sent the OLD stock_qty to Firestore.
      // Correct approach: build a new map with the updated value.
      final data = Map<String, dynamic>.from(rows.first); // copy from DB
      data['stock_qty'] = newQty; // ← FIX 3: explicit assignment, always correct

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

  @override
  Future<void> delete(String productId) => safeVoidCall(() async {
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

  Map<String, dynamic> _toMap(Product p, String? userId) {
    final m = <String, dynamic>{
      'id':              p.id,
      'name':            p.name,
      'description':     p.description,
      'category':        p.category.displayName,
      'price':           p.price,
      'stock_qty':       p.stockQty,
      'min_stock_level': p.minStockLevel,
      'image_path':      p.imagePath,
      'created_at':      p.createdAt.toIso8601String(),
    };
    if (userId != null && userId.isNotEmpty) m['user_id'] = userId;
    return m;
  }

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
