import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/screens/accounting_screen.dart';
import 'package:knz_scent_admin/screens/analytics_screen.dart';
import 'package:knz_scent_admin/screens/custom_orders_screen.dart';
import 'package:knz_scent_admin/screens/inventory_screen.dart';
import 'package:knz_scent_admin/screens/orders_screen.dart';
import 'package:knz_scent_admin/screens/overview_screen.dart';
import 'package:knz_scent_admin/screens/products_screen.dart';
import 'package:knz_scent_admin/screens/recycle_bin_screen.dart';
import 'package:knz_scent_admin/screens/registration_requests_screen.dart';
import 'package:knz_scent_admin/screens/reports_screen.dart';
import 'package:knz_scent_admin/screens/reseller_accounting_screen.dart';
import 'package:knz_scent_admin/screens/reseller_screen.dart';
import 'package:knz_scent_admin/screens/sales_screen.dart';
import 'package:knz_scent_admin/screens/sync_issues_screen.dart';
import 'package:knz_scent_admin/screens/utang_screen.dart';

import '../support/feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = FeatureFixture();
  setUpAll(() async {
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final bytes = await File(
      '${artifacts.path}/material_fonts/roboto-regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'FeatureRoboto',
    )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    await fixture.open();
  });
  tearDownAll(fixture.close);
  final screens = <String, Widget>{
    'Overview': const OverviewScreen(),
    'Inventory': const InventoryScreen(),
    'Orders': const OrdersScreen(),
    'Products': const ProductsScreen(),
    'Analytics': const AnalyticsScreen(),
    'Utang': const UtangScreen(),
    'Sales Table': const SalesScreen(),
    'Resellers': const ResellersScreen(),
    'Reseller Accounting': const ResellerAccountingScreen(),
    'Accounting': const AccountingScreen(),
    'Custom Orders': const CustomOrdersScreen(),
    'Reports': const ReportsScreen(),
    'Registration Requests': const RegistrationRequestsScreen(),
    'Recycle Bin': const RecycleBinScreen(),
    'Sync Issues': const SyncIssuesScreen(),
  };
  for (final width in [400.0, 1000.0]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} renders at $width with synthetic local data', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'FeatureRoboto'),
            home: Scaffold(body: entry.value),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        if (entry.key == 'Registration Requests') {
          expect(
            find.text('Registration requests could not be loaded.'),
            findsOneWidget,
          );
        }
      });
    }
  }
  testWidgets('Staff can open Products and edit without a delete action', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await fixture.state.logout();
      await fixture.signInAs('Staff');
    });
    addTearDown(() async {
      await fixture.state.logout();
      await fixture.signInAs('Administrator');
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'FeatureRoboto'),
        home: const ProductsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}
