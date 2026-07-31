// ─────────────────────────────────────────────────────────────────────────────
// utang_screen.dart
// Purpose : Debt (utang) tracker screen showing all customer debts with payment
//           management and receipt printing.
// Function: Applies FIX 5 (extracted dialogs) and FIX 6 (AppStateBuilder scoping).
//           The header summary (_UtangHeader) and the debt list are each wrapped in
//           separate AppStateBuilder instances so only the affected subtrees rebuild.
//           Local state (_search, _showPaidOnly) filters the debt list without
//           triggering AppState rebuilds. Each debt card (_DebtCard) is expandable
//           to show payment history and supports Add Payment, Receipt, and Delete.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../core/app_state_builder.dart'; // ← FIX 6
import '../models/debt_model.dart';
import '../widgets/shared_widgets.dart';
import '../dialogs/utang_payment_dialog.dart'; // ← FIX 5
import '../dialogs/utang_receipt_printer.dart'; // ← FIX 5
import '../dialogs/export_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UtangScreen — FIX 5 + FIX 6 applied
// ─────────────────────────────────────────────────────────────────────────────
class UtangScreen extends StatefulWidget {
  const UtangScreen({super.key});

  @override
  State<UtangScreen> createState() => _UtangScreenState();
}

class _UtangScreenState extends State<UtangScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _showPaidOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CustomerDebt> _filtered(List<CustomerDebt> debts) {
    return debts.where((d) {
      final matchSearch =
          d.customerName.toLowerCase().contains(_search.toLowerCase()) ||
          d.orderId.toLowerCase().contains(_search.toLowerCase());
      final matchPaid = _showPaidOnly ? d.isPaid : !d.isPaid;
      return matchSearch && matchPaid;
    }).toList()..sort((a, b) {
      if (a.isOverdue && !b.isOverdue) return -1;
      if (!a.isOverdue && b.isOverdue) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStateBuilder(
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _UtangHeader(
                  totalUnpaid: state.totalDebtAmount,
                  overdueCount: state.overdueDebts.length,
                  unpaidCount: state.unpaidDebts.length,
                  currency: currency,
                ),
              ],
            );
          },
        ),

        _SearchAndFilter(
          controller: _searchCtrl,
          showPaid: _showPaidOnly,
          onSearch: (v) => setState(() => _search = v),
          onTogglePaid: () => setState(() => _showPaidOnly = !_showPaidOnly),
        ),

        Expanded(
          child: AppStateBuilder(
            builder: (context, state) {
              final filtered = _filtered(state.debts);
              // Get the logged-in user's display name once per build
              final userName = AppState().currentUser?.displayName ?? '';
              return filtered.isEmpty
                  ? _EmptyState(showPaid: _showPaidOnly)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _DebtCard(
                        debt: filtered[i],
                        currency: currency,
                        onPay: () => _showPaymentDialog(filtered[i]),
                        onDelete: () => _confirmDelete(filtered[i]),
                        onReceipt: () =>
                            _showUtangReceipt(filtered[i], userName),
                      ),
                    );
            },
          ),
        ),
      ],
    );
  }

  void _showUtangReceipt(CustomerDebt debt, String userName) {
    UtangReceiptScreen.show(context, debt, userName: userName);
  }

  void _showPaymentDialog(CustomerDebt debt) {
    showDialog(
      context: context,
      builder: (_) => UtangPaymentDialog(debt: debt),
    );
  }

  void _confirmDelete(CustomerDebt debt) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Utang Record',
      message:
          'Delete utang record for ${debt.customerName}? It can be restored from the Recycle Bin.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await AppState().deleteDebt(debt.id);
      if (mounted) {
        KnzToast.info(
          context,
          'Utang for ${debt.customerName} moved to Recycle Bin.',
        );
      }
    } catch (_) {
      if (mounted) {
        KnzToast.error(context, 'The utang record could not be deleted.');
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _UtangHeader — summary stats at the top
// ─────────────────────────────────────────────────────────────────────────────
class _UtangHeader extends StatelessWidget {
  final Money totalUnpaid;
  final int overdueCount;
  final int unpaidCount;
  final NumberFormat currency;

  const _UtangHeader({
    required this.totalUnpaid,
    required this.overdueCount,
    required this.unpaidCount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionHeader(title: '💳  Utang Tracker')),
              IconButton(
                icon: const Icon(
                  Icons.download_outlined,
                  color: AppColors.whiteTertiary,
                ),
                tooltip: 'Export Utang',
                onPressed: () => showExportDialog(context, ExportType.debts),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatChip(
                label: 'TOTAL UTANG',
                value: totalUnpaid.format(),
                color: AppColors.error,
                icon: Icons.money_off,
              ),
              const SizedBox(width: 10),
              _StatChip(
                label: 'UNPAID',
                value: '$unpaidCount orders',
                color: AppColors.warning,
                icon: Icons.pending_outlined,
              ),
              const SizedBox(width: 10),
              _StatChip(
                label: 'OVERDUE',
                value: '$overdueCount (7d+)',
                color: overdueCount > 0 ? AppColors.error : AppColors.success,
                icon: Icons.warning_amber_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 2,
              style: const TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 8,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SearchAndFilter
// ─────────────────────────────────────────────────────────────────────────────
class _SearchAndFilter extends StatelessWidget {
  final TextEditingController controller;
  final bool showPaid;
  final ValueChanged<String> onSearch;
  final VoidCallback onTogglePaid;

  const _SearchAndFilter({
    required this.controller,
    required this.showPaid,
    required this.onSearch,
    required this.onTogglePaid,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: TextField(
                controller: controller,
                onChanged: onSearch,
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search by customer or order ID...',
                  hintStyle: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.whiteTertiary,
                    size: 18,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onTogglePaid,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: showPaid
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: showPaid
                      ? AppColors.success.withValues(alpha: 0.5)
                      : AppColors.cardBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showPaid
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    color: showPaid
                        ? AppColors.success
                        : AppColors.whiteTertiary,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    showPaid ? 'Paid' : 'Unpaid',
                    style: TextStyle(
                      color: showPaid
                          ? AppColors.success
                          : AppColors.whiteTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DebtCard
// ─────────────────────────────────────────────────────────────────────────────
class _DebtCard extends StatefulWidget {
  final CustomerDebt debt;
  final NumberFormat currency;
  final VoidCallback onPay;
  final VoidCallback onDelete;
  final VoidCallback onReceipt;

  const _DebtCard({
    required this.debt,
    required this.currency,
    required this.onPay,
    required this.onDelete,
    required this.onReceipt,
  });

  @override
  State<_DebtCard> createState() => _DebtCardState();
}

class _DebtCardState extends State<_DebtCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AppStateBuilder(
      builder: (context, state) {
        final debt = state.debts.firstWhere(
          (d) => d.id == widget.debt.id,
          orElse: () => widget.debt,
        );
        final dateFmt = DateFormat('MMM dd, yyyy');

        final borderColor = debt.isPaid
            ? AppColors.success
            : debt.isOverdue
            ? AppColors.error
            : AppColors.cardBorder;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: debt.isPaid
                                ? AppColors.success
                                : debt.isOverdue
                                ? AppColors.error
                                : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                debt.customerName,
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 6,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    debt.orderId,
                                    style: const TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    '• ${dateFmt.format(debt.createdAt)}',
                                    style: const TextStyle(
                                      color: AppColors.whiteTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (debt.isOverdue)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${debt.daysOld}d overdue',
                                        style: const TextStyle(
                                          color: AppColors.error,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  // ── v6: Interest badge ──────────────────
                                  if (debt.hasInterest)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: AppColors.warning.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        // FIX: Abbreviated to prevent overflow on narrow screens.
                                        // Old: "10% daily (+₱1,234 as of May 23)" — 35+ chars
                                        // New: "10%/day +₱1,234"
                                        '${(debt.interestRateBasisPoints / 100).toStringAsFixed(2)}%'
                                        '/${debt.interestType == 'daily' ? 'day' : 'mo'} '
                                        '+${debt.accruedInterest.format()}',
                                        style: const TextStyle(
                                          color: AppColors.warning,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  debt.totalWithInterest.format(),
                                  style: TextStyle(
                                    color: debt.isPaid
                                        ? AppColors.success
                                        : AppColors.error,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                'of ${debt.totalAmount.format()}',
                                style: const TextStyle(
                                  color: AppColors.whiteTertiary,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ProgressBar(
                      paid: debt.amountPaid,
                      total: debt.totalAmount,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _expanded = !_expanded),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.history,
                                  color: AppColors.whiteTertiary,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'History (${debt.payments.length})',
                                  style: const TextStyle(
                                    color: AppColors.whiteTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _expanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: AppColors.whiteTertiary,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: widget.onReceipt,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.receipt_outlined,
                              color: AppColors.gold,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onDelete,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: AppColors.error,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!debt.isPaid)
                      GestureDetector(
                        onTap: widget.onPay,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            gradient: AppColors.goldGradient,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_card,
                                color: AppColors.background,
                                size: 14,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Add Payment',
                                style: TextStyle(
                                  color: AppColors.background,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.4),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: AppColors.success,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'FULLY PAID',
                              style: TextStyle(
                                color: AppColors.success,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_expanded)
                _PaymentHistory(debt: debt, currency: widget.currency),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProgressBar
// ─────────────────────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final Money paid;
  final Money total;

  const _ProgressBar({required this.paid, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total.isPositive
        ? (paid.centavos / total.centavos).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Paid ${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 10,
              ),
            ),
            Text(
              'Remaining ${((1 - pct) * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppColors.cardBorder,
            valueColor: AlwaysStoppedAnimation(
              pct >= 1.0 ? AppColors.success : AppColors.gold,
            ),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PaymentHistory — expandable list of all payments made
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentHistory extends StatelessWidget {
  final CustomerDebt debt;
  final NumberFormat currency;

  const _PaymentHistory({required this.debt, required this.currency});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM dd, yyyy hh:mm a');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment History',
            style: TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (debt.payments.isEmpty)
            const Text(
              'No payments yet.',
              style: TextStyle(color: AppColors.whiteTertiary, fontSize: 12),
            )
          else
            ...debt.payments.reversed.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.payments_outlined,
                      color: AppColors.success,
                      size: 14,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateFmt.format(p.paidAt),
                            style: const TextStyle(
                              color: AppColors.whiteSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (p.note != null && p.note!.isNotEmpty)
                            Text(
                              p.note!,
                              style: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '+ ${p.amount.format()}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool showPaid;
  const _EmptyState({required this.showPaid});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            showPaid
                ? Icons.check_circle_outline
                : Icons.account_balance_wallet_outlined,
            color: AppColors.whiteTertiary,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            showPaid ? 'No paid utang yet' : 'No unpaid utang! 🎉',
            style: const TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
