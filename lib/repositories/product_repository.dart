import '../models/product_model.dart';

abstract class ProductRepository {
  Future<List<Product>> getAll(String userId);
  Future<void> add(Product product, String userId);
  Future<void> update(Product product);
  Future<void> updateStock(String productId, int newQty);
  Future<void> delete(String productId);

  // Recycle-bin operations
  Future<List<Product>> getDeleted(String userId);
  Future<void> restore(String productId);
  Future<void> hardDelete(String productId);
}
