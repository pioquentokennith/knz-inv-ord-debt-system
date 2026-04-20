// ─────────────────────────────────────────────────────────────────────────────
// recycle_bin_screen.dart — View and restore soft-deleted items
// Features:
//   • Tab view: Products | Orders
//   • Restore button — un-deletes and puts back to active list
//   • Permanent delete button — hard purge with confirmation dialog
//   • Shows deleted_at timestamp for audit trail
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends State<RecycleBinScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _appState = AppState();

  List<Order>        _deletedOrders   = [];
  List<Product>      _deletedProducts = [];
  List<CustomerDebt> _deletedDebts    = [];
  bool _isLoading = true;

  // ── Search ────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<Order> get _filteredOrders {
    if (_searchQuery.isEmpty) return _deletedOrders;
    final q = _searchQuery.toLowerCase();
    return _deletedOrders.where((o) =>
      o.orderId.toLowerCase().contains(q) ||
      o.customerName.toLowerCase().contains(q)).toList();
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _deletedProducts;
    final q = _searchQuery.toLowerCase();
    return _deletedProducts.where((p) =>
      p.name.toLowerCase().contains(q) ||
      p.category.displayName.toLowerCase().contains(q)).toList();
  }

  List<CustomerDebt> get _filteredDebts {
    if (_searchQuery.isEmpty) return _deletedDebts;
    final q = _searchQuery.toLowerCase();
    return _deletedDebts.where((d) =>
      d.customerName.toLowerCase().contains(q) ||
      d.orderId.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // FIX: was 2, now 3 tabs
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _appState.getDeletedOrders(),
      _appState.getDeletedProducts(),
      _appState.getDeletedDebts(),
    ]);
    if (mounted) {
      setState(() {
        _deletedOrders   = results[0] as List<Order>;
        _deletedProducts = results[1] as List<Product>;
        _deletedDebts    = results[2] as List<CustomerDebt>;
        _isLoading       = false;
      });
    }
  }

  Future<void> _restoreOrder(Order order) async {
    final confirm = await _restoreDialog(
        'Restore order ${order.orderId}?',
        'This will move it back to your active Orders list.');
    if (confirm != true) return;
    await _appState.restoreOrder(order.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order ${order.orderId} restored'),
        backgroundColor: AppColors.success,
      ));
    }
    await _load();
  }

  Future<void> _restoreProduct(Product product) async {
    final confirm = await _restoreDialog(
        'Restore "${product.name}"?',
        'This will move it back to your active Inventory list.');
    if (confirm != true) return;
    await _appState.restoreProduct(product.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${product.name}" restored'),
        backgroundColor: AppColors.success,
      ));
    }
    await _load();
  }

  Future<void> _hardDeleteOrder(Order order) async {
    final confirm = await _confirmDialog(
        'Permanently delete order ${order.orderId}?\n\nThis cannot be undone.');
    if (confirm != true) return;
    await _appState.hardDeleteOrder(order.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Order permanently deleted'),
        backgroundColor: AppColors.error,
      ));
    }
    await _load();
  }

  Future<void> _hardDeleteProduct(Product product) async {
    final confirm = await _confirmDialog(
        'Permanently delete "${product.name}"?\n\nThis cannot be undone.');
    if (confirm != true) return;
    await _appState.hardDeleteProduct(product.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Product permanently deleted'),
        backgroundColor: AppColors.error,
      ));
    }
    await _load();
  }

  Future<void> _restoreDebt(CustomerDebt debt) async {
    final confirm = await _restoreDialog(
        'Restore utang for ${debt.customerName}?',
        'This will move it back to your active Utang list.');
    if (confirm != true) return;
    await _appState.restoreDebt(debt.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Utang for ${debt.customerName} restored'),
        backgroundColor: AppColors.success,
      ));
    }
    await _load();
  }

  Future<void> _hardDeleteDebt(CustomerDebt debt) async {
    final confirm = await _confirmDialog(
        'Permanently delete utang for ${debt.customerName}?\n\nThis cannot be undone.');
    if (confirm != true) return;
    await _appState.hardDeleteDebt(debt.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Utang record permanently deleted'),
        backgroundColor: AppColors.error,
      ));
    }
    await _load();
  }

  Future<bool?> _restoreDialog(String title, String message) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.restore, color: AppColors.success, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              style: const TextStyle(color: AppColors.white, fontSize: 15)),
        ),
      ]),
      content: Text(message,
          style: const TextStyle(color: AppColors.whiteSecondary, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.whiteTertiary)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.restore, size: 16),
          label: const Text('Yes, Restore'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );

  Future<bool?> _confirmDialog(String message) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Confirm', style: TextStyle(color: AppColors.white)),
      content: Text(message,
          style: const TextStyle(color: AppColors.whiteSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.whiteTertiary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Forever',
              style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        title: const Text('Recycle Bin',
            style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.whiteTertiary),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              // ── Search Bar ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  style: const TextStyle(color: AppColors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by name, ID, category...',
                    hintStyle: const TextStyle(
                        color: AppColors.whiteTertiary, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.whiteTertiary, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                color: AppColors.whiteTertiary, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 12),
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
                  ),
                ),
              ),
              // ── Tabs ────────────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.whiteTertiary,
                indicatorColor: AppColors.gold,
                tabs: [
                  Tab(text: 'Orders (${_filteredOrders.length})'),
                  Tab(text: 'Products (${_filteredProducts.length})'),
                  Tab(text: 'Utang (${_filteredDebts.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : TabBarView(
              controller: _tabController,
              children: [
                _ordersBin(),
                _productsBin(),
                _debtsBin(),
              ],
            ),
    );
  }

  // ── Deleted Orders Tab ────────────────────────────────────────────────────
  Widget _ordersBin() {
    final list = _filteredOrders;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty ? 'No deleted orders' : 'No results for "$_searchQuery"',
        Icons.receipt_long_outlined,
      );
    }
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final order = list[i];
        return _BinCard(
          title: order.orderId,
          subtitle: order.customerName,
          detail: currency.format(order.totalAmount),
          badge: order.status.displayName,
          badgeColor: order.status.color,
          onRestore: () => _restoreOrder(order),
          onDelete:  () => _hardDeleteOrder(order),
        );
      },
    );
  }

  // ── Deleted Products Tab ──────────────────────────────────────────────────
  Widget _productsBin() {
    final list = _filteredProducts;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty ? 'No deleted products' : 'No results for "$_searchQuery"',
        Icons.inventory_2_outlined,
      );
    }
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        return _BinCard(
          title: p.name,
          subtitle: p.category.displayName,
          detail: currency.format(p.price),
          badge: 'Stock was: ${p.stockQty}',
          badgeColor: AppColors.whiteTertiary,
          onRestore: () => _restoreProduct(p),
          onDelete:  () => _hardDeleteProduct(p),
        );
      },
    );
  }

  // ── Deleted Debts Tab — FIX: debts now have recycle bin support ───────────
  Widget _debtsBin() {
    final list = _filteredDebts;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty ? 'No deleted utang records' : 'No results for "$_searchQuery"',
        Icons.account_balance_wallet_outlined,
      );
    }
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final d = list[i];
        final statusLabel = d.isPaid ? 'Paid' : d.isOverdue ? 'Overdue' : 'Unpaid';
        final statusColor = d.isPaid
            ? AppColors.success
            : d.isOverdue ? AppColors.error : AppColors.warning;
        return _BinCard(
          title: d.customerName,
          subtitle: 'Order: ${d.orderId}',
          detail: currency.format(d.remainingBalance),
          badge: statusLabel,
          badgeColor: statusColor,
          onRestore: () => _restoreDebt(d),
          onDelete:  () => _hardDeleteDebt(d),
        );
      },
    );
  }

  Widget _emptyState(String label, IconData icon) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: AppColors.whiteTertiary),
        const SizedBox(height: 12),
        Text(label,
            style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 16)),
      ],
    ),
  );
}

// ── Reusable bin card ─────────────────────────────────────────────────────────
class _BinCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String detail;
  final String badge;
  final Color  badgeColor;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _BinCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.badge,
    required this.badgeColor,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_outline,
                  color: AppColors.error, size: 20),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.whiteSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(detail,
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge,
                          style: TextStyle(
                              color: badgeColor, fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                _actionBtn(
                  icon: Icons.restore,
                  color: AppColors.success,
                  tooltip: 'Restore',
                  onTap: onRestore,
                ),
                const SizedBox(height: 6),
                _actionBtn(
                  icon: Icons.delete_forever,
                  color: AppColors.error,
                  tooltip: 'Delete Forever',
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      );
}
