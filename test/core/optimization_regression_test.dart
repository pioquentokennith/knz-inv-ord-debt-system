import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/dto/product_dto.dart';
import 'package:knz_scent_admin/repositories/inbound_change_buffer.dart';
import 'package:knz_scent_admin/screens/sales_screen.dart';

void main() {
  for (final entry in {
    0: 1,
    1: 1,
    49: 1,
    50: 1,
    51: 2,
    100: 2,
    101: 3,
  }.entries) {
    test('${entry.key} sales records require ${entry.value} pages', () {
      expect(SalesScreen.pageCountFor(entry.key), entry.value);
    });
  }
  test('extreme inputs and multiplication cannot wrap integer centavos', () {
    expect(Money.tryParse('9223372036854775807'), isNull);
    expect(Money.parse('1.005').centavos, 101);
    expect(Money.parse('-1.005').centavos, -101);
    expect(
      () => const Money.fromCentavos(100) * 9223372036854775807,
      throwsArgumentError,
    );
    expect(
      () =>
          const Money.fromCentavos(Money.maxStoredCentavos) +
          const Money.fromCentavos(1),
      throwsArgumentError,
    );
    expect(
      roundProductRatioHalfUp(Money.maxStoredCentavos, 10000, 10000),
      Money.maxStoredCentavos,
    );
  });
  test('historical data and aggregate reports can exceed new input policy', () {
    final product = ProductDto.fromLocal({
      'id': 'old',
      'user_id': 'u',
      'name': 'Legacy',
      'category': 'Perfume',
      'price_centavos': Money.maxUnitCentavos + 1,
      'stock_qty': Money.maxQuantity + 1,
      'min_stock_level': 1,
      'created_at': '2026-01-01T00:00:00Z',
    }).toDomain();
    expect(product.price.centavos, Money.maxUnitCentavos + 1);
    expect(product.stockQty, Money.maxQuantity + 1);
    expect(
      (const Money.fromCentavos(Money.maxCentavos) * 2).centavos,
      Money.maxCentavos * 2,
    );
  });
  test(
    'buffer retains unacknowledged writes and newer arrivals during commit',
    () async {
      final buffer = InboundChangeBuffer(() {})..expect('products');
      buffer.add('products', [
        {'id': 'p', 'revision': 1},
      ]);
      final first = await buffer.snapshot(['products']);
      expect(
        (await buffer.snapshot(['products'])).single.single['revision'],
        1,
      );
      buffer.add('products', [
        {'id': 'p', 'revision': 2},
      ]);
      buffer.acknowledge(['products'], first);
      final second = await buffer.snapshot(['products']);
      expect(second.single.single['revision'], 2);
      buffer.acknowledge(['products'], second);
      expect((await buffer.snapshot(['products'])).single, isEmpty);
    },
  );
}
