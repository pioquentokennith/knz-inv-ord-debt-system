// stub_product_repository.dart — In-memory stub for ProductRepository
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/repositories/product_repository.dart';

class StubProductRepository implements ProductRepository {
  final Map<String, Product> store   = {};
  final Map<String, Product> deleted = {};

  @override Future<List<Product>> getAll(String userId) async => store.values.toList();
  @override Future<void> add(Product product, String userId) async { store[product.id] = product; }
  @override Future<void> update(Product product) async { if (store.containsKey(product.id)) store[product.id] = product; }
  @override Future<void> updateStock(String productId, int newQty) async {
    final p = store[productId];
    if (p != null) store[productId] = p.copyWith(stockQty: newQty);
  }
  @override Future<void> delete(String productId) async {
    final p = store.remove(productId);
    if (p != null) deleted[productId] = p;
  }
  @override Future<List<Product>> getDeleted(String userId) async => deleted.values.toList();
  @override Future<void> restore(String productId) async {
    final p = deleted.remove(productId);
    if (p != null) store[productId] = p;
  }
  @override Future<void> hardDelete(String productId) async {
    store.remove(productId);
    deleted.remove(productId);
  }

  void seed(Product product) => store[product.id] = product;
  void clear() { store.clear(); deleted.clear(); }
  int get count        => store.length;
  int get deletedCount => deleted.length;
}
