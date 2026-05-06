// ─────────────────────────────────────────────────────────────────────────────
// analytics_screen.dart
// Purpose : Displays business analytics including revenue stats, order breakdowns,
//           debt summaries, and top-selling products.
// Function: Uses AppStateBuilder (FIX 6) so only the data section rebuilds on
//           AppState changes. Renders a pie chart of orders by status via fl_chart,
//           a utang breakdown with payment progress bars, and a top-5 products list
//           with per-day sales that expand/collapse on tap. All data is derived from
//           AppState.orders and AppState.debts at build time.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/app_state_builder.dart'; // ← FIX 6
import '../dialogs/export_dialog.dart';
import '../models/order_model.dart';
import '../models/debt_model.dart';
import '../widgets/shared_widgets.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  // FIX 6: No _state, no addListener, no _onStateChange — removed.
  final Set<String> _expandedProducts = {};
  String _utangTab = 'Unpaid'; // 'Unpaid' or 'Paid'

  // ── PRIORITY 1: Cache _topProductsAllTime result ─────────────────────────
  // Cached result is invalidated when the orders list identity changes.
  // Avoids recomputing the full aggregation on every AppState rebuild.
  List<Order>? _cachedOrdersRef;            // last seen orders list reference
  List<_ProductSalesData>? _cachedTopProducts; // computed result

  // Aggregates all non-cancelled order items into a map of product name → (date → qty sold).
  // Returns products sorted by total units sold, each with a per-day breakdown.
  // Result is memoised: recomputed only when the orders list reference changes.
  List<_ProductSalesData> _topProductsAllTime() {
    final currentOrders = AppState().orders;
    // Return cached result if orders haven't changed since last computation
    if (_cachedOrdersRef == currentOrders && _cachedTopProducts != null) {
      return _cachedTopProducts!;
    }
    final map = <String, Map<String, int>>{};
    for (final order in AppState().orders) {
      if (order.status == OrderStatus.cancelled) continue;
      final dateKey = DateFormat('MMM dd, yyyy').format(order.orderDate);
      for (final item in order.items) {
        map.putIfAbsent(item.productName, () => {});
        map[item.productName]![dateKey] =
            (map[item.productName]![dateKey] ?? 0) + item.quantity;
      }
    }
    final result = map.entries.map((e) {
      final total = e.value.values.fold(0, (a, b) => a + b);
      final days = e.value.entries.toList()
        ..sort((a, b) {
          final da = DateFormat('MMM dd, yyyy').parse(a.key);
          final db = DateFormat('MMM dd, yyyy').parse(b.key);
          return db.compareTo(da);
        });
      return _ProductSalesData(name: e.key, total: total, byDay: days);
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    // Store result in cache along with the orders reference used to compute it
    _cachedOrdersRef    = currentOrders;
    _cachedTopProducts  = result;
    return result;
  }

  // Returns the chart/badge color for a given order status for the pie chart sections
  // COLOR GUIDE:
  //   Pending    = amber/yellow  — "naghihintay pa"
  //   Processing = blue          — "in progress"
  //   Shipped    = purple        — "nasa daan na"
  //   Delivered  = green         — "natapos na"
  //   Cancelled  = red           — "hindi natuloy"
  //   Utang      = deep orange   — "may utang pa" (distinct from Pending amber)
  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0xFFFFCA28);   // Amber/yellow — "naghihintay"
      case OrderStatus.processing:
        return AppColors.info;             // Blue — "in progress"
      case OrderStatus.shipped:
        return Colors.purple;              // Purple — "nasa daan na"
      case OrderStatus.delivered:
        return AppColors.success;          // Green — "delivered na"
      case OrderStatus.cancelled:
        return AppColors.error;            // Red — "cancelled"
      case OrderStatus.utang:
        return const Color(0xFFFF6D00);   // Deep orange — "may utang pa"
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    // FIX 6: AppStateBuilder scopes rebuilds to only this subtree.
    // All 'state.xxx' calls are now INSIDE the builder where 'state' is defined.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AppStateBuilder(
        builder: (context, state) {
          final statusMap = state.ordersByStatus;
          final totalOrders = state.totalOrders;
          final topProducts = _topProductsAllTime();
          final totalDebt = state.totalDebtAmount;
          final unpaidDebts = state.unpaidDebts;
          final paidDebts = state.paidDebts;
          final overdueDebts = state.overdueDebts;

          // Pie chart data
          final pieData = OrderStatus.values
              .where((s) => (statusMap[s] ?? 0) > 0)
              .map((s) => PieChartSectionData(
                    value: (statusMap[s] ?? 0).toDouble(),
                    color: _statusColor(s),
                    radius: 55,
                    title: '',
                  ))
              .toList();

          return AnimationLimiter(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: AnimationConfiguration.toStaggeredList(
                  duration: const Duration(milliseconds: 400),
                  childAnimationBuilder: (w) => SlideAnimation(
                    verticalOffset: 30,
                    child: FadeInAnimation(child: w),
                  ),
                  children: [
                    Row(children: [
                      const Icon(Icons.trending_up, color: AppColors.gold, size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Analytics & Reports',
                            style: TextStyle(
                                color: AppColors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis),
                      ),
                      GestureDetector(
                        onTap: () => showExportDialog(context, ExportType.analytics),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.download_outlined, color: AppColors.gold, size: 16),
                            SizedBox(width: 5),
                            Text('Export',
                                style: TextStyle(
                                    color: AppColors.gold,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),

                    // ── All Stat Cards — single unified grid ──
                    LayoutBuilder(builder: (ctx, constraints) {
                      final cols = constraints.maxWidth > 600 ? 4 : 2;
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: cols == 4 ? 1.3 : 1.05,
                        children: [
                          // Row 0: Total Revenue (Delivered + Utang Collected)
                          StatCard(
                            emoji: '💰',
                            value: currency.format(state.totalRevenue),
                            label: 'TOTAL REVENUE',
                            subtitle: 'Delivered + Utang paid',
                            subtitleColor: AppColors.gold,
                          ),
                          // Row 1: Revenue + Orders
                          StatCard(
                            emoji: '💵',
                            value: currency.format(state.deliveredRevenue),
                            label: 'DELIVERED REVENUE',
                            subtitle: 'Delivered only',
                            subtitleColor: AppColors.success,
                          ),
                          // Row 2: Order cards
                          StatCard(
                            emoji: '📦',
                            value: state.totalOrders.toString(),
                            label: 'TOTAL ORDERS',
                          ),
                          StatCard(
                            emoji: '✅',
                            value: state.deliveredCount.toString(),
                            label: 'DELIVERED',
                            subtitleColor: AppColors.success,
                          ),
                          // Row 3: Items + Paid
                          StatCard(
                            emoji: '🛍️',
                            value: state.orders
                                    .where((o) => o.status != OrderStatus.cancelled)
                                    .fold(0, (sum, o) => sum + o.quantity)
                                    .toString(),
                            label: 'ITEMS SOLD',
                          ),
                          StatCard(
                            emoji: '💸',
                            value: currency.format(state.totalUtangCollected),
                            label: 'TOTAL PAID',
                            subtitle: 'Utang collected',
                            subtitleColor: AppColors.success,
                          ),
                          // Row 4: Utang cards
                          StatCard(
                            emoji: '💳',
                            value: currency.format(totalDebt),
                            label: 'TOTAL UTANG',
                            subtitleColor: totalDebt > 0 ? AppColors.error : AppColors.success,
                          ),
                          StatCard(
                            emoji: '⏳',
                            value: unpaidDebts.length.toString(),
                            label: 'UNPAID',
                            subtitleColor: unpaidDebts.isNotEmpty ? AppColors.warning : AppColors.success,
                          ),
                          StatCard(
                            emoji: '✅',
                            value: paidDebts.length.toString(),
                            label: 'PAID',
                            subtitleColor: AppColors.success,
                          ),
                          StatCard(
                            emoji: '🚨',
                            value: overdueDebts.length.toString(),
                            label: 'OVERDUE',
                            subtitleColor: overdueDebts.isNotEmpty ? AppColors.error : AppColors.success,
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 16),

                    // Utang breakdown section
                    _buildUtangBreakdown(unpaidDebts, paidDebts, currency),
                    const SizedBox(height: 20),

                    // Orders by status + Top products
                    LayoutBuilder(builder: (ctx, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      final content = [
                        _buildOrdersByStatus(statusMap, totalOrders, pieData),
                        const SizedBox(width: 16, height: 16),
                        _buildTopProducts(topProducts),
                      ];
                      return isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: content[0]),
                                content[1],
                                Expanded(child: content[2]),
                              ],
                            )
                          : Column(children: [
                              content[0],
                              content[1],
                              content[2],
                            ]);
                    }),
                  ],
                ),
              ),
            ),
          );
        },
        ),
      ),
    );
  }

  Widget _buildUtangBreakdown(
      List<CustomerDebt> unpaidDebts, List<CustomerDebt> paidDebts, NumberFormat currency) {
    final dateFmt = DateFormat('MMM dd');
    final displayDebts = _utangTab == 'Unpaid' ? unpaidDebts : paidDebts;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
            const Text('💳', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            const Flexible(
              child: Text('Utang Breakdown',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
            const SizedBox(width: 8),
            // Unpaid / Paid tab toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: ['Unpaid', 'Paid'].map((tab) {
                  final isActive = _utangTab == tab;
                  final tabColor = tab == 'Unpaid' ? AppColors.error : AppColors.success;
                  final count = tab == 'Unpaid' ? unpaidDebts.length : paidDebts.length;
                  return GestureDetector(
                    onTap: () => setState(() => _utangTab = tab),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive ? tabColor.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: isActive ? Border.all(color: tabColor, width: 1.0) : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tab,
                              style: TextStyle(
                                color: isActive ? tabColor : AppColors.whiteTertiary,
                                fontSize: 10,
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                              )),
                          const SizedBox(width: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: isActive ? tabColor.withValues(alpha: 0.3) : AppColors.cardBorder,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('$count',
                                style: TextStyle(
                                  color: isActive ? tabColor : AppColors.whiteTertiary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (displayDebts.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  _utangTab == 'Unpaid' ? 'No unpaid utang! 🎉' : 'No paid utang yet.',
                  style: const TextStyle(color: AppColors.whiteTertiary),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: displayDebts.map((d) {
                    final pct = (d.amountPaid / d.totalAmount).clamp(0.0, 1.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: d.isPaid
                                      ? AppColors.success
                                      : d.isOverdue
                                          ? AppColors.error
                                          : AppColors.warning,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.customerName,
                                        style: const TextStyle(
                                            color: AppColors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                    Row(children: [
                                      Text(d.orderId,
                                          style: const TextStyle(
                                              color: AppColors.gold, fontSize: 11)),
                                      const SizedBox(width: 8),
                                      Text('• ${dateFmt.format(d.createdAt)}',
                                          style: const TextStyle(
                                              color: AppColors.whiteTertiary,
                                              fontSize: 11)),
                                      if (d.isOverdue) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('${d.daysOld}d overdue',
                                              style: const TextStyle(
                                                  color: AppColors.error,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                      if (d.isPaid) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('PAID',
                                              style: TextStyle(
                                                  color: AppColors.success,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ]),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    d.isPaid
                                        ? currency.format(d.totalAmount)
                                        : currency.format(d.remainingBalance),
                                    style: TextStyle(
                                        color: d.isPaid ? AppColors.success : AppColors.error,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14),
                                  ),
                                  Text('of ${currency.format(d.totalAmount)}',
                                      style: const TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 10)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: AppColors.cardBorder,
                              valueColor: AlwaysStoppedAnimation(
                                pct >= 1.0 ? AppColors.success : AppColors.gold,
                              ),
                              minHeight: 5,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrdersByStatus(
      Map<OrderStatus, int> statusMap, int totalOrders, List<PieChartSectionData> pieData) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('📦', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text('Orders by Status',
                style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ]),
          const SizedBox(height: 20),
          if (pieData.isNotEmpty)
            SizedBox(
              height: 160,
              child: PieChart(
                PieChartData(
                  sections: pieData,
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),
          const SizedBox(height: 20),
          ...OrderStatus.values.map((s) {
            final count = statusMap[s] ?? 0;
            final pct = totalOrders > 0 ? count / totalOrders : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_statusIcon(s), color: _statusColor(s), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.displayName,
                            style: const TextStyle(
                                color: AppColors.white, fontSize: 13)),
                      ),
                      Text(
                        '$count (${(pct * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(
                            color: AppColors.whiteTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.inputFill,
                      valueColor: AlwaysStoppedAnimation(_statusColor(s)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _statusIcon(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return Icons.hourglass_empty;
      case OrderStatus.processing:
        return Icons.sync;
      case OrderStatus.shipped:
        return Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        return Icons.check_circle_outline;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
      case OrderStatus.utang:
        return Icons.account_balance_wallet_outlined;
    }
  }

  Widget _buildTopProducts(List<_ProductSalesData> topProducts) {
    final maxSales =
        topProducts.isNotEmpty ? topProducts.first.total.toDouble() : 1.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🏆', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Text('Top Products by Sales',
                style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            SizedBox(width: 8),
            Text('(All Time)',
                style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          if (topProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No sales data yet',
                  style: TextStyle(color: AppColors.whiteTertiary),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  children: topProducts.asMap().entries.map((entry) {
              final i = entry.key;
              final data = entry.value;
              final pct = data.total / maxSales;
              final isExpanded = _expandedProducts.contains(data.name);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isExpanded
                          ? AppColors.gold.withValues(alpha: 0.3)
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          if (isExpanded) {
                            _expandedProducts.remove(data.name);
                          } else {
                            _expandedProducts.add(data.name);
                          }
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(data.name,
                                    style: const TextStyle(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${data.total} SOLD',
                                  style: const TextStyle(
                                      color: AppColors.success,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: AppColors.whiteTertiary,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: AppColors.inputFill,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.success),
                            minHeight: 5,
                          ),
                        ),
                      ),
                      AnimatedCrossFade(
                        firstChild: const SizedBox.shrink(),
                        secondChild: Column(
                          children: [
                            const Divider(color: AppColors.divider, height: 1),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 200),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: data.byDay.map((day) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.calendar_today_outlined,
                                            size: 12,
                                            color: AppColors.whiteTertiary),
                                        const SizedBox(width: 8),
                                        Text(
                                          day.key,
                                          style: const TextStyle(
                                              color: AppColors.whiteSecondary,
                                              fontSize: 12),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.gold.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                                color: AppColors.gold.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            '${day.value} sold',
                                            style: const TextStyle(
                                                color: AppColors.gold,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                        crossFadeState: isExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 250),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Helper data class for top products with per-day breakdown
class _ProductSalesData {
  final String name;
  final int total;
  final List<MapEntry<String, int>> byDay; // date string -> qty

  _ProductSalesData({
    required this.name,
    required this.total,
    required this.byDay,
  });
}