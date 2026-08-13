// ─────────────────────────────────────────────────────────────────────────────
// app_state.dart — Optimized Singleton ChangeNotifier
// Purpose : Central in-memory state store for the entire app.
//           Holds products, orders, debts, and activity logs.
//           Exposes methods that coordinate service calls and notify the UI.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/domain_exceptions.dart';
import '../core/money.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';
import '../models/debt_model.dart';
import '../models/business_event_model.dart';
import '../models/payment_method_model.dart';
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
import '../services/cloud_auth_service.dart';
import '../services/login_rate_limiter.dart'; // ← Brute-force login protection
import '../services/notification_service.dart'; // ← Low-stock push notifications
import '../services/accounting_service.dart';
import '../models/reseller_model.dart';
import '../models/sales_record_model.dart';
import '../models/custom_order_model.dart';
import '../repositories/local_reseller_repository.dart';
import '../repositories/local_custom_order_repository.dart';
import '../repositories/local_business_event_repository.dart';
import '../repositories/sync_queue.dart';
import '../repositories/inbound_sync_coordinator.dart';
import '../services/session_timeout_service.dart';
import '../widgets/shared_widgets.dart';
import 'protected_navigation.dart';

// Singleton ChangeNotifier — widgets listen to this for reactive UI updates
class AppState extends ChangeNotifier {
  // ── Singleton pattern ─────────────────────────────────────────────────────
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance; // Always returns the same instance
  AppState._internal(); // Private constructor prevents external instantiation

  // ── Dependency Inversion: depend on interfaces, not concretions ───────────
  // Null until configure() is called; replaced with mocks during unit tests
  IProductService? _productService;
  IOrderService? _orderService;
  IDebtService? _debtService;
  IAuthService? _authService;
  IActivityLogRepository? _logRepoInstance;
  StreamSubscription<SyncStatus>? _syncStatusSubscription;
  Future<void> Function() _stopSynchronization =
      SyncQueue.instance.stopMonitoring;
  Future<void> Function() _cancelNotifications =
      NotificationService.instance.cancelAll;
  Future<void> Function(List<Product>, List<CustomerDebt>) _syncBusinessAlerts =
      NotificationService.instance.syncBusinessAlerts;
  Timer? _dueDateTimer;
  Future<void>? _logoutInProgress;

  // Lazy-initializes a real ActivityLogRepository if none was injected via configure()
  IActivityLogRepository get _logRepo =>
      _logRepoInstance ??= ActivityLogRepository();

  // Fail-fast getters — throw StateError if configure() was never called
  IProductService get _ps =>
      _productService ?? (throw StateError('AppState not configured'));
  IOrderService get _os =>
      _orderService ?? (throw StateError('AppState not configured'));
  IDebtService get _ds =>
      _debtService ?? (throw StateError('AppState not configured'));
  IAuthService get _as =>
      _authService ?? (throw StateError('AppState not configured'));

  // Wires up all service dependencies; call once at app startup (or with mocks in tests)
  void configure({
    IProductService? productService,
    IOrderService? orderService,
    IDebtService? debtService,
    IAuthService? authService,
    IActivityLogRepository? logRepository, // injectable for tests
    Future<void> Function()? stopSynchronization,
    Future<void> Function()? cancelNotifications,
    Future<void> Function(List<Product>, List<CustomerDebt>)?
    syncBusinessAlerts,
  }) {
    if (logRepository != null) _logRepoInstance = logRepository;
    // Create concrete local repositories (SQLite-backed)
    final productRepo = LocalProductRepository();
    final orderRepo = LocalOrderRepository();
    final debtRepo = LocalDebtRepository();
    final userRepo = LocalUserRepository();

    // Use injected service if provided (test); otherwise use real concrete implementation
    _productService = productService ?? ProductService(productRepo);
    _orderService = orderService ?? OrderService(orderRepo);
    _debtService = debtService ?? DebtService(debtRepo);
    _authService =
        authService ??
        AuthService(userRepo, cloudAuth: CloudAuthService.instance);
    _stopSynchronization =
        stopSynchronization ?? SyncQueue.instance.stopMonitoring;
    _cancelNotifications =
        cancelNotifications ?? NotificationService.instance.cancelAll;
    _syncBusinessAlerts =
        syncBusinessAlerts ?? NotificationService.instance.syncBusinessAlerts;
    unawaited(_syncStatusSubscription?.cancel());
    _syncStatusSubscription = SyncQueue.instance.statusStream.listen((status) {
      if (!_isLoggedIn) return;
      _syncStatus = status;
      _batchNotify();
    });
    SyncQueue.instance.setAuthorizationGate(_authorizeSynchronization);
    SyncQueue.instance.setAfterSuccessfulSync(_reconcileInbound);
  }

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isLoggedIn = false;
  bool _isOfflineSession = false;
  AppUser? _currentUser;
  String _activeUser = ''; // Lowercase username — used as DB partition key
  String? _lastAuthMessage;
  String? _lastAuthStatus;
  String? _lastDataError;
  SyncStatus _syncStatus = const SyncStatus.empty();
  int _sessionGeneration = 0;
  bool _notifyPending = false; // Guards against double-notify in same microtask

  // In-memory lists — source of truth for the UI
  List<Product> _products = [];
  List<Order> _orders = [];
  List<CustomerDebt> _debts = [];
  List<ActivityLog> _activityLogs = [];
  List<Reseller> _resellers = [];
  List<CustomOrder> _customOrders = [];
  List<BusinessEvent> _businessEvents = [];

  final LocalResellerRepository _resellerRepo = LocalResellerRepository();
  final LocalCustomOrderRepository _customOrderRepo =
      LocalCustomOrderRepository();
  final LocalBusinessEventRepository _businessEventRepo =
      LocalBusinessEventRepository();

  // ── Public read-only getters ──────────────────────────────────────────────
  bool get isLoggedIn => _isLoggedIn;
  bool get isOfflineSession => _isOfflineSession;
  AppUser? get currentUser => _currentUser;
  String get activeUser => _activeUser;
  String? get lastAuthMessage => _lastAuthMessage;
  String? get lastAuthStatus => _lastAuthStatus;
  String? get lastDataError => _lastDataError;
  SyncStatus get syncStatus => _syncStatus;
  bool get isAdministrator => _currentUser?.role == 'Administrator';

  // Unmodifiable views prevent external mutation of internal lists
  List<Product> get products => List.unmodifiable(_products);
  List<Order> get orders => List.unmodifiable(_orders);
  List<CustomerDebt> get debts => List.unmodifiable(_debts);
  List<ActivityLog> get activityLogs => List.unmodifiable(_activityLogs);
  List<Reseller> get resellers => List.unmodifiable(_resellers);
  List<CustomOrder> get customOrders => List.unmodifiable(_customOrders);
  List<BusinessEvent> get businessEvents => List.unmodifiable(_businessEvents);

  List<BusinessEvent> eventsForOrder(String orderId) => _businessEvents
      .where(
        (event) =>
            event.subject == BusinessEventSubject.order &&
            event.subjectId == orderId,
      )
      .toList(growable: false);

  AccountingReport get accountingReport => AccountingService.instance.summarize(
    orders: _orders,
    debts: _debts,
    customOrders: _customOrders,
    businessEvents: _businessEvents,
  );

  // ── Computed aggregate getters ────────────────────────────────────────────
  int get totalProducts => _products.length;
  int get totalStock => _products.fold(0, (s, p) => s + p.stockQty);
  int get totalOrders => _orders.length;
  int get lowStockCount => _products.where((p) => p.isLowStock).length;
  int get deliveredCount =>
      _orders.where((o) => o.status == OrderStatus.delivered).length;
  int get pendingCount =>
      _orders.where((o) => o.status == OrderStatus.pending).length;

  // Filtered list helpers used by UI widgets
  List<Product> get lowStockProducts =>
      _products.where((p) => p.isLowStock).toList();
  List<CustomerDebt> get unpaidDebts => _debts.where((d) => !d.isPaid).toList();
  List<CustomerDebt> get paidDebts => _debts.where((d) => d.isPaid).toList();
  List<CustomerDebt> get overdueDebts =>
      _debts.where((d) => d.isOverdue).toList();
  List<CustomerDebt> get dueDebts => _debts.where((d) => d.isDue).toList();

  // Total amount collected from utang payments (initial + additional payments)
  Money get totalUtangCollected => accountingReport.debtCollections;

  // Total outstanding principal plus accrued interest across all customers.
  Money get totalDebtAmount => accountingReport.receivables;

  // Sum ng lahat ng delivered orders lang.
  // FIX: Use customerPayAmount (net) instead of totalAmount (SRP) so reseller
  // delivered orders don't overcount revenue by the discount amount.
  Money get deliveredRevenue => accountingReport.netSales;

  // Cash received from paid orders, debt collections, and custom-order receipts.
  Money get totalRevenue => accountingReport.cashReceived;

  // Returns a count for each OrderStatus enum value — used by analytics pie chart
  Map<OrderStatus, int> get ordersByStatus => {
    for (final s in OrderStatus.values)
      s: _orders.where((o) => o.status == s).length,
  };

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

  // ── Auth ──────────────────────────────────────────────────────────────────

  // Authenticates with Firebase email/password, then loads the UID partition.
  Future<bool> login(String email, String password) async {
    await _waitForLogoutCleanup();
    final operation = ++_sessionGeneration;
    _batchNotify();
    _lastAuthMessage = null;
    _lastAuthStatus = null;
    try {
      // ── Rate limiting: reject immediately if locked out ─────────────────
      final limiter = LoginRateLimiter.instance;
      if (limiter.isLockedOut(email)) {
        _batchNotify();
        return false; // UI reads secondsRemaining() for the countdown message
      }

      final result = await _as.login(email, password);
      if (operation != _sessionGeneration) return false;
      _lastAuthStatus = result.status;
      final user = result.user;
      if (user == null) {
        _lastAuthMessage = result.message;
        if (result.status == 'denied') await limiter.recordFailure(email);
        _batchNotify();
        return false;
      }

      await limiter.recordSuccess(email);
      _activeUser = user.id;
      _currentUser = user;
      _isLoggedIn = true;
      _isOfflineSession = false;
      await SyncQueue.instance.startMonitoring();
      _syncStatus = await SyncQueue.instance.statusForUser(_activeUser);
      await _loadAllData();
      _scheduleDueDateCheck();
      _addLogSilent('${user.username} signed in', 'auth');
      return true;
    } catch (_) {
      _lastAuthMessage = 'Authentication failed. Please try again.';
      _batchNotify();
      return false;
    }
  }

  // Creates a Firebase account and starts verified pending Staff registration.
  // It never enters protected state before Administrator approval.
  Future<bool> register(
    String name,
    String username,
    String password, {
    String confirm = '',
    String? email,
  }) async {
    _batchNotify();
    _lastAuthMessage = null;
    _lastAuthStatus = null;
    try {
      if (password != (confirm.isEmpty ? password : confirm)) {
        _lastAuthMessage = 'Passwords do not match.';
        _batchNotify();
        return false;
      }
      final result = await _as.requestRegistration(
        name: name,
        username: username,
        email: email ?? '',
        password: password,
      );
      _lastAuthMessage = result.message;
      _lastAuthStatus = result.status;
      _batchNotify();
      return result.status == 'verification_required' ||
          result.status == 'pending';
    } catch (_) {
      _lastAuthMessage = 'Registration request failed. Please try again.';
      _batchNotify();
      return false;
    }
  }

  Future<bool> completeRegistration() async {
    _batchNotify();
    final result = await _as.completeRegistration();
    _lastAuthMessage = result.message;
    _lastAuthStatus = result.status;
    _batchNotify();
    return result.status == 'pending';
  }

  Future<void> deferRegistration() => _as.deferRegistration();

  Future<void> sendPasswordReset(String email) => _as.sendPasswordReset(email);

  Future<void> restoreSession() async {
    await _waitForLogoutCleanup();
    final operation = ++_sessionGeneration;
    final result = await _as.restoreSession();
    final user = result.user;
    if (user == null || operation != _sessionGeneration || _isLoggedIn) return;
    _activeUser = user.id;
    _currentUser = user;
    _isLoggedIn = true;
    _isOfflineSession = false;
    await SyncQueue.instance.startMonitoring();
    await _loadAllData();
    _scheduleDueDateCheck();
  }

  Future<void> restoreTrustedDevice() async {
    await _waitForLogoutCleanup();
    final operation = ++_sessionGeneration;
    final result = await _as.restoreTrustedDevice();
    final user = result.user;
    if (user == null || operation != _sessionGeneration) return;
    _activeUser = user.id;
    _currentUser = user;
    _isLoggedIn = true;
    _isOfflineSession = true;
    await _loadAllData();
    _scheduleDueDateCheck();
  }

  Future<void> completePendingSignOut() => _as.completePendingSignOut();

  Future<void> reconcileCloudPrincipal(String? uid) async {
    if (!_isLoggedIn || uid == null) return;
    if (uid != _activeUser) {
      await _closeRevokedSession(
        'reauth_required',
        'The cloud account changed. Sign in online to select an account.',
      );
      return;
    }
    await _authorizeSynchronization(uid);
  }

  Future<bool> _authorizeSynchronization(String uid) async {
    if (!_isLoggedIn || uid != _activeUser) return false;
    final generation = _sessionGeneration;
    final result = await _as.revalidateAccess(uid);
    if (generation != _sessionGeneration || uid != _activeUser) return false;
    if (result.success) {
      _currentUser = result.user;
      _isOfflineSession = false;
      _batchNotify();
      return true;
    }
    if (result.status == 'offline' || result.status == 'unavailable') {
      _isOfflineSession = true;
      _batchNotify();
      return false;
    }
    if ({'suspended', 'rejected', 'reauth_required'}.contains(result.status)) {
      await _closeRevokedSession(result.status, result.message);
    }
    return false;
  }

  Future<void> _reconcileInbound(String uid) async {
    if (!_isLoggedIn || uid != _activeUser || _isOfflineSession) return;
    final generation = _sessionGeneration;
    final result = await InboundSyncCoordinator.instance.reconcile(uid);
    if (!result.changed ||
        generation != _sessionGeneration ||
        uid != _activeUser) {
      return;
    }
    await _loadAllData();
    if (generation == _sessionGeneration && uid == _activeUser) {
      _batchNotify();
    }
  }

  Future<void> _closeRevokedSession(String reason, String? message) async {
    final uid = _activeUser;
    await _clearProtectedState();
    _lastAuthStatus = reason;
    _lastAuthMessage = message ?? 'Account access has been revoked.';
    _batchNotify();
    try {
      await _stopSynchronization();
      await _as.revokeAccess(uid, reason);
    } catch (error) {
      if (kDebugMode) debugPrint('[AppState] revoke cleanup: $error');
    }
    await _cancelNotifications();
  }

  // Clears all in-memory state and triggers full UI rebuild to show LoginScreen
  Future<void> logout() {
    final existing = _logoutInProgress;
    if (existing != null) return existing;
    late final Future<void> tracked;
    tracked = _performLogout().whenComplete(() {
      if (identical(_logoutInProgress, tracked)) _logoutInProgress = null;
    });
    _logoutInProgress = tracked;
    return tracked;
  }

  Future<void> _waitForLogoutCleanup() async {
    final logout = _logoutInProgress;
    if (logout == null) return;
    try {
      await logout;
    } catch (_) {
      // Local state is already fail-closed; a fresh login may retry auth.
    }
  }

  Future<void> _performLogout() async {
    await _clearProtectedState();

    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> runLogoutStep(Future<void> Function() step) async {
      try {
        await step();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await runLogoutStep(_stopSynchronization);
    await runLogoutStep(_as.logout);
    await runLogoutStep(_cancelNotifications);
    ProtectedNavigation.removeRoutesAboveRoot();
    KnzToast.dismissCurrent();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  Future<void> _clearProtectedState() async {
    SessionTimeoutService.instance.stop();
    _dueDateTimer?.cancel();
    _dueDateTimer = null;
    KnzToast.dismissCurrent();
    _sessionGeneration++;
    _isLoggedIn = false;
    _isOfflineSession = false;
    _currentUser = null;
    _activeUser = '';
    _products = [];
    _orders = [];
    _debts = [];
    _activityLogs = [];
    _resellers = [];
    // FIX: Also clear _customOrders — omitting this caused the previous user's
    // custom orders to be briefly visible until _loadAllData() finished on re-login.
    _customOrders = [];
    _businessEvents = [];
    _lastDataError = null;
    _syncStatus = const SyncStatus.empty();
    notifyListeners();
    ProtectedNavigation.removeRoutesAboveRoot();
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadAllData() async {
    try {
      final generation = _sessionGeneration;
      final ownerUid = _activeUser;
      final (
        products,
        orders,
        debts,
        logs,
        resellers,
        customOrders,
        businessEvents,
      ) = await (
        _ps.getAll(ownerUid),
        _os.getAll(ownerUid),
        _ds.getAll(ownerUid),
        _logRepo.getAll(ownerUid),
        _resellerRepo.getAll(ownerUid),
        _customOrderRepo.getAll(ownerUid),
        _businessEventRepo.getAll(ownerUid),
      ).wait;
      if (generation != _sessionGeneration || ownerUid != _activeUser) return;
      _products = products;
      _orders = orders;
      _debts = debts;
      _activityLogs = logs;
      _resellers = resellers;
      _customOrders = customOrders;
      _businessEvents = businessEvents;
      _lastDataError = null;
      _syncStatus = await SyncQueue.instance.statusForUser(ownerUid);
      await _syncNotificationsForCurrentState();
    } catch (error, stackTrace) {
      if (kDebugMode) debugPrint('[AppState] data load: $error\n$stackTrace');
      _lastDataError =
          'Data refresh failed. Showing the last successfully loaded records.';
    } finally {
      _batchNotify();
    }
  }

  // Public shortcut to re-fetch all data (e.g. after sync or pull-to-refresh)
  Future<void> refreshData() => _loadAllData();

  Future<void> _syncNotificationsForCurrentState() async {
    if (!_isLoggedIn) return;
    try {
      await _syncBusinessAlerts(_products, _debts);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AppState] notification sync: ${error.runtimeType}');
      }
    }
  }

  void _scheduleDueDateCheck() {
    _dueDateTimer?.cancel();
    if (!_isLoggedIn) return;
    final now = DateTime.now();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _dueDateTimer = Timer(nextDay.difference(now), () async {
      await _syncNotificationsForCurrentState();
      _scheduleDueDateCheck();
    });
  }

  // ── Products ──────────────────────────────────────────────────────────────

  // Adds a new product to the DB then refreshes the in-memory list
  Future<void> addProduct(Product product) async {
    try {
      await _ps.addProduct(
        userId: _activeUser,
        name: product.name,
        description: product.description,
        category: product.category,
        price: product.price,
        stockQty: product.stockQty,
        minStockLevel: product.minStockLevel,
        imagePath: product.imagePath,
      );
      await _refreshAfterCommit(() async {
        _products = await _ps.getAll(_activeUser);
      });
      await _syncNotificationsForCurrentState();
      _addLogSilent('Product "${product.name}" added', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
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
      await _syncNotificationsForCurrentState();
      _addLogSilent('Product "${updated.name}" updated', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
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
        _products = List.of(_products)
          ..[idx] = _products[idx].copyWith(stockQty: newQty);
        _addLogSilent('Stock updated for "${_products[idx].name}"', 'stock');
      }
      await _syncNotificationsForCurrentState();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  // Soft-deletes a product (moves to Recycle Bin, not permanently removed)
  Future<void> deleteProduct(String productId) async {
    _requireAdministrator();
    try {
      final product = _products.firstWhere((p) => p.id == productId);
      await _ps.deleteProduct(productId, _activeUser);
      // Remove from local list immediately for instant UI feedback
      _products = _products.where((p) => p.id != productId).toList();
      await _syncNotificationsForCurrentState();
      _addLogSilent('Product "${product.name}" removed', 'product');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
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
  // Creates a new order, deducts stock via OrderService, and refreshes both lists.
  // AUTO-UTANG: If the order status is utang, automatically creates a matching
  // CustomerDebt record so the order appears in the Utang Tracker immediately.
  Future<bool> addOrder(
    Order order, {
    void Function(String)? onError,
    int interestRateBasisPoints = 0,
    String interestType = 'none',
    DateTime? dueDate,
  }) async {
    final generation = _sessionGeneration;
    final ownerUid = _activeUser;
    try {
      final debt = order.status == OrderStatus.utang
          ? CustomerDebt(
              id: const Uuid().v4(),
              customerName: order.customerName,
              orderId: order.orderId,
              principalOriginal: order.customerPayAmount,
              principalOutstanding: order.customerPayAmount,
              createdAt: DateTime.now().toUtc(),
              interestRateBasisPoints: interestRateBasisPoints,
              interestType: interestType,
              interestStartTimestamp: order.orderDate.toUtc(),
              lastAccrualTimestamp: order.orderDate.toUtc(),
              dueDate: dueDate,
            )
          : null;
      final result = await _os.createOrder(order, ownerUid, debt: debt);
      if (generation != _sessionGeneration || ownerUid != _activeUser) {
        return true;
      }

      if (debt != null && result.created) {
        _addLogSilent(
          'Utang auto-recorded for ${order.customerName} — '
              '₱${debt.remainingBalance.toStringAsFixed(2)} remaining',
          'payment',
        );
      }

      await _refreshAfterCommit(() async {
        final (products, orders, debts) = await (
          _ps.getAll(ownerUid),
          _os.getAll(ownerUid),
          _ds.getAll(ownerUid),
        ).wait;
        if (generation != _sessionGeneration || ownerUid != _activeUser) return;
        _products = products;
        _orders = orders;
        _debts = debts;
      });
      await _reloadBusinessEvents();
      await _syncNotificationsForCurrentState();
      if (generation != _sessionGeneration || ownerUid != _activeUser) {
        return true;
      }
      if (result.created) {
        _addLogSilent(
          'New order ${result.order.orderId} created for ${order.customerName}',
          'order',
        );
      }
      return true; // ← FIX 4: returns true on success
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AppState] addOrder: $e\n$stackTrace');
      }
      final detail = e is DomainException
          ? e.message
          : e is StateError
          ? e.message
          : e is ArgumentError
          ? e.message?.toString()
          : null;
      onError?.call(
        detail == null || detail.trim().isEmpty
            ? 'Failed to create order. Please try again.'
            : detail,
      );
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
        _orders = List.of(_orders)
          ..[idx] = _orders[idx].copyWith(status: status);
      }
      _addLogSilent('Order status updated → ${status.displayName}', 'order');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  Future<BusinessEvent> recordOrderPayment({
    required String orderId,
    required Money amount,
    required PaymentMethod method,
    String? reference,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final event = BusinessEvent(
      id: id,
      userId: _activeUser,
      subject: BusinessEventSubject.order,
      subjectId: orderId,
      type: BusinessEventType.payment,
      amount: amount,
      occurredAt: now,
      recordedAt: now,
      paymentMethod: method.storageKey,
      reference: reference?.trim().isEmpty ?? true ? null : reference!.trim(),
      reason: note?.trim().isEmpty ?? true ? null : note!.trim(),
      commandId: id,
    );
    final saved = await _os.recordPayment(orderId, event);
    await _reloadBusinessEvents();
    _addLogSilent('Order payment recorded — ${amount.format()}', 'payment');
    _batchNotify();
    return saved;
  }

  Future<BusinessEvent> recordOrderDelivery(String orderId) async {
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final event = BusinessEvent(
      id: id,
      userId: _activeUser,
      subject: BusinessEventSubject.order,
      subjectId: orderId,
      type: BusinessEventType.delivery,
      occurredAt: now,
      recordedAt: now,
      commandId: id,
    );
    final saved = await _os.recordDelivery(orderId, event);
    final index = _orders.indexWhere((order) => order.id == orderId);
    if (index >= 0) {
      _orders = List.of(_orders)
        ..[index] = _orders[index].copyWith(status: OrderStatus.delivered);
    }
    await _reloadBusinessEvents();
    _addLogSilent('Order delivered', 'order');
    _batchNotify();
    return saved;
  }

  Future<BusinessEvent> issueOrderRefund({
    required String orderId,
    required Money amount,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final event = BusinessEvent(
      id: id,
      userId: _activeUser,
      subject: BusinessEventSubject.order,
      subjectId: orderId,
      type: BusinessEventType.refund,
      amount: amount,
      occurredAt: now,
      recordedAt: now,
      reason: reason,
      commandId: id,
    );
    final saved = await _os.issueRefund(orderId, event);
    await _reloadBusinessEvents();
    _addLogSilent('Order refund issued — ${amount.format()}', 'payment');
    _batchNotify();
    return saved;
  }

  Future<BusinessEvent> reverseOrderEvent({
    required String orderId,
    required BusinessEvent target,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final event = BusinessEvent(
      id: id,
      userId: _activeUser,
      subject: BusinessEventSubject.order,
      subjectId: orderId,
      type: BusinessEventType.reversal,
      amount: target.amount,
      occurredAt: now,
      recordedAt: now,
      relatedEventId: target.id,
      reason: reason,
      commandId: id,
    );
    final saved = await _os.reverseEvent(orderId, event);
    await _reloadBusinessEvents();
    _addLogSilent('Order event reversed', 'payment');
    _batchNotify();
    return saved;
  }

  Future<void> _reloadBusinessEvents() async {
    _businessEvents = await _businessEventRepo.getAll(_activeUser);
  }

  /// Atomically converts an existing order to utang and creates its debt.
  Future<void> markOrderAsUtang(String orderId, CustomerDebt debt) async {
    try {
      await _os.markAsUtang(orderId, debt);
      await _refreshAfterCommit(() async {
        final (orders, debts) = await (
          _os.getAll(_activeUser),
          _ds.getAll(_activeUser),
        ).wait;
        _orders = orders;
        _debts = debts;
      });
      await _reloadBusinessEvents();
      await _syncNotificationsForCurrentState();
      _addLogSilent(
        'Utang recorded for ${debt.customerName} — '
            '₱${debt.totalWithInterest.toStringAsFixed(2)} due',
        'payment',
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AppState] markOrderAsUtang: $error\n$stackTrace');
      }
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  // Soft-deletes an order and removes it from the in-memory list.
  // BUG FIX (Stock restore on delete): When an order is soft-deleted we add the
  // ordered quantities back to their products so stock stays accurate.
  Future<void> deleteOrder(String orderId) async {
    _requireAdministrator();
    try {
      await _os.deleteOrder(orderId, _activeUser);
      _orders = _orders.where((o) => o.id != orderId).toList();
      _products = await _ps.getAll(_activeUser);
      await _syncNotificationsForCurrentState();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] deleteOrder: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  // ── Recycle Bin (fully DIP-compliant — routes through service interfaces) ─

  /// Returns all soft-deleted orders for the current user.
  // Used by RecycleBinScreen to list orders pending permanent deletion
  Future<List<Order>> getDeletedOrders() async {
    _requireAdministrator();
    return _os.getDeleted(_activeUser);
  }

  /// Returns all soft-deleted products for the current user.
  // Used by RecycleBinScreen to list products pending permanent deletion
  Future<List<Product>> getDeletedProducts() async {
    _requireAdministrator();
    return _ps.getDeleted(_activeUser);
  }

  // Un-deletes an order and refreshes the active orders list.
  // BUG FIX (Stock re-deduction on restore): When an order is restored we
  // re-deduct its quantities from stock so the delete+restore cycle stays neutral.
  Future<void> restoreOrder(String orderId) async {
    _requireAdministrator();
    try {
      await _os.restoreOrder(orderId, _activeUser);
      await refreshData(); // Full reload — pulls the restored order into _orders
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] restoreOrder: $e\n$st');
      rethrow;
    }
  }

  // Un-deletes a product and refreshes the active products list
  Future<void> restoreProduct(String productId) async {
    _requireAdministrator();
    try {
      await _ps.restoreProduct(productId, _activeUser);
      await refreshData(); // Full reload — isLogin defaults to false, no notifs
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
    }
  }

  // Permanently removes an order from both SQLite and Firestore (no recovery)
  Future<void> hardDeleteOrder(String orderId) async {
    await _requireFreshAdministrator();
    try {
      await _os.hardDeleteOrder(orderId, _activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
    }
  }

  // Permanently removes a product from both SQLite and Firestore (no recovery)
  Future<void> hardDeleteProduct(String productId) async {
    await _requireFreshAdministrator();
    try {
      await _ps.hardDeleteProduct(productId, _activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
    }
  }

  /// Returns all soft-deleted debts for the current user.
  // Used by RecycleBinScreen to list debts pending permanent deletion
  Future<List<CustomerDebt>> getDeletedDebts() async {
    _requireAdministrator();
    return _ds.getDeleted(_activeUser);
  }

  /// Returns all soft-deleted custom orders for the current user.
  Future<List<CustomOrder>> getDeletedCustomOrders() async {
    _requireAdministrator();
    return _customOrderRepo.getDeleted(_activeUser);
  }

  /// Returns all soft-deleted resellers for the current user.
  Future<List<Reseller>> getDeletedResellers() async {
    _requireAdministrator();
    return _resellerRepo.getDeleted(_activeUser);
  }

  // Un-deletes a debt record and refreshes all data
  Future<void> restoreDebt(String debtId) async {
    _requireAdministrator();
    try {
      await _ds.restoreDebt(debtId, _activeUser);
      await refreshData(); // Full reload — isLogin defaults to false, no notifs
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] restoreDebt: $e\n$st');
      rethrow;
    }
  }

  // Permanently removes a debt record (no recovery after this)
  Future<void> hardDeleteDebt(String debtId) async {
    await _requireFreshAdministrator();
    try {
      await _ds.hardDeleteDebt(debtId, _activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] hardDeleteDebt: $e\n$st');
      rethrow;
    }
  }

  /// Restores a custom order owned by the active user.
  Future<void> restoreCustomOrder(String customOrderId) async {
    _requireAdministrator();
    try {
      await _customOrderRepo.restore(customOrderId, _activeUser);
      _customOrders = await _customOrderRepo.getAll(_activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] restoreCustomOrder: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  /// Permanently removes an already-deleted custom order for the active user.
  Future<void> hardDeleteCustomOrder(String customOrderId) async {
    await _requireFreshAdministrator();
    try {
      await _customOrderRepo.hardDelete(customOrderId, _activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] hardDeleteCustomOrder: $e\n$st');
      rethrow;
    }
  }

  /// Restores a reseller owned by the active user.
  Future<void> restoreReseller(String resellerId) async {
    _requireAdministrator();
    try {
      await _resellerRepo.restore(resellerId, _activeUser);
      _resellers = await _resellerRepo.getAll(_activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] restoreReseller: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  /// Permanently removes an already-deleted reseller for the active user.
  Future<void> hardDeleteReseller(String resellerId) async {
    await _requireFreshAdministrator();
    try {
      await _resellerRepo.hardDelete(resellerId, _activeUser);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] hardDeleteReseller: $e\n$st');
      rethrow;
    }
  }

  // ── Debts ─────────────────────────────────────────────────────────────────

  // Records a partial or full payment against an existing debt; reloads debts list
  Future<String?> addPayment(String debtId, PaymentRecord payment) async {
    final generation = _sessionGeneration;
    final ownerUid = _activeUser;
    try {
      final debt = _debts.firstWhere((d) => d.id == debtId);
      // FIX: Pass totalWithInterest (principal + accrued interest) as the ceiling,
      // not remainingBalance (principal only). The dialog validates against
      // totalWithInterest, so the service must use the same ceiling or it will
      // silently reject valid interest-inclusive payments.
      final validationError = await _ds.addPayment(
        debtId,
        payment,
        debt.totalWithInterest,
      );
      if (validationError != null) return validationError;
      if (generation != _sessionGeneration || ownerUid != _activeUser) {
        return null;
      }
      // Full reload because amountPaid and isPaid may have changed
      await _refreshAfterCommit(() async {
        final debts = await _ds.getAll(ownerUid);
        if (generation != _sessionGeneration || ownerUid != _activeUser) return;
        _debts = debts;
      });
      await _reloadBusinessEvents();
      await _syncNotificationsForCurrentState();
      if (generation != _sessionGeneration || ownerUid != _activeUser) {
        return null;
      }
      _addLogSilent(
        'Payment ₱${payment.amount.toStringAsFixed(2)} received',
        'payment',
      );
      return null;
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      return 'The payment could not be saved. Please try again.';
    } finally {
      _batchNotify();
    }
  }

  // Soft-deletes a debt and removes it from the in-memory list
  Future<void> deleteDebt(String debtId) async {
    _requireAdministrator();
    try {
      await _ds.deleteDebt(debtId, _activeUser);
      _debts = _debts.where((d) => d.id != debtId).toList();
      await _syncNotificationsForCurrentState();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  // ── Custom Orders (Feature 5) ─────────────────────────────────────────────

  Future<void> addCustomOrder(CustomOrder order) async {
    try {
      await _customOrderRepo.save(order);
      _customOrders = [order, ..._customOrders];
      await _reloadBusinessEvents();
      _addLogSilent(
        'Custom order created for ${order.customerName}',
        'custom_order',
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] addCustomOrder: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  Future<void> updateCustomOrder(CustomOrder order) async {
    try {
      await _customOrderRepo.update(order);
      final idx = _customOrders.indexWhere((o) => o.id == order.id);
      if (idx != -1) {
        _customOrders = List.of(_customOrders)..[idx] = order;
      } else {
        _customOrders = await _customOrderRepo.getAll(_activeUser);
      }
      _addLogSilent(
        'Custom order updated for ${order.customerName}',
        'custom_order',
      );
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] updateCustomOrder: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  Future<void> addCustomOrderPayment(
    String customOrderId,
    CustomOrderPayment payment,
  ) async {
    try {
      final order = _customOrders.firstWhere(
        (item) => item.id == customOrderId,
      );
      if (payment.customOrderId != customOrderId) {
        throw ArgumentError('Payment does not belong to this custom order.');
      }
      if (payment.amount > order.balanceDue) {
        throw StateError('Payment exceeds the custom-order balance.');
      }
      final payments = [...order.payments, payment];
      final updated = order.copyWith(
        depositPaid: order.depositPaid + payment.amount,
        payments: payments,
      );
      await _customOrderRepo.update(updated);
      final index = _customOrders.indexWhere(
        (item) => item.id == customOrderId,
      );
      _customOrders = List.of(_customOrders)..[index] = updated;
      await _reloadBusinessEvents();
      _addLogSilent(
        'Custom-order payment ₱${payment.amount.toStringAsFixed(2)} received',
        'payment',
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AppState] addCustomOrderPayment: $error\n$stackTrace');
      }
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  Future<void> updateCustomOrderStatus(
    String id,
    CustomOrderStatus status,
  ) async {
    try {
      await _customOrderRepo.updateStatus(id, _activeUser, status.storageKey);
      final idx = _customOrders.indexWhere((o) => o.id == id);
      if (idx != -1) {
        _customOrders = List.of(_customOrders)
          ..[idx] = _customOrders[idx].copyWith(status: status);
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] updateCustomOrderStatus: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  Future<void> deleteCustomOrder(String id) async {
    _requireAdministrator();
    try {
      await _customOrderRepo.delete(id, _activeUser);
      _customOrders = _customOrders.where((o) => o.id != id).toList();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[AppState] deleteCustomOrder: $e\n$st');
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  // ── Resellers ─────────────────────────────────────────────────────────────

  /// Adds a new reseller and reloads the list.
  Future<void> addReseller(Reseller reseller) async {
    try {
      await _resellerRepo.save(reseller);
      _resellers = [reseller, ..._resellers];
      _addLogSilent('Reseller added: ${reseller.name}', 'reseller');
    } catch (_) {
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  /// Updates an existing reseller.
  Future<void> updateReseller(Reseller reseller) async {
    try {
      await _resellerRepo.update(reseller);
      final index = _resellers.indexWhere((item) => item.id == reseller.id);
      if (index >= 0) {
        _resellers = List.of(_resellers)..[index] = reseller;
      }
      _addLogSilent('Reseller updated: ${reseller.name}', 'reseller');
    } catch (_) {
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  /// Soft-deletes a reseller.
  Future<void> deleteReseller(String resellerId) async {
    _requireAdministrator();
    try {
      await _resellerRepo.delete(resellerId, _activeUser);
      _resellers = _resellers.where((r) => r.id != resellerId).toList();
    } catch (_) {
      rethrow;
    } finally {
      _batchNotify();
    }
  }

  // ── Sales Records (flattened view for Feature 8) ──────────────────────────

  /// Flattens all active orders + their items into SalesRecord rows.
  /// Filtered to recognized (delivered or fulfilled-credit) sales only.
  List<SalesRecord> get salesRecords {
    final List<SalesRecord> records = [];
    for (final order in accountingReport.recognizedOrders) {
      for (final item in order.items) {
        // unitPrice = actual selling price (after deduction, always correct)
        final discountedPrice = item.unitPrice;

        // SRP: use stored srpPrice. For legacy orders saved before the fix,
        // srpPrice == unitPrice (both 220) — no item-level discount was tracked then.
        // Do NOT try to reconstruct SRP from deductionPerItem for legacy rows:
        //   220 + 50 = 270 is WRONG — the true SRP was already 220.
        // New orders (post-fix) correctly save unitPrice=170, srpPrice=220.
        final srp = item.srpPrice;

        final displayDiscountBasisPoints =
            srp.isPositive && srp != discountedPrice
            ? roundRatioHalfUp(
                (srp - discountedPrice).centavos * 10000,
                srp.centavos,
              )
            : 0;
        records.add(
          SalesRecord(
            orderId: order.orderId,
            itemName: item.productName,
            srp: srp,
            discountedPrice: discountedPrice,
            quantity: item.quantity,
            customerName: order.customerName,
            datePurchased: order.orderDate,
            totalSales: discountedPrice * item.quantity,
            isReseller: order.isReseller,
            discountBasisPoints: displayDiscountBasisPoints,
          ),
        );
      }
    }
    // Most recent first
    records.sort((a, b) => b.datePurchased.compareTo(a.datePurchased));
    return records;
  }

  void _requireAdministrator() {
    if (!_isLoggedIn || !isAdministrator) {
      throw StateError('Administrator access is required.');
    }
  }

  Future<void> _requireFreshAdministrator() async {
    _requireAdministrator();
    if (_isOfflineSession || !await _authorizeSynchronization(_activeUser)) {
      throw StateError(
        'Connect to the internet and verify Administrator access before permanent deletion.',
      );
    }
    _requireAdministrator();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _refreshAfterCommit(Future<void> Function() refresh) async {
    try {
      await refresh();
      _lastDataError = null;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AppState] post-commit refresh: $error\n$stackTrace');
      }
      _lastDataError =
          'Changes were saved locally, but the screen could not refresh. '
          'The last loaded data is still shown.';
    }
  }

  // Creates and stores an activity log entry without triggering a UI notify
  // (the calling method's _batchNotify() will cover the rebuild)
  void _addLogSilent(String message, String type) {
    final now = DateTime.now();
    // FIX 6: Dati microsecondsSinceEpoch — posible ang collision sa mabilis na ops.
    // Ngayon Uuid().v4() — guaranteed unique, consistent sa ibang parts ng codebase.
    // UUID v4 guarantees uniqueness even for rapid back-to-back log entries
    final log = ActivityLog(
      id: const Uuid().v4(),
      message: message,
      timestamp: now,
      type: type,
    );
    // Keep at most 50 entries in memory; oldest entries are dropped
    _activityLogs = [
      log,
      if (_activityLogs.length < 50)
        ..._activityLogs
      else
        ..._activityLogs.take(49),
    ];
    // Keep the primary commit successful, but surface an activity-log failure
    // separately instead of discarding it.
    unawaited(
      _logRepo.add(log, _activeUser).catchError((Object error) {
        _lastDataError = 'Activity log could not be saved: $error';
        _batchNotify();
      }),
    );
  }

  Future<void> retryFailedSync() async {
    if (_activeUser.isEmpty) return;
    await SyncQueue.instance.retryFailed(_activeUser);
    _syncStatus = await SyncQueue.instance.statusForUser(_activeUser);
    _batchNotify();
  }
}
