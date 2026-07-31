// ─────────────────────────────────────────────────────────────────────────────
// notification_service.dart — Local Push Notification Manager
// Purpose : Initialises flutter_local_notifications, fires an immediate
//           low-stock alert and an overdue-debt alert on login.
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
  static const int _overdueDebtId = 1002;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

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

  Future<void> cancelAll() => _plugin.cancelAll();

  // ── Low-stock alert (existing) ────────────────────────────────────────────
  Future<void> showLowStockAlert(List<Product> lowItems, String _) async {
    if (!_ready || lowItems.isEmpty) return;

    const title = 'Inventory needs attention';
    const body = 'Open KNZ Scent to review inventory.';

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

  // ── Overdue debt alert (NEW) ──────────────────────────────────────────────
  /// Fires once on login when [overdueDebts] is non-empty.
  /// The notification deliberately contains only a count. Customer identity,
  /// balances, and overdue periods remain behind the app's authentication UI.
  Future<void> showOverdueDebtAlert(
    List<CustomerDebt> overdueDebts,
    String _,
  ) async {
    if (!_ready || overdueDebts.isEmpty) return;

    const title = 'Account review needed';
    const body = 'Open KNZ Scent to review accounts.';
    await _plugin.show(
      _overdueDebtId,
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
      'Overdue Debt Alerts',
      channelDescription: 'Notifies when customer debts become overdue.',
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
