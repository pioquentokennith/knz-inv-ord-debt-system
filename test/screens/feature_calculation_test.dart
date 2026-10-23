import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/screens/analytics_screen.dart';
import 'package:knz_scent_admin/screens/reports_screen.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';

import '../support/feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = FeatureFixture();
  setUpAll(fixture.open);
  setUp(() {
    fixture.sharedBytes = null;
    fixture.shared = Completer<void>();
  });
  tearDownAll(fixture.close);

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  Future<void> may(WidgetTester tester) async {
    await tester.tap(find.text('All time (no filter)'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop(
      DateTimeRange(
        start: DateTime.utc(2026, 5, 1),
        end: DateTime.utc(2026, 5, 31),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Orders PDF recognized total includes delivery events', (
    tester,
  ) async {
    await show(tester, const ReportsScreen());
    await tester.runAsync(() async {
      await tester.tap(find.text('PDF'));
      await fixture.shared.future.timeout(const Duration(seconds: 20));
    });
    await tester.pump();
    expect(fixture.sharedBytes, isNotNull);
    final content = fixture.pdfContent();
    expect('(630.00)'.allMatches(content), hasLength(2));
    expect(content, isNot(contains('(cancelled)')));
  });

  testWidgets(
    'reseller report preview uses delivery date rather than creation date',
    (tester) async {
      await show(tester, const ReportsScreen());
      await tester.tap(find.text('Reseller Sales'));
      await tester.pumpAndSettle();
      await may(tester);
      expect(find.text('₱150.00'), findsOneWidget);
    },
  );

  testWidgets(
    'Accounting CSV retains orders created before the reporting period',
    (tester) async {
      await show(tester, const ReportsScreen());
      await tester.tap(find.text('Accounting Summary'));
      await tester.pumpAndSettle();
      await may(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Excel / CSV'));
        await fixture.shared.future.timeout(const Duration(seconds: 20));
      });
      await tester.pump();
      expect(fixture.sharedBytes, isNotNull);
      final csv = utf8.decode(fixture.sharedBytes!);
      expect(csv, contains('Net Sales (PHP),630.00'));
      expect(csv, contains('Total Cash Received (PHP),550.00'));
    },
  );

  testWidgets(
    'Analytics trend totals cash events without counting unpaid sales as cash',
    (tester) async {
      await show(tester, const AnalyticsScreen());
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final total = chart.data.lineBarsData.single.spots.fold<double>(
        0,
        (sum, p) => sum + p.y,
      );
      // Order payments 330 + debt payment 100 + custom installments 150.
      expect(total, 580);
    },
  );

  testWidgets(
    'Reports refreshes displayed cash after a business-event update',
    (tester) async {
      await show(tester, const ReportsScreen());
      await tester.tap(find.text('Accounting Summary'));
      await tester.pumpAndSettle();
      expect(find.text('₱580.00'), findsOneWidget);
      final refund = BusinessEvent(
        id: 'live-refund',
        userId: 'owner-1',
        subject: BusinessEventSubject.order,
        subjectId: 'paid',
        type: BusinessEventType.refund,
        amount: const Money.fromCentavos(1000),
        reason: 'Test update',
        occurredAt: DateTime.utc(2026, 7, 1),
        recordedAt: DateTime.utc(2026, 7, 1),
        commandId: 'live-refund',
      );
      await tester.runAsync(() async {
        await fixture.db.insert(
          'business_events',
          BusinessEventDto.fromDomain(refund).toLocal(),
        );
        await fixture.state.refreshData(collections: {'business_events'});
      });
      await tester.pumpAndSettle();
      expect(find.text('₱570.00'), findsOneWidget);
      // Events are immutable: reverse the synthetic refund rather than deleting
      // ledger facts. The complete disposable database is removed by close().
      await tester.runAsync(() async {
        final reversal = BusinessEvent(
          id: 'live-refund-reversal',
          userId: 'owner-1',
          subject: BusinessEventSubject.order,
          subjectId: 'paid',
          type: BusinessEventType.reversal,
          amount: const Money.fromCentavos(1000),
          reason: 'Correct test refund',
          relatedEventId: refund.id,
          occurredAt: refund.occurredAt,
          recordedAt: refund.recordedAt,
          commandId: 'live-refund-reversal',
        );
        await fixture.db.insert(
          'business_events',
          BusinessEventDto.fromDomain(reversal).toLocal(),
        );
        await fixture.state.refreshData(collections: {'business_events'});
      });
      await tester.pumpAndSettle();
      expect(find.text('₱580.00'), findsOneWidget);
    },
  );

  testWidgets(
    'Analytics trend handles refunds, reversals and collection projections once',
    (tester) async {
      final events = [
        BusinessEvent(
          id: 'audit-refund',
          userId: 'owner-1',
          subject: BusinessEventSubject.order,
          subjectId: 'paid',
          type: BusinessEventType.refund,
          amount: const Money.fromCentavos(5000),
          reason: 'Test refund',
          occurredAt: DateTime.utc(2026, 7, 1),
          recordedAt: DateTime.utc(2026, 7, 1),
          commandId: 'audit-refund',
        ),
        BusinessEvent(
          id: 'audit-reverse',
          userId: 'owner-1',
          subject: BusinessEventSubject.order,
          subjectId: 'paid',
          type: BusinessEventType.reversal,
          amount: const Money.fromCentavos(5000),
          reason: 'Test reversal',
          relatedEventId: 'audit-refund',
          occurredAt: DateTime.utc(2026, 7, 2),
          recordedAt: DateTime.utc(2026, 7, 2),
          commandId: 'audit-reverse',
        ),
        BusinessEvent(
          id: 'audit-debt',
          userId: 'owner-1',
          subject: BusinessEventSubject.debt,
          subjectId: 'debt-1',
          type: BusinessEventType.collection,
          amount: const Money.fromCentavos(10000),
          occurredAt: DateTime.utc(2026, 5, 15),
          recordedAt: DateTime.utc(2026, 5, 15),
          commandId: 'audit-debt',
        ),
        for (final payment in fixture.data.customOrders.single.payments)
          BusinessEvent(
            id: 'audit-${payment.id}',
            userId: 'owner-1',
            subject: BusinessEventSubject.customOrder,
            subjectId: 'custom-1',
            type: BusinessEventType.collection,
            amount: payment.amount,
            occurredAt: payment.paidAt,
            recordedAt: payment.paidAt,
            commandId: 'audit-${payment.id}',
          ),
      ];
      await tester.runAsync(() async {
        for (final event in events) {
          await fixture.db.insert(
            'business_events',
            BusinessEventDto.fromDomain(event).toLocal(),
          );
        }
        await fixture.state.refreshData(collections: {'business_events'});
      });
      await show(tester, const AnalyticsScreen());
      List<FlSpot> spots() => tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData
          .single
          .spots;
      expect(spots().map((p) => p.y), contains(-50));
      expect(spots().fold<double>(0, (sum, p) => sum + p.y), 580);
      await tester.ensureVisible(find.text('Month'));
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(spots().fold<double>(0, (sum, p) => sum + p.y), 580);
    },
  );
}
