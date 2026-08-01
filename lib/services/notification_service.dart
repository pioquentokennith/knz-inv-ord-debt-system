// ─────────────────────────────────────────────────────────────────────────────
// notification_service.dart — Local Push Notification Manager
// Purpose : Initialises flutter_local_notifications and keeps low-stock and
//           due-Utang alerts synchronized while an authenticated session runs.
//           Notification text intentionally avoids customer, account, balance,
//           and inventory details that could be exposed on a lock screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/debt_model.dart';
import '../models/product_model.dart';

class NotificationService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static const int _lowStockId = 1001;
  static const int _dueDebtId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  Set<String>? _lowStockIds;
  Set<String>? _dueDebtIds;

  // ── Initialisation ────────────────────────────────────────────────────────
  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');

    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onTap,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _ready = true;
    if (kDebugMode) debugPrint('[NotificationService] initialised ✓');
  }

  void _onTap(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('[NotificationService] tapped: ${response.payload}');
    }
  }

  Future<void> cancelAll() async {
    _lowStockIds = null;
    _dueDebtIds = null;
    await _plugin.cancelAll();
  }

  Future<void> syncBusinessAlerts(
    List<Product> products,
    List<CustomerDebt> debts,
  ) async {
    if (!_ready) return;

    final lowItems = products.where((product) => product.isLowStock).toList();
    final lowIds = lowItems.map((product) => product.id).toSet();
    if (_lowStockIds == null || !_sameIds(lowIds, _lowStockIds!)) {
      if (lowItems.isEmpty) {
        await _plugin.cancel(_lowStockId);
      } else {
        await showLowStockAlert(lowItems);
      }
      _lowStockIds = Set.unmodifiable(lowIds);
    }

    final dueDebts = debts.where((debt) => debt.isDue).toList();
    final dueIds = dueDebts.map((debt) => debt.id).toSet();
    if (_dueDebtIds == null || !_sameIds(dueIds, _dueDebtIds!)) {
      if (dueDebts.isEmpty) {
        await _plugin.cancel(_dueDebtId);
      } else {
        await showDueDebtAlert(dueDebts);
      }
      _dueDebtIds = Set.unmodifiable(dueIds);
    }
  }

  // ── Low-stock alert (existing) ────────────────────────────────────────────
  Future<void> showLowStockAlert(List<Product> lowItems) async {
    if (!_ready || lowItems.isEmpty) return;

    const title = 'Inventory needs attention';
    final body = '${lowItems.length} product(s) reached the low-stock level.';

    await _plugin.show(
      _lowStockId,
      title,
      body,
      _buildStockDetails(),
      payload: 'inventory',
    );

    if (kDebugMode) {
      debugPrint('[NotificationService] low-stock alert requested');
    }
  }

  // ── Due debt alert ────────────────────────────────────────────────────────
  /// Alerts without exposing customer identity or financial values.
  /// The notification deliberately contains only a count. Customer identity,
  /// balances, and overdue periods remain behind the app's authentication UI.
  Future<void> showDueDebtAlert(List<CustomerDebt> dueDebts) async {
    if (!_ready || dueDebts.isEmpty) return;

    const title = 'Utang payment is due';
    final body = '${dueDebts.length} account(s) need review.';
    await _plugin.show(
      _dueDebtId,
      title,
      body,
      _buildDebtDetails(),
      payload: 'utang',
    );

    if (kDebugMode) {
      debugPrint('[NotificationService] account review alert requested');
    }
  }

  // ── Channel details ────────────────────────────────────────────────────────
  NotificationDetails _buildStockDetails() {
    const android = AndroidNotificationDetails(
      'knz_low_stock',
      'Low Stock Alerts',
      channelDescription:
          'Notifies you when fragrance products are running low on stock.',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      icon: '@mipmap/launcher_icon',
      color: Color(0xFFD4AF37),
      playSound: true,
    );
    const darwin = DarwinNotificationDetails(
      categoryIdentifier: 'knz_low_stock',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin);
  }

  NotificationDetails _buildDebtDetails() {
    const android = AndroidNotificationDetails(
      'knz_overdue_debt',
      'Utang Due-Date Alerts',
      channelDescription: 'Notifies when an Utang due date is reached.',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      icon: '@mipmap/launcher_icon',
      color: Color(0xFFD4AF37),
      playSound: true,
    );
    const darwin = DarwinNotificationDetails(
      categoryIdentifier: 'knz_overdue_debt',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin);
  }
}

bool _sameIds(Set<String> first, Set<String> second) =>
    first.length == second.length && first.containsAll(second);
