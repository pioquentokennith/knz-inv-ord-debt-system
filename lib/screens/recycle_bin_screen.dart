// ─────────────────────────────────────────────────────────────────────────────
// recycle_bin_screen.dart
// Purpose : Shows soft-deleted items (orders, products, utang) and lets the admin
//           restore or permanently delete them.
// Function: Loads deleted records from AppState on mount via parallel Future.wait().
//           Provides three tabs (Orders, Products, Utang) each with their own
//           filtered list. A shared search bar filters results in real time across
//           all tabs. Restore triggers AppState.restoreX() and hard-delete triggers
//           AppState.hardDeleteX(), both with confirmation dialogs. Each item is
//           rendered as a _BinCard with restore and delete-forever action buttons.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../widgets/shared_widgets.dart';

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

  // Loads all soft-deleted items from AppState in parallel using Future.wait().
  // Updates local lists and clears the loading flag on completion.
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

  // Shows a restore confirmation dialog, then calls AppState.restoreOrder()
  // to move the order back to the active list. Refreshes the bin list after.
  Future<void> _restoreOrder(Order order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Restore Order',
      message: 'Move order ${order.orderId} back to your active Orders list?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      icon: Icons.restore_rounded,
    );
    if (!confirm || !mounted) return;
    await _appState.restoreOrder(order.id);
    if (mounted) KnzToast.success(context, '♻️ Order ${order.orderId} restored.');
    await _load();
  }

  Future<void> _restoreProduct(Product product) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Restore Product',
      message: 'Move "${product.name}" back to your active Inventory list?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      icon: Icons.restore_rounded,
    );
    if (!confirm || !mounted) return;
    await _appState.restoreProduct(product.id);
    if (mounted) KnzToast.success(context, '♻️ "${product.name}" restored to Inventory.');
    await _load();
  }

  Future<void> _hardDeleteOrder(Order order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message: 'Permanently delete order ${order.orderId}? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    await _appState.hardDeleteOrder(order.id);
    if (mounted) KnzToast.error(context, '❌ Order ${order.orderId} permanently deleted.');
    await _load();
  }

  Future<void> _hardDeleteProduct(Product product) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message: 'Permanently delete "${product.name}"? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    await _appState.hardDeleteProduct(product.id);
    if (mounted) KnzToast.error(context, '❌ "${product.name}" permanently deleted.');
    await _load();
  }

  Future<void> _restoreDebt(CustomerDebt debt) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Restore Utang',
      message: 'Move utang for ${debt.customerName} back to your active Utang list?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      icon: Icons.restore_rounded,
    );
    if (!confirm || !mounted) return;
    await _appState.restoreDebt(debt.id);
    if (mounted) KnzToast.success(context, '♻️ Utang for ${debt.customerName} restored.');
    await _load();
  }

  Future<void> _hardDeleteDebt(CustomerDebt debt) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message: 'Permanently delete utang record for ${debt.customerName}? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    await _appState.hardDeleteDebt(debt.id);
    if (mounted) KnzToast.error(context, '❌ Utang record for ${debt.customerName} permanently deleted.');
    await _load();
  }

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
