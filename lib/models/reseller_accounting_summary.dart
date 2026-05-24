// ─────────────────────────────────────────────────────────────────────────────
// reseller_accounting_summary.dart — Per-reseller aggregated accounting summary
// Purpose : Aggregated view computed by AccountingService.resellerSummary().
//           Not persisted — always derived from orders table.
// ─────────────────────────────────────────────────────────────────────────────

class ResellerAccountingSummary {
  final String resellerName;
  final int    totalOrders;
  final double grossSales;        // SRP total before deduction
  final double totalDiscount;     // Total peso deduction given to reseller
  final double netRevenue;        // What KNZ actually earned
  final double averageDeduction;  // Average fixed peso deduction per item across orders

  const ResellerAccountingSummary({
    required this.resellerName,
    required this.totalOrders,
    required this.grossSales,
    required this.totalDiscount,
    required this.netRevenue,
    required this.averageDeduction,
  });
}
