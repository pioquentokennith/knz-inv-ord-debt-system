// ─────────────────────────────────────────────────────────────────────────────
// overview_screen.dart  — RESPONSIVE FIX: no overflow on any Android device
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state_builder.dart';
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  bool _isActivityExpanded = true;
  String _selectedFilter = 'All';
  final List<String> _filterOptions = [
    'All',
    'Auth',
    'Orders',
    'Payments/Utang',
    'Products/Stock',
  ];

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEE, MMM d, yyyy').format(DateTime.now());
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AppStateBuilder(
          builder: (context, state) => AnimationLimiter(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: AnimationConfiguration.toStaggeredList(
                  duration: const Duration(milliseconds: 400),
                  childAnimationBuilder: (widget) => SlideAnimation(
                    verticalOffset: 30,
                    child: FadeInAnimation(child: widget),
                  ),
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_greeting()}, ${state.currentUser?.displayName ?? "Admin"} 👑',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '${AppStrings.appName} Admin Dashboard',
                                style: TextStyle(
                                    color: AppColors.whiteTertiary,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(dateStr,
                                style: const TextStyle(
                                    color: AppColors.whiteTertiary,
                                    fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Stats Grid ──────────────────────────────────────
                    LayoutBuilder(builder: (ctx, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      final cards = [
                        StatCard(
                          emoji: '🧴',
                          value: state.totalProducts.toString(),
                          label: AppStrings.totalProducts,
                          subtitle: '▲ Active SKUs',
                          subtitleColor: AppColors.success,
                        ),
                        StatCard(
                          emoji: '📊',
                          value: state.totalStock.toString(),
                          label: 'TOTAL STOCKS',
                          subtitle: 'All items combined',
                          subtitleColor: AppColors.info,
                        ),
                        StatCard(
                          emoji: '📦',
                          value: state.totalOrders.toString(),
                          label: AppStrings.totalOrders,
                          subtitle: '${state.pendingCount} pending',
                          subtitleColor: AppColors.warning,
                        ),
                        StatCard(
                          emoji: '⚠️',
                          value: state.lowStockCount.toString(),
                          label: AppStrings.lowStockItems,
                          subtitle: 'Needs restocking',
                          subtitleColor: AppColors.error,
                        ),
                      ];
                      if (isWide) {
                        return Row(
                          children: cards
                              .map((c) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: c,
                                    ),
                                  ))
                              .toList(),
                        );
                      }
                      return Column(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: 10),
                                Expanded(child: cards[1]),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: cards[2]),
                                const SizedBox(width: 10),
                                Expanded(child: cards[3]),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: StatCard(
                                    emoji: '💰',
                                    value: currency.format(state.totalRevenue),
                                    label: AppStrings.totalRevenue,
                                    subtitle: '${state.deliveredCount} delivered and utang',
                                    subtitleColor: AppColors.success,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: StatCard(
                                    emoji: '💵',
                                    value: currency.format(state.deliveredRevenue),
                                    label: 'DELIVERED REVENUE',
                                    subtitle: 'Delivered orders only',
                                    subtitleColor: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 20),

                    // ── Low Stock ───────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(
                            title: '⚠️ ${AppStrings.lowStockAlerts}',
                            trailing: '${state.lowStockCount} ITEMS',
                          ),
                          const SizedBox(height: 14),
                          if (state.lowStockProducts.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('All products well stocked! 🎉',
                                  style: TextStyle(
                                      color: AppColors.success,
                                      fontSize: 14)),
                            )
                          else
                            ...state.lowStockProducts.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.name,
                                          style: const TextStyle(
                                              color: AppColors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          CategoryBadge(label: p.category.shortName),
                                          const SizedBox(width: 8),
                                          Text(p.stockQty.toString(),
                                              style: const TextStyle(
                                                  color: AppColors.warning,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15)),
                                          const SizedBox(width: 8),
                                          const StockBadge(isLowStock: true),
                                        ],
                                      ),
                                    ],
                                  ),
                                )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Recent Activity ─────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _isActivityExpanded = !_isActivityExpanded;
                              });
                            },
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(
                                  _isActivityExpanded ? 0 : 12),
                              bottomRight: Radius.circular(
                                  _isActivityExpanded ? 0 : 12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      '🕐 Recent Activity',
                                      style: TextStyle(
                                        color: AppColors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: _isActivityExpanded ? 0 : -0.5,
                                    duration: const Duration(milliseconds: 300),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: AppColors.whiteTertiary,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 16, bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(
                                      color: AppColors.cardBorder, height: 1),
                                  const SizedBox(height: 10),
                                  // Filter chips
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: _filterOptions.map((filter) {
                                        final isSelected =
                                            _selectedFilter == filter;
                                        return GestureDetector(
                                          onTap: () => setState(
                                              () => _selectedFilter = filter),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 200),
                                            margin: const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? _filterColor(filter)
                                                      .withValues(alpha: 0.2)
                                                  : AppColors.cardBorder
                                                      .withValues(alpha: 0.3),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: isSelected
                                                    ? _filterColor(filter)
                                                    : AppColors.cardBorder,
                                                width: isSelected ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Text(
                                              filter,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? _filterColor(filter)
                                                    : AppColors.whiteTertiary,
                                                fontSize: 11,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Filtered logs
                                  Builder(builder: (_) {
                                    final filtered = _selectedFilter == 'All'
                                        ? state.activityLogs
                                        : state.activityLogs
                                            .where((log) =>
                                                log.type ==
                                                _filterType(_selectedFilter))
                                            .toList();

                                    if (filtered.isEmpty) {
                                      return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'No activity found',
                                          style: TextStyle(
                                              color: AppColors.whiteTertiary,
                                              fontSize: 13),
                                        ),
                                      );
                                    }

                                    return ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxHeight: 280,
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: filtered.length,
                                        itemBuilder: (_, idx) {
                                          final log = filtered[idx];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 10),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  margin: const EdgeInsets.only(
                                                      top: 5, right: 10),
                                                  decoration: BoxDecoration(
                                                    color: _logColor(log.type),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    log.message,
                                                    style: const TextStyle(
                                                        color: AppColors
                                                            .whiteSecondary,
                                                        fontSize: 12),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  log.timeAgo,
                                                  style: const TextStyle(
                                                      color: AppColors
                                                          .whiteTertiary,
                                                      fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            secondChild: const SizedBox.shrink(),
                            crossFadeState: _isActivityExpanded
                                ? CrossFadeState.showFirst
                                : CrossFadeState.showSecond,
                            duration: const Duration(milliseconds: 300),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _filterType(String filter) {
    switch (filter) {
      case 'Auth': return 'auth';
      case 'Orders': return 'order';
      case 'Payments/Utang': return 'payment';
      case 'Products/Stock': return 'product';
      default: return '';
    }
  }

  Color _filterColor(String filter) {
    switch (filter) {
      case 'Auth': return AppColors.info;
      case 'Orders': return AppColors.success;
      case 'Payments/Utang': return AppColors.warning;
      case 'Products/Stock': return AppColors.gold;
      default: return AppColors.whiteTertiary;
    }
  }

  Color _logColor(String type) {
    switch (type) {
      case 'auth': return AppColors.info;
      case 'product': return AppColors.gold;
      case 'order': return AppColors.success;
      case 'stock': return AppColors.warning;
      default: return AppColors.whiteTertiary;
    }
  }
}
