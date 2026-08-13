// ─────────────────────────────────────────────────────────────────────────────
// export_dialog.dart
// Purpose : Dialog that lets the admin export data as CSV, PDF, or direct print.
// Function: Accepts an ExportType enum (orders, inventory, or debts) and presents
//           three export options as tappable tiles. Delegates the actual export
//           work to ExportService methods. Shows a loading spinner while busy
//           and an error message if the export fails. The showExportDialog()
//           convenience function can be called from any screen.
//
// MINOR 3 FIX: Added date range picker for orders, debts, and analytics exports.
//   • Inventory export hindi nangangailangan ng date filter (snapshot ng stock).
//   • Orders at debts ay na-fi-filter by orderDate / createdAt.
//   • "All time" ang default — existing behavior ay hindi nabago.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/order_model.dart';
import '../services/export_service.dart';

enum ExportType {
  orders,
  inventory,
  debts,
  analytics,
  customOrders,
  accounting,
}

class ExportDialog extends StatefulWidget {
  final ExportType type;

  const ExportDialog({super.key, required this.type});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isLoading = false;
  String? _error;

  // MINOR 3 FIX: Date range state — null = all time (default)
  DateTimeRange? _dateRange;

  String get _typeLabel {
    switch (widget.type) {
      case ExportType.orders:
        return 'Orders';
      case ExportType.inventory:
        return 'Inventory';
      case ExportType.debts:
        return 'Utang / Debts';
      case ExportType.analytics:
        return 'Analytics Report';
      case ExportType.customOrders:
        return 'Custom Orders';
      case ExportType.accounting:
        return 'Accounting Summary';
    }
  }

  // MINOR 3 FIX: Whether this export type supports date filtering
  bool get _supportsDateFilter =>
      widget.type != ExportType.inventory &&
      widget.type != ExportType.customOrders &&
      widget.type != ExportType.debts;

  // MINOR 3 FIX: Human-readable label for the selected range
  String get _dateRangeLabel {
    if (_dateRange == null) return 'All time';
    final start = _dateRange!.start;
    final end = _dateRange!.end;
    String fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';
    return '${fmt(start)} – ${fmt(end)}';
  }

  // MINOR 3 FIX: Open date range picker
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange:
          _dateRange ??
          DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: AppColors.background,
              surface: AppColors.surface,
              onSurface: AppColors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  // MINOR 3 FIX: Filter helpers
  List<Order> _filteredOrders(List<Order> orders) {
    if (_dateRange == null) return orders;
    final start = _dateRange!.start;
    // Include the full end day (up to 23:59:59)
    final end = _dateRange!.end.add(const Duration(days: 1));
    return orders
        .where(
          (o) =>
              o.orderDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
              o.orderDate.isBefore(end),
        )
        .toList();
  }

  Future<void> _export(String format) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final state = AppState();
    final userName = state.currentUser?.displayName;

    try {
      switch (widget.type) {
        case ExportType.orders:
          final orders = _filteredOrders(
            state.orders
                .where((order) => order.status != OrderStatus.cancelled)
                .toList(),
          );
          if (format == 'csv') {
            await ExportService.exportOrdersCsv(orders);
          } else if (format == 'pdf') {
            await ExportService.exportOrdersPdf(
              orders,
              businessName: AppStrings.appName,
              userName: userName,
            );
          } else {
            await ExportService.printOrdersPdf(
              orders,
              businessName: AppStrings.appName,
              userName: userName,
            );
          }
          break;

        case ExportType.inventory:
          if (format == 'csv') {
            await ExportService.exportInventoryCsv(state.products);
          } else if (format == 'pdf') {
            await ExportService.exportInventoryPdf(
              state.products,
              businessName: AppStrings.appName,
              userName: userName,
            );
          } else {
            await ExportService.printInventoryPdf(
              state.products,
              businessName: AppStrings.appName,
              userName: userName,
            );
          }
          break;

        case ExportType.debts:
          final debts = state.debts.toList();
          if (format == 'csv') {
            await ExportService.exportDebtsCsv(debts);
          } else if (format == 'pdf') {
            await ExportService.exportDebtsPdf(
              debts,
              businessName: AppStrings.appName,
              userName: userName,
            );
          } else {
            await ExportService.printDebtsPdf(
              debts,
              businessName: AppStrings.appName,
              userName: userName,
            );
          }
          break;

        case ExportType.analytics:
          final orders = state.orders.toList();
          final debts = state.debts.toList();
          if (format == 'csv') {
            await ExportService.exportAnalyticsCsv(
              orders: orders,
              debts: debts,
              customOrders: state.customOrders,
              businessEvents: state.businessEvents,
              paymentFrom: _dateRange?.start,
              paymentTo: _dateRange?.end,
            );
          } else if (format == 'pdf') {
            await ExportService.exportAnalyticsPdf(
              orders: orders,
              debts: debts,
              customOrders: state.customOrders,
              businessEvents: state.businessEvents,
              businessName: AppStrings.appName,
              userName: userName,
              paymentFrom: _dateRange?.start,
              paymentTo: _dateRange?.end,
            );
          } else {
            await ExportService.printAnalyticsPdf(
              orders: orders,
              debts: debts,
              customOrders: state.customOrders,
              businessEvents: state.businessEvents,
              businessName: AppStrings.appName,
              userName: userName,
              paymentFrom: _dateRange?.start,
              paymentTo: _dateRange?.end,
            );
          }
          break;

        case ExportType.customOrders:
          await ExportService.exportCustomOrdersCsv(state.customOrders);
          break;

        case ExportType.accounting:
          final acctOrders = state.orders.toList();
          final acctDebts = state.debts.toList();
          if (format == 'csv') {
            await ExportService.exportAnalyticsCsv(
              orders: acctOrders,
              debts: acctDebts,
              customOrders: state.customOrders,
              businessEvents: state.businessEvents,
              paymentFrom: _dateRange?.start,
              paymentTo: _dateRange?.end,
            );
          } else {
            await ExportService.exportAnalyticsPdf(
              orders: acctOrders,
              debts: acctDebts,
              customOrders: state.customOrders,
              businessEvents: state.businessEvents,
              businessName: AppStrings.appName,
              userName: userName,
              paymentFrom: _dateRange?.start,
              paymentTo: _dateRange?.end,
              reportTitle: 'Revenue & Collections Summary',
            );
          }
          break;
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Export failed. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.download_outlined,
                    color: AppColors.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Export $_typeLabel',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      'Choose format',
                      style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // MINOR 3 FIX: Date range picker row (hidden for inventory)
            if (_supportsDateFilter) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDateRange,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _dateRange != null
                          ? AppColors.gold.withValues(alpha: 0.6)
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.date_range_outlined,
                        color: _dateRange != null
                            ? AppColors.gold
                            : AppColors.whiteTertiary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dateRangeLabel,
                          style: TextStyle(
                            color: _dateRange != null
                                ? AppColors.white
                                : AppColors.whiteTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_dateRange != null)
                        GestureDetector(
                          onTap: () => setState(() => _dateRange = null),
                          child: const Icon(
                            Icons.close,
                            color: AppColors.whiteTertiary,
                            size: 16,
                          ),
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.whiteTertiary,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.gold),
                      SizedBox(height: 12),
                      Text(
                        'Generating export...',
                        style: TextStyle(color: AppColors.whiteSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // CSV option
              _ExportOption(
                icon: Icons.table_chart_outlined,
                title: 'Export as CSV',
                subtitle: 'Open in Excel, Google Sheets, or Numbers',
                color: AppColors.success,
                onTap: () => _export('csv'),
              ),
              const SizedBox(height: 10),

              // PDF option
              _ExportOption(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Export as PDF',
                subtitle: 'Professional report — share or archive',
                color: AppColors.error,
                onTap: () => _export('pdf'),
              ),
              const SizedBox(height: 10),

              // Print option
              _ExportOption(
                icon: Icons.print_outlined,
                title: 'Print',
                subtitle: 'Direct print or Bluetooth printer',
                color: AppColors.info,
                onTap: () => _export('print'),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.whiteTertiary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!disabled)
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.whiteTertiary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience function — call this from any screen
/// ```dart
/// showExportDialog(context, ExportType.orders);
/// ```
void showExportDialog(BuildContext context, ExportType type) {
  showDialog(
    context: context,
    builder: (_) => ExportDialog(type: type),
  );
}
