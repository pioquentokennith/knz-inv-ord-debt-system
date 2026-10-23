import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/services/notification_service.dart';
import 'package:knz_scent_admin/widgets/notification_status_banner.dart';
import 'package:timezone/data/latest.dart' as tz_data;

import '../support/notification_fakes.dart';

class _CacheFailurePlatform extends FakeAlertPlatform {
  bool failCache = true;

  @override
  Future<Set<int>> pendingIds() async {
    if (failCache) {
      throw PlatformException(
        code: 'error',
        message: 'TypeToken must be created with a type argument',
      );
    }
    return super.pendingIds();
  }
}

void main() {
  testWidgets(
    'Retry shows persistent native cache failures and clears after recovery without duplicate stock alerts',
    (tester) async {
      tz_data.initializeTimeZones();
      final platform = _CacheFailurePlatform();
      final service =
          NotificationService(
            platform: platform,
            store: MemoryAlertStore(),
            now: () => DateTime.utc(2026, 1, 3, 2),
          )..configure(
            activeUser: () => 'synthetic-owner',
            snapshot: () => NotificationSnapshot('synthetic-owner', [
              Product(
                id: 'synthetic-stock',
                name: 'Synthetic stock',
                description: '',
                category: ProductCategory.eauDeParfum,
                price: const Money.fromCentavos(100),
                stockQty: 1,
                minStockLevel: 5,
              ),
            ], []),
          );
      await service.init();
      await service.idle;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NotificationStatusBanner(service: service)),
        ),
      );
      const message = 'Notification update failed. Please retry.';
      expect(find.text(message), findsOneWidget);
      expect(platform.shows, hasLength(1));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(platform.shows, hasLength(1));

      platform.failCache = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(service.lastError, isNull);
      expect(find.text(message), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(platform.shows, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await service.idle;
      service.dispose();
    },
  );
}
