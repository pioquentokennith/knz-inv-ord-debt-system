// ─────────────────────────────────────────────────────────────────────────────
// accounting_service.dart — Accounting computation layer
// Purpose : Derives gross sales, total discounts, net sales, and per-reseller
//           summaries from a list of Order objects (already in AppState memory).
//           All methods are pure (no I/O) so they are fast and testable.
// OOP Pillars:
//   • Encapsulation — computation logic lives here, not scattered in screens
//   • Abstraction   — callers receive typed summary objects, not raw SQL
// ─────────────────────────────────────────────────────────────────────────────

import '../models/order_model.dart';
import '../models/reseller_accounting_summary.dart';

class AccountingService {
  AccountingService._(); // Static-only class
  static final AccountingService instance = AccountingService._();

  // ── Top-level aggregates ──────────────────────────────────────────────────

  /// Gross sales = sum of SRP × qty for each item across non-cancelled orders.
  /// Uses item.srpPrice (catalog price) when available, falls back to unitPrice.
  double grossSales(List<Order> orders) => orders
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0.0, (s, o) => s + o.srpTotal);

  /// Total discounts = per-item deductions (srpPrice - unitPrice) × qty.
  /// This is the authoritative discount since totalAmount is always saved as net.
  double totalDiscounts(List<Order> orders) => orders
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0.0, (s, o) => s + o.totalDiscountAmount);

  /// Net sales = sum of customerPayAmount across orders (the true net each customer paid).
  double netSales(List<Order> orders) => orders
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0.0, (s, o) => s + o.customerPayAmount);

  /// Revenue from customized orders (order_type == 'customized').
  double customizedOrderRevenue(List<Order> orders) => orders
      .where((o) =>
          o.status != OrderStatus.cancelled && o.orderType == 'customized')
      .fold(0.0, (s, o) => s + o.discountedTotal);

  // ── Reseller-specific summaries ───────────────────────────────────────────

  /// Groups reseller orders by customer name and builds per-reseller summaries.
  /// Orders that are not flagged as reseller orders are excluded.
  List<ResellerAccountingSummary> resellerSummary(List<Order> orders) {
    // Group orders by reseller (customer) name
    final Map<String, List<Order>> byReseller = {};
    for (final order in orders) {
      if (!order.isReseller) continue;
      if (order.status == OrderStatus.cancelled) continue;
      byReseller.putIfAbsent(order.customerName, () => []).add(order);
    }

    return byReseller.entries.map((entry) {
      final name           = entry.key;
      final resellerOrders = entry.value;

      // Gross = true SRP total using srpTotal getter (srpPrice × qty per item)
      final gross = resellerOrders.fold(0.0, (s, o) => s + o.srpTotal);

      // Discount = (srpPrice - unitPrice) × qty per item — always correct
      // because srpPrice and unitPrice are saved at order time in order_items.
      final discount = resellerOrders.fold(0.0,
          (s, o) => s + o.itemDiscountAmount);

      // Net = customerPayAmount per order (discountedTotal for resellers, totalAmount for regular)
      final net = resellerOrders.fold(0.0, (s, o) => s + o.customerPayAmount);
      final avgDeduction = resellerOrders.isEmpty
          ? 0.0
          : resellerOrders.fold(0.0, (s, o) => s + o.deductionPerItem) /
              resellerOrders.length;

      return ResellerAccountingSummary(
        resellerName:     name,
        totalOrders:      resellerOrders.length,
        grossSales:       gross,
        totalDiscount:    discount,
        netRevenue:       net,
        averageDeduction: avgDeduction,
      );
    }).toList()
      ..sort((a, b) => b.netRevenue.compareTo(a.netRevenue)); // Highest earner first
  }

  // ── Date-range filter helper ──────────────────────────────────────────────

  /// Filters orders by an optional date range, inclusive on both ends
  /// (from = start of [from] day, to = end of [to] day at 23:59:59.999999).
  List<Order> filterByDateRange(
    List<Order> orders, {
    DateTime? from,
    DateTime? to,
  }) {
    // End-of-day boundary: add 1 day then subtract 1 microsecond so orders
    // placed at any time on the [to] date are included, but nothing from the
    // following day leaks through.
    final endOfToDay = to
        ?.add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    return orders.where((o) {
      if (from       != null && o.orderDate.isBefore(from))       return false;
      if (endOfToDay != null && o.orderDate.isAfter(endOfToDay))  return false;
      return true;
    }).toList();
  }
}
