// ─────────────────────────────────────────────────────────────────────────────
// edit_stock_dialog.dart
// Purpose : Dialog for directly editing the stock quantity of a specific product.
// Function: Displays a numeric text field pre-filled with the current stock value,
//           plus increment (+) and decrement (-) icon buttons for quick adjustments.
//           On "Update", shows a confirmation dialog then calls AppState.updateStock()
//           to persist the change. Closes itself after a successful update.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

// Dialog widget for editing the stock quantity of a single product
class EditStockDialog extends StatefulWidget {
  final Product product;
  const EditStockDialog({super.key, required this.product});

  @override
  State<EditStockDialog> createState() => _EditStockDialogState();
}

class _EditStockDialogState extends State<EditStockDialog> {
  // Controller pre-filled with the product's current stock quantity
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.product.stockQty.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '📦 Edit Stock — ${widget.product.name}',
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                DarkIconButton(
                  icon: Icons.remove,
                  color: AppColors.error,
                  // Decrement stock — floor at 0 to prevent negative stock values
                  onPressed: () {
                    final v = int.tryParse(_ctrl.text) ?? 0;
                    if (v > 0) _ctrl.text = (v - 1).toString();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DarkTextField(
                    hint: '0',
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 12),
                DarkIconButton(
                  icon: Icons.add,
                  color: AppColors.success,
                  // Increment stock — no upper limit enforced here
                  onPressed: () {
                    final v = int.tryParse(_ctrl.text) ?? 0;
                    _ctrl.text = (v + 1).toString();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Min stock level: ${widget.product.minStockLevel}',
              style: const TextStyle(
                  color: AppColors.whiteTertiary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      alignment: Alignment.center,
                      child: const Text(AppStrings.cancel,
                          style: TextStyle(color: AppColors.whiteSecondary)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GoldButton(
                    label: 'Update',
                    height: 44,
                    // Parse the field value, confirm with the user, then persist the update
                    onPressed: () async {
                      final v = int.tryParse(_ctrl.text) ?? 0;
                      final confirmed = await showConfirmDialog(
                        context,
                        title: 'Update Stock',
                        message:
                            'Set stock for "${widget.product.name}" to $v units?',
                        confirmLabel: 'Update',
                        icon: Icons.inventory_2_rounded,
                      );
                      if (!confirmed || !context.mounted) return;
                      await AppState().updateStock(widget.product.id, v);
                      if (context.mounted) {
                        Navigator.pop(context);
                        KnzToast.success(context, '📦 Stock for "${widget.product.name}" set to $v units.');
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
