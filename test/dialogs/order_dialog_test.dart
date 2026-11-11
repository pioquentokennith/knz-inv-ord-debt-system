import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/dialogs/order_dialog.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/payment_method_model.dart';
import 'package:knz_scent_admin/widgets/interest_type_selector.dart';

void main() {
  testWidgets(
    'weekly interest can be selected and cleared on a mobile order dialog',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OrderDialog())),
      );
      tester
          .widget<DropdownButton<OrderStatus>>(
            find.byType(DropdownButton<OrderStatus>),
          )
          .onChanged!(OrderStatus.utang);
      await tester.pumpAndSettle();
      final selector = find.byType(InterestTypeSelector);
      expect(
        find
            .descendant(of: selector, matching: find.byType(Text))
            .evaluate()
            .map((element) => (element.widget as Text).data),
        orderedEquals(['None', 'Daily', 'Weekly', 'Monthly']),
      );
      await tester.ensureVisible(find.text('Weekly'));
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      expect(tester.widget<InterestTypeSelector>(selector).value, 'weekly');
      expect(find.text('%  weekly'), findsOneWidget);
      expect(find.textContaining('every completed 7 days'), findsOneWidget);
      final rate = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.suffixText == '%  weekly',
      );
      await tester.enterText(rate, '2.50');
      await tester.ensureVisible(find.text('None'));
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(rate, findsNothing);
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(rate).controller!.text, '0');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new order requires explicit delivery and keeps Utang payment aligned',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OrderDialog())),
      );

      DropdownButton<OrderStatus> statusDropdown = tester.widget(
        find.byType(DropdownButton<OrderStatus>),
      );
      expect(
        statusDropdown.items!.map((item) => item.value),
        orderedEquals(
          OrderStatus.values.where((status) => status != OrderStatus.delivered),
        ),
      );

      statusDropdown.onChanged!(OrderStatus.utang);
      await tester.pump();

      var paymentDropdown = tester.widget<DropdownButton<PaymentMethod>>(
        find.byType(DropdownButton<PaymentMethod>),
      );
      expect(paymentDropdown.value, PaymentMethod.utang);

      paymentDropdown.onChanged!(PaymentMethod.gcash);
      await tester.pump();

      statusDropdown = tester.widget(find.byType(DropdownButton<OrderStatus>));
      expect(statusDropdown.value, OrderStatus.pending);
    },
  );
}
