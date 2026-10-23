import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../models/debt_model.dart';
import '../models/product_model.dart';
import 'notification_platform.dart';
export 'notification_platform.dart' show AlertPermission;

class NotificationSnapshot {
  NotificationSnapshot(
    this.userId,
    List<Product> products,
    List<CustomerDebt> debts,
  ) : products = List.unmodifiable(products),
      debts = List.unmodifiable(debts);
  final String userId;
  final List<Product> products;
  final List<CustomerDebt> debts;
}

enum NotificationDestination { inventory, utang }

typedef AlertNavigation =
    void Function(String userId, NotificationDestination destination);

/// Local-only notification coordinator. Plugin effects and persistent history
/// are serialized; account/session checks surround each asynchronous effect.
class NotificationService extends ChangeNotifier {
  NotificationService({
    required AlertPlatform platform,
    required AlertStore store,
    DateTime Function()? now,
  }) : _platform = platform,
       _store = store,
       _now = now ?? DateTime.now;
  static final instance = NotificationService(
    platform: LocalAlertPlatform(),
    store: PreferenceAlertStore(),
  );

  final AlertPlatform _platform;
  final AlertStore _store;
  final DateTime Function() _now;
  NotificationSnapshot? Function() _snapshot = () => null;
  String? Function() _activeUser = () => null;
  Future<void>? _initializing;
  Future<void> _tail = Future.value();
  bool initialized = false;
  AlertPermission permission = AlertPermission.unknown;
  String? lastError;
  int _generation = 0;
  String? _boundUser;
  String? _scope;
  String? _pendingTap;
  AlertNavigation? _navigate;
  bool _backgrounded = false;
  int _open = 0;
  int _evaluatedOpen = -1;
  int _debtAlertOpen = -1;
  final _stockAlertOpens = <int, int>{};
  // Treat a launch within one minute of 9 AM and that day's scheduled alert
  // as one reminder. Earlier launches still keep the upcoming 9 AM alarm.
  static const _scheduleOverlap = Duration(minutes: 1);
  static const _bindingKey = 'notifications.session.v1';
  static const _promptKey = 'notifications.permission_prompted.v1';

  void configure({
    required NotificationSnapshot? Function() snapshot,
    required String? Function() activeUser,
  }) {
    _snapshot = snapshot;
    _activeUser = activeUser;
  }

  Future<void> get idle => _tail;
  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.catchError((Object error, StackTrace stack) {
      lastError = 'Notification update failed. Please retry.';
      if (kDebugMode) debugPrint('[Notifications] ${error.runtimeType}');
      notifyListeners();
    });
    return result;
  }

  Future<void> init() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final payload = await _platform.initialize(handleTap);
      _pendingTap ??= payload;
      permission = await _platform.permission();
      initialized = true;
      notifyListeners();
      // Evaluation can post many alerts; permission dialogs and evaluation do
      // not hold the application's optional startup initialization open.
      unawaited(refresh());
    } catch (error) {
      permission = AlertPermission.unavailable;
      lastError = 'Notifications could not be initialized.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> requestPermissionOnce() async {
    try {
      await init();
      await _serial(() async {
        permission = await _platform.permission();
        if (permission == AlertPermission.denied &&
            await _store.read(_promptKey) == null) {
          await _store.write(_promptKey, 'asked');
          permission = await _platform.requestPermission();
        }
        notifyListeners();
        await _evaluate();
      });
    } catch (_) {
      // init/_serial publish a visible failure state; app access is unaffected.
    }
  }

  Future<void> openSettings() async {
    try {
      await _platform.openSettings();
    } catch (_) {
      lastError = 'Notification settings could not be opened.';
      notifyListeners();
    }
  }

  Future<void> syncBusinessAlerts(
    List<Product> products,
    List<CustomerDebt> debts,
  ) => refresh();

  /// Only a real background/foreground transition starts another alert pass.
  /// Initial resumed callbacks and temporary inactive states (e.g. permission
  /// dialogs) share the cold-start pass, even while data/plugin loading overlaps.
  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgrounded = true;
    } else if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      _open++;
      try {
        await refresh();
      } catch (_) {
        // _serial publishes failures; a later refresh can retry this open.
      }
    }
  }

  void _resetOpenAlerts() {
    _evaluatedOpen = -1;
    _debtAlertOpen = -1;
    _stockAlertOpens.clear();
  }

  Future<void> refresh() {
    if (!initialized) {
      return Future.value(); // init() re-evaluates the current snapshot.
    }
    return _serial(() async {
      permission = await _platform.permission();
      lastError = null;
      notifyListeners();
      await _evaluate();
    });
  }

  /// Called synchronously when trusted access is cleared, before remote logout.
  void invalidateSession() {
    _generation++;
    _pendingTap = null;
    if (initialized) unawaited(cancelAll());
  }

  Future<void> cancelAll() {
    _generation++;
    _pendingTap = null;
    if (!initialized) return Future.value();
    return _serial(() async {
      await _platform.cancelAll();
      if (permission != AlertPermission.unavailable) {
        await _store.remove(_bindingKey);
      }
      _boundUser = null;
      _scope = null;
      _resetOpenAlerts();
    });
  }

  VoidCallback attachNavigation(AlertNavigation navigate) {
    _navigate = navigate;
    _deliverTap();
    return () {
      if (identical(_navigate, navigate)) _navigate = null;
    };
  }

  void handleTap(String? payload) {
    if (payload == null) return;
    _pendingTap = payload;
    _deliverTap();
  }

  void _deliverTap() {
    final payload = _pendingTap;
    if (payload == null ||
        _scope == null ||
        _navigate == null ||
        _snapshot() == null) {
      return;
    }
    _pendingTap = null;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (data['v'] != 1 ||
          data['scope'] != _scope ||
          _activeUser() != _boundUser) {
        return;
      }
      final destination = switch (data['target']) {
        'inventory' => NotificationDestination.inventory,
        'utang' => NotificationDestination.utang,
        _ => null,
      };
      if (destination != null) _navigate!(_boundUser!, destination);
    } catch (_) {
      // Reject legacy/invalid payloads rather than guessing their account.
    }
  }

  String _payload(String target) =>
      jsonEncode({'v': 1, 'scope': _scope, 'target': target});
  String _ownerKey(String uid) => sha256.convert(utf8.encode(uid)).toString();
  String _historyKey(String uid) =>
      'notifications.history.v1.${_ownerKey(uid)}';
  int _id(String uid, String kind, String entity) {
    final bytes = sha256
        .convert(utf8.encode('$uid\u0000$kind\u0000$entity'))
        .bytes;
    return (bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]) &
        0x7fffffff;
  }

  bool _current(String uid, int generation) =>
      _activeUser() == uid && generation == _generation;
  Future<void> _save(String uid, Map<String, dynamic> history) =>
      _store.write(_historyKey(uid), jsonEncode(history));

  Future<void> _evaluate() async {
    if (!initialized || permission == AlertPermission.unavailable) return;
    final snapshot = _snapshot();
    if (snapshot == null) {
      if (_activeUser() == null) {
        await _platform.cancelAll();
        await _store.remove(_bindingKey);
        _boundUser = null;
        _scope = null;
        _pendingTap = null;
        _resetOpenAlerts();
      }
      return;
    }
    final uid = snapshot.userId;
    final generation = _generation;
    final open = _open;
    if (!_current(uid, generation)) return;
    if (_boundUser != uid) {
      final saved = await _store.read(_bindingKey);
      if (!_current(uid, generation)) return;
      final binding = saved == null
          ? null
          : jsonDecode(saved) as Map<String, dynamic>;
      if (binding?['owner'] != _ownerKey(uid)) {
        await _platform.cancelAll();
        if (!_current(uid, generation)) return;
        _scope = const Uuid().v4();
        await _store.write(
          _bindingKey,
          jsonEncode({'owner': _ownerKey(uid), 'scope': _scope}),
        );
      } else {
        _scope = binding!['scope'] as String;
      }
      if (!_current(uid, generation)) return;
      _boundUser = uid;
      _resetOpenAlerts();
      await _platform.cancel(
        1001,
      ); // Retire old aggregate IDs, not their channels.
      await _platform.cancel(1002);
    }
    _deliverTap();
    final opening = _evaluatedOpen != open;
    final encoded = await _store.read(_historyKey(uid));
    if (!_current(uid, generation)) return;
    final history = encoded == null
        ? <String, dynamic>{}
        : jsonDecode(encoded) as Map<String, dynamic>;
    final stocks = Map<String, dynamic>.from(history['stocks'] as Map? ?? {});
    history['stocks'] = stocks;
    final products = {for (final p in snapshot.products) p.id: p};
    for (final id in {...stocks.keys, ...products.keys}) {
      if (!_current(uid, generation)) return;
      final product = products[id];
      final level = product == null || !product.isLowStock
          ? 0
          : product.stockQty == 0
          ? 2
          : 1;
      final previous = stocks[id] as Map?;
      final notificationId = _id(uid, 'stock', id);
      if (level == 0) {
        if (previous != null) {
          await _platform.cancel(notificationId);
          stocks.remove(id);
        }
        continue;
      }
      final oldLevel = previous?['level'] as int? ?? 0;
      final pending = level < oldLevel
          ? false
          : level > oldLevel || previous?['pending'] == true;
      stocks[id] = {'level': level, 'pending': pending};
      final repeatOnOpen = opening && _stockAlertOpens[notificationId] != open;
      if ((pending || repeatOnOpen) && permission == AlertPermission.granted) {
        await _save(uid, history);
        if (!_current(uid, generation)) return;
        await _platform.show(
          notificationId,
          level == 2
              ? 'A product is out of stock'
              : 'Inventory needs attention',
          'Open Inventory to review stock levels.',
          _payload('inventory'),
          stock: true,
        );
        if (!_current(uid, generation)) {
          await _platform.cancel(notificationId);
          return;
        }
        stocks[id] = {'level': level, 'pending': false};
        _stockAlertOpens[notificationId] = open;
        await _save(uid, history);
      } else if (level < oldLevel && permission == AlertPermission.granted) {
        await _platform.cancel(
          notificationId,
        ); // Partial restock: remove the stale out-of-stock alert.
      }
    }
    if (!_current(uid, generation)) return;
    await _save(uid, history);
    if (permission != AlertPermission.granted) {
      // Also clears an alarm created just before a failed history write.
      await _platform.cancelAll();
      history['scheduled'] = <String, dynamic>{};
      await _save(uid, history);
      return;
    }
    await _scheduleDebts(snapshot, history, generation, open, opening);
    if (_current(uid, generation)) _evaluatedOpen = open;
  }

  String _day(tz.TZDateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  bool _dueOn(CustomerDebt debt, tz.TZDateTime day) =>
      !debt.isPaid &&
      debt.dueDate != null &&
      !DateTime.utc(day.year, day.month, day.day).isBefore(debt.dueDate!);

  Future<void> _scheduleDebts(
    NotificationSnapshot snapshot,
    Map<String, dynamic> history,
    int generation,
    int open,
    bool opening,
  ) async {
    final uid = snapshot.userId;
    final location = await _platform.timeZone();
    final now = tz.TZDateTime.from(_now(), location);
    final today = _day(now);
    if (history['lastVisibleDueDay'] case final String previousDay) {
      if (previousDay != today) {
        await _platform.cancel(_id(uid, 'due', previousDay));
      }
    }
    if (history['lastDueDay'] case final String previousDay) {
      if (previousDay != today) {
        await _platform.cancel(_id(uid, 'due', previousDay));
      }
    }
    final pending = await _platform.pendingIds();
    if (!_current(uid, generation)) return;
    final old = Map<String, dynamic>.from(history['scheduled'] as Map? ?? {});
    final updated = <String, dynamic>{};
    final dueNow = snapshot.debts.any((debt) => _dueOn(debt, now));
    final todayId = _id(uid, 'due', today);
    final previousToday = old[today] as Map?;
    final todayNine = tz.TZDateTime(location, now.year, now.month, now.day, 9);
    final nearNine = now.difference(todayNine).abs() <= _scheduleOverlap;
    var justDelivered = false;
    if (previousToday != null &&
        previousToday['zone'] != location.name &&
        !now.isBefore(todayNine) &&
        pending.contains(todayId)) {
      await _platform.cancel(todayId);
      pending.remove(todayId);
    }
    // An OS-delivered scheduled reminder cannot write Dart history. Its past
    // schedule plus disappearance from pending requests records that day's alert.
    if (previousToday != null &&
        previousToday['zone'] == location.name &&
        !now.isBefore(DateTime.parse(previousToday['at'] as String)) &&
        !pending.contains(todayId)) {
      justDelivered = history['lastDueDay'] != today && nearNine;
      history['lastDueDay'] = today;
    }
    final repeatOnOpen = opening && _debtAlertOpen != open;
    if (repeatOnOpen && justDelivered) _debtAlertOpen = open;
    if (!dueNow) {
      await _platform.cancel(todayId);
    } else if ((repeatOnOpen && !justDelivered) ||
        (!now.isBefore(todayNine) &&
            history['lastDueDay'] != today &&
            !pending.contains(todayId))) {
      if (!_current(uid, generation)) return;
      // Replace today's due/delayed alarm before posting, so it cannot also
      // fire after this opening's immediate reminder. Preserve earlier alarms.
      final consumesSchedule = !now.isBefore(todayNine) || nearNine;
      if (consumesSchedule) {
        await _platform.cancel(todayId);
        pending.remove(todayId);
        if (!_current(uid, generation)) return;
      }
      await _platform.show(
        todayId,
        'Utang payment is due',
        'Open Utang to review unpaid accounts.',
        _payload('utang'),
        stock: false,
      );
      if (!_current(uid, generation)) {
        await _platform.cancel(todayId);
        return;
      }
      _debtAlertOpen = open;
      // Track visible pre-9 alerts too, so a later day can retire them without
      // marking today's scheduled reminder as already delivered.
      history['lastVisibleDueDay'] = today;
      if (consumesSchedule) history['lastDueDay'] = today;
      await _save(uid, history);
    }
    for (var offset = 0; offset < 14; offset++) {
      if (!_current(uid, generation)) return;
      final when = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day + offset,
        9,
      );
      final day = _day(when);
      final id = _id(uid, 'due', day);
      if (!snapshot.debts.any((debt) => _dueOn(debt, when))) {
        // A prior partial schedule may exist even if its history write failed.
        if (pending.contains(id)) await _platform.cancel(id);
        continue;
      }
      if (!when.isAfter(now)) {
        // Keep a due inexact alarm queued, rather than also posting immediately.
        if (pending.contains(id) && old[day] != null) updated[day] = old[day];
        continue;
      }
      if (day == today && history['lastDueDay'] == today) continue;
      final record = {
        'id': id,
        'at': when.toUtc().toIso8601String(),
        'zone': location.name,
        'scope': _scope,
      };
      if (!pending.contains(id) || jsonEncode(old[day]) != jsonEncode(record)) {
        await _platform.schedule(id, when, _payload('utang'));
        if (!_current(uid, generation)) {
          await _platform.cancel(id);
          return;
        }
      }
      updated[day] = record;
    }
    for (final entry in old.entries) {
      if (!updated.containsKey(entry.key) && entry.key != today) {
        await _platform.cancel((entry.value as Map)['id'] as int);
      }
    }
    if (!_current(uid, generation)) return;
    history['scheduled'] = updated;
    await _save(uid, history);
  }
}
