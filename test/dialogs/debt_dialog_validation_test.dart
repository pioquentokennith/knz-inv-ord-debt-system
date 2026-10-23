import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/dialogs/mark_as_utang_dialog.dart';
import 'package:knz_scent_admin/dialogs/utang_payment_dialog.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/widgets/shared_widgets.dart';

Order order({String name = 'Customer'}) => Order(
  id: 'o',
  orderId: 'KNZ-000001',
  customerName: name,
  items: const [],
  totalAmount: const Money.fromCentavos(10000),
  status: OrderStatus.pending,
  orderDate: DateTime.utc(2026),
);

void main() {
  testWidgets('invalid initial payment is rejected instead of becoming zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarkAsUtangDialog(order: order())),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'not-a-number');
    await tester.ensureVisible(find.text('Record Utang'));
    await tester.tap(find.text('Record Utang'));
    await tester.pumpAndSettle();
    expect(find.text('Record Utang?'), findsNothing);
    expect(find.text('Please enter a valid initial payment.'), findsOneWidget);
  });

  for (final payment in [false, true]) {
    testWidgets(
      '${payment ? 'Payment' : 'Utang'} rapid submissions open only one confirmation',
      (tester) async {
        final dialog = payment
            ? UtangPaymentDialog(
                debt: CustomerDebt(
                  id: 'd',
                  customerName: 'Customer',
                  orderId: 'KNZ-000001',
                  principalOriginal: const Money.fromCentavos(10000),
                  principalOutstanding: const Money.fromCentavos(10000),
                  createdAt: DateTime.utc(2026),
                ),
              )
            : MarkAsUtangDialog(order: order());
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));
        await tester.enterText(find.byType(TextField).first, '10');
        final VoidCallback submit = payment
            ? tester.widget<GoldButton>(find.byType(GoldButton)).onPressed!
            : tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Record Utang'),
                  )
                  .onPressed!;
        submit();
        submit();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Cancel'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
      },
    );
    testWidgets(
      '${payment ? 'Payment' : 'Utang'} dialog handles long identities on a small screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const name =
            'A customer with a very long full name for the school demonstration';
        final dialog = payment
            ? UtangPaymentDialog(
                debt: CustomerDebt(
                  id: 'd',
                  customerName: name,
                  orderId: 'TMP-ABCD-000001',
                  principalOriginal: const Money.fromCentavos(10000),
                  principalOutstanding: const Money.fromCentavos(10000),
                  createdAt: DateTime.utc(2026),
                ),
              )
            : MarkAsUtangDialog(order: order(name: name));
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('payment rejects overpayment and validates GCash details', (
    tester,
  ) async {
    final debt = CustomerDebt(
      id: 'd',
      customerName: 'Customer',
      orderId: 'KNZ-000001',
      principalOriginal: const Money.fromCentavos(10000),
      principalOutstanding: const Money.fromCentavos(10000),
      createdAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: UtangPaymentDialog(debt: debt)),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '101');
    await tester.tap(find.text('Confirm Payment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Amount exceeds total due'), findsOneWidget);
    await tester.tap(find.text('Full'));
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '100.00',
    );
    await tester.tap(find.text('GCash'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm Payment'));
    await tester.tap(find.text('Confirm Payment'));
    await tester.pumpAndSettle();
    expect(
      find.text('Please enter the GCash reference number.'),
      findsOneWidget,
    );
  });
}
