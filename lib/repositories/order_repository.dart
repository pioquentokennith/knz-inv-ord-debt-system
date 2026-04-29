// ─────────────────────────────────────────────────────────────────────────────
// order_repository.dart — Abstract OrderRepository interface
// Purpose : Defines the data-access contract for orders.
//           OrderService depends on this interface, not on LocalOrderRepository,
//           which allows easy swapping with stub implementations in tests.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/order_model.dart';

abstract class OrderRepository {
  // Returns all active (non-deleted) orders for a given user, newest first
  // PRIORITY 3: Optional date-range filter — pass fromDate/toDate to narrow results.
  // Useful for analytics or export when data grows large.
  Future<List<Order>> getAll(String userId, {DateTime? fromDate, DateTime? toDate});

  // Persists a new order and its line items to storage
  Future<void> add(Order order, String userId);

  // Updates only the status field of an existing order
  Future<void> updateStatus(String orderId, OrderStatus status);

  // Soft-deletes an order (moves to Recycle Bin)
  Future<void> delete(String orderId);

  // Returns the next sequential order number to generate a KNZ-XXX ID
  Future<int>  getNextOrderNumber(String userId);

  // ── Recycle Bin operations ────────────────────────────────────────────────

  // Returns all soft-deleted orders for the Recycle Bin screen
  Future<List<Order>> getDeleted(String userId);

  // Restores a soft-deleted order back to the active list
  Future<void> restore(String orderId);

  // Permanently removes an order and its items from storage (admin-only purge)
  Future<void> hardDelete(String orderId);
}
