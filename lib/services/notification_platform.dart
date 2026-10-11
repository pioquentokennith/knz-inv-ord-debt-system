import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum AlertPermission { unknown, granted, denied, restricted, unavailable }

abstract interface class AlertStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class PreferenceAlertStore implements AlertStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Notification history could not be saved.');
    }
  }

  @override
  Future<void> remove(String key) async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Notification session could not be cleared.');
    }
  }
}

abstract interface class AlertPlatform {
  Future<String?> initialize(void Function(String?) onTap);
  Future<AlertPermission> permission();
  Future<AlertPermission> requestPermission();
  Future<tz.Location> timeZone();
  Future<Set<int>> pendingIds();
  Future<void> show(
    int id,
    String title,
    String body,
    String payload, {
    required bool stock,
    bool silent = false,
  });
  Future<void> schedule(int id, tz.TZDateTime when, String payload);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<void> openSettings();
}

class LocalAlertPlatform implements AlertPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _native = MethodChannel('com.knzscent.admin/notifications');
  bool get _supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<String?> initialize(void Function(String?) onTap) async {
    tz_data.initializeTimeZones();
    if (!_supported) return null;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    if (Platform.isAndroid) {
      final existing = await _android!.getNotificationChannels() ?? [];
      for (final channel in const [
        AndroidNotificationChannel(
          'knz_low_stock',
          'Low Stock Alerts',
          description: 'Important stock-level alerts.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
        AndroidNotificationChannel(
          'knz_overdue_debt',
          'Utang Due-Date Alerts',
          description: 'Due and overdue Utang reminders.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      ]) {
        // Never delete/recreate or override a user's existing channel choices.
        if (!existing.any((value) => value.id == channel.id)) {
          await _android!.createNotificationChannel(channel);
        }
      }
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp == true
        ? launch?.notificationResponse?.payload
        : null;
  }

  @override
  Future<AlertPermission> permission() async {
    if (!_supported) return AlertPermission.unavailable;
    if (Platform.isAndroid) {
      final enabled = await _android!.areNotificationsEnabled();
      if (enabled == null) return AlertPermission.unavailable;
      if (enabled) return AlertPermission.granted;
    }
    final status = await Permission.notification.status;
    if (status.isGranted || status.isProvisional) {
      return AlertPermission.granted;
    }
    if (status.isRestricted || status.isPermanentlyDenied) {
      return AlertPermission.restricted;
    }
    return AlertPermission.denied;
  }

  @override
  Future<AlertPermission> requestPermission() async {
    if (!_supported) return AlertPermission.unavailable;
    if (Platform.isAndroid) {
      await _android!.requestNotificationsPermission();
    } else {
      await Permission.notification.request();
    }
    return permission();
  }

  @override
  Future<tz.Location> timeZone() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Device timezone scheduling is currently supported on Android.',
      );
    }
    final name = await _native.invokeMethod<String>('timeZone');
    if (name == null) throw StateError('Device timezone unavailable.');
    return tz.getLocation(name);
  }

  static NotificationDetails details({
    required bool stock,
    bool silent = false,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      stock ? 'knz_low_stock' : 'knz_overdue_debt',
      stock ? 'Low Stock Alerts' : 'Utang Due-Date Alerts',
      importance: Importance.high,
      priority: Priority.high,
      playSound: !silent,
      enableVibration: !silent,
      silent: silent,
      onlyAlertOnce: silent,
      visibility: NotificationVisibility.private,
      icon: '@mipmap/launcher_icon',
      color: const Color(0xFFD4AF37),
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !silent,
    ),
    macOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !silent,
    ),
  );

  @override
  Future<void> show(
    int id,
    String title,
    String body,
    String payload, {
    required bool stock,
    bool silent = false,
  }) => _plugin.show(
    id,
    title,
    body,
    details(stock: stock, silent: silent),
    payload: payload,
  );
  @override
  Future<void> schedule(int id, tz.TZDateTime when, String payload) =>
      _plugin.zonedSchedule(
        id,
        'Utang payment is due',
        'Open Utang to review unpaid accounts.',
        when,
        details(stock: false),
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
  @override
  Future<Set<int>> pendingIds() async =>
      (await _plugin.pendingNotificationRequests()).map((e) => e.id).toSet();
  @override
  Future<void> cancel(int id) async {
    if (_supported) await _plugin.cancel(id);
  }

  @override
  Future<void> cancelAll() async {
    if (_supported) await _plugin.cancelAll();
  }

  @override
  Future<void> openSettings() async {
    if (Platform.isAndroid) {
      await _native.invokeMethod<bool>('openSettings');
    } else if (_supported && !await openAppSettings()) {
      throw StateError('Notification settings could not be opened.');
    }
  }
}
