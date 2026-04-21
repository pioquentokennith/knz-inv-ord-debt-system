// ─────────────────────────────────────────────────────────────────────────────
// orders_screen.dart
// Purpose : Order tracker showing all customer orders with status management.
// Function: Applies FIX 6 pattern — header and search bar are outside AppStateBuilder
//           so they never rebuild from AppState changes. Only the order list subtree
//           rebuilds. Supports searching by order ID, customer name, or product name,
//           and filtering by order status. Each order shows a status badge, total,
//           and action buttons (update status, view receipt, delete). Updating a
//           status to "utang" automatically opens the MarkAsUtangDialog.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/app_state_builder.dart'; // ← FIX 6
import '../models/order_model.dart';
import '../widgets/shared_widgets.dart';
import '../dialogs/order_dialog.dart';
import '../dialogs/mark_as_utang_dialog.dart'; // ← FIX 5 import
import 'receipt_screen.dart';
import '../dialogs/export_dialog.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  // ── FIX 6: No more _state, addListener, or _onStateChange boilerplate ────
  // Local UI state only — search text and filter dropdown
  final _searchCtrl = TextEditingController();
  OrderStatus? _filterStatus;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Filters the order list by search query and/or status dropdown.
  // Pure function — takes the current list and returns a filtered copy.
  List<Order> _filtered(List<Order> orders) {
    var list = orders.toList();
    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((o) =>
              o.orderId.toLowerCase().contains(q) ||
              o.customerName.toLowerCase().contains(q) ||
              o.productName.toLowerCase().contains(q))
          .toList();
    }
    if (_filterStatus != null) {
      list = list.where((o) => o.status == _filterStatus).toList();
    }
    return list;
  }

  // Opens a status picker dialog then confirms the change with the user.
  // If the new status is 'utang', automatically opens MarkAsUtangDialog.
  void _updateStatus(Order order) async {
    final result = await showDialog<OrderStatus>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Update ${order.orderId}',
            style: const TextStyle(color: AppColors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...OrderStatus.values.map((s) => ListTile(
                  leading: OrderStatusBadge(status: s),
                  onTap: () => Navigator.pop(context, s),
                  selected: order.status == s,
                  selectedColor: AppColors.gold,
                )),
          ],
        ),
      ),
    );

    if (result == null) return;

    // ── Confirmation prompt ───────────────────────────────────────────────
    if (!mounted) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Update Status?',
      message:
          'Change status of ${order.orderId} to "${result.displayName}"?',
      confirmLabel: 'Update',
    );
    if (!confirmed || !mounted) return;
    // ── END Confirmation ──────────────────────────────────────────────────

    await AppState().updateOrderStatus(order.id, result);

    if (result == OrderStatus.utang && mounted) {
      MarkAsUtangDialog.show(context, order);
    }
  }

  // Shows a confirmation dialog then soft-deletes the order via AppState.
  void _deleteOrder(Order order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Order',
            style: TextStyle(color: AppColors.white)),
        content: Text('Remove order ${order.orderId}?',
            style:
                const TextStyle(color: AppColors.whiteSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style:
                      TextStyle(color: AppColors.whiteTertiary))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm == true) await AppState().deleteOrder(order.id);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFmt  = DateFormat('MMM dd, yyyy');
    final isWide   = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // ── Header + New Order button — NEVER rebuilds from AppState ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined,
                    color: AppColors.gold, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Order Tracker',
                      style: TextStyle(
                          color: AppColors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                ),
                GoldButton(
                  label: '+ New Order',
                  width: 130,
                  height: 44,
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const OrderDialog(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.download_outlined, color: AppColors.whiteTertiary),
                  tooltip: 'Export Orders',
                  onPressed: () => showExportDialog(context, ExportType.orders),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Search + Filter — local setState only ─────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                        color: AppColors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search by ID or customer...',
                      hintStyle: const TextStyle(
                          color: AppColors.whiteTertiary,
                          fontSize: 14),
                      prefixIcon: const Icon(Icons.search,
                          color: AppColors.whiteTertiary, size: 20),
                      filled: true,
                      fillColor: AppColors.inputFill,
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<OrderStatus?>(
                        value: _filterStatus,
                        hint: const Text('All Status',
                            style: TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 13)),
                        dropdownColor: AppColors.surfaceElevated,
                        style: const TextStyle(
                            color: AppColors.white, fontSize: 13),
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: AppColors.whiteTertiary),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<OrderStatus?>(
                            value: null,
                            child: Text('All Status'),
                          ),
                          ...OrderStatus.values.map(
                            (s) => DropdownMenuItem<OrderStatus?>(
                              value: s,
                              child: Text(s.displayName),
                            ),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _filterStatus = v),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── FIX 6: AppStateBuilder scopes rebuilds to the list only ──
          // The header, search bar, and filter above this line are
          // completely unaffected by AppState changes.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppStateBuilder(                      // ← FIX 6
                builder: (context, state) {
                  final filtered = _filtered(state.orders);
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(children: [
                                Icon(Icons.list,
                                    color: AppColors.gold, size: 18),
                                SizedBox(width: 8),
                                Text('Orders',
                                    style: TextStyle(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                              ]),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.gold
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${filtered.length} ORDERS',
                                  style: const TextStyle(
                                      color: AppColors.gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(
                            color: AppColors.divider, height: 1),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text('No orders found.',
                                      style: TextStyle(
                                          color: AppColors.whiteTertiary,
                                          fontSize: 14)))
                              : AnimationLimiter(
                                  child: ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(
                                            color: AppColors.divider,
                                            height: 1),
                                    itemBuilder: (ctx, i) {
                                      final o = filtered[i];
                                      return AnimationConfiguration
                                          .staggeredList(
                                        position: i,
                                        duration: const Duration(
                                            milliseconds: 300),
                                        child: SlideAnimation(
                                          horizontalOffset: 30,
                                          child: FadeInAnimation(
                                            child: isWide
                                                ? _OrderRowWide(
                                                    order: o,
                                                    currency: currency,
                                                    dateFmt: dateFmt,
                                                    onUpdate: () =>
                                                        _updateStatus(o),
                                                    onDelete: () =>
                                                        _deleteOrder(o),
                                                    onReceipt: () =>
                                                        ReceiptScreen.show(
                                                            context, o),
                                                    onUtang: () =>
                                                        MarkAsUtangDialog
                                                            .show(
                                                                context,
                                                                o),
                                                  )
                                                : _OrderCard(
                                                    order: o,
                                                    currency: currency,
                                                    dateFmt: dateFmt,
                                                    onUpdate: () =>
                                                        _updateStatus(o),
                                                    onDelete: () =>
                                                        _deleteOrder(o),
                                                    onReceipt: () =>
                                                        ReceiptScreen.show(
                                                            context, o),
                                                    onUtang: () =>
                                                        MarkAsUtangDialog
                                                            .show(
                                                                context,
                                                                o),
                                                  ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Card / Row widgets unchanged from original ────────────────────────────────
class _OrderCard extends StatelessWidget {
  final Order order;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onReceipt;
  final VoidCallback onUtang;

  const _OrderCard({
    required this.order,
    required this.currency,
    required this.dateFmt,
    required this.onUpdate,
    required this.onDelete,
    required this.onReceipt,
    required this.onUtang,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(order.orderId,
                style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            const Spacer(),
            OrderStatusBadge(status: order.status),
            const SizedBox(width: 8),
            DarkIconButton(
              icon: Icons.delete_outline,
              color: AppColors.error,
              onPressed: onDelete,
            ),
          ]),
          const SizedBox(height: 6),
          Text(order.customerName,
              style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 8),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.circle,
                      size: 5, color: AppColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${item.productName} × ${item.quantity}',
                      style: const TextStyle(
                          color: AppColors.whiteSecondary,
                          fontSize: 12),
                    ),
                  ),
                  Text(
                    currency.format(item.subtotal),
                    style: const TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 12),
                  ),
                ]),
              )),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dateFmt.format(order.orderDate),
                  style: const TextStyle(
                      color: AppColors.whiteTertiary, fontSize: 11)),
              Text(currency.format(order.totalAmount),
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
              onPressed: onUpdate,
              icon: const Icon(Icons.edit_outlined,
                  size: 14, color: AppColors.gold),
              label: const Text('Status',
                  style: TextStyle(
                      color: AppColors.gold, fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.cardBorder),
                padding:
                    const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton.icon(
              onPressed: onReceipt,
              icon: const Icon(Icons.receipt_outlined,
                  size: 14, color: AppColors.whiteSecondary),
              label: const Text('Receipt',
                  style: TextStyle(
                      color: AppColors.whiteSecondary,
                      fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.cardBorder),
                padding:
                    const EdgeInsets.symmetric(vertical: 8),
              ),
            )),
          ]),
        ],
      ),
    );
  }
}

class _OrderRowWide extends StatelessWidget {
  final Order order;
  final NumberFormat currency;
  final DateFormat dateFmt;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onReceipt;
  final VoidCallback onUtang;

  const _OrderRowWide({
    required this.order,
    required this.currency,
    required this.dateFmt,
    required this.onUpdate,
    required this.onDelete,
    required this.onReceipt,
    required this.onUtang,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: 100,
          child: Text(order.orderId,
              style: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
        ),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customerName,
                    style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(order.productName,
                    style: const TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11)),
              ]),
        ),
        const SizedBox(width: 12),
        OrderStatusBadge(status: order.status),
        const SizedBox(width: 16),
        Text(currency.format(order.totalAmount),
            style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
        const SizedBox(width: 16),
        Text(dateFmt.format(order.orderDate),
            style: const TextStyle(
                color: AppColors.whiteTertiary, fontSize: 11)),
        const SizedBox(width: 12),
        DarkIconButton(
            icon: Icons.edit_outlined,
            color: AppColors.gold,
            onPressed: onUpdate),
        DarkIconButton(
            icon: Icons.receipt_outlined,
            color: AppColors.whiteSecondary,
            onPressed: onReceipt),
        DarkIconButton(
            icon: Icons.delete_outline,
            color: AppColors.error,
            onPressed: onDelete),
      ]),
    );
  }
}
