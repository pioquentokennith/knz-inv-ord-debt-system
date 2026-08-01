import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/dialogs/order_dialog.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/payment_method_model.dart';

void main() {
  testWidgets(
    'new order supports all statuses and keeps Utang payment aligned',
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
        orderedEquals(OrderStatus.values),
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
