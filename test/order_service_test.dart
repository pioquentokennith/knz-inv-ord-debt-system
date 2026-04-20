// ─────────────────────────────────────────────────────────────────────────────
// order_service_test.dart — Integration tests for OrderService
//
// Coverage:
//   ✔ createOrder — order persisted, stock deducted per item
//   ✔ createOrder — stock never goes negative (clamped to 0)
//   ✔ createOrder — unknown product in order.items is skipped gracefully
//   ✔ generateOrderId — sequential IDs with zero-padding
//   ✔ updateStatus — status change propagates to stored order
//   ✔ deleteOrder — soft-delete moves order to deleted bucket
//   ✔ getDeleted / restoreOrder / hardDeleteOrder — full recycle-bin cycle
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'stubs/stub_product_repository.dart';
import 'stubs/stub_order_repository.dart';
import 'stubs/stub_services.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Product _product({
  String id      = 'prod-1',
  String name    = 'Noir Intense',
  int stockQty   = 20,
}) =>
    Product(
      id:            id,
      name:          name,
      description:   '',
      category:      ProductCategory.eauDeParfum,
      price:         1299.0,
      stockQty:      stockQty,
      minStockLevel: 5,
    );

Order _order({
  String orderId       = 'KNZ-001',
  String customerId    = 'o-uuid-1',
  String customerName  = 'Ana Reyes',
  String productId     = 'prod-1',
  String productName   = 'Noir Intense',
  int    quantity      = 3,
  double unitPrice     = 1299.0,
}) =>
    Order(
      id:           customerId,
      orderId:      orderId,
      customerName: customerName,
      items: [
        OrderItem(
          id:          'item-1',
          productId:   productId,
          productName: productName,
          unitPrice:   unitPrice,
          quantity:    quantity,
        ),
      ],
      totalAmount:  unitPrice * quantity,
      status:       OrderStatus.pending,
      orderDate:    DateTime(2025, 6, 1),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late StubProductRepository productRepo;
  late StubOrderRepository   orderRepo;
  late StubOrderService      service;

  setUp(() {
    productRepo = StubProductRepository();
    orderRepo   = StubOrderRepository();
    service     = StubOrderService(orderRepo, productRepo);
  });

  group('OrderService — createOrder()', () {
    test('persists order to repo', () async {
      final product = _product();
      productRepo.seed(product);

      await service.createOrder(_order(), 'u1', [product]);

      expect(orderRepo.count, 1);
    });

    test('deducts stock for each ordered item', () async {
      final product = _product(stockQty: 20);
      productRepo.seed(product);

      await service.createOrder(_order(quantity: 3), 'u1', [product]);

      // stockQty should now be 20 - 3 = 17
      expect(productRepo.store['prod-1']!.stockQty, 17);
    });

    test('stock is clamped to 0 when order qty exceeds available stock', () async {
      final product = _product(stockQty: 2); // only 2 in stock
      productRepo.seed(product);

      await service.createOrder(_order(quantity: 10), 'u1', [product]);

      expect(productRepo.store['prod-1']!.stockQty, 0,
          reason: 'Clamp prevents negative stock');
    });

    test('unknown product in order items is skipped — no crash', () async {
      final product = _product();
      productRepo.seed(product);

      // orderId references a product NOT in productRepo
      final unknownItem = Order(
        id:           'o-uuid-99',
        orderId:      'KNZ-099',
        customerName: 'Ghost Customer',
        items: [
          OrderItem(
            id:          'item-x',
            productId:   'does-not-exist',
            productName: 'Phantom Scent',
            unitPrice:   500.0,
            quantity:    1,
          ),
        ],
        totalAmount:  500.0,
        status:       OrderStatus.pending,
        orderDate:    DateTime.now(),
      );

      // Should complete without throwing
      await service.createOrder(unknownItem, 'u1', [product]);

      expect(orderRepo.count, 1);
      expect(productRepo.store['prod-1']!.stockQty, 20,
          reason: 'Stock for known product must be untouched');
    });
  });

  group('OrderService — generateOrderId()', () {
    test('generates KNZ-001 for empty repo', () async {
      final id = await service.generateOrderId('u1');
      expect(id, 'KNZ-001');
    });

    test('increments to KNZ-002 after one order exists', () async {
      final product = _product();
      productRepo.seed(product);
      await service.createOrder(_order(), 'u1', [product]);

      final id = await service.generateOrderId('u1');
      expect(id, 'KNZ-002');
    });
  });

  group('OrderService — updateStatus()', () {
    test('status change is reflected in the stored order', () async {
      final product = _product();
      productRepo.seed(product);
      await service.createOrder(_order(customerId: 'o-1'), 'u1', [product]);

      await service.updateStatus('o-1', OrderStatus.delivered);

      expect(orderRepo.store['o-1']!.status, OrderStatus.delivered);
    });
  });

  group('OrderService — Recycle Bin', () {
    test('deleteOrder soft-deletes: active count drops, deleted count rises', () async {
      final product = _product();
      productRepo.seed(product);
      await service.createOrder(_order(customerId: 'o-soft'), 'u1', [product]);

      await service.deleteOrder('o-soft');

      expect(orderRepo.count, 0);
      expect(orderRepo.deletedCount, 1);
    });

    test('getDeleted returns the soft-deleted order', () async {
      final product = _product();
      productRepo.seed(product);
      await service.createOrder(_order(customerId: 'o-soft'), 'u1', [product]);
      await service.deleteOrder('o-soft');

      final deleted = await service.getDeleted('u1');

      expect(deleted.length, 1);
      expect(deleted.first.id, 'o-soft');
    });

    test('restoreOrder moves order back to active', () async {
      final product = _product();
      productRepo.seed(product);
      await service.createOrder(_order(customerId: 'o-soft'), 'u1', [product]);
      await service.deleteOrder('o-soft');

      await service.restoreOrder('o-soft');

      expect(orderRepo.count, 1);
      expect(orderRepo.deletedCount, 0);
    });

    test('hardDeleteOrder purges order permanently', () async {
      final product = _product();
      productRepo.seed(product);
      await service.createOrder(_order(customerId: 'o-hard'), 'u1', [product]);
      await service.deleteOrder('o-hard');

      await service.hardDeleteOrder('o-hard');

      expect(orderRepo.count, 0);
      expect(orderRepo.deletedCount, 0);
    });
  });
}
