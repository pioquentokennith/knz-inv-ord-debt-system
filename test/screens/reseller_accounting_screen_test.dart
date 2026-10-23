import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/screens/reseller_accounting_screen.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fixtures/accounting_fixture.dart';

class _Auth extends Fake implements IAuthService {
  @override
  Future<AuthResult> restoreTrustedDevice() async => AuthResult(
    status: 'offline',
    user: AppUser(
      id: 'owner-1',
      username: 'owner',
      name: 'Owner',
      email: 'owner@example.com',
      role: 'Administrator',
      accountStatus: 'approved',
      isActive: true,
      createdAt: DateTime.utc(2026),
    ),
  );

  @override
  Future<void> logout() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final state = AppState();
  final fixture = AccountingFixture();
  late Directory directory;
  late Database db;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('reseller-accounting-');
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(directory.path);
    db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (final order in fixture.orders) {
      final dto = OrderDto.fromDomain(order, userId: 'owner-1');
      batch.insert('orders', dto.toLocal());
      for (final item in dto.items) {
        batch.insert('order_items', item.toLocal());
      }
    }
    for (final event in fixture.businessEvents) {
      if (event.id == 'reseller-delivery') continue;
      batch.insert(
        'business_events',
        BusinessEventDto.fromDomain(event).toLocal(),
      );
    }
    await batch.commit(noResult: true);
    state.configure(
      authService: _Auth(),
      stopSynchronization: () async {},
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );
    await state.restoreTrustedDevice();
  });

  tearDownAll(() async {
    await state.logout();
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'delivery events refresh reseller totals and logout clears the summary',
    (tester) async {
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: ResellerAccountingScreen()),
      );
      await tester.pumpAndSettle();

      // Payment alone (even with a delivered status) does not recognize a sale.
      expect(find.text('No reseller orders yet'), findsOneWidget);
      await tester.runAsync(() async {
        final delivery = fixture.businessEvents.singleWhere(
          (event) => event.id == 'reseller-delivery',
        );
        await db.insert(
          'business_events',
          BusinessEventDto.fromDomain(delivery).toLocal(),
        );
        await state.refreshData(collections: {'business_events'});
      });
      await tester.pumpAndSettle();

      expect(find.text('No reseller orders yet'), findsNothing);
      expect(find.text('Fixture Reseller'), findsOneWidget);
      expect(find.text('Fixture Customer'), findsNothing);
      expect(find.text('1 order · −₱50/item avg'), findsOneWidget);
      expect(find.text('₱200.00'), findsNWidgets(2));
      expect(find.text('₱50.00'), findsNWidgets(2));
      expect(find.text('₱150.00'), findsNWidgets(3));
      expect(tester.takeException(), isNull);

      await tester.runAsync(state.logout);
      await tester.pumpAndSettle();
      expect(find.text('No reseller orders yet'), findsOneWidget);
      expect(find.text('Fixture Reseller'), findsNothing);
    },
  );
}
