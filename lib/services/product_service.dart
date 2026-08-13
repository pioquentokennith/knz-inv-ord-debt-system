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
import '../core/money.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Abstract contract for product business logic (Abstraction).
/// AppState and tests program to this interface, not to the concrete class.
abstract class IProductService {
  // Returns all active products for the given user
  Future<List<Product>> getAll(String userId);

  // Validates fields, generates a UUID, and persists a new product
  Future<void> addProduct({
    required String userId,
    required String name,
    required String description,
    required ProductCategory category,
    required Money price,
    required int stockQty,
    required int minStockLevel,
    String? imagePath,
  });

  // Updates all fields of an existing product
  Future<void> updateProduct(Product product);

  // Validates that newQty >= 0 then updates just the stock column
  Future<void> updateStock(String productId, int newQty);

  // Soft-deletes a product (moves to Recycle Bin)
  Future<void> deleteProduct(String productId, String userId);

  // ── Recycle Bin operations ────────────────────────────────────────────────
  Future<List<Product>> getDeleted(
    String userId,
  ); // Returns soft-deleted products
  Future<void> restoreProduct(String productId, String userId);
  Future<void> hardDeleteProduct(String productId, String userId);
}

/// Concrete implementation — all business logic for products.
class ProductService implements IProductService {
  final ProductRepository _repo; // Depends on abstract interface (DIP)
  final _uuid = const Uuid(); // UUID generator for new product IDs

  ProductService(this._repo);

  // Delegates directly to repo — no business logic needed for a simple fetch
  @override
  Future<List<Product>> getAll(String userId) => _repo.getAll(userId);

  // Validates all fields before creating and persisting a new Product instance
  @override
  Future<void> addProduct({
    required String userId,
    required String name,
    required String description,
    required ProductCategory category,
    required Money price,
    required int stockQty,
    required int minStockLevel,
    String? imagePath,
  }) async {
    // Validate each business rule and return the first error found
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User ID is required');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Product name is required');
    }
    if (price.isNegative) {
      throw ArgumentError.value(price, 'price', 'Price must be non-negative');
    }
    if (stockQty < 0) {
      throw ArgumentError.value(
        stockQty,
        'stockQty',
        'Stock cannot be negative',
      );
    }
    if (minStockLevel < 0) {
      throw ArgumentError.value(
        minStockLevel,
        'minStockLevel',
        'Min stock level cannot be negative',
      );
    }

    // All validations passed — create the model and hand off to the repository
    await _repo.add(
      Product(
        id: _uuid.v4(), // Generate a unique ID for the new product
        name: name.trim(),
        description: description.trim(),
        category: category,
        price: price,
        stockQty: stockQty,
        minStockLevel: minStockLevel,
        imagePath: imagePath,
      ),
      userId.trim(),
    );
  }

  // No additional business logic — delegates directly to repo
  @override
  Future<void> updateProduct(Product product) => _repo.update(product);

  // Guards against setting negative stock (business rule) before updating
  @override
  Future<void> updateStock(String productId, int newQty) async {
    if (productId.trim().isEmpty) {
      throw ArgumentError.value(
        productId,
        'productId',
        'Product ID is required',
      );
    }
    if (newQty < 0) {
      throw ArgumentError.value(newQty, 'newQty', 'Stock cannot be negative');
    }
    await _repo.updateStock(productId, newQty);
  }

  // Delegates soft-delete to the repository
  @override
  Future<void> deleteProduct(String productId, String userId) {
    _requireProductId(productId);
    return _repo.delete(productId, userId);
  }

  // Delegates Recycle Bin operations to the repository
  @override
  Future<List<Product>> getDeleted(String userId) => _repo.getDeleted(userId);

  @override
  Future<void> restoreProduct(String productId, String userId) {
    _requireProductId(productId);
    return _repo.restore(productId, userId);
  }

  @override
  Future<void> hardDeleteProduct(String productId, String userId) {
    _requireProductId(productId);
    return _repo.hardDelete(productId, userId);
  }

  void _requireProductId(String productId) {
    if (productId.trim().isEmpty) {
      throw ArgumentError.value(
        productId,
        'productId',
        'Product id cannot be blank.',
      );
    }
  }
}
