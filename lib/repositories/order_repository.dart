// ─────────────────────────────────────────────────────────────────────────────
// order_repository.dart — Abstract OrderRepository interface
// Purpose : Defines the data-access contract for orders.
//           OrderService depends on this interface, not on LocalOrderRepository,
//           which allows easy swapping with stub implementations in tests.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';
import '../models/order_model.dart';

class OrderCreationResult {
  const OrderCreationResult({required this.order, required this.created});

  final Order order;
  final bool created;
}

abstract class OrderRepository {
  // Returns all active (non-deleted) orders for a given user, newest first
  // PRIORITY 3: Optional date-range filter — pass fromDate/toDate to narrow results.
  // Useful for analytics or export when data grows large.
  Future<List<Order>> getAll(
    String userId, {
    DateTime? fromDate,
    DateTime? toDate,
  });

  // Persists a new order and its line items to storage
  Future<void> add(Order order, String userId);

  /// Atomically persists an order, deducts current SQLite inventory, and may
  /// create the order's initial debt. Returns the saved order with the final
  /// per-user human-readable order id allocated by the transaction.
  Future<OrderCreationResult> addWithInventory(
    Order order,
    String userId, {
    CustomerDebt? debt,
  });

  // Updates only the status field of an existing order
  Future<void> updateStatus(String orderId, OrderStatus status);

  /// Atomically changes an active order to utang and creates its debt ledger.
  Future<void> markAsUtang(String orderId, CustomerDebt debt);

  // Soft-deletes an order (moves to Recycle Bin)
  Future<void> delete(String orderId);

  /// Atomically soft-deletes an order and returns its quantities to inventory.
  Future<void> deleteWithInventory(String orderId);

  // ── Recycle Bin operations ────────────────────────────────────────────────

  // Returns all soft-deleted orders for the Recycle Bin screen
  Future<List<Order>> getDeleted(String userId);

  // Restores a soft-deleted order back to the active list
  Future<void> restore(String orderId);

  /// Atomically restores an order and re-deducts its quantities. Throws and
  /// rolls the transaction back if a product is missing or stock is short.
  Future<void> restoreWithInventory(String orderId);

  // Permanently removes an order and its items from storage (admin-only purge)
  Future<void> hardDelete(String orderId);
}
