// ─────────────────────────────────────────────────────────────────────────────
// mark_as_utang_dialog.dart  (v6: optional interest rate fields added)
// Purpose : Converts a completed order into a debt record.
//           v6 adds: interest rate %, type (daily/monthly/none), start date.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static void show(BuildContext context, Order order) {
    final alreadyExists = AppState().debts.any((d) => d.orderId == order.orderId);
    if (alreadyExists) {
      KnzToast.error(context, 'May utang na ang order na ito. Hindi pwedeng mag-record ulit.');
      return;
    }
    showDialog(context: context, builder: (_) => MarkAsUtangDialog(order: order));
  }

  @override
  State<MarkAsUtangDialog> createState() => _MarkAsUtangDialogState();
}

class _MarkAsUtangDialogState extends State<MarkAsUtangDialog> {
  final _amountCtrl      = TextEditingController();
  final _interestCtrl    = TextEditingController(text: '0');
  final _uuid = const Uuid();
  String? _error;

  // v6 interest
  String _interestType = 'none'; // 'none' | 'daily' | 'monthly'

  // Use order.discountedTotal — this is the actual net amount the customer owes.
  // For reseller orders: totalAmount = SRP, discountedTotal = net selling price.
  // For regular orders: discountedTotal falls back to totalAmount (no difference).
  double get _orderTotal => widget.order.discountedTotal;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _interestCtrl.dispose();
    super.dispose();
  }

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

    final interestRate = double.tryParse(_interestCtrl.text.trim()) ?? 0;
    if (interestRate < 0) {
      setState(() => _error = 'Interest rate cannot be negative.');
      return;
    }

    final currency  = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final remaining = _orderTotal - initialPaid;

    String confirmMsg =
        'Record ₱${remaining.toStringAsFixed(2)} utang for ${widget.order.customerName} (${widget.order.orderId})?'
        '${initialPaid > 0 ? '\n\nInitial payment: ${currency.format(initialPaid)}' : ''}';

    if (_interestType != 'none' && interestRate > 0) {
      confirmMsg += '\nInterest: $interestRate% $_interestType';
    }

    final confirmed = await showConfirmDialog(context,
        title: 'Record Utang?',
        message: confirmMsg,
        confirmLabel: 'Yes, Record',
        confirmColor: AppColors.warning);
    if (!confirmed || !mounted) return;

    final debt = CustomerDebt(
      id:              _uuid.v4(),
      customerName:    widget.order.customerName,
      orderId:         widget.order.orderId,
      totalAmount:     _orderTotal,
      amountPaid:      initialPaid,
      createdAt:       DateTime.now(),
      payments:        initialPaid > 0
          ? [PaymentRecord(id: _uuid.v4(), amount: initialPaid,
              paidAt: DateTime.now(), note: 'Initial payment')]
          : [],
      // v6 interest
      interestRate:     interestRate,
      interestType:     _interestType,
      interestStartDate: DateTime.now(),
    );

    final ok = await AppState().addDebt(debt, onError: (msg) {
      if (mounted) KnzToast.error(context, msg);
    });

    if (!ok || !mounted) return;
    await AppState().updateOrderStatus(widget.order.id, OrderStatus.utang);
    if (!mounted) return;
    Navigator.pop(context);

    KnzToast.warning(context,
      '💳 Utang recorded for ${widget.order.customerName} — '
      '₱${debt.remainingBalance.toStringAsFixed(2)} remaining.',
    );
    final shell = context.findAncestorStateOfType<MainShellState>();
    shell?.navigateTo(NavItem.utang);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

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
            const Row(children: [
              Icon(Icons.money_off, color: AppColors.warning, size: 20),
              SizedBox(width: 10),
              Text('Mark as Utang',
                  style: TextStyle(color: AppColors.white,
                      fontWeight: FontWeight.w700, fontSize: 16)),
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
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.order.customerName,
                        style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w600)),
                    Text(widget.order.orderId,
                        style: const TextStyle(color: AppColors.gold, fontSize: 12)),
                  ]),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Order Total',
                      style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12)),
                  Text(currency.format(_orderTotal),
                      style: const TextStyle(color: AppColors.white, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),

            // Initial payment
            const Text('INITIAL PAYMENT (0 if walang bayad)',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(color: AppColors.whiteTertiary),
                prefixText: '₱ ',
                prefixStyle: const TextStyle(color: AppColors.gold),
                filled: true,
                fillColor: AppColors.inputFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.warning)),
              ),
            ),
            const SizedBox(height: 16),

            // ── v6: Interest rate section ─────────────────────────────────
            const Divider(color: AppColors.cardBorder),
            const SizedBox(height: 10),
            const Text('INTEREST (OPTIONAL)',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11,
                    letterSpacing: 1.2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            // Interest type selector
            Row(children: [
              for (final type in ['none', 'daily', 'monthly'])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _interestType = type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _interestType == type
                            ? AppColors.warning.withValues(alpha: 0.15)
                            : AppColors.inputFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _interestType == type
                              ? AppColors.warning
                              : AppColors.cardBorder,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        type == 'none' ? 'None' : type[0].toUpperCase() + type.substring(1),
                        style: TextStyle(
                          color: _interestType == type
                              ? AppColors.warning
                              : AppColors.whiteTertiary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),

            if (_interestType != 'none') ...[
              const SizedBox(height: 12),
              const Text('RATE (%)',
                  style: TextStyle(color: AppColors.whiteTertiary,
                      fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              TextField(
                controller: _interestCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  hintText: '2.0',
                  hintStyle: const TextStyle(color: AppColors.whiteTertiary),
                  suffixText: '%  $_interestType',
                  suffixStyle: const TextStyle(color: AppColors.warning, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.cardBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.warning, width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _interestType == 'daily'
                    ? 'Accrued = balance × rate% × days unpaid'
                    : 'Accrued = balance × rate% × (days/30)',
                style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 10),
              ),
            ],

            const SizedBox(height: 8),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),

            const SizedBox(height: 8),
            const Text('Ang remaining balance ay itatala bilang utang ng customer.',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11)),
            const SizedBox(height: 20),

            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppColors.whiteTertiary)),
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
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Record Utang',
                        style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
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