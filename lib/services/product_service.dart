// ─────────────────────────────────────────────────────────────────────────────
// product_service.dart — Interface + Implementation (Abstraction + Polymorphism)
// IProductService defines the contract; ProductService implements it.
// AppState depends on the interface — not the concrete class (DIP).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:uuid/uuid.dart';
import '../models/product_model.dart';
import '../repositories/product_repository.dart';

/// Abstract contract for product business logic (Abstraction).
/// AppState and tests program to this interface — not to the concrete class.
abstract class IProductService {
  Future<List<Product>> getAll(String userId);
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
  Future<void>    updateProduct(Product product);
  Future<String?> updateStock(String productId, int newQty);
  Future<void>    deleteProduct(String productId);
}

/// Concrete implementation — all business logic for products.
/// Extends the abstract interface (Polymorphism via override).
class ProductService implements IProductService {
  final ProductRepository _repo;
  final _uuid = const Uuid();

  ProductService(this._repo);

  @override
  Future<List<Product>> getAll(String userId) => _repo.getAll(userId);

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
    if (name.trim().isEmpty)   return 'Product name is required';
    if (price < 0)             return 'Price cannot be negative';
    if (stockQty < 0)          return 'Stock cannot be negative';
    if (minStockLevel < 0)     return 'Min stock level cannot be negative';

    await _repo.add(
      Product(
        id:            _uuid.v4(),
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
    return null;
  }

  @override
  Future<void> updateProduct(Product product) => _repo.update(product);

  @override
  Future<String?> updateStock(String productId, int newQty) async {
    if (newQty < 0) return 'Stock cannot be negative';
    await _repo.updateStock(productId, newQty);
    return null;
  }

  @override
  Future<void> deleteProduct(String productId) => _repo.delete(productId);
}
