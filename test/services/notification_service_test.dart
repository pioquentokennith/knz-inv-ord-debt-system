import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/services/notification_platform.dart';
import 'package:knz_scent_admin/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import '../support/notification_fakes.dart';

Product product(int stock, {String id = 'p'}) => Product(
  id: id,
  name: 'Private fragrance name',
  description: '',
  category: ProductCategory.eauDeParfum,
  price: const Money.fromCentavos(10000),
  stockQty: stock,
  minStockLevel: 5,
);
CustomerDebt debt({String id = 'd', DateTime? due, bool paid = false}) =>
    CustomerDebt(
      id: id,
      customerName: 'Private customer name',
      orderId: 'order',
      principalOriginal: const Money.fromCentavos(10000),
      principalOutstanding: paid ? Money.zero : const Money.fromCentavos(10000),
      createdAt: DateTime.utc(2026, 1, 1),
      dueDate: due ?? DateTime.utc(2026, 1, 3),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  late FakeAlertPlatform platform;
  late MemoryAlertStore store;
  late NotificationService service;
  late DateTime now;
  String? owner;
  late bool dataReady;
  late List<Product> products;
  late List<CustomerDebt> debts;
  NotificationService create() {
    final result = NotificationService(
      platform: platform,
      store: store,
      now: () => now,
    );
    result.configure(
      activeUser: () => owner,
      snapshot: () => owner != null && dataReady
          ? NotificationSnapshot(owner!, products, debts)
          : null,
    );
    return result;
  }

  Future<void> start() async {
    await service.init();
    await service.idle;
  }

  setUp(() {
    platform = FakeAlertPlatform();
    store = MemoryAlertStore();
    owner = 'a';
    dataReady = true;
    products = [];
    debts = [];
    now = DateTime.utc(2026, 1, 3, 2); // 10 AM Manila.
    service = create();
  });
  tearDown(() async {
    await service.idle;
    service.dispose();
  });

  test(
    'local data before plugin readiness is evaluated when initialization completes',
    () async {
      products = [product(5)];
      platform.initializing = Completer<void>();
      await service.syncBusinessAlerts(products, debts);
      final first = service.init();
      final second = service.init();
      expect(identical(first, second), isTrue);
      expect(platform.shows, isEmpty);
      expect(service.initialized, isFalse);
      platform.initializing!.complete();
      await first;
      await service.idle;
      expect(service.initialized, isTrue);
      expect(platform.initCalls, 1);
      expect(platform.shows, hasLength(1));
    },
  );
  test(
    'service ready before local data does not clear history or infer empty data',
    () async {
      dataReady = false;
      products = [product(5)];
      await start();
      expect(platform.shows, isEmpty);
      dataReady = true;
      await service.refresh();
      expect(platform.shows, hasLength(1));
    },
  );
  test(
    'denied permission differs from initialization and foreground grant reevaluates',
    () async {
      platform.status = AlertPermission.denied;
      products = [product(4)];
      await start();
      expect(service.initialized, isTrue);
      expect(service.permission, AlertPermission.denied);
      expect(platform.shows, isEmpty);
      expect(platform.permissionRequests, 0);
      platform.status = AlertPermission.granted;
      await service.refresh();
      expect(platform.shows, hasLength(1));
    },
  );
  test(
    'permission prompt is separate from startup and persists across restarts',
    () async {
      platform.status = AlertPermission.denied;
      platform.requestResult = AlertPermission.denied;
      platform.requesting = Completer<void>();
      await start(); // A pending permission dialog does not hold initialization.
      final request = service.requestPermissionOnce();
      await Future<void>.delayed(Duration.zero);
      expect(service.initialized, isTrue);
      expect(platform.permissionRequests, 1);
      platform.requesting!.complete();
      await request;
      await service.requestPermissionOnce();
      expect(platform.permissionRequests, 1);
      service.dispose();
      service = create();
      await start();
      await service.requestPermissionOnce();
      expect(platform.permissionRequests, 1);
      await service.openSettings();
      expect(platform.settingsCalls, 1);
    },
  );
  for (final permission in [
    AlertPermission.unavailable,
    AlertPermission.restricted,
  ]) {
    test(
      '$permission keeps local access independent and does not repeatedly prompt',
      () async {
        platform.status = permission;
        products = [product(0)];
        await start();
        await service.requestPermissionOnce();
        await service.refresh();
        expect(service.initialized, isTrue);
        expect(service.permission, permission);
        expect(platform.permissionRequests, 0);
        expect(platform.shows, isEmpty);
      },
    );
  }
  test(
    'normal low out unchanged and restock transitions alert only when meaningful',
    () async {
      products = [product(20)];
      await start();
      expect(platform.shows, isEmpty);
      products = [product(5)];
      await service.refresh();
      expect(platform.shows, hasLength(1));
      final id = platform.shows.single.id;
      await service.refresh();
      expect(platform.shows, hasLength(1));
      products = [product(0)];
      await service.refresh();
      expect(platform.shows, hasLength(2));
      expect(platform.shows.last.id, id);
      expect(platform.shows.last.title, contains('out of stock'));
      await service.refresh();
      expect(platform.shows, hasLength(2));
      products = [product(2)];
      await service.refresh(); // Partial improvement, no sound.
      expect(platform.shows, hasLength(2));
      expect(platform.visible, isEmpty);
      products = [product(0)];
      await service.refresh();
      expect(platform.shows, hasLength(3));
      products = [product(20)];
      await service.refresh();
      expect(platform.visible, isEmpty);
      products = [product(5)];
      await service.refresh();
      expect(platform.shows, hasLength(4));
    },
  );
  test(
    'restart retains low-stock suppression and stable notification IDs',
    () async {
      products = [product(4)];
      await start();
      final id = platform.shows.single.id;
      service.dispose();
      service = create();
      await start();
      expect(platform.shows, hasLength(1));
      products = [product(0)];
      await service.refresh();
      expect(platform.shows.last.id, id);
    },
  );
  test('removed products cancel their active alerts', () async {
    products = [product(4)];
    await start();
    products = [];
    await service.refresh();
    expect(platform.visible, isEmpty);
  });
  test(
    'simultaneous triggers post one stock alert and one grouped Utang alert',
    () async {
      products = [product(4)];
      debts = [debt(), debt(id: 'd2')];
      await start();
      await Future.wait(List.generate(20, (_) => service.refresh()));
      expect(platform.shows.where((e) => e.stock), hasLength(1));
      expect(platform.shows.where((e) => !e.stock), hasLength(1));
      expect(platform.planned, hasLength(13));
      expect(platform.scheduleCalls, 13);
    },
  );
  test(
    'newly due after 9 AM alerts once; unchanged overdue debt does not spam',
    () async {
      debts = [debt()];
      await start();
      expect(platform.shows, hasLength(1));
      expect(platform.shows.single.stock, isFalse);
      await service.refresh();
      await service.refresh();
      expect(platform.shows, hasLength(1));
      service.dispose();
      service = create();
      await start();
      expect(platform.shows, hasLength(1));
    },
  );
  test(
    'before 9 AM uses one grouped OS reminder per day in a 14-day window',
    () async {
      now = DateTime.utc(2026, 1, 2, 23); // Jan 3, 7 AM Manila.
      debts = [debt(), debt(id: 'd2')];
      await start();
      expect(platform.shows, isEmpty);
      expect(platform.planned, hasLength(14));
      expect(
        platform.planned.values.every(
          (e) => e.when.hour == 9 && e.when.location.name == 'Asia/Manila',
        ),
        isTrue,
      );
      expect(
        platform.planned.values.map((e) => e.when.day).toSet(),
        hasLength(14),
      );
      await service.refresh();
      expect(platform.scheduleCalls, 14);
    },
  );
  test(
    'future due dates schedule only eligible days; settled debt removes reminders',
    () async {
      debts = [debt(due: DateTime.utc(2026, 1, 10))];
      await start();
      expect(platform.shows, isEmpty);
      expect(platform.planned, hasLength(7));
      expect(platform.planned.values.every((e) => e.when.day >= 10), isTrue);
      debts = [debt(paid: true)];
      await service.refresh();
      expect(platform.planned, isEmpty);
      expect(platform.visible, isEmpty);
    },
  );
  test(
    'settling one debt leaves a single generic grouped reminder for remaining debt',
    () async {
      debts = [debt(), debt(id: 'd2')];
      await start();
      final calls = platform.scheduleCalls;
      debts = [debt(paid: true), debt(id: 'd2')];
      await service.refresh();
      expect(platform.planned, hasLength(13));
      expect(platform.scheduleCalls, calls);
      debts = [debt(paid: true), debt(id: 'd2', paid: true)];
      await service.refresh();
      expect(platform.planned, isEmpty);
      expect(platform.visible, isEmpty);
    },
  );
  test(
    'OS-fired reminder is not duplicated after reopening; delayed inexact alarm stays single',
    () async {
      now = DateTime.utc(2026, 1, 2, 23);
      debts = [debt()];
      await start();
      final today = platform.planned.values.firstWhere((e) => e.when.day == 3);
      now = DateTime.utc(2026, 1, 3, 2);
      await service.refresh();
      expect(platform.shows, isEmpty); // Still awaiting the OS.
      platform.planned.remove(today.id); // OS consumed it while app was closed.
      service.dispose();
      service = create();
      await start();
      expect(platform.shows, isEmpty);
      expect(platform.planned.containsKey(today.id), isFalse);
    },
  );
  test(
    'date and timezone refresh remain bounded and account for daylight saving',
    () async {
      now = DateTime.utc(
        2026,
        3,
        7,
        11,
      ); // Before 9 AM New York, just before DST.
      platform.zone = 'America/New_York';
      debts = [debt(due: DateTime.utc(2026, 3, 7))];
      await start();
      final sorted = platform.planned.values.toList()
        ..sort((a, b) => a.when.compareTo(b.when));
      expect(
        sorted[1].when.difference(sorted[0].when),
        const Duration(hours: 23),
      );
      expect(sorted.every((entry) => entry.when.hour == 9), isTrue);
      platform.zone = 'Asia/Manila';
      await service.refresh();
      expect(
        platform.planned.values.every(
          (e) => e.when.location.name == 'Asia/Manila',
        ),
        isTrue,
      );
      now = now.add(const Duration(days: 3));
      // Advance the fake OS as well as the wall clock. Retaining a due inexact
      // alarm is intentional and covered separately by the delayed-alarm test.
      platform.planned.removeWhere((_, alert) => !alert.when.isAfter(now));
      await service.refresh();
      expect(platform.planned.length, lessThanOrEqualTo(14));
      expect(platform.planned.values.every((e) => e.when.isAfter(now)), isTrue);
    },
  );
  test(
    'account histories and payloads are isolated; stale taps cannot navigate',
    () async {
      products = [product(4)];
      await start();
      final old = platform.shows.single;
      final navigated = <String>[];
      service.attachNavigation(
        (uid, target) => navigated.add('$uid:${target.name}'),
      );
      service.handleTap(old.payload);
      expect(navigated, ['a:inventory']);
      owner = 'b';
      await service.refresh();
      expect(platform.shows, hasLength(2));
      expect(platform.shows.last.id, isNot(old.id));
      service.handleTap(old.payload);
      expect(navigated, hasLength(1));
      service.handleTap(platform.shows.last.payload);
      expect(navigated.last, 'b:inventory');
      expect(
        jsonDecode(old.payload).keys,
        unorderedEquals(['v', 'scope', 'target']),
      );
      expect(
        '${store.values} ${platform.shows.map((e) => e.body)}',
        isNot(contains('Private')),
      );
    },
  );
  test(
    'in-flight old-account post is cancelled before new-account evaluation',
    () async {
      await start();
      products = [product(4)];
      platform.showing = Completer<void>();
      final old = service.refresh();
      await Future<void>.delayed(Duration.zero);
      owner = 'b';
      final next = service.refresh();
      platform.showing!.complete();
      await Future.wait([old, next]);
      expect(platform.visible, hasLength(1));
      expect(
        platform.visible.values.single.payload,
        platform.shows.last.payload,
      );
      expect(platform.cancelAllCalls, greaterThanOrEqualTo(2));
    },
  );
  test(
    'logout invalidates callbacks immediately and clears scheduled/visible alerts',
    () async {
      products = [product(4)];
      debts = [debt()];
      await start();
      final oldPayload = platform.shows.first.payload;
      var taps = 0;
      service.attachNavigation((_, __) => taps++);
      owner = null;
      service.invalidateSession();
      service.handleTap(oldPayload);
      await service.idle;
      expect(taps, 0);
      expect(platform.visible, isEmpty);
      expect(platform.planned, isEmpty);
      owner = 'a';
      await service.refresh();
      service.handleTap(oldPayload);
      expect(taps, 0);
    },
  );
  test(
    'launch tap waits for initialized trusted data and a mounted navigation handler',
    () async {
      debts = [debt()];
      await start();
      final payload = platform.shows.single.payload;
      service.dispose();
      platform.launchPayload = payload;
      dataReady = false;
      service = create();
      var taps = 0;
      await start();
      service.attachNavigation((uid, target) {
        expect(uid, 'a');
        expect(target, NotificationDestination.utang);
        taps++;
      });
      expect(taps, 0);
      dataReady = true;
      await service.refresh();
      expect(taps, 1);
      await service.refresh();
      expect(taps, 1);
    },
  );
  test('signed-out notification launch cannot bypass authentication', () async {
    products = [product(4)];
    await start();
    final payload = platform.shows.single.payload;
    service.dispose();
    owner = null;
    platform.launchPayload = payload;
    service = create();
    var taps = 0;
    service.attachNavigation((_, __) => taps++);
    await start();
    owner = 'b';
    await service.refresh();
    expect(taps, 0);
  });
  test(
    'platform failure remains visible and does not permanently suppress retry',
    () async {
      platform.failShow = true;
      products = [product(4)];
      await start();
      expect(service.lastError, isNotNull);
      expect(platform.shows, isEmpty);
      platform.failShow = false;
      await service.refresh();
      expect(platform.shows, hasLength(1));
      expect(service.lastError, isNull);
    },
  );
  test(
    'settlement cancels alarms left behind by a partial scheduling failure',
    () async {
      now = DateTime.utc(2026, 1, 2, 23);
      debts = [debt()];
      platform.failScheduleAt = 2;
      await start();
      expect(service.lastError, isNotNull);
      expect(platform.planned, hasLength(2));
      debts = [debt(paid: true)];
      platform.failScheduleAt = null;
      await service.refresh();
      expect(platform.planned, isEmpty);
    },
  );
  test('logout during schedule completion cancels the stale alarm', () async {
    await start();
    debts = [debt()];
    platform.scheduling = Completer<void>();
    final updating = service.refresh();
    await Future<void>.delayed(Duration.zero);
    owner = null;
    service.invalidateSession();
    platform.scheduling!.complete();
    await updating;
    await service.idle;
    expect(platform.planned, isEmpty);
    expect(platform.visible, isEmpty);
  });
  test(
    'channel details explicitly request sound/vibration/high importance, without custom sound',
    () {
      for (final stock in [false, true]) {
        final android = LocalAlertPlatform.details(stock: stock).android!;
        expect(android.importance, Importance.high);
        expect(android.priority, Priority.high);
        expect(android.playSound, isTrue);
        expect(android.enableVibration, isTrue);
        expect(android.sound, isNull);
        expect(android.visibility, NotificationVisibility.private);
        expect(android.fullScreenIntent, isFalse);
      }
    },
  );
}
