// ─────────────────────────────────────────────────────────────────────────────
// recycle_bin_screen.dart
// Purpose : Shows all soft-deleted records and lets the admin restore or
//           permanently delete them.
// Function: Loads deleted records from AppState on mount via parallel Future.wait().
//           Provides tabs for orders, products, utang, custom orders, and
//           resellers, each with their own
//           filtered list. A shared search bar filters results in real time across
//           all tabs. Restore triggers AppState.restoreX() and hard-delete triggers
//           AppState.hardDeleteX(), both with confirmation dialogs. Each item is
//           rendered as a _BinCard with restore and delete-forever action buttons.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../models/custom_order_model.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/reseller_model.dart';
import '../services/accounting_service.dart';
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

  List<Order> _deletedOrders = [];
  List<Product> _deletedProducts = [];
  List<CustomerDebt> _deletedDebts = [];
  List<CustomOrder> _deletedCustomOrders = [];
  List<Reseller> _deletedResellers = [];
  bool _isLoading = true;

  // ── Search ────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  List<Order> get _filteredOrders {
    if (_searchQuery.isEmpty) return _deletedOrders;
    final q = _searchQuery.toLowerCase();
    return _deletedOrders
        .where(
          (o) =>
              o.orderId.toLowerCase().contains(q) ||
              o.customerName.toLowerCase().contains(q),
        )
        .toList();
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) return _deletedProducts;
    final q = _searchQuery.toLowerCase();
    return _deletedProducts
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.category.displayName.toLowerCase().contains(q),
        )
        .toList();
  }

  List<CustomerDebt> get _filteredDebts {
    if (_searchQuery.isEmpty) return _deletedDebts;
    final q = _searchQuery.toLowerCase();
    return _deletedDebts
        .where(
          (d) =>
              d.customerName.toLowerCase().contains(q) ||
              d.orderId.toLowerCase().contains(q),
        )
        .toList();
  }

  List<CustomOrder> get _filteredCustomOrders {
    if (_searchQuery.isEmpty) return _deletedCustomOrders;
    final q = _searchQuery.toLowerCase();
    return _deletedCustomOrders
        .where(
          (order) =>
              order.customerName.toLowerCase().contains(q) ||
              order.fragranceSpecs.toLowerCase().contains(q) ||
              (order.contact?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  List<Reseller> get _filteredResellers {
    if (_searchQuery.isEmpty) return _deletedResellers;
    final q = _searchQuery.toLowerCase();
    return _deletedResellers
        .where(
          (reseller) =>
              reseller.name.toLowerCase().contains(q) ||
              (reseller.contact?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
      _appState.getDeletedCustomOrders(),
      _appState.getDeletedResellers(),
    ]);
    if (mounted) {
      setState(() {
        _deletedOrders = results[0] as List<Order>;
        _deletedProducts = results[1] as List<Product>;
        _deletedDebts = results[2] as List<CustomerDebt>;
        _deletedCustomOrders = results[3] as List<CustomOrder>;
        _deletedResellers = results[4] as List<Reseller>;
        _isLoading = false;
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
    try {
      await _appState.restoreOrder(order.id);
      if (mounted)
        KnzToast.success(context, 'Order ${order.orderId} restored.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      KnzToast.error(context, error.toString().replaceFirst('Exception: ', ''));
    }
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
    try {
      await _appState.restoreProduct(product.id);
      if (mounted)
        KnzToast.success(context, '"${product.name}" restored to Inventory.');
      await _load();
    } catch (_) {
      if (mounted)
        KnzToast.error(context, 'The product could not be restored.');
    }
  }

  Future<void> _hardDeleteOrder(Order order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message:
          'Permanently delete order ${order.orderId}? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.hardDeleteOrder(order.id);
      if (mounted)
        KnzToast.info(context, 'Order ${order.orderId} permanently deleted.');
      await _load();
    } catch (error) {
      if (mounted) {
        KnzToast.error(
          context,
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
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
    try {
      await _appState.hardDeleteProduct(product.id);
      if (mounted)
        KnzToast.info(context, '"${product.name}" permanently deleted.');
      await _load();
    } catch (_) {
      if (mounted)
        KnzToast.error(
          context,
          'The product could not be permanently deleted.',
        );
    }
  }

  Future<void> _restoreDebt(CustomerDebt debt) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Restore Utang',
      message:
          'Move utang for ${debt.customerName} back to your active Utang list?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      icon: Icons.restore_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.restoreDebt(debt.id);
      if (mounted)
        KnzToast.success(context, 'Utang for ${debt.customerName} restored.');
      await _load();
    } catch (_) {
      if (mounted)
        KnzToast.error(context, 'The utang record could not be restored.');
    }
  }

  Future<void> _hardDeleteDebt(CustomerDebt debt) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message:
          'Permanently delete utang record for ${debt.customerName}? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.hardDeleteDebt(debt.id);
      if (mounted) {
        KnzToast.info(
          context,
          'Utang record for ${debt.customerName} permanently deleted.',
        );
      }
      await _load();
    } catch (_) {
      if (mounted)
        KnzToast.error(
          context,
          'The utang record could not be permanently deleted.',
        );
    }
  }

  Future<void> _restoreCustomOrder(CustomOrder order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Restore Custom Order',
      message:
          'Move the custom order for ${order.customerName} back to the active list?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      icon: Icons.restore_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.restoreCustomOrder(order.id);
      if (mounted) {
        KnzToast.success(
          context,
          'Custom order for ${order.customerName} restored.',
        );
      }
      await _load();
    } catch (_) {
      if (mounted)
        KnzToast.error(context, 'The custom order could not be restored.');
    }
  }

  Future<void> _hardDeleteCustomOrder(CustomOrder order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message:
          'Permanently delete the custom order for ${order.customerName}? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.hardDeleteCustomOrder(order.id);
      if (mounted) {
        KnzToast.info(
          context,
          'Custom order for ${order.customerName} permanently deleted.',
        );
      }
      await _load();
    } catch (_) {
      if (mounted) {
        KnzToast.error(
          context,
          'The custom order could not be permanently deleted.',
        );
      }
    }
  }

  Future<void> _restoreReseller(Reseller reseller) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Restore Reseller',
      message: 'Move "${reseller.name}" back to the active Resellers list?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      icon: Icons.restore_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.restoreReseller(reseller.id);
      if (mounted) KnzToast.success(context, '"${reseller.name}" restored.');
      await _load();
    } catch (_) {
      if (mounted)
        KnzToast.error(context, 'The reseller could not be restored.');
    }
  }

  Future<void> _hardDeleteReseller(Reseller reseller) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Delete Forever?',
      message:
          'Permanently delete reseller "${reseller.name}"? This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirm || !mounted) return;
    try {
      await _appState.hardDeleteReseller(reseller.id);
      if (mounted)
        KnzToast.info(context, '"${reseller.name}" permanently deleted.');
      await _load();
    } catch (_) {
      if (mounted) {
        KnzToast.error(
          context,
          'The reseller could not be permanently deleted.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        title: const Text(
          'Recycle Bin',
          style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
        ),
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
                      color: AppColors.whiteTertiary,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.whiteTertiary,
                      size: 18,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: AppColors.whiteTertiary,
                              size: 16,
                            ),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
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
                ),
              ),
              // ── Tabs ────────────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: AppColors.gold,
                unselectedLabelColor: AppColors.whiteTertiary,
                indicatorColor: AppColors.gold,
                tabs: [
                  Tab(text: 'Orders (${_filteredOrders.length})'),
                  Tab(text: 'Products (${_filteredProducts.length})'),
                  Tab(text: 'Utang (${_filteredDebts.length})'),
                  Tab(text: 'Custom (${_filteredCustomOrders.length})'),
                  Tab(text: 'Resellers (${_filteredResellers.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _ordersBin(),
                _productsBin(),
                _debtsBin(),
                _customOrdersBin(),
                _resellersBin(),
              ],
            ),
    );
  }

  // ── Deleted Orders Tab ────────────────────────────────────────────────────
  Widget _ordersBin() {
    final list = _filteredOrders;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty
            ? 'No deleted orders'
            : 'No results for "$_searchQuery"',
        Icons.receipt_long_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final order = list[i];
        return _BinCard(
          title: order.orderId,
          subtitle: order.customerName,
          detail: AccountingService.instance
              .orderBreakdown(order)
              .customerPayTotal
              .format(),
          badge: order.status.displayName,
          badgeColor: order.status.color,
          onRestore: () => _restoreOrder(order),
          onDelete: () => _hardDeleteOrder(order),
        );
      },
    );
  }

  // ── Deleted Products Tab ──────────────────────────────────────────────────
  Widget _productsBin() {
    final list = _filteredProducts;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty
            ? 'No deleted products'
            : 'No results for "$_searchQuery"',
        Icons.inventory_2_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        return _BinCard(
          title: p.name,
          subtitle: p.category.displayName,
          detail: p.price.format(),
          badge: 'Stock was: ${p.stockQty}',
          badgeColor: AppColors.whiteTertiary,
          onRestore: () => _restoreProduct(p),
          onDelete: () => _hardDeleteProduct(p),
        );
      },
    );
  }

  // ── Deleted Debts Tab — FIX: debts now have recycle bin support ───────────
  Widget _debtsBin() {
    final list = _filteredDebts;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty
            ? 'No deleted utang records'
            : 'No results for "$_searchQuery"',
        Icons.account_balance_wallet_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final d = list[i];
        final statusLabel = d.isPaid
            ? 'Paid'
            : d.isOverdue
            ? 'Overdue'
            : 'Unpaid';
        final statusColor = d.isPaid
            ? AppColors.success
            : d.isOverdue
            ? AppColors.error
            : AppColors.warning;
        return _BinCard(
          title: d.customerName,
          subtitle: 'Order: ${d.orderId}',
          detail: d.totalWithInterest.format(),
          badge: statusLabel,
          badgeColor: statusColor,
          onRestore: () => _restoreDebt(d),
          onDelete: () => _hardDeleteDebt(d),
        );
      },
    );
  }

  // ── Deleted Custom Orders Tab ────────────────────────────────────────────
  Widget _customOrdersBin() {
    final list = _filteredCustomOrders;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty
            ? 'No deleted custom orders'
            : 'No results for "$_searchQuery"',
        Icons.auto_awesome_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final order = list[i];
        return _BinCard(
          title: order.customerName,
          subtitle: order.fragranceSpecs,
          detail: order.agreedPrice.format(),
          badge: order.status.displayName,
          badgeColor: _customOrderStatusColor(order.status),
          onRestore: () => _restoreCustomOrder(order),
          onDelete: () => _hardDeleteCustomOrder(order),
        );
      },
    );
  }

  Color _customOrderStatusColor(CustomOrderStatus status) {
    switch (status) {
      case CustomOrderStatus.pending:
        return AppColors.warning;
      case CustomOrderStatus.inProgress:
        return AppColors.gold;
      case CustomOrderStatus.ready:
      case CustomOrderStatus.delivered:
        return AppColors.success;
      case CustomOrderStatus.cancelled:
        return AppColors.error;
    }
  }

  // ── Deleted Resellers Tab ────────────────────────────────────────────────
  Widget _resellersBin() {
    final list = _filteredResellers;
    if (list.isEmpty) {
      return _emptyState(
        _searchQuery.isEmpty
            ? 'No deleted resellers'
            : 'No results for "$_searchQuery"',
        Icons.storefront_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final reseller = list[i];
        final contact = reseller.contact?.trim();
        return _BinCard(
          title: reseller.name,
          subtitle: contact == null || contact.isEmpty
              ? 'No contact details'
              : contact,
          detail: '${reseller.deductionPerItem.format()}/item',
          badge: 'Reseller',
          badgeColor: AppColors.gold,
          onRestore: () => _restoreReseller(reseller),
          onDelete: () => _hardDeleteReseller(reseller),
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
        Text(
          label,
          style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 16),
        ),
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
  final Color badgeColor;
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: AppColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.whiteSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        detail,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: badgeColor,
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
  }) => Tooltip(
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
