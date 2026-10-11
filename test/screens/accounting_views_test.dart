import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/screens/accounting_screen.dart';
import 'package:knz_scent_admin/screens/overview_screen.dart';
import 'package:knz_scent_admin/screens/reports_screen.dart';
import 'package:knz_scent_admin/screens/sales_screen.dart';
import 'package:knz_scent_admin/services/accounting_service.dart';

import '../fixtures/accounting_fixture.dart';

void main() {
  late AccountingReport report;

  setUp(() {
    final fixture = AccountingFixture();
    report = AccountingService.instance.summarize(
      orders: fixture.orders,
      debts: fixture.debts,
      customOrders: fixture.customOrders,
      businessEvents: fixture.businessEvents,
      period: AccountingPeriod(from: fixture.periodFrom, to: fixture.periodTo),
    );
  });

  testWidgets('dashboard displays the fixed fixture cash totals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: OverviewScreen(accountingReport: report)),
    );
    await tester.pump();

    expect(find.text('₱630.00'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget);
    expect(find.text('₱550.00'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('Reports fits a 320px screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ReportsScreen(accountingReport: report),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(
        find
            .byWidgetPredicate((widget) => widget is DropdownButtonFormField)
            .first,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Revenue Summary'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('Revenue Summary').last),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revenue Summary').hitTestable().last);
      await tester.pumpAndSettle();
      expect(find.text('REVENUE & COLLECTIONS SUMMARY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('Sales empty state fits a 320px screen at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: SalesScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('accounting cards and ledger use the fixed fixture report', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccountingScreen(accountingReport: report)),
      ),
    );
    await tester.pump();

    expect(find.text('₱700.00'), findsOneWidget);
    expect(find.text('₱70.00'), findsOneWidget);
    expect(find.text('₱630.00'), findsOneWidget);
    expect(find.text('₱120.00'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget);
    expect(find.text('₱550.00'), findsOneWidget);
    expect(find.text('cancelled'), findsNothing);
    expect(find.text('utang'), findsOneWidget);
  });

  testWidgets('revenue report preview uses the fixed fixture cash total', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ReportsScreen(accountingReport: report)),
    );
    await tester.tap(find.text('Revenue Summary'));
    await tester.pump();

    expect(find.text('₱550.00'), findsWidgets);
    expect(find.text('REVENUE & COLLECTIONS SUMMARY'), findsOneWidget);
  });
}
