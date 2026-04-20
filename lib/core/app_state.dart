// ─────────────────────────────────────────────────────────────────────────────
// app_state.dart — Optimized Singleton ChangeNotifier
// FIX 4: addOrder() and addDebt() now accept an optional onError callback
//        so callers (dialogs/screens) can show a SnackBar when something fails.
//        All other methods unchanged.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';
import '../models/debt_model.dart';
import '../repositories/local_user_repository.dart';
import '../repositories/local_product_repository.dart';
import '../repositories/local_order_repository.dart';
import '../repositories/local_debt_repository.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/i_activity_log_repository.dart';
import '../services/product_service.dart';
import '../services/order_service.dart';
import '../services/debt_service.dart';
import '../services/auth_service.dart';

class AppState extends ChangeNotifier {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // ── Dependency Inversion: depend on interfaces, not concretions ───────────
  IProductService?        _productService;
  IOrderService?          _orderService;
  IDebtService?           _debtService;
  IAuthService?           _authService;
  IActivityLogRepository? _logRepoInstance;

  // Always returns a real repo (lazy-init). Injectable via configure() for tests.
  IActivityLogRepository get _logRepo =>
      _logRepoInstance ??= ActivityLogRepository();

  // Convenience getters that throw if not yet configured (fail-fast)
  IProductService get _ps => _productService ?? (throw StateError('AppState not configured'));
  IOrderService   get _os => _orderService   ?? (throw StateError('AppState not configured'));
  IDebtService    get _ds => _debtService    ?? (throw StateError('AppState not configured'));
  IAuthService    get _as => _authService    ?? (throw StateError('AppState not configured'));

  void configure({
    IProductService?       productService,
    IOrderService?         orderService,
    IDebtService?          debtService,
    IAuthService?          authService,
    IActivityLogRepository? logRepository,   // injectable for tests
  }) {
    if (logRepository != null) _logRepoInstance = logRepository;
    final productRepo = LocalProductRepository();
    final orderRepo   = LocalOrderRepository();
    final debtRepo    = LocalDebtRepository();
    final userRepo    = LocalUserRepository();

    _productService = productService ?? ProductService(productRepo);
    _orderService   = orderService   ?? OrderService(orderRepo, productRepo);
    _debtService    = debtService    ?? DebtService(debtRepo);
    _authService    = authService    ?? AuthService(userRepo);
  }

  /// FIX: Reset services so a different user's login gets fresh repo instances.
  /// Call this before configure() when switching accounts.
  void reset() {
    _productService  = null;
    _orderService    = null;
    _debtService     = null;
    _authService     = null;
    _logRepoInstance = null;
    logout();
  }

  // ── State ─────────────────────────────────────────────────────────────────
  bool      _isLoggedIn     = false;
  AppUser?  _currentUser;
  String    _activeUser     = '';
  bool      _isLoading      = false;
  bool      _notifyPending  = false;

  List<Product>      _products     = [];
  List<Order>        _orders       = [];
  List<CustomerDebt> _debts        = [];
  List<ActivityLog>  _activityLogs = [];

  // ── Getters ───────────────────────────────────────────────────────────────
  bool     get isLoggedIn  => _isLoggedIn;
  bool     get isLoading   => _isLoading;
  AppUser? get currentUser => _currentUser;
  String   get activeUser  => _activeUser;

  List<Product>      get products     => List.unmodifiable(_products);
  List<Order>        get orders       => List.unmodifiable(_orders);
  List<CustomerDebt> get debts        => List.unmodifiable(_debts);
  List<ActivityLog>  get activityLogs => List.unmodifiable(_activityLogs);

  int get totalProducts  => _products.length;
  int get totalStock     => _products.fold(0, (s, p) => s + p.stockQty);
  int get totalOrders    => _orders.length;
  int get lowStockCount  => _products.where((p) => p.isLowStock).length;
  int get deliveredCount => _orders.where((o) => o.status == OrderStatus.delivered).length;
  int get pendingCount   => _orders.where((o) => o.status == OrderStatus.pending).length;

  List<Product>      get lowStockProducts => _products.where((p) => p.isLowStock).toList();
  List<CustomerDebt> get unpaidDebts      => _debts.where((d) => !d.isPaid).toList();
  List<CustomerDebt> get overdueDebts     => _debts.where((d) => d.isOverdue).toList();

  // FIX 5: Dati kasama ang utang sa revenue — misleading kasi hindi pa nababayaran.
  // Ngayon: delivered lang = actual collected revenue.
  // Ang utang ay tracked na separately sa totalDebtAmount getter.
  double get totalRevenue => _orders
      .where((o) => o.status == OrderStatus.delivered)
      .fold(0.0, (s, o) => s + o.totalAmount);

  // Billed revenue (lahat maliban cancelled) — para sa analytics na gusto ng gross view
  double get totalBilledRevenue => _orders
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0.0, (s, o) => s + o.totalAmount);

  double get totalDebtAmount => _debts.fold(0.0, (s, d) => s + d.remainingBalance);

  double get avgOrderValue {
    final delivered = _orders.where((o) => o.status == OrderStatus.delivered).toList();
    return delivered.isEmpty ? 0 : totalRevenue / delivered.length;
  }

  Map<OrderStatus, int> get ordersByStatus => {
    for (final s in OrderStatus.values)
      s: _orders.where((o) => o.status == s).length,
  };

  List<MapEntry<String, int>> get topProductsBySales {
    final map = <String, int>{};
    for (final order in _orders) {
      if (order.status == OrderStatus.cancelled) continue;
      for (final item in order.items) {
        map[item.productName] = (map[item.productName] ?? 0) + item.quantity;
      }
    }
    return (map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();
  }

  // ── Batch notify ──────────────────────────────────────────────────────────
  void _batchNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    Future.microtask(() {
      _notifyPending = false;
      notifyListeners();
    });
  }

  void _setLoading(bool value) {
    _isLoading = value;
    _batchNotify();
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<bool> login(String username, String password) async {
    _setLoading(true);
    try {
      final user = await _as.login(username, password);
      if (user == null) { _setLoading(false); return false; }
      _activeUser  = username.toLowerCase();
      _currentUser = user;
      _isLoggedIn  = true;
      await _loadAllData();
      _addLogSilent('${user.username} signed in', 'auth');
      return true;
    } catch (_) {
      _setLoading(false);
      return false;
    }
  }

  Future<bool> register(String name, String username, String password,
      {String confirm = '', String? email}) async {
    _setLoading(true);
    try {
      final error = await _as.register(
          name, username, password,
          confirm.isEmpty ? password : confirm, email ?? '');
      if (error != null) { _setLoading(false); return false; }
      final user = await _as.login(username, password);
      // FIX 1: null-check — kung null ang user, huwag i-proceed (crash prevention)
      if (user == null) { _setLoading(false); return false; }
      _activeUser  = username.toLowerCase();
      _currentUser = user;
      _isLoggedIn  = true;
      _products    = []; _orders = []; _debts = []; _activityLogs = [];
      _addLogSilent('New account registered: $name', 'auth');
      _setLoading(false);
      return true;
    } catch (_) {
      _setLoading(false);
      return false;
    }
  }

  Future<bool> resetPassword(String username, String newPassword) async {
    try {
      final error =
          await _as.resetPassword(username, newPassword, newPassword);
      if (error == null) _addLogSilent('Password reset for: $username', 'auth');
      return error == null;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    _isLoggedIn  = false;
    _currentUser = null;
    _activeUser  = '';
    _products    = []; _orders = []; _debts = []; _activityLogs = [];
    _batchNotify();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadAllData() async {
    try {
      final results = await Future.wait([
        _ps.getAll(_activeUser),
        _os.getAll(_activeUser),
        _ds.getAll(_activeUser),
        _logRepo.getAll(_activeUser),
      ]);
      _products     = results[0] as List<Product>;
      _orders       = results[1] as List<Order>;
      _debts        = results[2] as List<CustomerDebt>;
      _activityLogs = results[3] as List<ActivityLog>;
    } catch (_) {
      _products = []; _orders = []; _debts = []; _activityLogs = [];
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshData() => _loadAllData();

  // ── Products ──────────────────────────────────────────────────────────────

  Future<void> addProduct(Product product) async {
    try {
      await _ps.addProduct(
        userId:        _activeUser,
        name:          product.name,
        description:   product.description,
        category:      product.category,
        price:         product.price,
        stockQty:      product.stockQty,
        minStockLevel: product.minStockLevel,
        imagePath:     product.imagePath,
      );
      _products = await _ps.getAll(_activeUser);
      _addLogSilent('Product "${product.name}" added', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  Future<void> updateProduct(Product updated) async {
    try {
      await _ps.updateProduct(updated);
      final idx = _products.indexWhere((p) => p.id == updated.id);
      if (idx != -1) {
        _products = List.of(_products)..[idx] = updated;
      } else {
        _products = await _ps.getAll(_activeUser);
      }
      _addLogSilent('Product "${updated.name}" updated', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  Future<void> updateStock(String productId, int newQty) async {
    try {
      await _ps.updateStock(productId, newQty);
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        // FIX 7: Dati direktang binabago ang object (_products[idx].stockQty = newQty).
        // Ngayon gumagawa ng bagong list copy — consistent sa pattern ng ibang methods,
        // mas predictable ang state management.
        _products = List.of(_products)..[idx] = _products[idx].copyWith(stockQty: newQty);
        _addLogSilent('Stock updated for "${_products[idx].name}"', 'stock');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      await _ps.deleteProduct(productId);
      _products = _products.where((p) => p.id != productId).toList();
      _addLogSilent('Product "${product.name}" removed', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  // ── Orders ────────────────────────────────────────────────────────────────

  /// FIX 4: [onError] is called with a user-friendly message when the
  /// operation fails. Use it to show a SnackBar in the calling dialog.
  ///
  /// Example usage in a dialog:
  /// ```dart
  /// await AppState().addOrder(order, onError: (msg) {
  ///   ScaffoldMessenger.of(context).showSnackBar(
  ///     SnackBar(content: Text(msg), backgroundColor: AppColors.error),
  ///   );
  /// });
  /// ```
  Future<bool> addOrder(Order order, {void Function(String)? onError}) async {
    try {
      await _os.createOrder(order, _activeUser, _products);
      _products = await _ps.getAll(_activeUser);
      _orders   = await _os.getAll(_activeUser);
      _addLogSilent(
          'New order ${order.orderId} created for ${order.customerName}',
          'order');
      return true; // ← FIX 4: returns true on success
    } catch (e) {
      // ← FIX 4: call onError so the UI can show a SnackBar
      onError?.call('Failed to create order. Please try again.');
      return false;
    } finally {
      _batchNotify();
    }
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    try {
      await _os.updateStatus(orderId, status);
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        _orders = List.of(_orders)..[idx] = _orders[idx].copyWith(status: status);
      }
      _addLogSilent('Order status updated → ${status.displayName}', 'order');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  Future<void> deleteOrder(String orderId) async {
    try {
      await _os.deleteOrder(orderId);
      _orders = _orders.where((o) => o.id != orderId).toList();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  Future<String> generateOrderId() async {
    try {
      return await _os.generateOrderId(_activeUser);
    } catch (_) {
      return 'KNZ-001';
    }
  }

  // ── Recycle Bin (fully DIP-compliant — routes through service interfaces) ─

  /// Returns all soft-deleted orders for the current user.
  Future<List<Order>> getDeletedOrders() async {
    try {
      return await _os.getDeleted(_activeUser);
    } catch (_) {
      return [];
    }
  }

  /// Returns all soft-deleted products for the current user.
  Future<List<Product>> getDeletedProducts() async {
    try {
      return await _ps.getDeleted(_activeUser);
    } catch (_) {
      return [];
    }
  }

  Future<void> restoreOrder(String orderId) async {
    try {
      await _os.restoreOrder(orderId);
      await refreshData();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  Future<void> restoreProduct(String productId) async {
    try {
      await _ps.restoreProduct(productId);
      await refreshData();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  Future<void> hardDeleteOrder(String orderId) async {
    try {
      await _os.hardDeleteOrder(orderId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  Future<void> hardDeleteProduct(String productId) async {
    try {
      await _ps.hardDeleteProduct(productId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  /// Returns all soft-deleted debts for the current user.
  Future<List<CustomerDebt>> getDeletedDebts() async {
    try {
      return await _ds.getDeleted(_activeUser);
    } catch (_) {
      return [];
    }
  }

  Future<void> restoreDebt(String debtId) async {
    try {
      await _ds.restoreDebt(debtId);
      await refreshData();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] restoreDebt: $e\n$st');
    }
  }

  Future<void> hardDeleteDebt(String debtId) async {
    try {
      await _ds.hardDeleteDebt(debtId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] hardDeleteDebt: $e\n$st');
    }
  }

  // ── Debts ─────────────────────────────────────────────────────────────────

  /// FIX 4: [onError] callback — same pattern as addOrder().
  Future<bool> addDebt(CustomerDebt debt, {void Function(String)? onError}) async {
    try {
      await _ds.addDebt(debt, _activeUser);
      _debts = [debt, ..._debts];
      _addLogSilent(
        'Utang recorded for ${debt.customerName} — '
        '₱${debt.remainingBalance.toStringAsFixed(2)} remaining',
        'payment',
      );
      return true; // ← FIX 4: returns true on success
    } catch (e) {
      // ← FIX 4: call onError so the UI can show a SnackBar
      onError?.call('Failed to record utang. Please try again.');
      return false;
    } finally {
      _batchNotify();
    }
  }

  Future<void> addPayment(String debtId, PaymentRecord payment) async {
    try {
      final debt = _debts.firstWhere((d) => d.id == debtId);
      await _ds.addPayment(debtId, payment, debt.remainingBalance);
      _debts = await _ds.getAll(_activeUser);
      _addLogSilent(
          'Payment ₱${payment.amount.toStringAsFixed(2)} received', 'payment');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  Future<void> deleteDebt(String debtId) async {
    try {
      await _ds.deleteDebt(debtId);
      _debts = _debts.where((d) => d.id != debtId).toList();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _addLogSilent(String message, String type) {
    final now = DateTime.now();
    // FIX 6: Dati microsecondsSinceEpoch — posible ang collision sa mabilis na ops.
    // Ngayon Uuid().v4() — guaranteed unique, consistent sa ibang parts ng codebase.
    final log = ActivityLog(
      id:        const Uuid().v4(),
      message:   message,
      timestamp: now,
      type:      type,
    );
    _activityLogs = [log, if (_activityLogs.length < 500) ..._activityLogs
        else ..._activityLogs.take(499)];
    _logRepo.add(log, _activeUser);
  }
}
