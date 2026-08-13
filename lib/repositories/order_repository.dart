// ─────────────────────────────────────────────────────────────────────────────
// order_repository.dart — Abstract OrderRepository interface
// Purpose : Defines the data-access contract for orders.
//           OrderService depends on this interface, not on LocalOrderRepository,
//           which allows easy swapping with stub implementations in tests.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';
import '../models/business_event_model.dart';
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

  Future<BusinessEvent> recordPayment(String orderId, BusinessEvent event);

  Future<BusinessEvent> recordDelivery(String orderId, BusinessEvent event);

  Future<BusinessEvent> issueRefund(String orderId, BusinessEvent event);

  Future<BusinessEvent> reverseEvent(String orderId, BusinessEvent event);

  /// Atomically changes an active order to utang and creates its debt ledger.
  Future<void> markAsUtang(String orderId, CustomerDebt debt);

  /// Atomically soft-deletes an order and returns its quantities to inventory.
  Future<void> deleteWithInventory(String orderId, String userId);

  // ── Recycle Bin operations ────────────────────────────────────────────────

  // Returns all soft-deleted orders for the Recycle Bin screen
  Future<List<Order>> getDeleted(String userId);

  /// Atomically restores an order and re-deducts its quantities. Throws and
  /// rolls the transaction back if a product is missing or stock is short.
  Future<void> restoreWithInventory(String orderId, String userId);

  // Permanently removes an order and its items from storage (admin-only purge)
  Future<void> hardDelete(String orderId, String userId);
}
