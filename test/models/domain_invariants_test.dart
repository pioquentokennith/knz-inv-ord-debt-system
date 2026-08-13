import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/repositories/product_repository.dart';
import 'package:knz_scent_admin/services/product_service.dart';

void main() {
  group('Product invariants', () {
    test('rejects blank identity and invalid inventory values', () {
      expect(() => _product(id: ' '), throwsArgumentError);
      expect(() => _product(name: '\t'), throwsArgumentError);
      expect(() => _product(priceCentavos: -1), throwsArgumentError);
      expect(() => _product(stockQty: -1), throwsArgumentError);
      expect(() => _product(minStockLevel: -1), throwsArgumentError);
    });

    test('stock setter also preserves the non-negative invariant', () {
      final product = _product();
      expect(() => product.stockQty = -1, throwsArgumentError);
      product.stockQty = 0;
      expect(product.stockQty, 0);
    });

    test('valid legacy maps still deserialize with optional defaults', () {
      final product = Product.fromMap({
        'id': 'product-1',
        'name': 'Legacy Scent',
        'category': 'Eau de Parfum',
        'priceCentavos': 10000,
        'stockQty': 2,
      });

      expect(product.description, '');
      expect(product.minStockLevel, 5);
    });

    test('copyWith can explicitly clear a local inventory image', () {
      final product = _product().copyWith(imagePath: 'local-product.jpg');

      expect(product.imagePath, 'local-product.jpg');
      expect(product.copyWith(clearImage: true).imagePath, isNull);
    });
  });

  group('CustomOrder invariants', () {
    test('requires identity, owner, customer, and fragrance details', () {
      expect(() => _customOrder(id: ''), throwsArgumentError);
      expect(() => _customOrder(userId: ' '), throwsArgumentError);
      expect(() => _customOrder(customerName: ' '), throwsArgumentError);
      expect(() => _customOrder(fragranceSpecs: '\n'), throwsArgumentError);
    });

    test('requires finite non-negative money and a bounded deposit', () {
      expect(() => _customOrder(agreedPriceCentavos: -1), throwsArgumentError);
      expect(() => _customOrder(depositPaidCentavos: -1), throwsArgumentError);
      expect(
        () => _customOrder(
          agreedPriceCentavos: 10000,
          depositPaidCentavos: 10001,
        ),
        throwsArgumentError,
      );
    });

    test('legacy rows without a deposit remain valid', () {
      final order = CustomOrder.fromMap({
        'id': 'custom-1',
        'customer_name': 'Legacy Customer',
        'fragrance_specs': 'Floral, 50 ml',
        'agreed_price_centavos': 50000,
        'deposit_paid_centavos': 0,
        'delivery_date': '2025-01-02T00:00:00.000',
        'user_id': 'owner-1',
        'created_at': '2025-01-01T00:00:00.000',
      });

      expect(order.depositPaid, Money.zero);
      expect(order.balanceDue, const Money.fromCentavos(50000));
    });
  });

  group('Reseller invariants', () {
    test('requires identity, owner, name, and a valid deduction', () {
      expect(() => _reseller(id: ' '), throwsArgumentError);
      expect(() => _reseller(userId: ''), throwsArgumentError);
      expect(() => _reseller(name: '\t'), throwsArgumentError);
      expect(() => _reseller(deductionCentavos: -1), throwsArgumentError);
    });

    test('validates SRP and never discounts below zero', () {
      final reseller = _reseller(deductionCentavos: 15000);
      expect(
        reseller.discountedPrice(const Money.fromCentavos(10000)),
        Money.zero,
      );
      expect(
        () => reseller.discountedPrice(const Money.fromCentavos(-1)),
        throwsArgumentError,
      );
    });

    test('legacy rows without a deduction remain valid', () {
      final reseller = Reseller.fromMap({
        'id': 'reseller-1',
        'name': 'Legacy Reseller',
        'user_id': 'owner-1',
        'created_at': '2025-01-01T00:00:00.000',
      });

      expect(reseller.deductionPerItem, Money.zero);
    });
  });

  group('Order invariants', () {
    test('line items require a name, positive quantity, and valid prices', () {
      expect(() => _item(productName: ' '), throwsArgumentError);
      expect(() => _item(unitPriceCentavos: -1), throwsArgumentError);
      expect(() => _item(srpPriceCentavos: -1), throwsArgumentError);
      expect(() => _item(quantity: 0), throwsArgumentError);
    });

    test('orders reject blank identity and invalid totals or deductions', () {
      expect(() => _order(id: ' '), throwsArgumentError);
      expect(() => _order(orderId: ''), throwsArgumentError);
      expect(() => _order(customerName: '\n'), throwsArgumentError);
      expect(() => _order(totalCentavos: -1), throwsArgumentError);
      expect(() => _order(deductionCentavos: -1), throwsArgumentError);
      expect(() => _order(discountedCentavos: -1), throwsArgumentError);
      expect(() => _order(orderType: ' '), throwsArgumentError);
    });

    test('defensively owns its line-item list', () {
      final source = <OrderItem>[_item()];
      final order = _order(items: source);
      source.clear();

      expect(order.items, hasLength(1));
      expect(() => order.items.clear(), throwsUnsupportedError);
    });

    test('calculates canonical gross and net totals from line items', () {
      final order = _order(
        items: [
          _item(unitPriceCentavos: 17000, srpPriceCentavos: 20000, quantity: 2),
        ],
        totalCentavos: 34000,
      );

      expect(order.lineSrpTotal, const Money.fromCentavos(40000));
      expect(order.lineCustomerPayTotal, const Money.fromCentavos(34000));
    });

    test('documented flat legacy orders remain readable', () {
      final order = Order.fromMap({
        'id': 'order-1',
        'orderId': 'KNZ-001',
        'customerName': 'Legacy Customer',
        'productName': 'Legacy Scent',
        'quantity': 2,
        'totalAmountCentavos': 20000,
        'status': 'Pending',
        'orderDate': '2025-01-01T00:00:00.000',
      });

      expect(order.items.single.id, '');
      expect(order.items.single.productId, '');
      expect(order.items.single.quantity, 2);
    });
  });

  group('ProductService validation', () {
    test(
      'rejects negative prices and blank owners before persistence',
      () async {
        final repository = _FakeProductRepository();
        final service = ProductService(repository);

        await expectLater(
          service.addProduct(
            userId: 'owner-1',
            name: 'Scent',
            description: '',
            category: ProductCategory.eauDeParfum,
            price: const Money.fromCentavos(-1),
            stockQty: 1,
            minStockLevel: 0,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('non-negative'),
            ),
          ),
        );
        await expectLater(
          service.addProduct(
            userId: ' ',
            name: 'Scent',
            description: '',
            category: ProductCategory.eauDeParfum,
            price: const Money.fromCentavos(1000),
            stockQty: 1,
            minStockLevel: 0,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('User ID'),
            ),
          ),
        );
        expect(repository.added, isNull);
      },
    );

    test('trims valid user and product names before persistence', () async {
      final repository = _FakeProductRepository();
      final service = ProductService(repository);

      await service.addProduct(
        userId: ' owner-1 ',
        name: ' Scent ',
        description: ' description ',
        category: ProductCategory.eauDeParfum,
        price: const Money.fromCentavos(1000),
        stockQty: 1,
        minStockLevel: 0,
      );

      expect(repository.userId, 'owner-1');
      expect(repository.added?.name, 'Scent');
      expect(repository.added?.description, 'description');
    });

    test('rejects blank mutation identifiers', () async {
      final repository = _FakeProductRepository();
      final service = ProductService(repository);

      await expectLater(service.updateStock(' ', 1), throwsArgumentError);
      expect(() => service.deleteProduct(' ', 'owner-1'), throwsArgumentError);
      expect(() => service.restoreProduct(' ', 'owner-1'), throwsArgumentError);
      expect(
        () => service.hardDeleteProduct(' ', 'owner-1'),
        throwsArgumentError,
      );
    });
  });
}

Product _product({
  String id = 'product-1',
  String name = 'Scent',
  int priceCentavos = 10000,
  int stockQty = 5,
  int minStockLevel = 1,
}) => Product(
  id: id,
  name: name,
  description: '',
  category: ProductCategory.eauDeParfum,
  price: Money.fromCentavos(priceCentavos),
  stockQty: stockQty,
  minStockLevel: minStockLevel,
);

CustomOrder _customOrder({
  String id = 'custom-1',
  String customerName = 'Customer',
  String fragranceSpecs = 'Floral, 50 ml',
  int agreedPriceCentavos = 50000,
  int depositPaidCentavos = 0,
  String userId = 'owner-1',
}) => CustomOrder(
  id: id,
  customerName: customerName,
  fragranceSpecs: fragranceSpecs,
  agreedPrice: Money.fromCentavos(agreedPriceCentavos),
  depositPaid: Money.fromCentavos(depositPaidCentavos),
  deliveryDate: DateTime(2025, 1, 2),
  userId: userId,
  createdAt: DateTime(2025),
);

Reseller _reseller({
  String id = 'reseller-1',
  String name = 'Reseller',
  int deductionCentavos = 2000,
  String userId = 'owner-1',
}) => Reseller(
  id: id,
  name: name,
  deductionPerItem: Money.fromCentavos(deductionCentavos),
  userId: userId,
  createdAt: DateTime(2025),
);

OrderItem _item({
  String id = 'item-1',
  String productId = 'product-1',
  String productName = 'Scent',
  int unitPriceCentavos = 10000,
  int? srpPriceCentavos,
  int quantity = 1,
}) => OrderItem(
  id: id,
  productId: productId,
  productName: productName,
  unitPrice: Money.fromCentavos(unitPriceCentavos),
  srpPrice: srpPriceCentavos == null
      ? null
      : Money.fromCentavos(srpPriceCentavos),
  quantity: quantity,
);

Order _order({
  String id = 'order-1',
  String orderId = 'KNZ-001',
  String customerName = 'Customer',
  List<OrderItem>? items,
  int totalCentavos = 10000,
  int deductionCentavos = 0,
  int? discountedCentavos,
  String orderType = 'regular',
}) => Order(
  id: id,
  orderId: orderId,
  customerName: customerName,
  items: items ?? <OrderItem>[_item()],
  totalAmount: Money.fromCentavos(totalCentavos),
  status: OrderStatus.pending,
  orderDate: DateTime(2025),
  deductionPerItem: Money.fromCentavos(deductionCentavos),
  discountedTotal: discountedCentavos == null
      ? null
      : Money.fromCentavos(discountedCentavos),
  orderType: orderType,
);

class _FakeProductRepository implements ProductRepository {
  Product? added;
  String? userId;

  @override
  Future<void> add(Product product, String userId) async {
    added = product;
    this.userId = userId;
  }

  @override
  Future<void> delete(String productId, String userId) async {}

  @override
  Future<List<Product>> getAll(String userId) async => <Product>[];

  @override
  Future<List<Product>> getDeleted(String userId) async => <Product>[];

  @override
  Future<void> hardDelete(String productId, String userId) async {}

  @override
  Future<void> restore(String productId, String userId) async {}

  @override
  Future<void> update(Product product) async {}

  @override
  Future<void> updateStock(String productId, int newQty) async {}
}
