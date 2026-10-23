import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_bootstrap.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/core/startup_gate.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../support/notification_fakes.dart';

Future<void> _succeeds() async {}

void main() {
  testWidgets('StartupGate repeats alerts only after a background return', (
    tester,
  ) async {
    tz_data.initializeTimeZones();
    final platform = FakeAlertPlatform();
    final service =
        NotificationService(
          platform: platform,
          store: MemoryAlertStore(),
          now: () => DateTime.utc(2026, 1, 2, 23), // 7 AM Manila.
        )..configure(
          activeUser: () => 'user',
          snapshot: () => NotificationSnapshot(
            'user',
            [
              Product(
                id: 'p',
                name: 'Product',
                description: '',
                category: ProductCategory.eauDeParfum,
                price: const Money.fromCentavos(100),
                stockQty: 0,
                minStockLevel: 5,
              ),
            ],
            [
              CustomerDebt(
                id: 'd',
                customerName: 'Customer',
                orderId: 'o',
                principalOriginal: const Money.fromCentavos(100),
                principalOutstanding: const Money.fromCentavos(100),
                createdAt: DateTime.utc(2026),
                dueDate: DateTime.utc(2026, 1, 3),
              ),
            ],
          ),
        );
    final bootstrap = AppBootstrap(
      initializeDatabase: _succeeds,
      initializePreferences: _succeeds,
      configureLocalState: _succeeds,
      restoreTrustedSession: _succeeds,
      initializeFirebase: _succeeds,
      initializeCrashlytics: _succeeds,
      initializeNotifications: service.init,
      initializeCloudAuthentication: _succeeds,
      startSynchronization: _succeeds,
    );
    final navigator = GlobalKey<NavigatorState>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: StartupGate(
          bootstrap: bootstrap,
          notifications: service,
          homeBuilder: (_) => const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(platform.shows, hasLength(2));

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Details')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(platform.shows, hasLength(2));

    for (var visit = 2; visit <= 3; visit++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(platform.shows, hasLength(visit * 2));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await service.idle;
    service.dispose();
    expect(tester.takeException(), isNull);
  });
}
