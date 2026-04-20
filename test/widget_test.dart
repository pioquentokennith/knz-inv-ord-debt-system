// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
// In-memory stubs — no SQLite / Firestore
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final uuid = const Uuid();


  // ══════════════════════════════════════════════════════════════════════════
  // PRODUCT MODEL
  // ══════════════════════════════════════════════════════════════════════════
  group('Product Model', () {
    Product makeProduct({int stock = 5, int min = 3}) => Product(
      id: uuid.v4(), name: 'Test EDP', description: '',
      category: ProductCategory.eauDeParfum,
      price: 1299, stockQty: stock, minStockLevel: min,
    );

    test('isLowStock true when stockQty <= minStockLevel', () {
      expect(makeProduct(stock: 2, min: 5).isLowStock, isTrue);
    });

    test('isLowStock false when stockQty > minStockLevel', () {
      expect(makeProduct(stock: 10, min: 5).isLowStock, isFalse);
    });

    test('isLowStock true when equal (boundary)', () {
      expect(makeProduct(stock: 5, min: 5).isLowStock, isTrue);
    });

    test('stockQty setter rejects negative values', () {
      final p = makeProduct();
      expect(() => p.stockQty = -1, throwsArgumentError);
    });

    test('stockQty setter accepts zero', () {
      final p = makeProduct();
      p.stockQty = 0;
      expect(p.stockQty, 0);
    });

    test('copyWith preserves unmodified fields', () {
      final p = makeProduct(stock: 20);
      final copy = p.copyWith(stockQty: 15);
      expect(copy.name, 'Test EDP');
      expect(copy.price, 1299);
      expect(copy.stockQty, 15);
    });

    test('toMap / fromMap round-trip', () {
      final p = makeProduct(stock: 8, min: 3);
      final back = Product.fromMap(p.toMap());
      expect(back.name, p.name);
      expect(back.price, p.price);
      expect(back.stockQty, p.stockQty);
      expect(back.category, p.category);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // ORDER MODEL
  // ══════════════════════════════════════════════════════════════════════════
  group('Order Model', () {
    OrderItem makeItem({double price = 500, int qty = 2}) => OrderItem(
      id: uuid.v4(), productId: uuid.v4(),
      productName: 'Test Item', unitPrice: price, quantity: qty,
    );

    test('OrderItem subtotal = unitPrice x quantity', () {
      expect(makeItem(price: 500, qty: 3).subtotal, 1500.0);
    });

    test('Order.quantity sums all item quantities', () {
      final o = Order(
        id: uuid.v4(), orderId: 'KNZ-001', customerName: 'Ana',
        items: [makeItem(qty: 2), makeItem(qty: 3)],
        totalAmount: 2500, status: OrderStatus.pending, orderDate: DateTime.now(),
      );
      expect(o.quantity, 5);
    });

    test('productName shows just name for single item', () {
      final o = Order(
        id: uuid.v4(), orderId: 'KNZ-002', customerName: 'Ben',
        items: [makeItem()],
        totalAmount: 1000, status: OrderStatus.pending, orderDate: DateTime.now(),
      );
      expect(o.productName, 'Test Item');
    });

    test('productName shows +N more for multiple items', () {
      final o = Order(
        id: uuid.v4(), orderId: 'KNZ-003', customerName: 'Cath',
        items: [makeItem(), makeItem(), makeItem()],
        totalAmount: 3000, status: OrderStatus.pending, orderDate: DateTime.now(),
      );
      expect(o.productName, contains('+2 more'));
    });

    test('OrderStatus.fromString parses case-insensitively', () {
      expect(OrderStatusExtension.fromString('delivered'), OrderStatus.delivered);
      expect(OrderStatusExtension.fromString('Cancelled'), OrderStatus.cancelled);
      expect(OrderStatusExtension.fromString('UTANG'),     OrderStatus.utang);
    });

    test('items list is unmodifiable', () {
      final o = Order(
        id: uuid.v4(), orderId: 'KNZ-004', customerName: 'D',
        items: [makeItem()], totalAmount: 500,
        status: OrderStatus.pending, orderDate: DateTime.now(),
      );
      expect(() => (o.items as List).add(makeItem()), throwsUnsupportedError);
    });

    test('copyWith updates only specified field', () {
      final o = Order(
        id: uuid.v4(), orderId: 'KNZ-005', customerName: 'E',
        items: [], totalAmount: 0,
        status: OrderStatus.pending, orderDate: DateTime.now(),
      );
      final updated = o.copyWith(status: OrderStatus.delivered);
      expect(updated.status,       OrderStatus.delivered);
      expect(updated.customerName, 'E');
    });

    test('every OrderStatus has non-empty displayName', () {
      for (final s in OrderStatus.values) {
        expect(s.displayName.isNotEmpty, isTrue,
            reason: '$s has empty displayName');
      }
    });

    test('every OrderStatus has a non-transparent color', () {
      for (final s in OrderStatus.values) {
        expect((s.color.a * 255.0).round().clamp(0, 255) > 0, isTrue,
            reason: '$s color is transparent');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // DEBT MODEL
  // ══════════════════════════════════════════════════════════════════════════
  group('Debt Model', () {
    CustomerDebt makeDebt({
      double total = 2000,
      double paid  = 0,
      int daysOld  = 0,
    }) =>
        CustomerDebt(
          id: uuid.v4(), customerName: 'Test Customer', orderId: uuid.v4(),
          totalAmount: total, amountPaid: paid,
          createdAt: DateTime.now().subtract(Duration(days: daysOld)),
        );

    test('remainingBalance = totalAmount - amountPaid', () {
      expect(makeDebt(total: 2000, paid: 800).remainingBalance, 1200.0);
    });

    test('isPaid true when fully settled', () {
      expect(makeDebt(total: 1000, paid: 1000).isPaid, isTrue);
    });

    test('isPaid false when partial', () {
      expect(makeDebt(total: 1000, paid: 500).isPaid, isFalse);
    });

    test('isOverdue true after 7+ days unpaid', () {
      expect(makeDebt(total: 1000, paid: 0, daysOld: 8).isOverdue, isTrue);
    });

    test('isOverdue false before 7 days', () {
      expect(makeDebt(total: 1000, paid: 0, daysOld: 3).isOverdue, isFalse);
    });

    test('isOverdue false when fully paid even if old', () {
      expect(makeDebt(total: 1000, paid: 1000, daysOld: 30).isOverdue, isFalse);
    });

    test('amountPaid setter rejects negative values', () {
      final d = makeDebt();
      expect(() => d.amountPaid = -1, throwsArgumentError);
    });

    test('payments list is unmodifiable', () {
      final d = makeDebt();
      expect(
        () => (d.payments as List).add(
          PaymentRecord(id: uuid.v4(), amount: 100, paidAt: DateTime.now()),
        ),
        throwsUnsupportedError,
      );
    });

    test('toMap / fromMap round-trip', () {
      final d = makeDebt(total: 1500, paid: 200);
      final back = CustomerDebt.fromMap(d.toMap());
      expect(back.customerName,   d.customerName);
      expect(back.totalAmount,    d.totalAmount);
      expect(back.amountPaid,     d.amountPaid);
      expect(back.remainingBalance, 1300);
    });

    test('daysOld reflects age correctly', () {
      final d = makeDebt(daysOld: 5);
      expect(d.daysOld, greaterThanOrEqualTo(5));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // PAYMENT RECORD MODEL
  // ══════════════════════════════════════════════════════════════════════════
  group('PaymentRecord Model', () {
    test('toMap / fromMap round-trip preserves all fields', () {
      final p = PaymentRecord(
        id: uuid.v4(), amount: 350.0,
        paidAt: DateTime(2025, 4, 1), note: 'partial',
      );
      final back = PaymentRecord.fromMap(p.toMap());
      expect(back.amount, p.amount);
      expect(back.note,   p.note);
    });
  });
}
