import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/payment_method_model.dart';
import 'package:knz_scent_admin/services/accounting_service.dart';

import '../fixtures/accounting_fixture.dart';

void main() {
  final service = AccountingService.instance;
  final date = DateTime.utc(2026, 1, 1);

  Order order(String id, OrderStatus status, {PaymentMethod? paymentMethod}) =>
      Order(
        id: id,
        orderId: id,
        customerName: 'Customer',
        items: [
          OrderItem(
            id: 'item-$id',
            productId: 'product-1',
            productName: 'Scent',
            unitPrice: const Money.fromCentavos(9000),
            srpPrice: const Money.fromCentavos(10000),
            quantity: 1,
          ),
        ],
        totalAmount: const Money.fromCentavos(9000),
        status: status,
        orderDate: date,
        paymentMethod: paymentMethod,
      );

  test('cash basis recognizes delivered orders but not new credit sales', () {
    final orders = [
      order('delivered', OrderStatus.delivered),
      order('utang', OrderStatus.utang),
      order('pending', OrderStatus.pending),
      order('shipped', OrderStatus.shipped),
      order('cancelled', OrderStatus.cancelled),
    ];

    expect(service.recognizedSales(orders).length, 1);
    expect(service.grossSales(orders).centavos, 10000);
    expect(service.totalDiscounts(orders).centavos, 1000);
    expect(service.netSales(orders).centavos, 9000);
  });

  test('settled delivered credit stays excluded from order revenue', () {
    final settledCredit = order(
      'settled-utang',
      OrderStatus.delivered,
      paymentMethod: PaymentMethod.utang,
    );
    final collection = PaymentRecord(
      id: 'payment',
      amount: const Money.fromCentavos(9000),
      principalApplied: const Money.fromCentavos(9000),
      paidAt: date,
    );
    final debt = CustomerDebt(
      id: 'debt',
      customerName: 'Customer',
      orderId: settledCredit.orderId,
      principalOriginal: const Money.fromCentavos(9000),
      principalOutstanding: Money.zero,
      createdAt: date,
      payments: [collection],
    );

    expect(service.isRecognizedSale(settledCredit), isFalse);
    expect(service.netSales([settledCredit]), Money.zero);
    expect(service.debtCollections([debt]), const Money.fromCentavos(9000));
  });

  test(
    'filters debt collections by payment date and excludes legacy unknowns',
    () {
      final inRange = PaymentRecord(
        id: 'payment-in',
        amount: const Money.fromCentavos(2500),
        principalApplied: const Money.fromCentavos(2500),
        paidAt: DateTime.utc(2026, 2, 10),
      );
      final outside = PaymentRecord(
        id: 'payment-out',
        amount: const Money.fromCentavos(1000),
        principalApplied: const Money.fromCentavos(1000),
        paidAt: DateTime.utc(2026, 1, 10),
      );
      final debt = CustomerDebt(
        id: 'debt',
        customerName: 'Customer',
        orderId: 'KNZ-001',
        principalOriginal: const Money.fromCentavos(10000),
        principalOutstanding: const Money.fromCentavos(6500),
        createdAt: date,
        payments: [outside, inRange],
      );

      expect(
        service.debtCollections(
          [debt],
          from: DateTime.utc(2026, 2, 1),
          to: DateTime.utc(2026, 2, 28),
        ),
        const Money.fromCentavos(2500),
      );
      expect(service.debtCollections([debt]), const Money.fromCentavos(3500));
    },
  );

  test('fixed fixture produces hand-computed cash-basis totals', () {
    final fixture = AccountingFixture();
    final report = service.summarize(
      orders: fixture.orders,
      debts: fixture.debts,
      customOrders: fixture.customOrders,
      period: AccountingPeriod(from: fixture.periodFrom, to: fixture.periodTo),
    );

    expect(report.recognizedOrders.map((order) => order.id), [
      'paid',
      'reseller',
    ]);
    expect(report.grossSales, const Money.fromCentavos(40000));
    expect(report.discounts, const Money.fromCentavos(7000));
    expect(report.netSales, const Money.fromCentavos(33000));
    expect(report.debtCollections, const Money.fromCentavos(10000));
    expect(report.debtPrincipalCollections, const Money.fromCentavos(8000));
    expect(report.debtInterestCollections, const Money.fromCentavos(2000));
    expect(report.customOrderReceipts, const Money.fromCentavos(12000));
    expect(report.cashReceived, const Money.fromCentavos(55000));
    expect(report.receivablesPrincipal, const Money.fromCentavos(22000));
    expect(report.receivablesInterest, const Money.fromCentavos(3000));
    expect(report.receivables, const Money.fromCentavos(25000));
    expect(report.itemsSold, 3);
    expect(
      report.resellerSummaries.single.netRevenue,
      const Money.fromCentavos(15000),
    );
  });

  test('date range includes both day boundaries and excludes the next day', () {
    final fixture = AccountingFixture();
    final report = service.summarize(
      orders: fixture.orders,
      debts: fixture.debts,
      customOrders: fixture.customOrders,
      period: AccountingPeriod(from: fixture.periodFrom, to: fixture.periodTo),
    );

    expect(report.recognizedOrders.length, 2);
    expect(report.customOrderPayments.length, 2);
    expect(report.customOrderPayments.map((row) => row.payment.id), [
      'custom-initial',
      'custom-later',
    ]);
  });

  test('legacy aggregate custom money is all-time only', () {
    final legacy = CustomOrder(
      id: 'legacy',
      customerName: 'Legacy Customer',
      fragranceSpecs: 'Legacy scent',
      agreedPrice: const Money.fromCentavos(10000),
      depositPaid: const Money.fromCentavos(2500),
      deliveryDate: DateTime.utc(2026, 6, 1),
      userId: 'owner',
      createdAt: date,
    );

    final allTime = service.summarize(
      orders: const [],
      debts: const [],
      customOrders: [legacy],
    );
    final bounded = service.summarize(
      orders: const [],
      debts: const [],
      customOrders: [legacy],
      period: AccountingPeriod(from: date, to: date),
    );

    expect(allTime.customOrderReceipts, const Money.fromCentavos(2500));
    expect(allTime.legacyCustomOrderReceipts, const Money.fromCentavos(2500));
    expect(bounded.customOrderReceipts, Money.zero);
  });
}
