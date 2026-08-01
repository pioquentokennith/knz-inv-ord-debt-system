// ─────────────────────────────────────────────────────────────────────────────
// mark_as_utang_dialog.dart  (v6: optional interest rate fields added)
// Purpose : Converts a completed order into a debt record.
//           v6 adds: interest rate %, type (daily/monthly/none), start date.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../screens/main_shell.dart';
import '../widgets/shared_widgets.dart';

class MarkAsUtangDialog extends StatefulWidget {
  final Order order;

  const MarkAsUtangDialog({super.key, required this.order});

  static void show(BuildContext context, Order order) {
    final alreadyExists = AppState().debts.any(
      (d) => d.orderId == order.orderId,
    );
    if (alreadyExists) {
      KnzToast.error(
        context,
        'May utang na ang order na ito. Hindi pwedeng mag-record ulit.',
      );
      return;
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
  final _interestCtrl = TextEditingController(text: '0');
  final _uuid = const Uuid();
  String? _error;
  bool _isSaving = false;
  DateTime? _dueDate;

  // v6 interest
  String _interestType = 'none'; // 'none' | 'daily' | 'monthly'

  // The customer-pay total is authoritative; SRP is reference data only.
  Money get _orderTotal => widget.order.customerPayAmount;

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = await showDatePicker(
      context: context,
      initialDate: _dueDate == null
          ? today
          : DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day),
      firstDate: today,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dueDate = DateTime.utc(selected.year, selected.month, selected.day);
    });
  }

  String get _dueDateLabel => _dueDate == null
      ? 'No due date selected'
      : MaterialLocalizations.of(context).formatMediumDate(
          DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day),
        );

  @override
  void dispose() {
    _amountCtrl.dispose();
    _interestCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final initialPaid = Money.tryParse(_amountCtrl.text.trim()) ?? Money.zero;

    if (initialPaid.isNegative) {
      setState(() => _error = 'Amount cannot be negative.');
      return;
    }
    if (initialPaid >= _orderTotal) {
      setState(
        () => _error =
            'Amount must be less than total (₱${_orderTotal.toStringAsFixed(2)}) to record as utang.',
      );
      return;
    }

    final interestRate = Money.tryParse(_interestCtrl.text.trim());
    if (interestRate == null || interestRate.isNegative) {
      setState(() => _error = 'Interest rate cannot be negative.');
      return;
    }

    final remaining = _orderTotal - initialPaid;

    String confirmMsg =
        'Record ₱${remaining.toStringAsFixed(2)} utang for ${widget.order.customerName} (${widget.order.orderId})?'
        '${initialPaid > 0 ? '\n\nInitial payment: ${initialPaid.format()}' : ''}';

    if (_interestType != 'none' && interestRate > 0) {
      confirmMsg +=
          '\nInterest: ${interestRate.toStringAsFixed(2)}% $_interestType';
    }
    if (_dueDate != null) confirmMsg += '\nDue: $_dueDateLabel';

    final confirmed = await showConfirmDialog(
      context,
      title: 'Record Utang?',
      message: confirmMsg,
      confirmLabel: 'Yes, Record',
      confirmColor: AppColors.warning,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final now = DateTime.now().toUtc();
    final effectiveInterestType = interestRate > 0 ? _interestType : 'none';

    var debt = CustomerDebt(
      id: _uuid.v4(),
      customerName: widget.order.customerName,
      orderId: widget.order.orderId,
      principalOriginal: _orderTotal,
      principalOutstanding: _orderTotal,
      createdAt: now,
      interestRateBasisPoints: interestRate.centavos,
      interestType: effectiveInterestType,
      interestStartTimestamp: now,
      lastAccrualTimestamp: now,
      dueDate: _dueDate,
    );
    if (initialPaid.isPositive) {
      debt = debt
          .allocatePayment(
            PaymentRecord(
              id: _uuid.v4(),
              amount: initialPaid,
              paidAt: now,
              note: 'Initial payment',
            ),
          )
          .debt;
    }

    try {
      await AppState().markOrderAsUtang(widget.order.id, debt);
      if (!mounted) return;
      Navigator.pop(context);
      KnzToast.warning(
        context,
        'Utang recorded for ${widget.order.customerName} — '
        '₱${debt.totalWithInterest.toStringAsFixed(2)} due.',
      );
      final shell = context.findAncestorStateOfType<MainShellState>();
      shell?.navigateTo(NavItem.utang);
    } catch (error) {
      if (!mounted) return;
      final duplicate = error.toString().toLowerCase().contains('debt');
      setState(() {
        _isSaving = false;
        _error = duplicate
            ? 'This order already has an active utang record.'
            : 'The utang record could not be saved. Please try again.';
      });
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
            const Row(
              children: [
                Icon(Icons.money_off, color: AppColors.warning, size: 20),
                SizedBox(width: 10),
                Text(
                  'Mark as Utang',
                  style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Order summary
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
                      Text(
                        widget.order.customerName,
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.order.orderId,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Order Total',
                        style: TextStyle(
                          color: AppColors.whiteTertiary,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _orderTotal.format(),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Initial payment
            const Text(
              'INITIAL PAYMENT (0 if walang bayad)',
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
                  borderSide: const BorderSide(color: AppColors.warning),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'DUE DATE (OPTIONAL)',
              style: TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_dueDateLabel),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: AppColors.gold,
                      side: const BorderSide(color: AppColors.cardBorder),
                    ),
                  ),
                ),
                if (_dueDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    tooltip: 'Clear due date',
                    onPressed: () => setState(() => _dueDate = null),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.whiteTertiary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── v6: Interest rate section ─────────────────────────────────
            const Divider(color: AppColors.cardBorder),
            const SizedBox(height: 10),
            const Text(
              'INTEREST (OPTIONAL)',
              style: TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            // Interest type selector
            Row(
              children: [
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
                          type == 'none'
                              ? 'None'
                              : type[0].toUpperCase() + type.substring(1),
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
              ],
            ),

            if (_interestType != 'none') ...[
              const SizedBox(height: 12),
              const Text(
                'RATE (%)',
                style: TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _interestCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: const TextStyle(color: AppColors.white),
                decoration: InputDecoration(
                  hintText: '2.0',
                  hintStyle: const TextStyle(color: AppColors.whiteTertiary),
                  suffixText: '%  $_interestType',
                  suffixStyle: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppColors.warning,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _interestType == 'daily'
                    ? 'Accrued = balance × rate% × days unpaid'
                    : 'Accrued = balance × rate% × (days/30)',
                style: const TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 10,
                ),
              ),
            ],

            const SizedBox(height: 8),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),

            const SizedBox(height: 8),
            const Text(
              'Ang remaining balance ay itatala bilang utang ng customer.',
              style: TextStyle(color: AppColors.whiteTertiary, fontSize: 11),
            ),
            const SizedBox(height: 20),

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
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _submit,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        backgroundColor: AppColors.warning.withValues(
                          alpha: 0.15,
                        ),
                        disabledForegroundColor: AppColors.whiteTertiary,
                        side: BorderSide(
                          color: AppColors.warning.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _isSaving ? 'Saving…' : 'Record Utang',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
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
