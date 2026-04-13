import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Inayos ang package name base sa iyong pubspec.yaml
import 'package:knz_scent_admin/main.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:uuid/uuid.dart';

void main() {
  final uuid = const Uuid();

  // ── App smoke test ────────────────────────────────────────────────────────
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Siguraduhin na KnzScentApp ang tawag sa root widget mo sa main.dart
    await tester.pumpWidget(const KnzScentApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  // ── Product model tests (No hardcoded data) ───────────────────────────────
  group('Product Logic', () {
    test('isLowStock returns true when stock is below threshold', () {
      final product = Product(
        id: uuid.v4(),
        name: 'Dynamic Product',
        description: '',
        category: ProductCategory.eauDeParfum,
        price: 0.0,
        stockQty: 2,
        minStockLevel: 5,
      );
      expect(product.isLowStock, isTrue);
    });
  });

  // ── Order model tests ─────────────────────────────────────────────────────
  group('Order Logic', () {
    test('Calculates order item subtotal correctly', () {
      final item = OrderItem(
        id: uuid.v4(),
        productId: uuid.v4(),
        productName: 'Test Item',
        unitPrice: 500.0,
        quantity: 3,
      );
      expect(item.subtotal, 1500.0);
    });
  });

  // ── CustomerDebt model tests ──────────────────────────────────────────────
  group('Debt Logic', () {
    test('Calculates remaining balance accurately', () {
      final debt = CustomerDebt(
        id: uuid.v4(),
        customerName: 'Test Customer',
        orderId: uuid.v4(),
        totalAmount: 2000.0,
        amountPaid: 800.0,
        createdAt: DateTime.now(),
      );
      expect(debt.remainingBalance, 1200.0);
    });
  });
}