import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

class EditStockDialog extends StatefulWidget {
  final Product product;
  const EditStockDialog({super.key, required this.product});

  @override
  State<EditStockDialog> createState() => _EditStockDialogState();
}

class _EditStockDialogState extends State<EditStockDialog> {
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
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
                    onPressed: () async {
                      final v = int.tryParse(_ctrl.text) ?? 0;
                      await AppState().updateStock(widget.product.id, v);
                      if (context.mounted) Navigator.pop(context);
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
