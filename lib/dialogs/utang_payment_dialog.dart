// ─────────────────────────────────────────────────────────────────────────────
// utang_payment_dialog.dart
// Purpose : Dialog for recording a payment towards an existing customer debt.
// Function: Shows the customer name, order ID, and remaining balance. Supports
//           Cash and GCash payment methods; GCash requires a reference number,
//           phone number, and account name. Validates the payment amount (cannot
//           exceed the remaining balance). On confirm, creates a PaymentRecord and
//           calls AppState.addPayment(). Shows a gold snackbar on partial payment
//           (with remaining balance) and a green snackbar on full payment.
// Usage   : UtangPaymentDialog.show(context, debt);
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/debt_model.dart';
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
  final _amountCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _gcashNumCtrl = TextEditingController();
  final _gcashNameCtrl = TextEditingController();
  final _uuid = const Uuid();
  String _method = 'Cash';
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _gcashNumCtrl.dispose();
    _gcashNameCtrl.dispose();
    super.dispose();
  }

  // Validates the payment amount and GCash fields (if applicable),
  // shows a confirmation dialog, records the payment in AppState,
  // then checks if the balance is now fully cleared.
  Future<void> _submit() async {
    if (_submitting) return;
    final amountText = _amountCtrl.text.trim();
    final amount = Money.tryParse(amountText);
    if (amount == null || !amount.isPositive) {
      setState(() => _error = 'Please enter a valid amount.');
      return;
    }
    // FIX: Validate against totalWithInterest (principal + accrued interest) instead
    // of remainingBalance (principal only). Without this, paying the full amount shown
    // in the UI ("Total Now Due") would be incorrectly blocked as "exceeds balance".
    // For debts with no interest, totalWithInterest == remainingBalance, so this is safe.
    final maxAllowed = widget.debt.totalWithInterest;
    if (amount > maxAllowed) {
      setState(
        () => _error =
            'Amount exceeds total due of ₱${maxAllowed.toStringAsFixed(2)}',
      );
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
    final confirmed = await showConfirmDialog(
      context,
      title: 'Confirm Payment',
      message:
          'Record a $_method payment of ${amount.format()} for ${widget.debt.customerName}?',
      confirmLabel: 'Yes, Confirm',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    // ── END Confirmation ──────────────────────────────────────────────────

    final note = _method == 'GCash'
        ? 'GCash | Ref: ${_refCtrl.text.trim()} | No: ${_gcashNumCtrl.text.trim()} | ${_gcashNameCtrl.text.trim()}'
        : 'Cash';

    final saveError = await AppState().addPayment(
      widget.debt.id,
      PaymentRecord(
        id: _uuid.v4(),
        amount: amount,
        paidAt: DateTime.now().toUtc(),
        paymentMethod: _method,
        reference: _method == 'GCash' ? _refCtrl.text.trim() : null,
        note: note,
      ),
    );

    if (!mounted) return;
    if (saveError != null) {
      setState(() {
        _submitting = false;
        _error = saveError;
      });
      return;
    }
    Navigator.pop(context);

    // FIX: Read the fresh debt from AppState after addPayment() completes instead
    // of computing newRemaining from the stale widget.debt.remainingBalance.
    // widget.debt is the snapshot passed at dialog-open time; AppState now holds
    // the updated record after the DB write.
    final freshDebt = AppState().debts.cast<CustomerDebt?>().firstWhere(
      (d) => d?.id == widget.debt.id,
      orElse: () => null,
    );
    final newRemaining = freshDebt?.totalWithInterest ?? Money.zero;
    if (newRemaining.isZero) {
      KnzToast.success(
        context,
        '🎉 Fully Paid! Tapos na ang utang ni ${widget.debt.customerName}.',
      );
    } else {
      KnzToast.info(
        context,
        '💳 Payment received! Remaining: ${newRemaining.format()}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.debt.remainingBalance;
    // FIX: "Full" fills totalWithInterest (principal + interest) so the customer
    // can pay the actual total due in one tap. For no-interest debts,
    // totalWithInterest == remainingBalance so behaviour is unchanged.
    final fullPayAmount = widget.debt.totalWithInterest;
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
              const Row(
                children: [
                  Icon(Icons.add_card, color: AppColors.gold, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Add Payment',
                    style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Customer info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.debt.customerName,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.debt.orderId,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Principal Balance',
                              style: TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              remaining.format(),
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // ── v6: Interest breakdown (only when interest is active) ──
                    if (widget.debt.hasInterest) ...[
                      const SizedBox(height: 8),
                      const Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Interest (${(widget.debt.interestRateBasisPoints / 100).toStringAsFixed(2)}% '
                            '${widget.debt.interestType} × '
                            '${widget.debt.interestDaysOld} days)',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '+ ${widget.debt.accruedInterest.format()}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Now Due',
                            style: TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            widget.debt.totalWithInterest.format(),
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Payment method
              const Text(
                'PAYMENT METHOD',
                style: TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MethodBtn(
                      label: 'Cash',
                      icon: Icons.payments_outlined,
                      selected: _method == 'Cash',
                      onTap: () => setState(() => _method = 'Cash'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MethodBtn(
                      label: 'GCash',
                      icon: Icons.phone_android_outlined,
                      selected: _method == 'GCash',
                      onTap: () => setState(() => _method = 'GCash'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Amount
              const Text(
                'PAYMENT AMOUNT',
                style: TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle: const TextStyle(color: AppColors.whiteTertiary),
                  prefixText: '₱ ',
                  prefixStyle: const TextStyle(color: AppColors.gold),
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.gold),
                  ),
                  suffixIcon: TextButton(
                    onPressed: () =>
                        _amountCtrl.text = fullPayAmount.toStringAsFixed(2),
                    child: const Text(
                      'Full',
                      style: TextStyle(color: AppColors.gold, fontSize: 12),
                    ),
                  ),
                ),
              ),

              // GCash fields
              if (_method == 'GCash') ...[
                const SizedBox(height: 14),
                const Text(
                  'GCASH REFERENCE NO.',
                  style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                _gcashField(
                  controller: _refCtrl,
                  hint: 'e.g. 1234567890',
                  icon: Icons.tag,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                const Text(
                  'GCASH NUMBER',
                  style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                _gcashField(
                  controller: _gcashNumCtrl,
                  hint: 'e.g. 09XXXXXXXXX',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),
                const Text(
                  'GCASH ACCOUNT NAME',
                  style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                _gcashField(
                  controller: _gcashNameCtrl,
                  hint: 'e.g. Juan dela Cruz',
                  icon: Icons.person_outline,
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],

              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: AppColors.whiteTertiary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GoldButton(
                      label: _submitting ? 'Saving…' : 'Confirm Payment',
                      onPressed: _submitting ? null : _submit,
                    ),
                  ),
                ],
              ),
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
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

// ── Payment method toggle button ──────────────────────────────────────────────
class _MethodBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label payment method',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.gold.withValues(alpha: 0.15)
                  : AppColors.inputFill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.gold : AppColors.cardBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected ? AppColors.gold : AppColors.whiteTertiary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppColors.gold : AppColors.whiteTertiary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
