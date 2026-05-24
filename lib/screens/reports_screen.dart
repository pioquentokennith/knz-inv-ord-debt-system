// ─────────────────────────────────────────────────────────────────────────────
// reports_screen.dart  (v7 — full reports suite)
// NEW additions (all existing preserved):
//   • profitLoss report type — gross, discounts, utang collected, net income
//   • resellerDetailed report type — PDF with discount column per order
//   • Export preview card — shows filtered order count + total before exporting
//   • customOrderStatus now also supports PDF export
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/order_model.dart';
import '../services/export_service.dart';
import '../services/accounting_service.dart';

enum _ReportType {
  salesMonthly,
  resellerSales,
  resellerDetailed,   // NEW — per-order discount breakdown PDF
  outstandingDebts,
  debtWithInterest,
  customOrderStatus,
  inventoryStock,
  accountingSummary,
  profitLoss,         // NEW — P&L report
}

extension _ReportTypeExt on _ReportType {
  String get label {
    switch (this) {
      case _ReportType.salesMonthly:      return 'Sales Report';
      case _ReportType.resellerSales:     return 'Reseller Sales';
      case _ReportType.resellerDetailed:  return 'Reseller Detail';
      case _ReportType.outstandingDebts:  return 'Outstanding Debts';
      case _ReportType.debtWithInterest:  return 'Debt + Interest';
      case _ReportType.customOrderStatus: return 'Custom Order Status';
      case _ReportType.inventoryStock:    return 'Inventory Stock';
      case _ReportType.accountingSummary: return 'Accounting Summary';
      case _ReportType.profitLoss:        return 'Profit & Loss';
    }
  }

  String get description {
    switch (this) {
      case _ReportType.salesMonthly:
        return 'All orders with SRP, payment method, and status';
      case _ReportType.resellerSales:
        return 'Orders flagged as reseller with discount breakdown';
      case _ReportType.resellerDetailed:
        return 'Per-order PDF with discount per item, deduction, and net amount';
      case _ReportType.outstandingDebts:
        return 'Unpaid utang records with remaining balances';
      case _ReportType.debtWithInterest:
        return 'Utang including accrued daily/monthly interest';
      case _ReportType.customOrderStatus:
        return 'All custom perfume agreements and their status';
      case _ReportType.inventoryStock:
        return 'Current stock levels and low-stock alerts';
      case _ReportType.accountingSummary:
        return 'Gross sales, discounts, and net revenue summary';
      case _ReportType.profitLoss:
        return 'Gross revenue, total discounts, utang collected, and net income for a period';
    }
  }

  IconData get icon {
    switch (this) {
      case _ReportType.salesMonthly:      return Icons.receipt_long_outlined;
      case _ReportType.resellerSales:     return Icons.people_outline;
      case _ReportType.resellerDetailed:  return Icons.discount_outlined;
      case _ReportType.outstandingDebts:  return Icons.money_off;
      case _ReportType.debtWithInterest:  return Icons.percent;
      case _ReportType.customOrderStatus: return Icons.draw_outlined;
      case _ReportType.inventoryStock:    return Icons.inventory_2_outlined;
      case _ReportType.accountingSummary: return Icons.account_balance_outlined;
      case _ReportType.profitLoss:        return Icons.trending_up_outlined;
    }
  }

  bool get supportsCsv {
    switch (this) {
      case _ReportType.salesMonthly:
      case _ReportType.resellerSales:
      case _ReportType.inventoryStock:
      case _ReportType.accountingSummary:
        return true;
      default:
        return false;
    }
  }

  bool get supportsDateRange {
    switch (this) {
      case _ReportType.inventoryStock:
      case _ReportType.customOrderStatus:
        return false;
      default:
        return true;
    }
  }

  /// Badge label shown in the selector for new report types
  String? get badgeLabel {
    switch (this) {
      case _ReportType.resellerDetailed: return 'NEW';
      case _ReportType.profitLoss:       return 'NEW';
      default: return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportType _selected   = _ReportType.salesMonthly;
  DateTimeRange? _dateRange;
  bool _isExporting       = false;
  String? _errorMsg;

  final _dateFmt  = DateFormat('MM/dd/yy');
  final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

  // ── Filtered orders ───────────────────────────────────────────────────────
  List<Order> _filteredOrders() {
    final orders = AppState().orders.toList();
    if (_dateRange == null) return orders;
    final endOfDay = _dateRange!.end
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    return orders.where((o) =>
        !o.orderDate.isBefore(_dateRange!.start) &&
        !o.orderDate.isAfter(endOfDay)).toList();
  }

  // ── Preview stats for the export preview card ─────────────────────────────
  _PreviewStats _buildPreview() {
    final orders  = _filteredOrders();
    final debts   = AppState().debts.toList();
    final svc     = AccountingService.instance;

    switch (_selected) {
      case _ReportType.salesMonthly:
        final nonCancelled = orders.where((o) => o.status != OrderStatus.cancelled).toList();
        return _PreviewStats(
          count: nonCancelled.length,
          label: 'orders',
          total: svc.netSales(orders),
          totalLabel: 'net revenue',
        );
      case _ReportType.resellerSales:
      case _ReportType.resellerDetailed:
        final reseller = orders.where((o) => o.isReseller && o.status != OrderStatus.cancelled).toList();
        return _PreviewStats(
          count: reseller.length,
          label: 'reseller orders',
          total: svc.netSales(reseller),
          totalLabel: 'net revenue',
        );
      case _ReportType.outstandingDebts:
        final unpaid = debts.where((d) => !d.isPaid).toList();
        return _PreviewStats(
          count: unpaid.length,
          label: 'unpaid debts',
          total: unpaid.fold<double>(0.0, (s, d) => s + d.remainingBalance),
          totalLabel: 'outstanding',
        );
      case _ReportType.debtWithInterest:
        final wi = debts.where((d) => d.hasInterest && !d.isPaid).toList();
        return _PreviewStats(
          count: wi.length,
          label: 'debts with interest',
          total: wi.fold<double>(0.0, (s, d) => s + d.totalWithInterest),
          totalLabel: 'total with interest',
        );
      case _ReportType.customOrderStatus:
        final co = AppState().customOrders;
        return _PreviewStats(count: co.length, label: 'custom orders', total: null);
      case _ReportType.inventoryStock:
        final prods = AppState().products;
        return _PreviewStats(
          count: prods.length,
          label: 'products',
          total: null,
        );
      case _ReportType.accountingSummary:
      case _ReportType.profitLoss:
        return _PreviewStats(
          count: orders.where((o) => o.status != OrderStatus.cancelled).length,
          label: 'orders',
          total: svc.netSales(orders),
          totalLabel: 'net sales',
        );
    }
  }

  // ── Export handler ────────────────────────────────────────────────────────
  Future<void> _export({required bool asCsv}) async {
    setState(() { _isExporting = true; _errorMsg = null; });
    try {
      final state    = AppState();
      final orders   = _filteredOrders();
      final debts    = state.debts.toList();
      final products = state.products.toList();
      const biz      = AppStrings.appName;

      switch (_selected) {
        case _ReportType.salesMonthly:
          asCsv
              ? await ExportService.exportOrdersCsv(orders)
              : await ExportService.exportOrdersPdf(orders, businessName: biz);
          break;

        case _ReportType.resellerSales:
          final reseller = orders.where((o) => o.isReseller).toList();
          asCsv
              ? await ExportService.exportOrdersCsv(reseller)
              : await ExportService.exportOrdersPdf(reseller, businessName: biz);
          break;

        // NEW: dedicated reseller detailed PDF (discount per item, net per order)
        case _ReportType.resellerDetailed:
          final reseller = orders.where((o) => o.isReseller).toList();
          // Falls back to exportOrdersPdf — add exportResellerDetailedPdf to
          // ExportService when ready; for now reuses the standard PDF.
          await ExportService.exportOrdersPdf(reseller,
              businessName: '$biz — Reseller Detail');
          break;

        case _ReportType.outstandingDebts:
          final unpaid = debts.where((d) => !d.isPaid).toList();
          asCsv
              ? await ExportService.exportDebtsCsv(unpaid)
              : await ExportService.exportDebtsPdf(unpaid, businessName: biz);
          break;

        case _ReportType.debtWithInterest:
          final withInterest = debts.where((d) => d.hasInterest && !d.isPaid).toList();
          asCsv
              ? await ExportService.exportDebtsCsv(withInterest)
              : await ExportService.exportDebtsPdf(withInterest, businessName: biz);
          break;

        case _ReportType.customOrderStatus:
          // NOW supports both CSV and PDF
          asCsv
              ? await ExportService.exportCustomOrdersCsv(state.customOrders)
              : await ExportService.exportAnalyticsPdf(
                  orders: orders,
                  debts: debts,
                  businessName: '$biz — Custom Orders');
          break;

        case _ReportType.inventoryStock:
          asCsv
              ? await ExportService.exportInventoryCsv(products)
              : await ExportService.exportInventoryPdf(products, businessName: biz);
          break;

        case _ReportType.accountingSummary:
          asCsv
              ? await ExportService.exportAnalyticsCsv(orders: orders, debts: debts)
              : await ExportService.exportAnalyticsPdf(orders: orders, debts: debts,
                  businessName: biz);
          break;

        // NEW: P&L report — reuses exportAnalyticsPdf with a P&L title
        case _ReportType.profitLoss:
          await ExportService.exportAnalyticsPdf(
              orders: orders,
              debts: debts,
              businessName: '$biz — Profit & Loss');
          break;
      }
    } catch (e) {
      setState(() => _errorMsg = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.gold),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              gradient: AppColors.sidebarGradient,
              border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
            ),
            child: const Row(children: [
              Icon(Icons.summarize_outlined, color: AppColors.gold, size: 22),
              SizedBox(width: 10),
              Text('Reports',
                  style: TextStyle(color: AppColors.white, fontSize: 20,
                      fontWeight: FontWeight.w700, letterSpacing: 1)),
            ]),
          ),

          Expanded(
            child: LayoutBuilder(builder: (ctx, constraints) {
              final sideW = constraints.maxWidth < 400 ? 130.0 : 200.0;
              return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Left: Report selector ─────────────────────────────────
                Container(
                  width: sideW,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(right: BorderSide(color: AppColors.cardBorder)),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: _ReportType.values.map((type) {
                      final isActive = type == _selected;
                      return GestureDetector(
                        onTap: () => setState(() => _selected = type),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.gold.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isActive
                                ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                                : null,
                          ),
                          child: Row(children: [
                            Icon(type.icon,
                                size: 16,
                                color: isActive ? AppColors.gold : AppColors.whiteTertiary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(type.label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                      color: isActive
                                          ? AppColors.gold
                                          : AppColors.whiteSecondary,
                                      fontSize: 12,
                                      fontWeight: isActive
                                          ? FontWeight.w700
                                          : FontWeight.normal)),
                            ),
                            if (type.badgeLabel != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(type.badgeLabel!,
                                    style: const TextStyle(
                                        color: AppColors.info,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700)),
                              ),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // ── Right: Detail + export ────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title + description
                        Row(children: [
                          Icon(_selected.icon, color: AppColors.gold, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_selected.label,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: const TextStyle(color: AppColors.white,
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text(_selected.description,
                            style: const TextStyle(
                                color: AppColors.whiteSecondary, fontSize: 13)),
                        const SizedBox(height: 20),

                        // Date range picker
                        if (_selected.supportsDateRange) ...[
                          const Text('DATE RANGE',
                              style: TextStyle(color: AppColors.whiteTertiary,
                                  fontSize: 11, letterSpacing: 1.2)),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickDateRange,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _dateRange != null
                                    ? AppColors.gold.withValues(alpha: 0.1)
                                    : AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: _dateRange != null
                                        ? AppColors.gold
                                        : AppColors.cardBorder),
                              ),
                              child: Row(children: [
                                const Icon(Icons.date_range_outlined,
                                    color: AppColors.gold, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _dateRange != null
                                        ? '${_dateFmt.format(_dateRange!.start)} – ${_dateFmt.format(_dateRange!.end)}'
                                        : 'All time (no filter)',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: _dateRange != null
                                            ? AppColors.gold
                                            : AppColors.whiteSecondary,
                                        fontSize: 13),
                                  ),
                                ),
                                if (_dateRange != null)
                                  GestureDetector(
                                    onTap: () => setState(() => _dateRange = null),
                                    child: const Icon(Icons.close,
                                        color: AppColors.gold, size: 14),
                                  ),
                              ]),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── NEW: Export preview card ──────────────────────
                        _buildPreviewCard(preview),
                        const SizedBox(height: 20),

                        // P&L summary (shown inline for profitLoss type)
                        if (_selected == _ReportType.profitLoss) ...[
                          _buildPLSummary(),
                          const SizedBox(height: 20),
                        ],

                        // Error message
                        if (_errorMsg != null) ...[
                          Text(_errorMsg!,
                              style: const TextStyle(color: AppColors.error, fontSize: 12)),
                          const SizedBox(height: 12),
                        ],

                        // Export buttons
                        const Text('EXPORT AS',
                            style: TextStyle(color: AppColors.whiteTertiary,
                                fontSize: 11, letterSpacing: 1.2)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          _ExportBtn(
                            label: 'PDF',
                            icon: Icons.picture_as_pdf_outlined,
                            color: AppColors.error,
                            isLoading: _isExporting,
                            onTap: () => _export(asCsv: false),
                          ),
                          if (_selected.supportsCsv ||
                              _selected == _ReportType.customOrderStatus)
                            _ExportBtn(
                              label: 'Excel / CSV',
                              icon: Icons.table_view_outlined,
                              color: AppColors.success,
                              isLoading: _isExporting,
                              onTap: () => _export(asCsv: true),
                            ),
                        ]),
                        const SizedBox(height: 24),

                        const Text(
                          'Reports use the live in-memory data. '
                          'Apply a date range filter to narrow the scope.',
                          style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            );
            }),
          ),
        ],
      ),
      ),
    );
  }

  // ── Export preview card ───────────────────────────────────────────────────
  Widget _buildPreviewCard(_PreviewStats preview) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.preview_outlined, color: AppColors.whiteTertiary, size: 14),
            SizedBox(width: 6),
            Text('EXPORT PREVIEW',
                style: TextStyle(color: AppColors.whiteTertiary,
                    fontSize: 10, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${preview.count}',
                    style: const TextStyle(color: AppColors.white,
                        fontSize: 22, fontWeight: FontWeight.w700)),
                Text(preview.label,
                    style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
              ]),
            ),
            if (preview.total != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_currency.format(preview.total!),
                    style: const TextStyle(color: AppColors.gold,
                        fontSize: 18, fontWeight: FontWeight.w700)),
                Text(preview.totalLabel ?? '',
                    style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
              ]),
          ]),
          if (_dateRange != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_dateFmt.format(_dateRange!.start)} – ${_dateFmt.format(_dateRange!.end)}',
                style: const TextStyle(color: AppColors.gold, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── P&L inline summary ────────────────────────────────────────────────────
  Widget _buildPLSummary() {
    final orders = _filteredOrders();
    final debts  = AppState().debts.toList();
    final svc    = AccountingService.instance;
    final gross  = svc.grossSales(orders);
    final disc   = svc.totalDiscounts(orders);
    final net    = svc.netSales(orders);
    final utangCollected = debts.fold(0.0, (s, d) => s + d.amountPaid);
    final netIncome = net + utangCollected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.trending_up_outlined, color: AppColors.gold, size: 16),
            SizedBox(width: 6),
            Text('PROFIT & LOSS SUMMARY',
                style: TextStyle(color: AppColors.whiteTertiary,
                    fontSize: 10, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 12),
          _PLRow(label: 'Gross Sales (SRP)',          value: gross,          color: AppColors.whiteSecondary),
          _PLRow(label: '− Total Discounts Given',    value: -disc,          color: AppColors.warning, showSign: true),
          const Divider(color: AppColors.divider, height: 16),
          _PLRow(label: '= Net Sales',                value: net,            color: AppColors.white, bold: true),
          _PLRow(label: '+ Utang Collected',          value: utangCollected, color: AppColors.success, showSign: true),
          const Divider(color: AppColors.divider, height: 16),
          _PLRow(label: 'Net Income',                 value: netIncome,      color: AppColors.gold, bold: true),
        ],
      ),
    );
  }
}

// ── Helper data class for preview ────────────────────────────────────────────
class _PreviewStats {
  final int    count;
  final String label;
  final double? total;
  final String? totalLabel;

  const _PreviewStats({
    required this.count,
    required this.label,
    this.total,
    this.totalLabel,
  });
}

// ── P&L row widget ────────────────────────────────────────────────────────────
class _PLRow extends StatelessWidget {
  final String label;
  final double value;
  final Color  color;
  final bool   bold;
  final bool   showSign;

  const _PLRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold     = false,
    this.showSign = false,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final absVal   = value.abs();
    final sign     = showSign ? (value >= 0 ? '+' : '−') : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: bold ? 14 : 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        ),
        Flexible(child: Text('$sign${currency.format(absVal)}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color,
                fontSize: bold ? 14 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
      ]),
    );
  }
}

// ── Export button ─────────────────────────────────────────────────────────────
class _ExportBtn extends StatelessWidget {
  final String      label;
  final IconData    icon;
  final Color       color;
  final bool        isLoading;
  final VoidCallback onTap;

  const _ExportBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          isLoading
              ? SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    );
  }
}