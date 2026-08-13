import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';
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

  BusinessEvent event(
    String id,
    String orderId,
    BusinessEventType type, {
    int? amount,
    String? relatedEventId,
    String? reason,
    DateTime? occurredAt,
  }) => BusinessEvent(
    id: id,
    userId: 'owner',
    subject: BusinessEventSubject.order,
    subjectId: orderId,
    type: type,
    amount: amount == null ? null : Money.fromCentavos(amount),
    occurredAt: occurredAt ?? date,
    recordedAt: occurredAt ?? date,
    paymentMethod: type == BusinessEventType.payment
        ? PaymentMethod.cashOnDelivery.storageKey
        : null,
    relatedEventId: relatedEventId,
    reason: reason,
    commandId: id,
  );

  test('delivery events recognize sales without implying payment', () {
    final orders = [
      order('delivered', OrderStatus.delivered),
      order('utang', OrderStatus.utang),
      order('pending', OrderStatus.pending),
      order('shipped', OrderStatus.shipped),
      order('cancelled', OrderStatus.cancelled),
    ];

    final events = [
      event('delivery-event', 'delivered', BusinessEventType.delivery),
    ];

    expect(service.recognizedSales(orders, events).length, 1);
    final report = service.summarize(
      orders: orders,
      debts: const [],
      businessEvents: events,
    );
    expect(report.grossSales.centavos, 10000);
    expect(report.discounts.centavos, 1000);
    expect(report.netSales.centavos, 9000);
    expect(report.cashReceived, Money.zero);
  });

  test('canonical order headers reconcile gross, discount, and net', () {
    final discounted = Order(
      id: 'discounted',
      orderId: 'KNZ-001',
      customerName: 'Customer',
      items: [
        OrderItem(
          id: 'item-discounted',
          productId: 'product-1',
          productName: 'Scent',
          unitPrice: const Money.fromCentavos(17000),
          srpPrice: const Money.fromCentavos(20000),
          quantity: 2,
        ),
      ],
      totalAmount: const Money.fromCentavos(34000),
      srpTotal: const Money.fromCentavos(40000),
      status: OrderStatus.delivered,
      orderDate: date,
      paymentMethod: PaymentMethod.cashOnDelivery,
    );

    final report = service.summarize(
      orders: [discounted],
      debts: const [],
      businessEvents: [
        event('discounted-delivery', discounted.id, BusinessEventType.delivery),
      ],
    );

    expect(report.grossSales, const Money.fromCentavos(40000));
    expect(report.discounts, const Money.fromCentavos(6000));
    expect(report.netSales, const Money.fromCentavos(34000));
    expect(report.grossSales - report.discounts, report.netSales);
  });

  test('delivered credit is sold once and collected only through debt', () {
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

    final events = [
      event('credit-delivery', settledCredit.id, BusinessEventType.delivery),
    ];
    expect(service.isRecognizedSale(settledCredit, events), isTrue);
    final report = service.summarize(
      orders: [settledCredit],
      debts: [debt],
      businessEvents: events,
    );
    expect(report.netSales, const Money.fromCentavos(9000));
    expect(report.netOrderCash, Money.zero);
    expect(report.debtCollections, const Money.fromCentavos(9000));
    expect(report.cashReceived, const Money.fromCentavos(9000));
  });

  test('payments refunds and reversals produce signed order cash', () {
    final paidOrder = order('event-order', OrderStatus.delivered);
    final events = [
      event('delivery', paidOrder.id, BusinessEventType.delivery),
      event('payment', paidOrder.id, BusinessEventType.payment, amount: 9000),
      event(
        'refund',
        paidOrder.id,
        BusinessEventType.refund,
        amount: 2000,
        reason: 'Returned item',
      ),
      event(
        'refund-reversal',
        paidOrder.id,
        BusinessEventType.reversal,
        amount: 2000,
        relatedEventId: 'refund',
        reason: 'Refund entered in error',
      ),
    ];

    final report = service.summarize(
      orders: [paidOrder],
      debts: const [],
      businessEvents: events,
    );

    expect(report.orderPayments, const Money.fromCentavos(9000));
    expect(report.orderRefunds, const Money.fromCentavos(2000));
    expect(report.orderReversalEffect, const Money.fromCentavos(2000));
    expect(report.netOrderCash, const Money.fromCentavos(9000));
    expect(report.cashReceived, const Money.fromCentavos(9000));
  });

  test('collection events replace projections without double counting', () {
    final payment = PaymentRecord(
      id: 'debt-payment',
      amount: const Money.fromCentavos(2500),
      principalApplied: const Money.fromCentavos(2500),
      paidAt: date,
    );
    final debt = CustomerDebt(
      id: 'debt',
      customerName: 'Customer',
      orderId: 'KNZ-001',
      principalOriginal: const Money.fromCentavos(5000),
      principalOutstanding: const Money.fromCentavos(2500),
      createdAt: date,
      payments: [payment],
    );
    final collection = BusinessEvent(
      id: 'debt-collection',
      userId: 'owner',
      subject: BusinessEventSubject.debt,
      subjectId: debt.id,
      type: BusinessEventType.collection,
      amount: payment.amount,
      occurredAt: payment.paidAt,
      recordedAt: payment.paidAt,
      commandId: 'debt-collection',
      sourceType: 'debt_payment',
      sourceId: payment.id,
    );

    final report = service.summarize(
      orders: const [],
      debts: [debt],
      businessEvents: [collection],
    );

    expect(report.debtCollections, const Money.fromCentavos(2500));
    expect(report.cashReceived, const Money.fromCentavos(2500));
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
      businessEvents: fixture.businessEvents,
      period: AccountingPeriod(from: fixture.periodFrom, to: fixture.periodTo),
    );

    expect(report.recognizedOrders.map((order) => order.id), [
      'paid',
      'reseller',
      'utang',
    ]);
    expect(report.grossSales, const Money.fromCentavos(70000));
    expect(report.discounts, const Money.fromCentavos(7000));
    expect(report.netSales, const Money.fromCentavos(63000));
    expect(report.orderPayments, const Money.fromCentavos(33000));
    expect(report.debtCollections, const Money.fromCentavos(10000));
    expect(report.debtPrincipalCollections, const Money.fromCentavos(8000));
    expect(report.debtInterestCollections, const Money.fromCentavos(2000));
    expect(report.customOrderReceipts, const Money.fromCentavos(12000));
    expect(report.cashReceived, const Money.fromCentavos(55000));
    expect(report.receivablesPrincipal, const Money.fromCentavos(22000));
    expect(report.receivablesInterest, const Money.fromCentavos(3000));
    expect(report.receivables, const Money.fromCentavos(25000));
    expect(report.itemsSold, 4);
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
      businessEvents: fixture.businessEvents,
      period: AccountingPeriod(from: fixture.periodFrom, to: fixture.periodTo),
    );

    expect(report.recognizedOrders.length, 3);
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
