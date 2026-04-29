// ─────────────────────────────────────────────────────────────────────────────
// app_state.dart — Optimized Singleton ChangeNotifier
// Purpose : Central in-memory state store for the entire app.
//           Holds products, orders, debts, and activity logs.
//           Exposes methods that coordinate service calls and notify the UI.
//        addOrder() and addDebt() now accept an optional onError callback
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

// Singleton ChangeNotifier — widgets listen to this for reactive UI updates
class AppState extends ChangeNotifier {
  // ── Singleton pattern ─────────────────────────────────────────────────────
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance; // Always returns the same instance
  AppState._internal();            // Private constructor prevents external instantiation

  // ── Dependency Inversion: depend on interfaces, not concretions ───────────
  // Null until configure() is called; replaced with mocks during unit tests
  IProductService?        _productService;
  IOrderService?          _orderService;
  IDebtService?           _debtService;
  IAuthService?           _authService;
  IActivityLogRepository? _logRepoInstance;

  // Lazy-initializes a real ActivityLogRepository if none was injected via configure()
  IActivityLogRepository get _logRepo =>
      _logRepoInstance ??= ActivityLogRepository();

  // Fail-fast getters — throw StateError if configure() was never called
  IProductService get _ps => _productService ?? (throw StateError('AppState not configured'));
  IOrderService   get _os => _orderService   ?? (throw StateError('AppState not configured'));
  IDebtService    get _ds => _debtService    ?? (throw StateError('AppState not configured'));
  IAuthService    get _as => _authService    ?? (throw StateError('AppState not configured'));

  // Wires up all service dependencies; call once at app startup (or with mocks in tests)
  void configure({
    IProductService?       productService,
    IOrderService?         orderService,
    IDebtService?          debtService,
    IAuthService?          authService,
    IActivityLogRepository? logRepository,   // injectable for tests
  }) {
    if (logRepository != null) _logRepoInstance = logRepository;
    // Create concrete local repositories (SQLite-backed)
    final productRepo = LocalProductRepository();
    final orderRepo   = LocalOrderRepository();
    final debtRepo    = LocalDebtRepository();
    final userRepo    = LocalUserRepository();

    // Use injected service if provided (test); otherwise use real concrete implementation
    _productService = productService ?? ProductService(productRepo);
    _orderService   = orderService   ?? OrderService(orderRepo, productRepo);
    _debtService    = debtService    ?? DebtService(debtRepo);
    _authService    = authService    ?? AuthService(userRepo);
  }

  /// FIX: Reset services so a different user's login gets fresh repo instances.
  /// Call this before configure() when switching accounts.
  void reset() {
    // Null out all services so configure() re-creates them on next login
    _productService  = null;
    _orderService    = null;
    _debtService     = null;
    _authService     = null;
    _logRepoInstance = null;
    logout(); // Also clears in-memory state and triggers UI rebuild
  }

  // ── State ─────────────────────────────────────────────────────────────────
  bool      _isLoggedIn     = false;
  AppUser?  _currentUser;
  String    _activeUser     = '';    // Lowercase username — used as DB partition key
  bool      _isLoading      = false;
  bool      _notifyPending  = false; // Guards against double-notify in same microtask

  // In-memory lists — source of truth for the UI
  List<Product>      _products     = [];
  List<Order>        _orders       = [];
  List<CustomerDebt> _debts        = [];
  List<ActivityLog>  _activityLogs = [];

  // ── Public read-only getters ──────────────────────────────────────────────
  bool     get isLoggedIn  => _isLoggedIn;
  bool     get isLoading   => _isLoading;
  AppUser? get currentUser => _currentUser;
  String   get activeUser  => _activeUser;

  // Unmodifiable views prevent external mutation of internal lists
  List<Product>      get products     => List.unmodifiable(_products);
  List<Order>        get orders       => List.unmodifiable(_orders);
  List<CustomerDebt> get debts        => List.unmodifiable(_debts);
  List<ActivityLog>  get activityLogs => List.unmodifiable(_activityLogs);

  // ── Computed aggregate getters ────────────────────────────────────────────
  int get totalProducts  => _products.length;
  int get totalStock     => _products.fold(0, (s, p) => s + p.stockQty);
  int get totalOrders    => _orders.length;
  int get lowStockCount  => _products.where((p) => p.isLowStock).length;
  int get deliveredCount => _orders.where((o) => o.status == OrderStatus.delivered).length;
  int get pendingCount   => _orders.where((o) => o.status == OrderStatus.pending).length;

  // Filtered list helpers used by UI widgets
  List<Product>      get lowStockProducts => _products.where((p) => p.isLowStock).toList();
  List<CustomerDebt> get unpaidDebts      => _debts.where((d) => !d.isPaid).toList();
  List<CustomerDebt> get paidDebts        => _debts.where((d) => d.isPaid).toList();
  List<CustomerDebt> get overdueDebts     => _debts.where((d) => d.isOverdue).toList();

  // Total amount collected from utang payments (initial + additional payments)
  double get totalUtangCollected => _debts.fold(0.0, (s, d) => s + d.amountPaid);

  // FIX 5: Dati kasama ang utang sa revenue — misleading kasi hindi pa nababayaran.
  // Ngayon: delivered + utang payments = actual collected revenue.
  // Ang utang ay tracked na separately sa totalDebtAmount getter.
  // Counts delivered orders + all payments collected from utang orders
  double get totalRevenue {
    final deliveredRevenue = _orders
        .where((o) => o.status == OrderStatus.delivered)
        .fold(0.0, (s, o) => s + o.totalAmount);
    return deliveredRevenue + totalUtangCollected;
  }

  // Billed revenue (lahat maliban cancelled) — para sa analytics na gusto ng gross view
  // Gross revenue including pending/processing/utang orders (not yet cancelled)
  double get totalBilledRevenue => _orders
      .where((o) => o.status != OrderStatus.cancelled)
      .fold(0.0, (s, o) => s + o.totalAmount);

  // Total outstanding debt across all customers
  double get totalDebtAmount => _debts.fold(0.0, (s, d) => s + d.remainingBalance);

  // Average order value based only on delivered (paid) orders
  double get avgOrderValue {
    final delivered = _orders.where((o) => o.status == OrderStatus.delivered).toList();
    return delivered.isEmpty ? 0 : totalRevenue / delivered.length;
  }

  // Returns a count for each OrderStatus enum value — used by analytics pie chart
  Map<OrderStatus, int> get ordersByStatus => {
    for (final s in OrderStatus.values)
      s: _orders.where((o) => o.status == s).length,
  };

  // Returns top 5 products by total units sold (non-cancelled orders only)
  List<MapEntry<String, int>> get topProductsBySales {
    final map = <String, int>{};
    for (final order in _orders) {
      if (order.status == OrderStatus.cancelled) continue;
      for (final item in order.items) {
        map[item.productName] = (map[item.productName] ?? 0) + item.quantity;
      }
    }
    // Sort descending and take top 5
    return (map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();
  }

  // ── Batch notify ──────────────────────────────────────────────────────────
  // Coalesces multiple synchronous state changes into a single UI rebuild
  void _batchNotify() {
    if (_notifyPending) return; // Already scheduled — skip duplicate
    _notifyPending = true;
    Future.microtask(() {
      _notifyPending = false;
      notifyListeners(); // Triggers all AppStateBuilder rebuilds
    });
  }

  // Helper to set loading flag and trigger UI update
  void _setLoading(bool value) {
    _isLoading = value;
    _batchNotify();
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  // Authenticates with username/password, loads all data on success
  Future<bool> login(String username, String password) async {
    _setLoading(true);
    try {
      final user = await _as.login(username, password);
      if (user == null) { _setLoading(false); return false; }
      _activeUser  = username.toLowerCase(); // Partition key for all DB queries
      _currentUser = user;
      _isLoggedIn  = true;
      await _loadAllData(); // Fetch products, orders, debts, logs from SQLite
      _addLogSilent('${user.username} signed in', 'auth');
      return true;
    } catch (_) {
      _setLoading(false);
      return false;
    }
  }

  // Registers a new user, then auto-logs them in and initializes empty data lists
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
      // New account starts with empty lists — no existing data to load
      _products    = []; _orders = []; _debts = []; _activityLogs = [];
      _addLogSilent('New account registered: $name', 'auth');
      _setLoading(false);
      return true;
    } catch (_) {
      _setLoading(false);
      return false;
    }
  }

  // Delegates password reset validation and update to AuthService
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

  // Clears all in-memory state and triggers full UI rebuild to show LoginScreen
  void logout() {
    _isLoggedIn  = false;
    _currentUser = null;
    _activeUser  = '';
    _products    = []; _orders = []; _debts = []; _activityLogs = [];
    _batchNotify();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  // Fetches all four data types in parallel for faster startup
  Future<void> _loadAllData() async {
    try {
      // Run all four fetches in parallel for faster startup.
      // Using named typed variables avoids the unsafe (results[N] as List<X>) cast
      // that Future.wait produces — a wrong index or unexpected return type would
      // throw a TypeError at runtime instead of a compile-time error.
      final (products, orders, debts, logs) = await (
        _ps.getAll(_activeUser),
        _os.getAll(_activeUser),
        _ds.getAll(_activeUser),
        _logRepo.getAll(_activeUser),
      ).wait;
      _products     = products;
      _orders       = orders;
      _debts        = debts;
      _activityLogs = logs;
    } catch (_) {
      // On any failure, fall back to empty lists rather than crashing
      _products = []; _orders = []; _debts = []; _activityLogs = [];
    } finally {
      _setLoading(false); // Always clears spinner even on error
    }
  }

  // Public shortcut to re-fetch all data (e.g. after sync or pull-to-refresh)
  Future<void> refreshData() => _loadAllData();

  // ── Products ──────────────────────────────────────────────────────────────

  // Adds a new product to the DB then refreshes the in-memory list
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
      // Re-fetch to ensure state matches DB (catches any service-side transforms)
      _products = await _ps.getAll(_activeUser);
      _addLogSilent('Product "${product.name}" added', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify(); // Rebuild UI regardless of success or failure
    }
  }

  // Updates an existing product; uses local index update to avoid a full re-fetch
  Future<void> updateProduct(Product updated) async {
    try {
      await _ps.updateProduct(updated);
      final idx = _products.indexWhere((p) => p.id == updated.id);
      if (idx != -1) {
        // Replace only the changed item in the list (O(n) copy, avoids DB round-trip)
        _products = List.of(_products)..[idx] = updated;
      } else {
        // Fallback: product not found locally, reload from DB
        _products = await _ps.getAll(_activeUser);
      }
      _addLogSilent('Product "${updated.name}" updated', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  // Updates only the stock quantity for a single product (used after order creation)
  Future<void> updateStock(String productId, int newQty) async {
    try {
      await _ps.updateStock(productId, newQty);
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        // FIX 7: Dati direktang binabago ang object (_products[idx].stockQty = newQty).
        // Ngayon gumagawa ng bagong list copy — consistent sa pattern ng ibang methods,
        // mas predictable ang state management.
        // Immutable-style update: creates new list with updated product copy
        _products = List.of(_products)..[idx] = _products[idx].copyWith(stockQty: newQty);
        _addLogSilent('Stock updated for "${_products[idx].name}"', 'stock');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  // Soft-deletes a product (moves to Recycle Bin, not permanently removed)
  Future<void> deleteProduct(String productId) async {
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      await _ps.deleteProduct(productId);
      // Remove from local list immediately for instant UI feedback
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
  // Creates a new order, deducts stock via OrderService, and refreshes both lists
  Future<bool> addOrder(Order order, {void Function(String)? onError}) async {
    try {
      await _os.createOrder(order, _activeUser, _products);
      // Refresh both products (stock changed) and orders (new entry)
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

  // Updates the status of a single order (e.g. Pending → Shipped → Delivered)
  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    try {
      await _os.updateStatus(orderId, status);
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx != -1) {
        // Local update avoids a full DB reload for a single field change
        _orders = List.of(_orders)..[idx] = _orders[idx].copyWith(status: status);
      }
      _addLogSilent('Order status updated → ${status.displayName}', 'order');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  // Soft-deletes an order and removes it from the in-memory list
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

  // Asks OrderService for the next sequential order ID (e.g. "KNZ-042")
  Future<String> generateOrderId() async {
    try {
      return await _os.generateOrderId(_activeUser);
    } catch (_) {
      return 'KNZ-001'; // Safe fallback if DB query fails
    }
  }

  // ── Recycle Bin (fully DIP-compliant — routes through service interfaces) ─

  /// Returns all soft-deleted orders for the current user.
  // Used by RecycleBinScreen to list orders pending permanent deletion
  Future<List<Order>> getDeletedOrders() async {
    try {
      return await _os.getDeleted(_activeUser);
    } catch (_) {
      return [];
    }
  }

  /// Returns all soft-deleted products for the current user.
  // Used by RecycleBinScreen to list products pending permanent deletion
  Future<List<Product>> getDeletedProducts() async {
    try {
      return await _ps.getDeleted(_activeUser);
    } catch (_) {
      return [];
    }
  }

  // Un-deletes an order and refreshes the active orders list
  Future<void> restoreOrder(String orderId) async {
    try {
      await _os.restoreOrder(orderId);
      await refreshData(); // Full reload ensures restored item appears in list
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  // Un-deletes a product and refreshes the active products list
  Future<void> restoreProduct(String productId) async {
    try {
      await _ps.restoreProduct(productId);
      await refreshData();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  // Permanently removes an order from both SQLite and Firestore (no recovery)
  Future<void> hardDeleteOrder(String orderId) async {
    try {
      await _os.hardDeleteOrder(orderId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  // Permanently removes a product from both SQLite and Firestore (no recovery)
  Future<void> hardDeleteProduct(String productId) async {
    try {
      await _ps.hardDeleteProduct(productId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    }
  }

  /// Returns all soft-deleted debts for the current user.
  // Used by RecycleBinScreen to list debts pending permanent deletion
  Future<List<CustomerDebt>> getDeletedDebts() async {
    try {
      return await _ds.getDeleted(_activeUser);
    } catch (_) {
      return [];
    }
  }

  // Un-deletes a debt record and refreshes all data
  Future<void> restoreDebt(String debtId) async {
    try {
      await _ds.restoreDebt(debtId);
      await refreshData();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] restoreDebt: $e\n$st');
    }
  }

  // Permanently removes a debt record (no recovery after this)
  Future<void> hardDeleteDebt(String debtId) async {
    try {
      await _ds.hardDeleteDebt(debtId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] hardDeleteDebt: $e\n$st');
    }
  }

  // ── Debts ─────────────────────────────────────────────────────────────────

  /// FIX 4: [onError] callback — same pattern as addOrder().
  // Records a new utang entry; prepends to local list for instant UI response
  Future<bool> addDebt(CustomerDebt debt, {void Function(String)? onError}) async {
    try {
      await _ds.addDebt(debt, _activeUser);
      // Prepend: newest debts appear first without re-sorting
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

  // Records a partial or full payment against an existing debt; reloads debts list
  Future<void> addPayment(String debtId, PaymentRecord payment) async {
    try {
      final debt = _debts.firstWhere((d) => d.id == debtId);
      await _ds.addPayment(debtId, payment, debt.remainingBalance);
      // Full reload because amountPaid and isPaid may have changed
      _debts = await _ds.getAll(_activeUser);
      _addLogSilent(
          'Payment ₱${payment.amount.toStringAsFixed(2)} received', 'payment');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
    } finally {
      _batchNotify();
    }
  }

  // Soft-deletes a debt and removes it from the in-memory list
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

  // Creates and stores an activity log entry without triggering a UI notify
  // (the calling method's _batchNotify() will cover the rebuild)
  void _addLogSilent(String message, String type) {
    final now = DateTime.now();
    // FIX 6: Dati microsecondsSinceEpoch — posible ang collision sa mabilis na ops.
    // Ngayon Uuid().v4() — guaranteed unique, consistent sa ibang parts ng codebase.
    // UUID v4 guarantees uniqueness even for rapid back-to-back log entries
    final log = ActivityLog(
      id:        const Uuid().v4(),
      message:   message,
      timestamp: now,
      type:      type,
    );
    // Keep at most 50 entries in memory; oldest entries are dropped
    _activityLogs = [log, if (_activityLogs.length < 50) ..._activityLogs
        else ..._activityLogs.take(49)];
    // Persist to SQLite (and Firestore via sync queue) asynchronously
    _logRepo.add(log, _activeUser);
  }
}