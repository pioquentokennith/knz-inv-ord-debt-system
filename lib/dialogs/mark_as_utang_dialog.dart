// ─────────────────────────────────────────────────────────────────────────────
// mark_as_utang_dialog.dart
// Purpose : Dialog for converting a completed order into a debt (utang) record.
// Function: First checks if the order already has an existing debt record to prevent
//           duplicates. If not, shows a form where the admin can enter an initial
//           payment amount (0 if nothing was paid). Validates the amount, shows a
//           confirmation dialog, then creates a CustomerDebt record in AppState.
//           Updates the order status to 'utang' and auto-navigates to the Utang tab.
// Usage   : MarkAsUtangDialog.show(context, order);
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../screens/main_shell.dart';
import '../widgets/shared_widgets.dart';

class MarkAsUtangDialog extends StatefulWidget {
  final Order order;

  const MarkAsUtangDialog({super.key, required this.order});

  // Factory method that checks for an existing debt record before opening the dialog.
  // Shows a snackbar error and returns early if a duplicate is found.
  static void show(BuildContext context, Order order) {
    // ── DUPLICATE CHECK ───────────────────────────────────────────────────
    // Bago buksan ang dialog, tingnan kung may existing na utang ang order.
    // Kung mayroon na, ipakita lang ang error snackbar — hindi na bubuksan
    // ang dialog para hindi malito ang admin/user.
    final alreadyExists = AppState()
        .debts
        .any((d) => d.orderId == order.orderId);

    if (alreadyExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          content: Text(
            'May utang na ang order na ito. Hindi pwedeng mag-record ulit.',
            style: TextStyle(color: AppColors.white),
          ),
        ),
      );
      return; // ← hindi na bubuksan ang dialog
    }

    showDialog(
      context: context,
      builder: (_) => MarkAsUtangDialog(order: order),
    );
  }

  @override
  State<MarkAsUtangDialog> createState() => _MarkAsUtangDialogState();
}

class _MarkAsUtangDialogState extends State<MarkAsUtangDialog> {
  final _amountCtrl = TextEditingController();
  final _uuid = const Uuid();
  String? _error;

  // Calculates the total order amount by summing all item subtotals
  double get _orderTotal =>
      widget.order.items.fold(0.0, (sum, i) => sum + i.subtotal);

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  // Validates the initial payment amount, confirms with the user, creates
  // a CustomerDebt record, updates the order status to 'utang', then
  // navigates to the Utang tab automatically.
  Future<void> _submit() async {
    final initialPaid = double.tryParse(_amountCtrl.text.trim()) ?? 0;

    if (initialPaid < 0) {
      setState(() => _error = 'Amount cannot be negative.');
      return;
    }
    if (initialPaid >= _orderTotal) {
      setState(() => _error =
          'Amount must be less than total (₱${_orderTotal.toStringAsFixed(2)}) to record as utang.');
      return;
    }

    // ── Confirmation prompt ───────────────────────────────────────────────
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final remaining = _orderTotal - initialPaid;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Record Utang?',
      message:
          'Record ₱${remaining.toStringAsFixed(2)} utang for ${widget.order.customerName} (${widget.order.orderId})?'
          '${initialPaid > 0 ? '\n\nInitial payment: ${currency.format(initialPaid)}' : ''}',
      confirmLabel: 'Yes, Record',
      confirmColor: AppColors.warning,
    );
    if (!confirmed || !mounted) return;
    // ── END Confirmation ──────────────────────────────────────────────────

    final debt = CustomerDebt(
      id:           _uuid.v4(),
      customerName: widget.order.customerName,
      orderId:      widget.order.orderId,
      totalAmount:  _orderTotal,
      amountPaid:   initialPaid,
      createdAt:    DateTime.now(),
      payments: initialPaid > 0
          ? [
              PaymentRecord(
                id:     _uuid.v4(),
                amount: initialPaid,
                paidAt: DateTime.now(),
                note:   'Initial payment',
              )
            ]
          : [],
    );

    final ok = await AppState().addDebt(debt, onError: (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text(msg,
                style: const TextStyle(color: AppColors.white)),
          ),
        );
      }
    });

    if (!ok || !mounted) return;

    await AppState().updateOrderStatus(widget.order.id, OrderStatus.utang);
    if (!mounted) return;

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.warning,
        content: Text(
          'Utang recorded for ${widget.order.customerName} — '
          '₱${debt.remainingBalance.toStringAsFixed(2)} remaining',
          style: const TextStyle(color: AppColors.background),
        ),
      ),
    );

    // Auto-navigate to Utang tab
    final shell = context.findAncestorStateOfType<MainShellState>();
    shell?.navigateTo(NavItem.utang);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

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
            const Row(children: [
              Icon(Icons.money_off, color: AppColors.warning, size: 20),
              SizedBox(width: 10),
              Text('Mark as Utang',
                  style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ]),
            const SizedBox(height: 16),

            // Order summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.order.customerName,
                        style: const TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600)),
                    Text(widget.order.orderId,
                        style: const TextStyle(
                            color: AppColors.gold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Order Total',
                        style: TextStyle(
                            color: AppColors.whiteTertiary, fontSize: 12)),
                    Text(currency.format(_orderTotal),
                        style: const TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Initial payment
            const Text('INITIAL PAYMENT (0 if walang bayad)',
                style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2)),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle:
                    const TextStyle(color: AppColors.whiteTertiary),
                prefixText: '₱ ',
                prefixStyle: const TextStyle(color: AppColors.gold),
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.cardBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.cardBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.warning)),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ],

            const SizedBox(height: 8),
            const Text(
              'Ang remaining balance ay itatala bilang utang ng customer.',
              style: TextStyle(
                  color: AppColors.whiteTertiary, fontSize: 11),
            ),
            const SizedBox(height: 20),

            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style:
                          TextStyle(color: AppColors.whiteTertiary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: _submit,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AppColors.warning.withValues(alpha: 0.5)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Record Utang',
                        style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
