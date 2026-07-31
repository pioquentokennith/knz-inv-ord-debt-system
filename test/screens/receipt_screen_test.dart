import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
