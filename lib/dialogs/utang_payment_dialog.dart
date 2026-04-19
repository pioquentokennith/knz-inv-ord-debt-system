// ─────────────────────────────────────────────────────────────────────────────
// utang_payment_dialog.dart
// FIX 5: Extracted from utang_screen.dart
// NEW:   Auto-deliver — pag fully paid na ang utang (remainingBalance == 0),
//        awtomatikong mag-a-update ang order status sa "delivered" at
//        mag-aalis ng utang status.
// Usage: showDialog(context: context, builder: (_) => UtangPaymentDialog(debt: debt));
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../widgets/shared_widgets.dart';

class UtangPaymentDialog extends StatefulWidget {
  final CustomerDebt debt;

  const UtangPaymentDialog({super.key, required this.debt});

  static void show(BuildContext context, CustomerDebt debt) {
    showDialog(
      context: context,
      builder: (_) => UtangPaymentDialog(debt: debt),
    );
  }

  @override
  State<UtangPaymentDialog> createState() => _UtangPaymentDialogState();
}

class _UtangPaymentDialogState extends State<UtangPaymentDialog> {
  final _amountCtrl    = TextEditingController();
  final _refCtrl       = TextEditingController();
  final _gcashNumCtrl  = TextEditingController();
  final _gcashNameCtrl = TextEditingController();
  final _uuid = const Uuid();
  String  _method = 'Cash';
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _gcashNumCtrl.dispose();
    _gcashNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter a valid amount.');
      return;
    }
    if (amount > widget.debt.remainingBalance) {
      setState(() => _error =
          'Amount exceeds remaining balance of ₱${widget.debt.remainingBalance.toStringAsFixed(2)}');
      return;
    }
    if (_method == 'GCash') {
      if (_refCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Please enter the GCash reference number.');
        return;
      }
      if (_gcashNumCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Please enter the GCash number.');
        return;
      }
      if (_gcashNameCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Please enter the GCash account name.');
        return;
      }
    }

    // ── Confirmation prompt ───────────────────────────────────────────────
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Confirm Payment',
      message:
          'Record a ${_method} payment of ${currency.format(amount)} for ${widget.debt.customerName}?',
      confirmLabel: 'Yes, Confirm',
    );
    if (!confirmed || !mounted) return;
    // ── END Confirmation ──────────────────────────────────────────────────

    final note = _method == 'GCash'
        ? 'GCash | Ref: ${_refCtrl.text.trim()} | No: ${_gcashNumCtrl.text.trim()} | ${_gcashNameCtrl.text.trim()}'
        : 'Cash';

    await AppState().addPayment(
      widget.debt.id,
      PaymentRecord(
        id:     _uuid.v4(),
        amount: amount,
        paidAt: DateTime.now(),
        note:   note,
      ),
    );

    // ── AUTO-DELIVER CHECK ────────────────────────────────────────────────
    // Kapag ang binayad ay katumbas ng remaining balance (fully paid na),
    // awtomatikong i-update ang order status sa "delivered".
    // Hindi na "utang" ang status — bayad na kasi lahat.
    final newRemaining = widget.debt.remainingBalance - amount;
    if (newRemaining <= 0) {
      // Hanapin ang order na may parehong orderId
      final matchingOrder = AppState().orders.where(
        (o) => o.orderId == widget.debt.orderId,
      ).firstOrNull;

      if (matchingOrder != null) {
        await AppState().updateOrderStatus(
          matchingOrder.id,
          OrderStatus.delivered, // ← auto-delivered pag fully paid
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              '${widget.debt.customerName} fully paid! Order marked as Delivered. ✅',
              style: const TextStyle(color: AppColors.white),
            ),
          ),
        );
      }
      return;
    }
    // ── END AUTO-DELIVER CHECK ────────────────────────────────────────────

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.debt.remainingBalance;
    final currency  = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Row(children: [
                Icon(Icons.add_card, color: AppColors.gold, size: 20),
                SizedBox(width: 10),
                Text('Add Payment',
                    style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ]),
              const SizedBox(height: 14),

              // Customer info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.debt.customerName,
                          style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600)),
                      Text(widget.debt.orderId,
                          style: const TextStyle(
                              color: AppColors.gold, fontSize: 12)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('Remaining',
                          style: TextStyle(
                              color: AppColors.whiteTertiary, fontSize: 11)),
                      Text(currency.format(remaining),
                          style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Payment method
              const Text('PAYMENT METHOD',
                  style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 11,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _MethodBtn(
                        label: 'Cash',
                        icon: Icons.payments_outlined,
                        selected: _method == 'Cash',
                        onTap: () => setState(() => _method = 'Cash'))),
                const SizedBox(width: 10),
                Expanded(
                    child: _MethodBtn(
                        label: 'GCash',
                        icon: Icons.phone_android_outlined,
                        selected: _method == 'GCash',
                        onTap: () => setState(() => _method = 'GCash'))),
              ]),
              const SizedBox(height: 14),

              // Amount
              const Text('PAYMENT AMOUNT',
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
                      borderSide: const BorderSide(color: AppColors.gold)),
                  suffixIcon: TextButton(
                    onPressed: () => _amountCtrl.text =
                        remaining.toStringAsFixed(2),
                    child: const Text('Full',
                        style: TextStyle(
                            color: AppColors.gold, fontSize: 12)),
                  ),
                ),
              ),

              // GCash fields
              if (_method == 'GCash') ...[
                const SizedBox(height: 14),
                const Text('GCASH REFERENCE NO.',
                    style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11,
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                _gcashField(controller: _refCtrl, hint: 'e.g. 1234567890',
                    icon: Icons.tag, keyboardType: TextInputType.number),
                const SizedBox(height: 14),
                const Text('GCASH NUMBER',
                    style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11,
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                _gcashField(controller: _gcashNumCtrl, hint: 'e.g. 09XXXXXXXXX',
                    icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                const SizedBox(height: 14),
                const Text('GCASH ACCOUNT NAME',
                    style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11,
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                _gcashField(controller: _gcashNameCtrl, hint: 'e.g. Juan dela Cruz',
                    icon: Icons.person_outline),
              ],

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: AppColors.error, fontSize: 12)),
              ],

              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                    child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style:
                          TextStyle(color: AppColors.whiteTertiary)),
                )),
                const SizedBox(width: 12),
                Expanded(
                    flex: 2,
                    child: GoldButton(
                        label: 'Confirm Payment', onPressed: _submit)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gcashField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.whiteTertiary),
        prefixIcon: Icon(icon, color: AppColors.gold, size: 18),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.cardBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.cardBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.gold)),
      ),
    );
  }
}

// ── Payment method toggle button ──────────────────────────────────────────────
class _MethodBtn extends StatelessWidget {
  final String     label;
  final IconData   icon;
  final bool       selected;
  final VoidCallback onTap;

  const _MethodBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.inputFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.gold : AppColors.cardBorder,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.gold
                    : AppColors.whiteTertiary,
                size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: selected
                        ? AppColors.gold
                        : AppColors.whiteTertiary,
                    fontWeight: selected
                        ? FontWeight.w700
                        : FontWeight.normal,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
