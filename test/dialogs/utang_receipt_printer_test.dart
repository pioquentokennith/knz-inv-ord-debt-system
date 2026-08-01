import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/dialogs/utang_receipt_printer.dart';
import 'package:knz_scent_admin/models/debt_model.dart';

void main() {
  testWidgets('debt receipt shows principal, interest, and full outstanding', (
    tester,
  ) async {
    final debt = CustomerDebt(
      id: 'debt-1',
      customerName: 'Customer',
      orderId: 'KNZ-001',
      principalOriginal: const Money.fromCentavos(10000),
      principalOutstanding: const Money.fromCentavos(10000),
      interestOutstanding: const Money.fromCentavos(1000),
      createdAt: DateTime.utc(2026),
      interestRateBasisPoints: 1000,
      interestType: 'daily',
    );

    await tester.pumpWidget(MaterialApp(home: UtangReceiptScreen(debt: debt)));

    expect(find.text('Principal Outstanding'), findsOneWidget);
    expect(find.text('Accrued Interest'), findsOneWidget);
    expect(find.text('₱10.00'), findsOneWidget);
    expect(find.text('₱110.00'), findsOneWidget);
  });
}
