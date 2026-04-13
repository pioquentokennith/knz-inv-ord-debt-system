// ─────────────────────────────────────────────────────────────────────────────
// order_service.dart — Interface + Implementation (Abstraction + Polymorphism)
// IOrderService defines the contract; OrderService implements it.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/order_model.dart';
import '../models/product_model.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';

/// Abstract contract for order business logic (Abstraction).
abstract class IOrderService {
  Future<List<Order>> getAll(String userId);
  Future<String>      generateOrderId(String userId);
  Future<void>        createOrder(Order order, String userId, List<Product> products);
  Future<void>        updateStatus(String orderId, OrderStatus status);
  Future<void>        deleteOrder(String orderId);
}

/// Concrete implementation — all business logic for orders.
class OrderService implements IOrderService {
  final OrderRepository   _orderRepo;
  final ProductRepository _productRepo;

  OrderService(this._orderRepo, this._productRepo);

  @override
  Future<List<Order>> getAll(String userId) => _orderRepo.getAll(userId);

  @override
  Future<String> generateOrderId(String userId) async {
    final num = await _orderRepo.getNextOrderNumber(userId);
    return 'KNZ-${num.toString().padLeft(3, '0')}';
  }

  /// Creates an order and auto-deducts stock for each item (Encapsulation of business rule).
  @override
  Future<void> createOrder(Order order, String userId, List<Product> products) async {
    await _orderRepo.add(order, userId);
    for (final item in order.items) {
      try {
        final product = products.firstWhere(
          (p) => p.id == item.productId ||
                 p.name.toLowerCase() == item.productName.toLowerCase(),
        );
        final newQty = (product.stockQty - item.quantity).clamp(0, 999999);
        await _productRepo.updateStock(product.id, newQty);
      } catch (_) {
        // Product not found in local list — skip stock deduction.
      }
    }
  }

  @override
  Future<void> updateStatus(String orderId, OrderStatus status) =>
      _orderRepo.updateStatus(orderId, status);

  @override
  Future<void> deleteOrder(String orderId) => _orderRepo.delete(orderId);
}
