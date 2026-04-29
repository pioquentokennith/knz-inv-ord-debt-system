// ─────────────────────────────────────────────────────────────────────────────
// order_service.dart — Order business logic
// Purpose : Encapsulates all order-related business rules, including automatic
//           stock deduction when a new order is created. Keeps screens thin.
// Interface + Implementation (Abstraction + Polymorphism)
// ─────────────────────────────────────────────────────────────────────────────

import '../models/order_model.dart';
import '../models/product_model.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';

/// Abstract contract for order business logic (Abstraction).
/// AppState depends on this interface so tests can inject a stub.
abstract class IOrderService {
  // Returns all active orders for the given user, newest first.
  // PRIORITY 3: Pass fromDate/toDate to filter by order_date range (optional).
  Future<List<Order>> getAll(String userId, {DateTime? fromDate, DateTime? toDate});

  // Generates the next sequential human-readable order ID (e.g. "KNZ-042")
  Future<String>      generateOrderId(String userId);

  // Persists the order and automatically deducts stock for each item
  Future<void>        createOrder(Order order, String userId, List<Product> products);

  // Updates only the status field of an existing order
  Future<void>        updateStatus(String orderId, OrderStatus status);

  // Soft-deletes an order (moves it to the Recycle Bin)
  Future<void>        deleteOrder(String orderId);

  // ── Recycle Bin operations ────────────────────────────────────────────────
  Future<List<Order>> getDeleted(String userId);        // Returns soft-deleted orders
  Future<void>        restoreOrder(String orderId);     // Un-deletes an order
  Future<void>        hardDeleteOrder(String orderId);  // Permanent purge
}

/// Concrete implementation — all business logic for orders.
class OrderService implements IOrderService {
  final OrderRepository   _orderRepo;   // Handles order persistence
  final ProductRepository _productRepo; // Needed for stock deduction

  OrderService(this._orderRepo, this._productRepo);

  // Delegates directly to repo — date params forwarded for optional range filtering
  @override
  Future<List<Order>> getAll(String userId, {DateTime? fromDate, DateTime? toDate}) =>
      _orderRepo.getAll(userId, fromDate: fromDate, toDate: toDate);

  // Reads the next sequential number from the DB and formats it as "KNZ-XXX"
  @override
  Future<String> generateOrderId(String userId) async {
    final num = await _orderRepo.getNextOrderNumber(userId);
    return 'KNZ-${num.toString().padLeft(3, '0')}'; // e.g. 1 → "KNZ-001"
  }

  /// Creates an order and auto-deducts stock for each item (Encapsulation of business rule).
  /// Stock deduction is a critical business rule — it belongs here, not in the screen.
  @override
  Future<void> createOrder(Order order, String userId, List<Product> products) async {
    // Save the order first; items are saved atomically within the repository
    await _orderRepo.add(order, userId);

    // Deduct stock for each ordered item from the product catalog
    for (final item in order.items) {
      try {
        // Match by product ID first; fall back to name matching for legacy orders
        final product = products.firstWhere(
          (p) => p.id == item.productId ||
                 p.name.toLowerCase() == item.productName.toLowerCase(),
        );
        // clamp(0, 999999) prevents negative stock if the order exceeds available qty
        final newQty = (product.stockQty - item.quantity).clamp(0, 999999);
        await _productRepo.updateStock(product.id, newQty);
      } catch (_) {
        // Product not found in the passed list — skip deduction silently
        // (can happen if the product was deleted before the order was confirmed)
      }
    }
  }

  // Delegates status update to the repository
  @override
  Future<void> updateStatus(String orderId, OrderStatus status) =>
      _orderRepo.updateStatus(orderId, status);

  // Delegates soft-delete to the repository
  @override
  Future<void> deleteOrder(String orderId) => _orderRepo.delete(orderId);

  // Delegates Recycle Bin operations to the repository
  @override
  Future<List<Order>> getDeleted(String userId) => _orderRepo.getDeleted(userId);

  @override
  Future<void> restoreOrder(String orderId) => _orderRepo.restore(orderId);

  @override
  Future<void> hardDeleteOrder(String orderId) => _orderRepo.hardDelete(orderId);
}
