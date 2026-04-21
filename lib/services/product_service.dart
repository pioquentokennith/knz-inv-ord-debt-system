// ─────────────────────────────────────────────────────────────────────────────
// product_service.dart — Product business logic
// Purpose : Validates product data and enforces business rules before
//           delegating storage operations to ProductRepository.
//           Keeps all product business rules in one testable class.
// Interface + Implementation (Abstraction + Polymorphism)
// AppState depends on IProductService — not ProductService directly — so
// tests can inject a stub without touching SQLite.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:uuid/uuid.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Abstract contract for product business logic (Abstraction).
/// AppState and tests program to this interface, not to the concrete class.
abstract class IProductService {
  // Returns all active products for the given user
  Future<List<Product>> getAll(String userId);

  // Validates fields, generates a UUID, and persists a new product
  // Returns null on success; returns an error message string on validation failure
  Future<String?> addProduct({
    required String          userId,
    required String          name,
    required String          description,
    required ProductCategory category,
    required double          price,
    required int             stockQty,
    required int             minStockLevel,
    String?                  imagePath,
  });

  // Updates all fields of an existing product
  Future<void>    updateProduct(Product product);

  // Validates that newQty >= 0 then updates just the stock column
  // Returns null on success; returns an error message string on failure
  Future<String?> updateStock(String productId, int newQty);

  // Soft-deletes a product (moves to Recycle Bin)
  Future<void>    deleteProduct(String productId);

  // ── Recycle Bin operations ────────────────────────────────────────────────
  Future<List<Product>> getDeleted(String userId);  // Returns soft-deleted products
  Future<void>          restoreProduct(String productId); // Un-deletes a product
  Future<void>          hardDeleteProduct(String productId); // Permanent purge
}

/// Concrete implementation — all business logic for products.
class ProductService implements IProductService {
  final ProductRepository _repo; // Depends on abstract interface (DIP)
  final _uuid = const Uuid();    // UUID generator for new product IDs

  ProductService(this._repo);

  // Delegates directly to repo — no business logic needed for a simple fetch
  @override
  Future<List<Product>> getAll(String userId) => _repo.getAll(userId);

  // Validates all fields before creating and persisting a new Product instance
  @override
  Future<String?> addProduct({
    required String          userId,
    required String          name,
    required String          description,
    required ProductCategory category,
    required double          price,
    required int             stockQty,
    required int             minStockLevel,
    String?                  imagePath,
  }) async {
    // Validate each business rule and return the first error found
    if (name.trim().isEmpty)   return 'Product name is required';
    if (price < 0)             return 'Price cannot be negative';
    if (stockQty < 0)          return 'Stock cannot be negative';
    if (minStockLevel < 0)     return 'Min stock level cannot be negative';

    // All validations passed — create the model and hand off to the repository
    await _repo.add(
      Product(
        id:            _uuid.v4(),  // Generate a unique ID for the new product
        name:          name.trim(),
        description:   description.trim(),
        category:      category,
        price:         price,
        stockQty:      stockQty,
        minStockLevel: minStockLevel,
        imagePath:     imagePath,
      ),
      userId,
    );
    return null; // null = success
  }

  // No additional business logic — delegates directly to repo
  @override
  Future<void> updateProduct(Product product) => _repo.update(product);

  // Guards against setting negative stock (business rule) before updating
  @override
  Future<String?> updateStock(String productId, int newQty) async {
    if (newQty < 0) return 'Stock cannot be negative';
    await _repo.updateStock(productId, newQty);
    return null; // null = success
  }

  // Delegates soft-delete to the repository
  @override
  Future<void> deleteProduct(String productId) => _repo.delete(productId);

  // Delegates Recycle Bin operations to the repository
  @override
  Future<List<Product>> getDeleted(String userId) => _repo.getDeleted(userId);

  @override
  Future<void> restoreProduct(String productId) => _repo.restore(productId);

  @override
  Future<void> hardDeleteProduct(String productId) => _repo.hardDelete(productId);
}
