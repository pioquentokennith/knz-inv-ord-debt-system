// ─────────────────────────────────────────────────────────────────────────────
// custom_orders_screen.dart — List + manage all custom perfume agreements
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/custom_order_model.dart';
import '../dialogs/custom_order_dialog.dart';
import '../services/agreement_pdf_service.dart';
import '../widgets/shared_widgets.dart';

class CustomOrdersScreen extends StatelessWidget {
  const CustomOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) {
        final orders = AppState().customOrders;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                Expanded(
                  child: orders.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: orders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _CustomOrderCard(order: orders[i]),
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add),
            label: const Text(
              'New Agreement',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const CustomOrderDialog(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        border: Border(bottom: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.draw_outlined, color: AppColors.gold, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Custom Orders',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          // Summary count
          ListenableBuilder(
            listenable: AppState(),
            builder: (context, _) {
              final pending = AppState().customOrders
                  .where((o) => o.status != CustomOrderStatus.delivered)
                  .length;
              if (pending == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '$pending active',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.draw_outlined, color: AppColors.whiteTertiary, size: 56),
          SizedBox(height: 12),
          Text(
            'No custom orders yet',
            style: TextStyle(color: AppColors.whiteSecondary, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            'Tap + to create the first agreement',
            style: TextStyle(color: AppColors.whiteTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomOrderCard
// ─────────────────────────────────────────────────────────────────────────────
class _CustomOrderCard extends StatelessWidget {
  final CustomOrder order;

  const _CustomOrderCard({required this.order});

  static final _dateFmt = DateFormat('MMM dd, yyyy');

  static const _statusColors = {
    CustomOrderStatus.pending: AppColors.warning,
    CustomOrderStatus.inProgress: Color(0xFF29B6F6),
    CustomOrderStatus.ready: AppColors.gold,
    CustomOrderStatus.delivered: AppColors.success,
    CustomOrderStatus.cancelled: AppColors.error,
  };

  Color get _statusColor =>
      _statusColors[order.status] ?? AppColors.whiteTertiary;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: order.isOverdue
              ? AppColors.error.withValues(alpha: 0.5)
              : AppColors.cardBorder,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row ──────────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (order.contact != null)
                      Text(
                        order.contact!,
                        style: const TextStyle(
                          color: AppColors.whiteTertiary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  order.status.displayName,
                  style: TextStyle(
                    color: _statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),

          // ── Fragrance specs (truncated) ───────────────────────────────────────
          Text(
            order.fragranceSpecs,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.whiteSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),

          // ── Pricing row ───────────────────────────────────────────────────────
          Row(
            children: [
              _PricePill(
                'Agreed',
                order.agreedPrice.format(),
                AppColors.whiteSecondary,
              ),
              const SizedBox(width: 8),
              _PricePill('Deposit', order.depositPaid.format(), AppColors.gold),
              const SizedBox(width: 8),
              _PricePill(
                'Balance',
                order.balanceDue.format(),
                order.balanceDue > 0 ? AppColors.error : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Delivery date ─────────────────────────────────────────────────────
          Row(
            children: [
              Icon(
                order.isOverdue
                    ? Icons.warning_amber_outlined
                    : Icons.calendar_today_outlined,
                size: 13,
                color: order.isOverdue
                    ? AppColors.error
                    : AppColors.whiteTertiary,
              ),
              const SizedBox(width: 5),
              Text(
                'Delivery: ${_dateFmt.format(order.deliveryDate)}'
                '${order.isOverdue ? '  ⚠ Overdue' : ''}',
                style: TextStyle(
                  color: order.isOverdue
                      ? AppColors.error
                      : AppColors.whiteTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Action row ────────────────────────────────────────────────────────
          Row(
            children: [
              // Status update dropdown
              Expanded(child: _StatusDropdown(order: order)),
              const SizedBox(width: 8),
              if (order.balanceDue.isPositive) ...[
                _IconBtn(
                  icon: Icons.payments_outlined,
                  color: AppColors.success,
                  tooltip: 'Record Payment',
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => _CustomOrderPaymentDialog(order: order),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // PDF export button
              _IconBtn(
                icon: Icons.picture_as_pdf_outlined,
                color: AppColors.gold,
                tooltip: 'Export Agreement PDF',
                onTap: () async {
                  final owner =
                      AppState().currentUser?.displayName ?? 'KNZ Scent';
                  await AgreementPdfService.instance.generateAndShare(
                    order,
                    ownerName: owner,
                  );
                },
              ),
              const SizedBox(width: 8),
              // Edit button
              _IconBtn(
                icon: Icons.edit_outlined,
                color: AppColors.whiteSecondary,
                tooltip: 'Edit',
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => CustomOrderDialog(existing: order),
                ),
              ),
              if (AppState().isAdministrator) ...[
                const SizedBox(width: 8),
                _IconBtn(
                  icon: Icons.delete_outline,
                  color: AppColors.error,
                  tooltip: 'Delete',
                  onTap: () => _confirmDelete(context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Agreement',
      message:
          'Delete custom order for ${order.customerName}? This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirm || !context.mounted) return;
    try {
      await AppState().deleteCustomOrder(order.id);
      if (context.mounted) {
        KnzToast.info(
          context,
          'Custom order for ${order.customerName} deleted.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        KnzToast.error(context, 'The custom order could not be deleted.');
      }
    }
  }
}

class _CustomOrderPaymentDialog extends StatefulWidget {
  const _CustomOrderPaymentDialog({required this.order});

  final CustomOrder order;

  @override
  State<_CustomOrderPaymentDialog> createState() =>
      _CustomOrderPaymentDialogState();
}

class _CustomOrderPaymentDialogState extends State<_CustomOrderPaymentDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Money.tryParse(_amountController.text.trim());
    if (amount == null ||
        !amount.isPositive ||
        amount > widget.order.balanceDue) {
      KnzToast.warning(context, 'Enter an amount up to the remaining balance.');
      return;
    }
    setState(() => _saving = true);
    try {
      await AppState().addCustomOrderPayment(
        widget.order.id,
        CustomOrderPayment(
          id: const Uuid().v4(),
          customOrderId: widget.order.id,
          amount: amount,
          paidAt: DateTime.now(),
          note: _noteController.text,
        ),
      );
      if (mounted) {
        Navigator.pop(context);
        KnzToast.success(context, 'Custom-order payment recorded.');
      }
    } catch (_) {
      if (mounted) {
        KnzToast.error(context, 'The payment could not be saved.');
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: AppColors.surface,
    title: const Text('Record Payment'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Balance: ${widget.order.balanceDue.format()}',
          style: const TextStyle(color: AppColors.whiteSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving...' : 'Save'),
      ),
    ],
  );
}

class _PricePill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _PricePill(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.7),
            fontSize: 9,
            letterSpacing: 1,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    ),
  );
}

// Status update dropdown — inline quick-update without opening the edit dialog
class _StatusDropdown extends StatelessWidget {
  final CustomOrder order;

  const _StatusDropdown({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CustomOrderStatus>(
          value: order.status,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          style: const TextStyle(color: AppColors.whiteSecondary, fontSize: 12),
          items: CustomOrderStatus.values
              .map(
                (s) => DropdownMenuItem(value: s, child: Text(s.displayName)),
              )
              .toList(),
          onChanged: (s) async {
            if (s != null) {
              try {
                await AppState().updateCustomOrderStatus(order.id, s);
                if (context.mounted) {
                  KnzToast.info(context, 'Status updated to ${s.displayName}.');
                }
              } catch (_) {
                if (context.mounted) {
                  KnzToast.error(context, 'The status could not be updated.');
                }
              }
            }
          },
        ),
      ),
    );
  }
}
