// ─────────────────────────────────────────────────────────────────────────────
// export_dialog.dart
// Purpose : Dialog that lets the admin export data as CSV, PDF, or direct print.
// Function: Accepts an ExportType enum (orders, inventory, or debts) and presents
//           three export options as tappable tiles. Delegates the actual export
//           work to ExportService methods. Shows a loading spinner while busy
//           and an error message if the export fails. The showExportDialog()
//           convenience function can be called from any screen.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../services/export_service.dart';

enum ExportType { orders, inventory, debts }

class ExportDialog extends StatefulWidget {
  final ExportType type;

  const ExportDialog({super.key, required this.type});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _isLoading = false;
  String? _error;

  String get _typeLabel {
    switch (widget.type) {
      case ExportType.orders:    return 'Orders';
      case ExportType.inventory: return 'Inventory';
      case ExportType.debts:     return 'Utang / Debts';
    }
  }

  Future<void> _export(String format) async {
    setState(() { _isLoading = true; _error = null; });
    final state = AppState();

    try {
      switch (widget.type) {
        case ExportType.orders:
          if (format == 'csv') {
            await ExportService.exportOrdersCsv(state.orders);
          } else if (format == 'pdf') {
            await ExportService.exportOrdersPdf(
              state.orders, businessName: AppStrings.appName);
          } else {
            await ExportService.printOrdersPdf(
              state.orders, businessName: AppStrings.appName);
          }
          break;

        case ExportType.inventory:
          if (format == 'csv') {
            await ExportService.exportInventoryCsv(state.products);
          } else if (format == 'pdf') {
            await ExportService.exportInventoryPdf(
              state.products, businessName: AppStrings.appName);
          } else {
            await ExportService.printInventoryPdf(
              state.products, businessName: AppStrings.appName);
          }
          break;

        case ExportType.debts:
          if (format == 'csv') {
            await ExportService.exportDebtsCsv(state.debts);
          } else if (format == 'pdf') {
            await ExportService.exportDebtsPdf(
              state.debts, businessName: AppStrings.appName);
          } else {
            await ExportService.printDebtsPdf(
              state.debts, businessName: AppStrings.appName);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.download_outlined,
                    color: AppColors.gold, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Export $_typeLabel',
                    style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const Text('Choose format',
                    style: TextStyle(
                        color: AppColors.whiteTertiary, fontSize: 12)),
              ]),
            ]),

            const SizedBox(height: 24),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: AppColors.gold),
                      SizedBox(height: 12),
                      Text('Generating export...',
                          style: TextStyle(color: AppColors.whiteSecondary)),
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
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12)),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.whiteTertiary)),
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
          child: Row(children: [
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
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.whiteTertiary, fontSize: 11)),
                ],
              ),
            ),
            if (!disabled)
              const Icon(Icons.chevron_right,
                  color: AppColors.whiteTertiary, size: 18),
          ]),
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
