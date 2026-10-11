import 'dart:async';
import 'package:knz_scent_admin/services/notification_platform.dart';
import 'package:timezone/timezone.dart' as tz;

class MemoryAlertStore implements AlertStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class PostedAlert {
  PostedAlert(
    this.id,
    this.title,
    this.body,
    this.payload,
    this.stock,
    this.silent,
  );
  final int id;
  final String title;
  final String body;
  final String payload;
  final bool stock;
  final bool silent;
}

class PlannedAlert {
  PlannedAlert(this.id, this.when, this.payload);
  final int id;
  final tz.TZDateTime when;
  final String payload;
}

class FakeAlertPlatform implements AlertPlatform {
  AlertPermission status = AlertPermission.granted;
  AlertPermission requestResult = AlertPermission.granted;
  String zone = 'Asia/Manila';
  String? launchPayload;
  void Function(String?)? tap;
  Completer<void>? initializing;
  Completer<void>? requesting;
  Completer<void>? showing;
  Completer<void>? scheduling;
  bool failShow = false;
  bool failSchedule = false;
  int? failScheduleAt;
  int initCalls = 0;
  int permissionRequests = 0;
  int settingsCalls = 0;
  int cancelAllCalls = 0;
  int scheduleCalls = 0;
  final shows = <PostedAlert>[];
  final visible = <int, PostedAlert>{};
  final planned = <int, PlannedAlert>{};
  final cancelled = <int>[];

  @override
  Future<String?> initialize(void Function(String?) onTap) async {
    initCalls++;
    tap = onTap;
    await initializing?.future;
    return launchPayload;
  }

  @override
  Future<AlertPermission> permission() async => status;
  @override
  Future<AlertPermission> requestPermission() async {
    permissionRequests++;
    await requesting?.future;
    return status = requestResult;
  }

  @override
  Future<tz.Location> timeZone() async => tz.getLocation(zone);
  @override
  Future<Set<int>> pendingIds() async => planned.keys.toSet();
  @override
  Future<void> show(
    int id,
    String title,
    String body,
    String payload, {
    required bool stock,
    bool silent = false,
  }) async {
    await showing?.future;
    if (failShow) throw StateError('show failed');
    final alert = PostedAlert(id, title, body, payload, stock, silent);
    shows.add(alert);
    visible[id] = alert;
  }

  @override
  Future<void> schedule(int id, tz.TZDateTime when, String payload) async {
    await scheduling?.future;
    if (failSchedule || failScheduleAt == scheduleCalls) {
      throw StateError('schedule failed');
    }
    scheduleCalls++;
    planned[id] = PlannedAlert(id, when, payload);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    planned.remove(id);
    visible.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    planned.clear();
    visible.clear();
  }

  @override
  Future<void> openSettings() async {
    settingsCalls++;
  }
}
