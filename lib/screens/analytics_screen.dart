// ─────────────────────────────────────────────────────────────────────────────
// analytics_screen.dart  (v7 — full analytics suite)
// NEW sections added (all existing sections preserved):
//   • Revenue Trend linechart — daily / weekly / monthly toggle
//   • Discount Summary stat cards — gross, discount, net, reseller breakdown
//   • Month-over-month % change on revenue cards
//   • Product revenue vs volume (revenue column in top products)
//   • Payment method breakdown — pie/bar chart
//   • Utang aging analysis — bar chart by age bracket
//   • Sales heatmap — order count by day-of-week × hour
//   • Reseller performance ranking — top reseller, most orders, highest discount
//   • Custom orders revenue card
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/app_state_builder.dart';
import '../dialogs/export_dialog.dart';
import '../models/order_model.dart';
import '../models/debt_model.dart';
import '../models/payment_method_model.dart';
import '../models/reseller_accounting_summary.dart';
import '../services/accounting_service.dart';
import '../widgets/shared_widgets.dart';

// ── Revenue trend granularity toggle ─────────────────────────────────────────
enum _TrendView { daily, weekly, monthly }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final Set<String> _expandedProducts = {};
  String _utangTab = 'Unpaid';
  _TrendView _trendView = _TrendView.daily;

  // ── Memoised top-products ─────────────────────────────────────────────────
  List<Order>? _cachedOrdersRef;
  List<_ProductSalesData>? _cachedTopProducts;

  List<_ProductSalesData> _topProductsAllTime() {
    final currentOrders = AppState().orders;
    if (_cachedOrdersRef == currentOrders && _cachedTopProducts != null) {
      return _cachedTopProducts!;
    }
    final map = <String, Map<String, int>>{};
    final revenueMap = <String, double>{};
    for (final order in AppState().orders) {
      if (order.status == OrderStatus.cancelled) continue;
      final dateKey = DateFormat('MMM dd, yyyy').format(order.orderDate);
      for (final item in order.items) {
        map.putIfAbsent(item.productName, () => {});
        map[item.productName]![dateKey] =
            (map[item.productName]![dateKey] ?? 0) + item.quantity;
        revenueMap[item.productName] =
            (revenueMap[item.productName] ?? 0) + item.unitPrice * item.quantity;
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
      return _ProductSalesData(
        name: e.key,
        total: total,
        revenue: revenueMap[e.key] ?? 0,
        byDay: days,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    _cachedOrdersRef = currentOrders;
    _cachedTopProducts = result;
    return result;
  }

  // ── Revenue trend buckets ─────────────────────────────────────────────────
  List<_TrendPoint> _buildTrendData(List<Order> orders) {
    final map = <String, double>{};
    for (final order in orders) {
      if (order.status != OrderStatus.delivered &&
          order.status != OrderStatus.utang) { continue; }
      final key = _bucketKey(order.orderDate);
      // FIX: Use customerPayAmount for both branches so reseller delivered orders
      // don't overcount revenue with SRP instead of the net selling price.
      final value = order.customerPayAmount;
      map[key] = (map[key] ?? 0) + value;
    }
    if (map.isEmpty) return [];
    final sorted = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => _TrendPoint(label: _displayLabel(e.key), value: e.value))
        .toList();
  }

  String _bucketKey(DateTime dt) {
    switch (_trendView) {
      case _TrendView.daily:
        return DateFormat('yyyy-MM-dd').format(dt);
      case _TrendView.weekly:
        final monday = dt.subtract(Duration(days: dt.weekday - 1));
        return DateFormat('yyyy-MM-dd').format(monday);
      case _TrendView.monthly:
        return DateFormat('yyyy-MM').format(dt);
    }
  }

  String _displayLabel(String key) {
    switch (_trendView) {
      case _TrendView.daily:
        return DateFormat('MMM d').format(DateTime.parse(key));
      case _TrendView.weekly:
        return 'W${_weekNumber(DateTime.parse(key))}';
      case _TrendView.monthly:
        return DateFormat('MMM yy').format(DateTime.parse('$key-01'));
    }
  }

  int _weekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    return ((date.difference(startOfYear).inDays) / 7).ceil() + 1;
  }

  // ── Month-over-month helper ───────────────────────────────────────────────
  double _revenueForMonth(List<Order> orders, DateTime month) {
    return orders
        .where((o) =>
            (o.status == OrderStatus.delivered || o.status == OrderStatus.utang) &&
            o.orderDate.year == month.year &&
            o.orderDate.month == month.month)
        .fold(0.0, (s, o) => s + o.customerPayAmount);
  }

  // ── Payment method aggregation ─────────────────────────────────────────────
  // Returns order COUNT per payment method (not revenue) so it shows
  // which method is most USED. All 5 enum values are always present (min 0).
  Map<PaymentMethod, int> _paymentMethodCount(List<Order> orders) {
    // Seed all 5 payment methods with 0 so they always appear in the chart
    final map = <PaymentMethod, int>{
      for (final pm in PaymentMethod.values) pm: 0,
    };
    for (final o in orders) {
      if (o.status == OrderStatus.cancelled) continue;
      final pm = o.paymentMethod ?? PaymentMethod.cashOnDelivery;
      map[pm] = (map[pm] ?? 0) + 1;
    }
    return map;
  }

  // ── Utang aging buckets ───────────────────────────────────────────────────
  Map<String, int> _utangAgingBuckets(List<CustomerDebt> unpaid) {
    final buckets = {'0–7d': 0, '8–30d': 0, '31–60d': 0, '60+d': 0};
    for (final d in unpaid) {
      final age = d.daysOld;
      if (age <= 7)       { buckets['0–7d']  = (buckets['0–7d']!  + 1); }
      else if (age <= 30) { buckets['8–30d'] = (buckets['8–30d']! + 1); }
      else if (age <= 60) { buckets['31–60d']= (buckets['31–60d']!+ 1); }
      else                { buckets['60+d']  = (buckets['60+d']!  + 1); }
    }
    return buckets;
  }

  // ── Sales heatmap (dow × hour) ────────────────────────────────────────────
  List<List<int>> _buildHeatmap(List<Order> orders) {
    // [dow 0=Mon..6=Sun][hour 0..23]
    final grid = List.generate(7, (_) => List.filled(24, 0));
    for (final o in orders) {
      if (o.status == OrderStatus.cancelled) continue;
      final dow = (o.orderDate.weekday - 1).clamp(0, 6);
      final hr = o.orderDate.hour.clamp(0, 23);
      grid[dow][hr]++;
    }
    return grid;
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:    return const Color(0xFFFFCA28);
      case OrderStatus.processing: return AppColors.info;
      case OrderStatus.shipped:    return Colors.purple;
      case OrderStatus.delivered:  return AppColors.success;
      case OrderStatus.cancelled:  return AppColors.error;
      case OrderStatus.utang:      return const Color(0xFFFF6D00);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AppStateBuilder(
          builder: (context, state) {
            final orders      = state.orders.toList();
            final statusMap   = state.ordersByStatus;
            final totalOrders = state.totalOrders;
            final topProducts = _topProductsAllTime();
            final totalDebt   = state.totalDebtAmount;
            final unpaidDebts = state.unpaidDebts;
            final paidDebts   = state.paidDebts;
            final overdueDebts= state.overdueDebts;

            // ── Accounting ─────────────────────────────────────────────────
            final svc          = AccountingService.instance;
            final gross        = svc.grossSales(orders);
            final discounts    = svc.totalDiscounts(orders);
            final netSales     = svc.netSales(orders);
            final customRev    = svc.customizedOrderRevenue(orders);
            final resellerSums = svc.resellerSummary(orders);
            final resellerDisc = resellerSums.fold(0.0, (s, r) => s + r.totalDiscount);
            final regularDisc  = discounts - resellerDisc;
            final discPct      = gross > 0 ? (discounts / gross * 100) : 0.0;

            // ── MoM ────────────────────────────────────────────────────────
            final now       = DateTime.now();
            final thisMonth = _revenueForMonth(orders, now);
            final lastMonth = _revenueForMonth(orders, DateTime(now.year, now.month - 1));
            final momPct    = lastMonth > 0
                ? ((thisMonth - lastMonth) / lastMonth * 100)
                : null;

            // ── Pie data ───────────────────────────────────────────────────
            final pieData = OrderStatus.values
                .where((s) => (statusMap[s] ?? 0) > 0)
                .map((s) => PieChartSectionData(
                      value: (statusMap[s] ?? 0).toDouble(),
                      color: _statusColor(s),
                      radius: 55,
                      title: '',
                    ))
                .toList();

            // ── Payment breakdown ──────────────────────────────────────────
            final pmRevenue = _paymentMethodCount(orders);

            // ── Aging ──────────────────────────────────────────────────────
            final agingBuckets = _utangAgingBuckets(unpaidDebts);

            // ── Heatmap ────────────────────────────────────────────────────
            final heatmap = _buildHeatmap(orders);

            // ── Trend ──────────────────────────────────────────────────────
            final trendPoints = _buildTrendData(orders);

            return AnimationLimiter(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: AnimationConfiguration.toStaggeredList(
                    duration: const Duration(milliseconds: 400),
                    childAnimationBuilder: (w) => SlideAnimation(
                      verticalOffset: 30,
                      child: KnzFadeIn(child: w),
                    ),
                    children: [
                      // ── Header ───────────────────────────────────────────
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

                      // ── MoM banner ───────────────────────────────────────
                      if (momPct != null)
                        _buildMomBanner(momPct, currency, thisMonth),
                      if (momPct != null) const SizedBox(height: 12),

                      // ── Core stat cards (original) ───────────────────────
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
                            StatCard(emoji: '💰', value: currency.format(state.totalRevenue),
                                label: 'TOTAL REVENUE', subtitle: 'Delivered + Utang paid',
                                subtitleColor: AppColors.gold),
                            StatCard(emoji: '💵', value: currency.format(state.deliveredRevenue),
                                label: 'DELIVERED REVENUE', subtitle: 'Delivered only',
                                subtitleColor: AppColors.success),
                            StatCard(emoji: '📦', value: state.totalOrders.toString(),
                                label: 'TOTAL ORDERS'),
                            StatCard(emoji: '✅', value: state.deliveredCount.toString(),
                                label: 'DELIVERED', subtitleColor: AppColors.success),
                            StatCard(
                                emoji: '🛍️',
                                value: state.orders
                                    .where((o) => o.status != OrderStatus.cancelled)
                                    .fold(0, (sum, o) => sum + o.quantity)
                                    .toString(),
                                label: 'ITEMS SOLD'),
                            StatCard(emoji: '💸', value: currency.format(state.totalUtangCollected),
                                label: 'TOTAL PAID', subtitle: 'Utang collected',
                                subtitleColor: AppColors.success),
                            StatCard(emoji: '💳', value: currency.format(totalDebt),
                                label: 'TOTAL UTANG',
                                subtitleColor: totalDebt > 0 ? AppColors.error : AppColors.success),
                            StatCard(emoji: '⏳', value: unpaidDebts.length.toString(),
                                label: 'UNPAID',
                                subtitleColor: unpaidDebts.isNotEmpty ? AppColors.warning : AppColors.success),
                            StatCard(emoji: '✅', value: paidDebts.length.toString(),
                                label: 'PAID', subtitleColor: AppColors.success),
                            StatCard(emoji: '🚨', value: overdueDebts.length.toString(),
                                label: 'OVERDUE',
                                subtitleColor: overdueDebts.isNotEmpty ? AppColors.error : AppColors.success),
                          ],
                        );
                      }),
                      const SizedBox(height: 16),

                      // ── NEW: Discount summary cards ──────────────────────
                      _buildDiscountSummary(currency, gross, discounts, netSales,
                          regularDisc, resellerDisc, discPct),
                      const SizedBox(height: 16),

                      // ── NEW: Custom orders revenue card ──────────────────
                      if (customRev > 0) ...[
                        _buildCustomOrdersCard(currency, customRev, orders),
                        const SizedBox(height: 16),
                      ],

                      // ── NEW: Revenue trend linechart ─────────────────────
                      _buildRevenueTrend(currency, trendPoints),
                      const SizedBox(height: 16),

                      // ── NEW: Payment method breakdown ────────────────────
                      _buildPaymentMethodBreakdown(currency, pmRevenue),
                      const SizedBox(height: 16),

                      // ── Utang breakdown (original) ───────────────────────
                      _buildUtangBreakdown(unpaidDebts, paidDebts, currency),
                      const SizedBox(height: 16),

                      // ── NEW: Utang aging analysis ────────────────────────
                      if (unpaidDebts.isNotEmpty) ...[
                        _buildUtangAging(agingBuckets),
                        const SizedBox(height: 16),
                      ],

                      // ── Orders by status + Top products (original) ────────
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
                            : Column(children: [content[0], content[1], content[2]]);
                      }),
                      const SizedBox(height: 16),

                      // ── NEW: Reseller performance ranking ────────────────
                      if (resellerSums.isNotEmpty) ...[
                        _buildResellerPerformance(currency, resellerSums),
                        const SizedBox(height: 16),
                      ],

                      // ── NEW: Sales heatmap ───────────────────────────────
                      _buildSalesHeatmap(heatmap),
                      const SizedBox(height: 24),
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

  // ── Month-over-month banner ───────────────────────────────────────────────
  Widget _buildMomBanner(double momPct, NumberFormat currency, double thisMonth) {
    final up      = momPct >= 0;
    final color   = up ? AppColors.success : AppColors.error;
    final arrow   = up ? '↑' : '↓';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(up ? Icons.trending_up : Icons.trending_down, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This month: ${currency.format(thisMonth)}  $arrow${momPct.abs().toStringAsFixed(1)}% vs last month',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  // ── Discount summary cards ────────────────────────────────────────────────
  Widget _buildDiscountSummary(NumberFormat currency, double gross,
      double discounts, double netSales, double regularDisc,
      double resellerDisc, double discPct) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🏷️', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Discount Summary',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, constraints) {
            final cols = constraints.maxWidth > 500 ? 3 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.4,
              children: [
                _MiniStatCard(label: 'GROSS SALES', value: currency.format(gross),
                    color: AppColors.whiteSecondary),
                _MiniStatCard(label: 'TOTAL DISCOUNTS', value: currency.format(discounts),
                    color: AppColors.warning),
                _MiniStatCard(label: 'NET SALES', value: currency.format(netSales),
                    color: AppColors.gold),
                _MiniStatCard(label: 'REGULAR DISC.', value: currency.format(regularDisc),
                    color: AppColors.info),
                _MiniStatCard(label: 'RESELLER DISC.', value: currency.format(resellerDisc),
                    color: Colors.purple.shade300),
                _MiniStatCard(
                    label: 'DISCOUNT %',
                    value: '${discPct.toStringAsFixed(1)}%',
                    color: discPct > 20 ? AppColors.error : AppColors.success),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Custom orders card ────────────────────────────────────────────────────
  Widget _buildCustomOrdersCard(NumberFormat currency, double customRev, List<Order> orders) {
    final customCount = orders.where((o) => o.orderType == 'customized' && o.status != OrderStatus.cancelled).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(children: [
        const Text('✨', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Custom Orders Revenue',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('$customCount customized orders',
                style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
          ]),
        ),
        Text(currency.format(customRev),
            style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
    );
  }

  // ── Revenue trend linechart ───────────────────────────────────────────────
  Widget _buildRevenueTrend(NumberFormat currency, List<_TrendPoint> points) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('📈', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Revenue Trend',
                  style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            // Toggle buttons
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TrendToggleBtn(label: 'Day',   active: _trendView == _TrendView.daily,
                      onTap: () => setState(() => _trendView = _TrendView.daily)),
                  _TrendToggleBtn(label: 'Week',  active: _trendView == _TrendView.weekly,
                      onTap: () => setState(() => _trendView = _TrendView.weekly)),
                  _TrendToggleBtn(label: 'Month', active: _trendView == _TrendView.monthly,
                      onTap: () => setState(() => _trendView = _TrendView.monthly)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (points.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No revenue data yet.',
                  style: TextStyle(color: AppColors.whiteTertiary))),
            )
          else
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: AppColors.cardBorder, strokeWidth: 0.5),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (val, meta) => Text(
                          '₱${(val / 1000).toStringAsFixed(0)}k',
                          style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: (points.length / 5).ceilToDouble().clamp(1, double.infinity),
                        getTitlesWidget: (val, meta) {
                          final i = val.toInt();
                          if (i < 0 || i >= points.length) return const SizedBox.shrink();
                          return Text(points[i].label,
                              style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 9));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: points.asMap().entries
                          .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                          .toList(),
                      isCurved: true,
                      color: AppColors.gold,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: points.length <= 14,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                            radius: 3, color: AppColors.gold, strokeWidth: 0),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.gold.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots.map((s) {
                        final i = s.x.toInt();
                        final label = (i >= 0 && i < points.length) ? points[i].label : '';
                        return LineTooltipItem(
                          '$label\n${currency.format(s.y)}',
                          const TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w600),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Payment method breakdown ──────────────────────────────────────────────
  Widget _buildPaymentMethodBreakdown(NumberFormat currency, Map<PaymentMethod, int> pmRevenue) {
    final total   = pmRevenue.values.fold(0, (s, v) => s + v);

    // Fixed color map per PaymentMethod — consistent, not index-based
    const pmColors = <PaymentMethod, Color>{
      PaymentMethod.cashOnDelivery  : AppColors.gold,
      PaymentMethod.gcash           : AppColors.info,
      PaymentMethod.creditDebitCard : Colors.purple,
      PaymentMethod.maya            : AppColors.success,
      PaymentMethod.utang           : Color(0xFFFF6D00),
    };

    // Sorted: used methods first, then zero-count ones
    final entries = pmRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Only used methods go into the pie (avoid invisible zero-slices)
    final usedEntries = entries.where((e) => e.value > 0).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(children: [
            const Text('💳', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Payment Method Breakdown',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.white,
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            if (total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
                ),
                child: Text('$total orders',
                    style: const TextStyle(color: AppColors.gold,
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 16),

          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No order data yet.',
                  style: TextStyle(color: AppColors.whiteTertiary))),
            )
          else
            Column(children: [
              // ── Donut chart (compact, centered) ───────────────────────────
              SizedBox(
                height: 150,
                child: PieChart(
                  PieChartData(
                    sections: usedEntries.map((e) {
                      final pct   = e.value / total;
                      final color = pmColors[e.key] ?? AppColors.gold;
                      // Only show label if slice is big enough to read
                      final label = pct >= 0.05
                          ? '${(pct * 100).toStringAsFixed(0)}%'
                          : '';
                      return PieChartSectionData(
                        value: e.value.toDouble(),
                        color: color,
                        radius: 48,
                        title: label,
                        titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                      );
                    }).toList(),
                    centerSpaceRadius: 36,
                    sectionsSpace: 2,
                    pieTouchData: PieTouchData(enabled: false),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Legend rows (all 5, used and unused) ──────────────────────
              ...entries.map((e) {
                final color   = pmColors[e.key] ?? AppColors.gold;
                final count   = e.value;
                final pct     = total > 0 ? count / total * 100.0 : 0.0;
                final hasData = count > 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        // Color dot
                        Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(
                            color: hasData ? color : AppColors.cardBorder,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Payment method name
                        Expanded(
                          child: Text(e.key.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: hasData
                                      ? AppColors.white
                                      : AppColors.whiteTertiary,
                                  fontSize: 13,
                                  fontWeight: hasData
                                      ? FontWeight.w500
                                      : FontWeight.w400)),
                        ),
                        // Count badge
                        if (hasData)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$count',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        // Percentage
                        SizedBox(
                          width: 42,
                          child: Text(
                            hasData ? '${pct.toStringAsFixed(1)}%' : '—',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                color: hasData ? color : AppColors.whiteTertiary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ]),
                      // Progress bar (only for used methods)
                      if (hasData) ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct / 100,
                            backgroundColor: AppColors.cardBorder,
                            valueColor: AlwaysStoppedAnimation(color),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ]),
        ],
      ),
    );
  }

  // ── Utang aging bar chart ─────────────────────────────────────────────────
  Widget _buildUtangAging(Map<String, int> buckets) {
    final maxVal = buckets.values.fold(0, (a, b) => a > b ? a : b).toDouble();
    final colors = [AppColors.success, AppColors.warning, const Color(0xFFFF6D00), AppColors.error];
    final keys   = ['0–7d', '8–30d', '31–60d', '60+d'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('⏱️', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Utang Aging Analysis',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            SizedBox(width: 8),
            Text('(unpaid debts)',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVal > 0 ? maxVal * 1.3 : 5,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: AppColors.cardBorder, strokeWidth: 0.5),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (val, _) => Text(
                      val.toInt().toString(),
                      style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (val, _) {
                      final i = val.toInt();
                      if (i < 0 || i >= keys.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(keys[i],
                            style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 10)),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: keys.asMap().entries.map((e) {
                final count = (buckets[e.value] ?? 0).toDouble();
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(
                    toY: count,
                    color: colors[e.key],
                    width: 20,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]);
              }).toList(),
            )),
          ),
        ],
      ),
    );
  }

  // ── Reseller performance ranking ──────────────────────────────────────────
  Widget _buildResellerPerformance(
      NumberFormat currency, List<ResellerAccountingSummary> sums) {
    final topNet      = sums.first;
    final topOrders   = [...sums]..sort((a, b) => b.totalOrders.compareTo(a.totalOrders));
    final topDiscount = [...sums]..sort((a, b) => b.totalDiscount.compareTo(a.totalDiscount));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🏅', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Reseller Performance',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (ctx, constraints) {
            // On narrow screens stack vertically; on wide screens use row
            final useRow = constraints.maxWidth >= 360;
            final cards = [
              _ResellerRankCard(
                emoji: '🥇', title: 'Top Earner',
                name: topNet.resellerName,
                value: currency.format(topNet.netRevenue),
                color: AppColors.gold,
              ),
              _ResellerRankCard(
                emoji: '📦', title: 'Most Orders',
                name: topOrders.first.resellerName,
                value: '${topOrders.first.totalOrders} orders',
                color: AppColors.info,
              ),
              _ResellerRankCard(
                emoji: '🏷️', title: 'Most Discount',
                name: topDiscount.first.resellerName,
                value: currency.format(topDiscount.first.totalDiscount),
                color: AppColors.warning,
              ),
            ];
            if (useRow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[2]),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cards[0],
                const SizedBox(height: 8),
                cards[1],
                const SizedBox(height: 8),
                cards[2],
              ],
            );
          }),
          const SizedBox(height: 14),
          // Full ranking list — scrollable when > 10 resellers
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: sums.length > 10 ? 420 : double.infinity,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: sums.length > 10
                  ? const ClampingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: sums.length,
              itemBuilder: (ctx, i) {
                final r   = sums[i];
                final pct = sums.first.netRevenue > 0
                    ? r.netRevenue / sums.first.netRevenue
                    : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        width: 22, height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Text('${i + 1}',
                            style: const TextStyle(color: AppColors.gold, fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.resellerName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.white, fontSize: 13))),
                      Text('${r.totalOrders}',
                          style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 11)),
                      const SizedBox(width: 4),
                      const Text('orders',
                          style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11)),
                      const SizedBox(width: 8),
                      Text(currency.format(r.netRevenue),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AppColors.cardBorder,
                        valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                        minHeight: 4,
                      ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Sales heatmap ─────────────────────────────────────────────────────────
  Widget _buildSalesHeatmap(List<List<int>> heatmap) {
    final maxVal = heatmap.expand((r) => r).fold(0, (a, b) => a > b ? a : b);
    final dows   = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // Show every 3 hours on x-axis
    const hourLabels = ['12a','3a','6a','9a','12p','3p','6p','9p'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('🔥', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Flexible(child: Text('Sales Heatmap',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15))),
            SizedBox(width: 8),
            Flexible(child: Text('(orders by day × hour)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12))),
          ]),
          const SizedBox(height: 12),
          // Hour labels
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Row(
              children: List.generate(8, (i) => Expanded(
                child: Text(hourLabels[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 8)),
              )),
            ),
          ),
          const SizedBox(height: 4),
          // Grid
          ...List.generate(7, (dow) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: Text(dows[dow],
                    style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 10)),
              ),
              ...List.generate(24, (hr) {
                final val  = heatmap[dow][hr];
                final intensity = maxVal > 0 ? val / maxVal : 0.0;
                return Expanded(
                  child: Container(
                    height: 14,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        AppColors.cardBorder,
                        AppColors.gold,
                        intensity,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ]),
          )),
          const SizedBox(height: 8),
          // Legend
          Row(children: [
            const SizedBox(width: 28),
            const Text('Low',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 9)),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.cardBorder, AppColors.gold]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text('High',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 9)),
          ]),
          if (maxVal == 0) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(child: Text('No order data yet.',
                  style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12))),
            ),
          ],
        ],
      ),
    );
  }

  // ── ORIGINAL WIDGETS (unchanged) ──────────────────────────────────────────

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
                        color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              const SizedBox(width: 8),
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
            ],
          ),
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
                                width: 8, height: 8,
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
                                        style: const TextStyle(color: AppColors.white,
                                            fontSize: 13, fontWeight: FontWeight.w500)),
                                    Row(children: [
                                      Text(d.orderId,
                                          style: const TextStyle(color: AppColors.gold, fontSize: 11)),
                                      const SizedBox(width: 8),
                                      Text('• ${dateFmt.format(d.createdAt)}',
                                          style: const TextStyle(
                                              color: AppColors.whiteTertiary, fontSize: 11)),
                                      if (d.isOverdue) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.error.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('${d.daysOld}d overdue',
                                              style: const TextStyle(color: AppColors.error,
                                                  fontSize: 9, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                      if (d.isPaid) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('PAID',
                                              style: TextStyle(color: AppColors.success,
                                                  fontSize: 9, fontWeight: FontWeight.w700)),
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
                                          color: AppColors.whiteTertiary, fontSize: 10)),
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
                                  pct >= 1.0 ? AppColors.success : AppColors.gold),
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
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 20),
          if (pieData.isNotEmpty)
            SizedBox(
              height: 160,
              child: PieChart(PieChartData(
                sections: pieData,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              )),
            ),
          const SizedBox(height: 20),
          ...OrderStatus.values.map((s) {
            final count = statusMap[s] ?? 0;
            final pct = totalOrders > 0 ? count / totalOrders : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(children: [
                Row(children: [
                  Icon(_statusIcon(s), color: _statusColor(s), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.displayName,
                        style: const TextStyle(color: AppColors.white, fontSize: 13)),
                  ),
                  Text('$count (${(pct * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
                ]),
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
              ]),
            );
          }),
        ],
      ),
    );
  }

  IconData _statusIcon(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:    return Icons.hourglass_empty;
      case OrderStatus.processing: return Icons.sync;
      case OrderStatus.shipped:    return Icons.local_shipping_outlined;
      case OrderStatus.delivered:  return Icons.check_circle_outline;
      case OrderStatus.cancelled:  return Icons.cancel_outlined;
      case OrderStatus.utang:      return Icons.account_balance_wallet_outlined;
    }
  }

  Widget _buildTopProducts(List<_ProductSalesData> topProducts) {
    final maxSales = topProducts.isNotEmpty ? topProducts.first.total.toDouble() : 1.0;
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
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
            Text('Top Products',
                style: TextStyle(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            SizedBox(width: 8),
            Text('(All Time)',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          if (topProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No sales data yet.',
                  style: TextStyle(color: AppColors.whiteTertiary))),
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
                        child: Column(children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              if (isExpanded) { _expandedProducts.remove(data.name); }
                              else { _expandedProducts.add(data.name); }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(children: [
                                Container(
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text('${i + 1}',
                                      style: const TextStyle(color: AppColors.gold,
                                          fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(data.name,
                                    style: const TextStyle(color: AppColors.white,
                                        fontWeight: FontWeight.w600, fontSize: 13))),
                                // NEW: revenue tag
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.gold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(currency.format(data.revenue),
                                      style: const TextStyle(color: AppColors.gold,
                                          fontSize: 9, fontWeight: FontWeight.w600)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('${data.total} SOLD',
                                      style: const TextStyle(color: AppColors.success,
                                          fontSize: 10, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 8),
                                AnimatedRotation(
                                  turns: isExpanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: const Icon(Icons.keyboard_arrow_down,
                                      color: AppColors.whiteTertiary, size: 18),
                                ),
                              ]),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: AppColors.inputFill,
                                valueColor: const AlwaysStoppedAnimation(AppColors.success),
                                minHeight: 5,
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox.shrink(),
                            secondChild: Column(children: [
                              const Divider(color: AppColors.divider, height: 1),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: data.byDay.map((day) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      child: Row(children: [
                                        const Icon(Icons.calendar_today_outlined,
                                            size: 12, color: AppColors.whiteTertiary),
                                        const SizedBox(width: 8),
                                        Text(day.key,
                                            style: const TextStyle(
                                                color: AppColors.whiteSecondary, fontSize: 12)),
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
                                          child: Text('${day.value} sold',
                                              style: const TextStyle(color: AppColors.gold,
                                                  fontSize: 11, fontWeight: FontWeight.w600)),
                                        ),
                                      ]),
                                    )).toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                            ]),
                            crossFadeState: isExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 250),
                          ),
                        ]),
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

// ── Helper data classes ───────────────────────────────────────────────────────
class _ProductSalesData {
  final String name;
  final int    total;
  final double revenue;
  final List<MapEntry<String, int>> byDay;

  _ProductSalesData({
    required this.name,
    required this.total,
    required this.revenue,
    required this.byDay,
  });
}

class _TrendPoint {
  final String label;
  final double value;
  _TrendPoint({required this.label, required this.value});
}

// ── Small reusable sub-widgets ────────────────────────────────────────────────
class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;

  const _MiniStatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.whiteTertiary,
                  fontSize: 9, letterSpacing: 0.8),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _TrendToggleBtn extends StatelessWidget {
  final String label;
  final bool   active;
  final VoidCallback onTap;

  const _TrendToggleBtn({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.gold.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active ? Border.all(color: AppColors.gold.withValues(alpha: 0.4)) : null,
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? AppColors.gold : AppColors.whiteTertiary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}

class _ResellerRankCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String name;
  final String value;
  final Color  color;

  const _ResellerRankCard({
    required this.emoji, required this.title,
    required this.name,  required this.value, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(title,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text(name,
              style: const TextStyle(color: AppColors.white, fontSize: 12,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          Text(value,
              style: TextStyle(color: color, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}