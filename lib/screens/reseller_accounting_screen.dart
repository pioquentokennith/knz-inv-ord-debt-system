// ─────────────────────────────────────────────────────────────────────────────
// reseller_accounting_screen.dart — Per-reseller sales + discount breakdown
// Purpose : Shows each reseller's total orders, gross sales, discounts given,
//           and net revenue contributed to KNZ Scent.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/reseller_accounting_summary.dart';
import '../core/money.dart';
import '../services/accounting_service.dart';

class ResellerAccountingScreen extends StatelessWidget {
  const ResellerAccountingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) {
        final orders = AppState().orders.toList();
        final summaries = AccountingService.instance.resellerSummary(orders);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                if (summaries.isEmpty)
                  _buildEmpty()
                else ...[
                  _buildGlobalRow(summaries),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: summaries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _ResellerSummaryCard(summary: summaries[i]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: const Row(
        children: [
          Icon(Icons.people_outline, color: AppColors.gold, size: 22),
          SizedBox(width: 10),
          Text(
            'Reseller Accounting',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalRow(List<ResellerAccountingSummary> summaries) {
    final grossTotal = summaries.fold(Money.zero, (s, r) => s + r.grossSales);
    final discountTotal = summaries.fold(
      Money.zero,
      (s, r) => s + r.totalDiscount,
    );
    final netTotal = summaries.fold(Money.zero, (s, r) => s + r.netRevenue);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _StatMini(
            label: 'Gross',
            value: grossTotal.format(),
            color: AppColors.whiteSecondary,
          ),
          const SizedBox(width: 16),
          _StatMini(
            label: 'Discount',
            value: discountTotal.format(),
            color: AppColors.warning,
          ),
          const SizedBox(width: 16),
          _StatMini(
            label: 'Net',
            value: netTotal.format(),
            color: AppColors.gold,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              color: AppColors.whiteTertiary,
              size: 56,
            ),
            SizedBox(height: 12),
            Text(
              'No reseller orders yet',
              style: TextStyle(color: AppColors.whiteSecondary, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Reseller-flagged orders will appear here',
              style: TextStyle(color: AppColors.whiteTertiary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResellerSummaryCard extends StatelessWidget {
  final ResellerAccountingSummary summary;
  const _ResellerSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                child: Text(
                  summary.resellerName[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.resellerName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${summary.totalOrders} order${summary.totalOrders == 1 ? '' : 's'} · '
                      '−₱${summary.averageDeduction.toStringAsFixed(0)}/item avg',
                      style: const TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Net revenue badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  summary.netRevenue.format(),
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),

          // ── Metrics ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _MetricItem(
                  label: 'Gross Sales',
                  value: summary.grossSales.format(),
                  color: AppColors.whiteSecondary,
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: 'Total Discount',
                  value: summary.totalDiscount.format(),
                  color: AppColors.warning,
                ),
              ),
              Expanded(
                child: _MetricItem(
                  label: 'Net Revenue',
                  value: summary.netRevenue.format(),
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.whiteTertiary,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatMini({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.whiteTertiary,
            fontSize: 10,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
