import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/dialogs/custom_order_dialog.dart';
import 'package:knz_scent_admin/dialogs/reseller_dialog.dart';
import 'package:knz_scent_admin/dialogs/product_dialog.dart';
import 'package:knz_scent_admin/dialogs/edit_stock_dialog.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/widgets/shared_widgets.dart';

import '../fixtures/accounting_fixture.dart';

void main() {
  final product = Product(
    id: 'p',
    name: 'Rose',
    description: '',
    category: ProductCategory.eauDeParfum,
    price: const Money.fromCentavos(20000),
    stockQty: 10,
    minStockLevel: 2,
  );
  for (final stock in [false, true]) {
    testWidgets(
      '${stock ? 'Stock' : 'Product'} rapid submissions open one confirmation',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: stock
                ? EditStockDialog(product: product)
                : ProductDialog(existing: product),
          ),
        );
        final submit = tester
            .widget<GoldButton>(find.byType(GoldButton))
            .onPressed!;
        submit();
        submit();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog, skipOffstage: false), findsNothing);
        // Cancellation releases the guard so the user can correct/retry.
        tester.widget<GoldButton>(find.byType(GoldButton)).onPressed!();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'leaving Product while confirmation is open does not update disposed state',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ProductDialog(existing: product)),
      );
      tester.widget<GoldButton>(find.byType(GoldButton)).onPressed!();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('editing a reseller preserves centavos in the saved deduction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResellerDialog(
          existing: Reseller(
            id: 'r',
            name: 'Reseller',
            deductionPerItem: const Money.fromCentavos(3050),
            userId: 'owner-1',
            createdAt: DateTime.utc(2026),
          ),
        ),
      ),
    );
    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields.last.controller!.text, '30.50');
  });

  testWidgets('editing an overdue custom agreement can open its date picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final order = AccountingFixture().customOrders.single.copyWith(
      deliveryDate: DateTime.now().subtract(const Duration(days: 10)),
    );
    await tester.pumpWidget(
      MaterialApp(home: CustomOrderDialog(existing: order)),
    );
    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
