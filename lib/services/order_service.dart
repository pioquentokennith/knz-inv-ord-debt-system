// ─────────────────────────────────────────────────────────────────────────────
// order_service.dart — Order business logic
// Purpose : Encapsulates all order-related business rules, including automatic
//           stock deduction when a new order is created. Keeps screens thin.
// Interface + Implementation (Abstraction + Polymorphism)
// ─────────────────────────────────────────────────────────────────────────────

import '../models/order_model.dart';
import '../models/debt_model.dart';
import '../repositories/order_repository.dart';

/// Abstract contract for order business logic (Abstraction).
/// AppState depends on this interface so tests can inject a stub.
abstract class IOrderService {
  // Returns all active orders for the given user, newest first.
  // PRIORITY 3: Pass fromDate/toDate to filter by order_date range (optional).
  Future<List<Order>> getAll(
    String userId, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  // Persists the order and automatically deducts stock for each item
  Future<OrderCreationResult> createOrder(
    Order order,
    String userId, {
    CustomerDebt? debt,
  });

  // Updates only the status field of an existing order
  Future<void> updateStatus(String orderId, OrderStatus status);

  // Atomically changes an existing active order to utang and creates its debt.
  Future<void> markAsUtang(String orderId, CustomerDebt debt);

  // Soft-deletes an order (moves it to the Recycle Bin)
  Future<void> deleteOrder(String orderId);

  // ── Recycle Bin operations ────────────────────────────────────────────────
  Future<List<Order>> getDeleted(String userId); // Returns soft-deleted orders
  Future<void> restoreOrder(String orderId); // Un-deletes an order
  Future<void> hardDeleteOrder(String orderId); // Permanent purge
}

/// Concrete implementation — all business logic for orders.
class OrderService implements IOrderService {
  final OrderRepository _orderRepo;

  OrderService(this._orderRepo);

  // Delegates directly to repo — date params forwarded for optional range filtering
  @override
  Future<List<Order>> getAll(
    String userId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) => _orderRepo.getAll(userId, fromDate: fromDate, toDate: toDate);

  /// Atomically allocates the final order number, saves the order/items,
  /// deducts current database stock, and optionally creates its debt record.
  @override
  Future<OrderCreationResult> createOrder(
    Order order,
    String userId, {
    CustomerDebt? debt,
  }) {
    _requireNonBlank(userId, 'userId');
    return _orderRepo.addWithInventory(order, userId.trim(), debt: debt);
  }

  // Delegates status update to the repository
  @override
  Future<void> updateStatus(String orderId, OrderStatus status) {
    _requireNonBlank(orderId, 'orderId');
    return _orderRepo.updateStatus(orderId, status);
  }

  @override
  Future<void> markAsUtang(String orderId, CustomerDebt debt) {
    _requireNonBlank(orderId, 'orderId');
    return _orderRepo.markAsUtang(orderId, debt);
  }

  // Delegates soft-delete to the repository
  @override
  Future<void> deleteOrder(String orderId) {
    _requireNonBlank(orderId, 'orderId');
    return _orderRepo.deleteWithInventory(orderId);
  }

  // Delegates Recycle Bin operations to the repository
  @override
  Future<List<Order>> getDeleted(String userId) =>
      _orderRepo.getDeleted(userId);

  @override
  Future<void> restoreOrder(String orderId) {
    _requireNonBlank(orderId, 'orderId');
    return _orderRepo.restoreWithInventory(orderId);
  }

  @override
  Future<void> hardDeleteOrder(String orderId) {
    _requireNonBlank(orderId, 'orderId');
    return _orderRepo.hardDelete(orderId);
  }

  void _requireNonBlank(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name, '$name cannot be blank.');
    }
  }
}
