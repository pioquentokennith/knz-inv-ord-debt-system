import 'package:flutter_test/flutter_test.dart';

import '../support/feature_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = FeatureFixture();
  setUpAll(fixture.open);
  tearDownAll(fixture.close);

  test('product restore preserves stock and offline purge is denied', () async {
    final state = fixture.state;
    await state.deleteProduct('fixture-product');
    expect(state.products, isEmpty);
    expect((await state.getDeletedProducts()).single.stockQty, 10);
    await state.restoreProduct('fixture-product');
    expect(state.products.single.stockQty, 10);
    expect(await state.getDeletedProducts(), isEmpty);
    await state.deleteProduct('fixture-product');
    await expectLater(
      state.hardDeleteProduct('fixture-product'),
      throwsStateError,
    );
    final row = (await fixture.db.query(
      'products',
      where: 'id = ?',
      whereArgs: ['fixture-product'],
    )).single;
    expect(row['purge_state'], 'none');
    expect(row['stock_qty'], 10);
  });

  test(
    'reseller restore preserves centavos and offline purge is denied',
    () async {
      final state = fixture.state;
      await state.deleteReseller('fixture-reseller');
      expect(state.resellers, isEmpty);
      expect(
        (await state.getDeletedResellers()).single.deductionPerItem.centavos,
        3050,
      );
      await state.restoreReseller('fixture-reseller');
      expect(state.resellers.single.deductionPerItem.centavos, 3050);
      await state.deleteReseller('fixture-reseller');
      await expectLater(
        state.hardDeleteReseller('fixture-reseller'),
        throwsStateError,
      );
      final row = (await fixture.db.query(
        'resellers',
        where: 'id = ?',
        whereArgs: ['fixture-reseller'],
      )).single;
      expect(row['purge_state'], 'none');
      expect(row['deduction_per_item_centavos'], 3050);
    },
  );

  test(
    'custom agreement restore retains installments and remaining balance',
    () async {
      final state = fixture.state;
      final before = state.customOrders.single;
      await state.deleteCustomOrder(before.id);
      expect(state.customOrders, isEmpty);
      expect(
        (await state.getDeletedCustomOrders()).single.payments,
        hasLength(3),
      );
      await state.restoreCustomOrder(before.id);
      final restored = state.customOrders.single;
      expect(restored.agreedPrice.centavos, 40000);
      expect(restored.depositPaid.centavos, 15000);
      expect(restored.balanceDue.centavos, 25000);
      expect(restored.payments, hasLength(3));
      await state.deleteCustomOrder(before.id);
      await expectLater(
        state.hardDeleteCustomOrder(before.id),
        throwsStateError,
      );
      expect(
        (await fixture.db.query('custom_orders')).single['purge_state'],
        'none',
      );
      expect(await fixture.db.query('custom_order_payments'), hasLength(3));
    },
  );
}
