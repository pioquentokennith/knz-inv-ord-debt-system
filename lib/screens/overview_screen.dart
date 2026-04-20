import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state_builder.dart'; // ← FIX 6
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  // FIX 6: No _state, no addListener, no _onStateChange — removed.

  // State para sa collapse/expand ng Recent Activity
  bool _isActivityExpanded = true;

  // ✅ Filter state
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
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    // FIX 6: Wrap entire scrollable body in AppStateBuilder so only it rebuilds
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AppStateBuilder(
        builder: (context, state) => AnimationLimiter(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: AnimationConfiguration.toStaggeredList(
              duration: const Duration(milliseconds: 400),
              childAnimationBuilder: (widget) => SlideAnimation(
                verticalOffset: 30,
                child: FadeInAnimation(child: widget),
              ),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_greeting()}, ${state.currentUser?.displayName ?? "Admin"} 👑',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '${AppStrings.appName} Admin Dashboard',
                            style: TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Text(dateStr,
                        style: const TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 28),

                // Stats Grid
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
                    StatCard(
                      emoji: '💰',
                      value: currency.format(state.totalRevenue),
                      label: AppStrings.totalRevenue,
                      subtitle: '${state.deliveredCount} delivered',
                      subtitleColor: AppColors.success,
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
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards[2]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[3]),
                          ],
                        ),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 24),

                // Low Stock
                Container(
                  padding: const EdgeInsets.all(20),
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
                      const SizedBox(height: 16),
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
                              padding:
                                  const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: const TextStyle(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.w600),
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
                                              fontSize: 16)),
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
                const SizedBox(height: 20),

                // ✅ Recent Activity na may Collapse/Expand + Filter
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header toggle (walang badge)
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
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '🕐 Recent Activity',
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Arrow icon na nag-rotate
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

                      // Animated expand/collapse
                      AnimatedCrossFade(
                        firstChild: Padding(
                          padding: const EdgeInsets.only(
                              left: 20, right: 20, bottom: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(
                                  color: AppColors.cardBorder, height: 1),
                              const SizedBox(height: 12),

                              // ✅ Filter buttons
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
                                        duration:
                                            const Duration(milliseconds: 200),
                                        margin:
                                            const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
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
                              const SizedBox(height: 12),

                              // ✅ Filtered logs
                              Builder(builder: (_) {
                                final filtered = _selectedFilter == 'All'
                                    ? state.activityLogs
                                    : state.activityLogs.where((log) =>
                                        log.type ==
                                        _filterType(_selectedFilter)).toList();

                                if (filtered.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    child: Text(
                                      'No activity found',
                                      style: TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 13),
                                    ),
                                  );
                                }

                                return Column(
                                  children: filtered.take(8).map((log) =>
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              margin: const EdgeInsets.only(
                                                  top: 5, right: 12),
                                              decoration: BoxDecoration(
                                                color: _logColor(log.type),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                log.message,
                                                style: const TextStyle(
                                                    color:
                                                        AppColors.whiteSecondary,
                                                    fontSize: 13),
                                              ),
                                            ),
                                            Text(
                                              log.timeAgo,
                                              style: const TextStyle(
                                                  color:
                                                      AppColors.whiteTertiary,
                                                  fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      )).toList(),
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
              ],
            ),
          ),
        ),
      ),
        ),
    );
  }

  // I-map ang filter label sa log.type value
  String _filterType(String filter) {
    switch (filter) {
      case 'Auth':
        return 'auth';
      case 'Orders':
        return 'order';
      case 'Payments/Utang':
        return 'payment';
      case 'Products/Stock':
        return 'product';
      default:
        return '';
    }
  }

  // ✅ Kulay ng bawat filter button
  Color _filterColor(String filter) {
    switch (filter) {
      case 'Auth':
        return AppColors.info;
      case 'Orders':
        return AppColors.success;
      case 'Payments/Utang':
        return AppColors.warning;
      case 'Products/Stock':
        return AppColors.gold;
      default:
        return AppColors.whiteTertiary;
    }
  }


  Color _logColor(String type) {
    switch (type) {
      case 'auth':
        return AppColors.info;
      case 'product':
        return AppColors.gold;
      case 'order':
        return AppColors.success;
      case 'stock':
        return AppColors.warning;
      default:
        return AppColors.whiteTertiary;
    }
  }
}
