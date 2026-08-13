// ─────────────────────────────────────────────────────────────────────────────
// main_shell.dart
// Purpose : The root scaffold that wraps all main screens behind authentication.
// Function: Manages navigation between Overview, Inventory, Orders, Products,
//           Analytics, and Utang screens via a sidebar (desktop) or slide-out
//           drawer (mobile). The sidebar uses ListenableBuilder scoped to AppState
//           so only the nav badges (lowStockCount, pendingCount) rebuild.
//           navigateTo(NavItem) is a public method used by dialogs to deep-link
//           to a specific tab (e.g., after recording a new utang).
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/protected_navigation.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/sync_status_banner.dart';
import 'overview_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';
import 'analytics_screen.dart';
import 'utang_screen.dart';
import 'recycle_bin_screen.dart';
import 'sales_screen.dart';
import 'reseller_screen.dart';
import 'reseller_accounting_screen.dart';
import 'accounting_screen.dart';
import 'custom_orders_screen.dart';
import 'reports_screen.dart';
import 'registration_requests_screen.dart';
import 'sync_issues_screen.dart';

enum NavItem {
  overview,
  inventory,
  orders,
  products,
  analytics,
  utang,
  sales,
  resellers,
  resellerAccounting,
  accounting,
  customOrders,
  reports,
  registrationRequests,
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  NavItem _selected = NavItem.overview;
  bool _sidebarOpen = false;
  bool _isLoggingOut = false;

  // Public method — allows child dialogs/screens to navigate to a specific tab
  // (e.g., MarkAsUtangDialog calls this to jump to the Utang tab after recording)
  void navigateTo(NavItem item) {
    setState(() {
      _selected = item;
      _sidebarOpen = false;
    });
  }

  late AnimationController _drawerCtrl;
  late Animation<Offset> _drawerAnim;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _drawerAnim = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _drawerCtrl, curve: Curves.easeOut));
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to access business data.',
      confirmLabel: 'Sign Out',
      confirmColor: AppColors.error,
      icon: Icons.logout_rounded,
    );
    if (confirmed && mounted) await _logoutAndNavigate();
  }

  Future<void> _logoutAndNavigate() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    if (mounted) {
      setState(() => _sidebarOpen = false);
      _drawerCtrl.reverse();
    }
    try {
      await AppState().logout();
    } catch (_) {
      // Logout is fail-closed: local protected state stays cleared even when a
      // remote cleanup step fails.
      final loginContext = ProtectedNavigation.navigatorKey.currentContext;
      if (loginContext != null) {
        KnzToast.error(
          loginContext,
          'Signed out locally, but remote sign-out cleanup was incomplete.',
        );
      }
    }
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    super.dispose();
  }

  Widget _buildScreen() {
    switch (_selected) {
      case NavItem.overview:
        return const OverviewScreen();
      case NavItem.inventory:
        return const InventoryScreen();
      case NavItem.orders:
        return const OrdersScreen();
      case NavItem.products:
        return const ProductsScreen();
      case NavItem.analytics:
        return const AnalyticsScreen();
      case NavItem.utang:
        return const UtangScreen();
      case NavItem.sales:
        return const SalesScreen();
      case NavItem.resellers:
        return const ResellersScreen();
      case NavItem.resellerAccounting:
        return const ResellerAccountingScreen();
      case NavItem.accounting:
        return const AccountingScreen();
      case NavItem.customOrders:
        return const CustomOrdersScreen();
      case NavItem.reports:
        return const ReportsScreen();
      case NavItem.registrationRequests:
        return const RegistrationRequestsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          ListenableBuilder(
            listenable: AppState(),
            builder: (context, _) => SyncStatusBanner(
              status: AppState().syncStatus,
              isOffline: AppState().isOfflineSession,
              dataError: AppState().lastDataError,
              onRetry: () => unawaited(AppState().retryFailedSync()),
            ),
          ),
          Expanded(child: isWide ? _buildWideLayout() : _buildNarrowLayout()),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        _buildSidebar(),
        Expanded(child: _buildScreen()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildScreen()),
          ],
        ),
        if (_sidebarOpen) ...[
          GestureDetector(
            onTap: () {
              _drawerCtrl.reverse();
              setState(() => _sidebarOpen = false);
            },
            child: Container(color: Colors.black54),
          ),
          SlideTransition(
            position: _drawerAnim,
            child: SizedBox(width: 240, child: _buildSidebar()),
          ),
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    // SafeArea top — prevents overlap with the system status bar
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      color: AppColors.sidebar,
      padding: EdgeInsets.only(top: topPadding, left: 8, right: 8),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.gold),
              onPressed: () {
                setState(() => _sidebarOpen = true);
                _drawerCtrl.forward();
              },
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      AppStrings.appName,
                      style: AppTextStyles.brandName.copyWith(fontSize: 20),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      AppStrings.appSubtitle,
                      style: AppTextStyles.brandSubtitle.copyWith(fontSize: 8),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Builds the left navigation sidebar.
  // Uses ListenableBuilder so only the sidebar (specifically the badge counts)
  // rebuilds when AppState notifies — not the entire shell.
  Widget _buildSidebar() {
    // ListenableBuilder scopes badge rebuilds to the sidebar only
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) {
        final state = AppState();
        // Use SafeArea so sidebar content clears the status bar on narrow layout
        final topPadding = MediaQuery.of(context).padding.top;
        return Container(
          width: 240,
          decoration: const BoxDecoration(
            gradient: AppColors.sidebarGradient,
            border: Border(right: BorderSide(color: AppColors.cardBorder)),
          ),
          child: Column(
            children: [
              // ── Fixed header ──────────────────────────────────────────────
              SizedBox(height: topPadding + 16),
              FadeInLeft(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.water_drop_outlined,
                        color: AppColors.gold,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.appName,
                            style: AppTextStyles.brandName.copyWith(
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            AppStrings.appSubtitle,
                            style: AppTextStyles.brandSubtitle.copyWith(
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.settings, color: AppColors.gold, size: 16),
                      SizedBox(width: 8),
                      Text(
                        AppStrings.adminPortal,
                        style: TextStyle(color: AppColors.gold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Scrollable nav items ──────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _navSection('MAIN'),
                      _navItem(
                        NavItem.overview,
                        Icons.bar_chart,
                        AppStrings.overview,
                      ),
                      const SizedBox(height: 12),
                      _navSection('MANAGEMENT'),
                      _navItem(
                        NavItem.inventory,
                        Icons.inventory_2_outlined,
                        AppStrings.inventory,
                        badge: state.lowStockCount > 0
                            ? state.lowStockCount
                            : null,
                      ),
                      _navItem(
                        NavItem.orders,
                        Icons.local_shipping_outlined,
                        AppStrings.orders,
                        badge: state.pendingCount > 0
                            ? state.pendingCount
                            : null,
                      ),
                      _navItem(
                        NavItem.products,
                        Icons.auto_awesome,
                        AppStrings.products,
                      ),
                      const SizedBox(height: 12),
                      _navSection('REPORTS'),
                      _navItem(
                        NavItem.analytics,
                        Icons.trending_up,
                        AppStrings.analytics,
                      ),
                      const SizedBox(height: 4),
                      _navItem(
                        NavItem.utang,
                        Icons.account_balance_wallet_outlined,
                        'Utang',
                      ),
                      const SizedBox(height: 4),
                      _navItem(
                        NavItem.sales,
                        Icons.table_chart_outlined,
                        'Sales Table',
                      ),
                      const SizedBox(height: 8),
                      _navSection('RESELLERS'),
                      _navItem(
                        NavItem.resellers,
                        Icons.people_outline,
                        'Resellers',
                      ),
                      const SizedBox(height: 4),
                      _navItem(
                        NavItem.resellerAccounting,
                        Icons.receipt_long_outlined,
                        'Reseller Accounting',
                      ),
                      const SizedBox(height: 8),
                      _navSection('ADVANCED'),
                      _navItem(
                        NavItem.accounting,
                        Icons.account_balance_outlined,
                        'Accounting',
                      ),
                      const SizedBox(height: 4),
                      _navItem(
                        NavItem.customOrders,
                        Icons.draw_outlined,
                        'Custom Orders',
                      ),
                      const SizedBox(height: 4),
                      _navItem(
                        NavItem.reports,
                        Icons.summarize_outlined,
                        'Reports',
                      ),
                      if (state.currentUser?.role == 'Administrator') ...[
                        const SizedBox(height: 8),
                        _navSection('ADMINISTRATION'),
                        _navItem(
                          NavItem.registrationRequests,
                          Icons.admin_panel_settings_outlined,
                          'Registration Requests',
                        ),
                      ],
                      if (state.isAdministrator) ...[
                        const SizedBox(height: 4),
                        _navSection('TOOLS'),
                        ListTile(
                          leading: const Icon(
                            Icons.delete_outline,
                            color: AppColors.whiteTertiary,
                          ),
                          title: const Text(
                            'Recycle Bin',
                            style: AppTextStyles.navItem,
                          ),
                          onTap: () {
                            if (_sidebarOpen) {
                              _drawerCtrl.reverse();
                              setState(() => _sidebarOpen = false);
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RecycleBinScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.sync_problem_outlined),
                          title: const Text('Sync Issues'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const SyncIssuesScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              // ── Fixed footer ──────────────────────────────────────────────
              const Divider(color: AppColors.divider),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.gold.withValues(alpha: 0.3),
                      child: Text(
                        state.currentUser?.avatarLetter ?? 'A',
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            state.currentUser?.displayName ?? 'Admin',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            state.currentUser?.role ?? 'Administrator',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.whiteTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Semantics(
                  button: true,
                  label: AppStrings.signOut,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _confirmSignOut,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          AppStrings.signOut,
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }, // end ListenableBuilder builder
    );
  }

  Widget _navSection(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.whiteTertiary,
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Renders a single navigation row with icon, label, active highlight,
  // and an optional numeric badge (e.g., pending order count).
  Widget _navItem(NavItem item, IconData icon, String label, {int? badge}) {
    final isActive = _selected == item;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selected = item;
          if (_sidebarOpen) {
            _drawerCtrl.reverse();
            _sidebarOpen = false;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.gold.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? AppColors.gold : AppColors.whiteTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: isActive
                    ? AppTextStyles.navItemActive
                    : AppTextStyles.navItem,
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge.toString(),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
