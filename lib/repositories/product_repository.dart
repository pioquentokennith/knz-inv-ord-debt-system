// ─────────────────────────────────────────────────────────────────────────────
// product_repository.dart — Abstract ProductRepository interface
// Purpose : Defines the data-access contract for products.
//           Concrete implementations (LocalProductRepository) fulfill this
//           contract; services depend only on this interface (DIP).
// ─────────────────────────────────────────────────────────────────────────────

import '../models/product_model.dart';

abstract class ProductRepository {
  // Returns all active (non-deleted) products for a given user
  Future<List<Product>> getAll(String userId);

  // Persists a new product to storage
  Future<void> add(Product product, String userId);

  // Updates all fields of an existing product
  Future<void> update(Product product);

  // Updates only the stock quantity (used after order creation)
  Future<void> updateStock(String productId, int newQty);

  // Soft-deletes a product (moves to Recycle Bin; not permanently removed)
  Future<void> delete(String productId);

  // ── Recycle Bin operations ────────────────────────────────────────────────

  // Returns all soft-deleted products for the Recycle Bin screen
  Future<List<Product>> getDeleted(String userId);

  // Restores a soft-deleted product back to the active list
  Future<void> restore(String productId);

  // Permanently removes a product from storage (admin-only purge)
  Future<void> hardDelete(String productId);
}
