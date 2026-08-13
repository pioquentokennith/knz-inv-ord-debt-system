import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';
import 'package:knz_scent_admin/screens/receipt_screen.dart';

import '../fixtures/accounting_fixture.dart';

void main() {
  testWidgets('reseller receipt shows true SRP and customer-pay total', (
    tester,
  ) async {
    final reseller = AccountingFixture().orders.firstWhere(
      (order) => order.id == 'reseller',
    );

    await tester.pumpWidget(MaterialApp(home: ReceiptScreen(order: reseller)));
    await tester.pump();

    expect(find.text('SRP TOTAL'), findsOneWidget);
    expect(find.text('₱200.00'), findsOneWidget);
    expect(find.text('₱150.00'), findsNWidgets(2));
  });

  testWidgets('receipt separates collected cash from remaining balance', (
    tester,
  ) async {
    final order = AccountingFixture().orders.firstWhere(
      (candidate) => candidate.id == 'paid',
    );
    final timestamp = DateTime.utc(2026, 5, 1);
    final payment = BusinessEvent(
      id: 'receipt-payment',
      userId: 'owner-1',
      subject: BusinessEventSubject.order,
      subjectId: order.id,
      type: BusinessEventType.payment,
      amount: const Money.fromCentavos(8000),
      occurredAt: timestamp,
      recordedAt: timestamp,
      paymentMethod: 'cash_on_delivery',
      commandId: 'receipt-payment',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptScreen(order: order, businessEvents: [payment]),
      ),
    );
    await tester.pump();

    expect(find.text('Net collected'), findsOneWidget);
    expect(find.text('₱80.00'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('₱100.00'), findsOneWidget);
  });
}
