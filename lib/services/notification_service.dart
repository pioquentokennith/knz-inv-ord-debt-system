// ─────────────────────────────────────────────────────────────────────────────
// notification_service.dart — Local Push Notification Manager
// Purpose : Initialises flutter_local_notifications, fires an immediate
//           low-stock alert and an overdue-debt alert on login.
//           Overdue alert shows each customer's name, remaining balance,
//           days overdue, and the logged-in account name in the title.
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

  static const int _lowStockId    = 1001;
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
      iOS:     darwinInit,
      macOS:   darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onTap,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
    if (kDebugMode) debugPrint('[NotificationService] initialised ✓');
  }

  void _onTap(NotificationResponse response) {
    if (kDebugMode) {
      debugPrint('[NotificationService] tapped: ${response.payload}');
    }
  }

  // ── Low-stock alert (existing) ────────────────────────────────────────────
  Future<void> showLowStockAlert(
    List<Product> lowItems,
    String activeUser,
  ) async {
    if (!_ready || lowItems.isEmpty) return;

    final displayUser = activeUser.isNotEmpty
        ? activeUser[0].toUpperCase() + activeUser.substring(1).toLowerCase()
        : 'Admin';

    final count = lowItems.length;
    final title = count == 1
        ? '[$displayUser] ⚠️ 1 Product is Running Low!'
        : '[$displayUser] ⚠️ $count Products are Running Low!';

    final names = lowItems.take(3).map((p) => p.name).join(', ');
    final extra = count > 3 ? ' …and ${count - 3} more' : '';
    final body  = 'Restock needed: $names$extra';

    await _plugin.show(_lowStockId, title, body, _buildStockDetails(),
        payload: 'inventory');

    if (kDebugMode) {
      debugPrint('[NotificationService] low-stock alert — $count item(s)');
    }
  }

  // ── Overdue debt alert (NEW) ──────────────────────────────────────────────
  /// Fires once on login when [overdueDebts] is non-empty.
  /// [activeUser] is shown in the title so the owner knows which account
  /// triggered the alert — e.g. "[Knzadmin] 🔴 5 Overdue Utang!"
  ///
  /// • 1 overdue  → single body line with name + balance + days
  /// • 2+ overdue → inbox-style expanded list, one line per customer
  Future<void> showOverdueDebtAlert(
    List<CustomerDebt> overdueDebts,
    String activeUser,
  ) async {
    if (!_ready || overdueDebts.isEmpty) return;

    final displayUser = activeUser.isNotEmpty
        ? activeUser[0].toUpperCase() + activeUser.substring(1).toLowerCase()
        : 'Admin';

    final count = overdueDebts.length;
    final title = '[$displayUser] 🔴 $count Overdue Utang!';

    if (count == 1) {
      final debt = overdueDebts.first;
      final body =
          '${debt.customerName} — ${_peso(debt.remainingBalance)} remaining '
          '(${debt.daysOld}d overdue)';

      await _plugin.show(_overdueDebtId, title, body, _buildDebtDetails(),
          payload: 'utang');
    } else {
      // Inbox-style: one line per customer
      final inboxLines = overdueDebts
          .map((d) =>
              '${d.customerName}  •  ${_peso(d.remainingBalance)}  •  ${d.daysOld}d overdue')
          .toList();

      final total = overdueDebts.fold<double>(
          0.0, (s, d) => s + d.remainingBalance);

      final androidDetails = AndroidNotificationDetails(
        'knz_overdue_debt',
        'Overdue Debt Alerts',
        channelDescription: 'Notifies when customer debts become overdue.',
        importance:       Importance.high,
        priority:         Priority.high,
        icon:             '@mipmap/launcher_icon',
        color:            const Color(0xFFD4AF37),
        playSound:        true,
        styleInformation: InboxStyleInformation(
          inboxLines,
          contentTitle: title,
          summaryText:  '$count customers overdue',
        ),
      );

      await _plugin.show(
        _overdueDebtId,
        title,
        'Total uncollected: ${_peso(total)}',
        NotificationDetails(android: androidDetails),
        payload: 'utang',
      );
    }

    if (kDebugMode) {
      debugPrint(
          '[NotificationService] overdue-debt alert — $count customer(s)');
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
      priority:   Priority.high,
      icon:       '@mipmap/launcher_icon',
      color:      Color(0xFFD4AF37),
      playSound:  true,
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
      priority:   Priority.high,
      icon:       '@mipmap/launcher_icon',
      color:      Color(0xFFD4AF37),
      playSound:  true,
    );
    const darwin = DarwinNotificationDetails(
      categoryIdentifier: 'knz_overdue_debt',
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: darwin);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _peso(double amount) {
    final fixed   = amount.toStringAsFixed(2);
    final parts   = fixed.split('.');
    final chars   = parts[0].split('').reversed.toList();
    final buffer  = StringBuffer();
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(',');
      buffer.write(chars[i]);
    }
    return '₱${buffer.toString().split('').reversed.join()}.${parts[1]}';
  }
}