import '../core/money.dart';
import '../dto/order_dto.dart';
import '../models/custom_order_model.dart';
import '../models/debt_model.dart';
import '../models/business_event_model.dart';
import '../models/order_model.dart';
import '../models/reseller_accounting_summary.dart';

class AccountingPeriod {
  const AccountingPeriod({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  bool get isBounded => from != null || to != null;

  bool contains(DateTime timestamp) {
    if (from != null && timestamp.isBefore(from!)) return false;
    final end = to;
    if (end == null) return true;
    final endExclusive = end.isUtc
        ? DateTime.utc(end.year, end.month, end.day + 1)
        : DateTime(end.year, end.month, end.day + 1);
    return timestamp.isBefore(endExclusive);
  }
}

class OrderFinancialBreakdown {
  const OrderFinancialBreakdown({
    required this.srpTotal,
    required this.discount,
    required this.customerPayTotal,
  });

  final Money srpTotal;
  final Money discount;
  final Money customerPayTotal;
}

class DebtCollectionRow {
  const DebtCollectionRow({required this.debt, required this.payment});

  final CustomerDebt debt;
  final PaymentRecord payment;
}

class CustomOrderCollectionRow {
  const CustomOrderCollectionRow({required this.order, required this.payment});

  final CustomOrder order;
  final CustomOrderPayment payment;
}

class OrderCashEventRow {
  const OrderCashEventRow({
    required this.order,
    required this.event,
    required this.cashEffect,
  });

  final Order order;
  final BusinessEvent event;
  final Money cashEffect;
}

class AccountingReport {
  AccountingReport({
    required Iterable<Order> recognizedOrders,
    required Iterable<DebtCollectionRow> debtPayments,
    required Iterable<CustomOrderCollectionRow> customOrderPayments,
    required Iterable<OrderCashEventRow> orderCashEvents,
    required this.legacyCustomOrderReceipts,
    required this.grossSales,
    required this.discounts,
    required this.netSales,
    required this.debtCollections,
    required this.debtPrincipalCollections,
    required this.debtInterestCollections,
    required this.customOrderReceipts,
    required this.orderPayments,
    required this.orderRefunds,
    required this.orderReversalEffect,
    required this.netOrderCash,
    required this.receivablesPrincipal,
    required this.receivablesInterest,
    required Iterable<ResellerAccountingSummary> resellerSummaries,
  }) : recognizedOrders = List.unmodifiable(recognizedOrders),
       debtPayments = List.unmodifiable(debtPayments),
       customOrderPayments = List.unmodifiable(customOrderPayments),
       orderCashEvents = List.unmodifiable(orderCashEvents),
       resellerSummaries = List.unmodifiable(resellerSummaries);

  final List<Order> recognizedOrders;
  final List<DebtCollectionRow> debtPayments;
  final List<CustomOrderCollectionRow> customOrderPayments;
  final List<OrderCashEventRow> orderCashEvents;
  final Money legacyCustomOrderReceipts;
  final Money grossSales;
  final Money discounts;
  final Money netSales;
  final Money debtCollections;
  final Money debtPrincipalCollections;
  final Money debtInterestCollections;
  final Money customOrderReceipts;
  final Money orderPayments;
  final Money orderRefunds;
  final Money orderReversalEffect;
  final Money netOrderCash;
  final Money receivablesPrincipal;
  final Money receivablesInterest;
  final List<ResellerAccountingSummary> resellerSummaries;

  Money get cashReceived =>
      netOrderCash + debtCollections + customOrderReceipts;
  Money get receivables => receivablesPrincipal + receivablesInterest;
  int get itemsSold =>
      recognizedOrders.fold(0, (sum, order) => sum + order.quantity);

  Money debtCollectionsFor(String debtId) => debtPayments
      .where((row) => row.debt.id == debtId)
      .fold(Money.zero, (sum, row) => sum + row.payment.amount);
}

/// Event-based fulfillment and cash calculations shared by UI and exports.
class AccountingService {
  AccountingService._();
  static final AccountingService instance = AccountingService._();

  AccountingReport summarize({
    required Iterable<Order> orders,
    required Iterable<CustomerDebt> debts,
    Iterable<CustomOrder> customOrders = const [],
    Iterable<BusinessEvent> businessEvents = const [],
    AccountingPeriod period = const AccountingPeriod(),
  }) {
    final orderList = orders.toList(growable: false);
    final orderById = {for (final order in orderList) order.id: order};
    final eventList = businessEvents.toList(growable: false);
    final eventById = {for (final event in eventList) event.id: event};
    final deliveredOrderIds = eventList
        .where(
          (event) =>
              event.subject == BusinessEventSubject.order &&
              event.type == BusinessEventType.delivery &&
              event.occurredAt != null &&
              period.contains(event.occurredAt!),
        )
        .map((event) => event.subjectId)
        .toSet();
    final recognized = orderList
        .where((order) => deliveredOrderIds.contains(order.id))
        .toList(growable: false);

    final orderCashRows = <OrderCashEventRow>[];
    var orderPayments = Money.zero;
    var orderRefunds = Money.zero;
    var orderReversalEffect = Money.zero;
    var netOrderCash = Money.zero;
    for (final event in eventList) {
      if (event.subject != BusinessEventSubject.order || !event.isFinancial) {
        continue;
      }
      final occurredAt = event.occurredAt;
      if (occurredAt == null) {
        if (period.isBounded) continue;
      } else if (!period.contains(occurredAt)) {
        continue;
      }
      final effect = BusinessEventLedger.cashEffect(event, eventById);
      netOrderCash += effect;
      if (event.type == BusinessEventType.payment) {
        orderPayments += event.amount!;
      } else if (event.type == BusinessEventType.refund) {
        orderRefunds += event.amount!;
      } else if (event.type == BusinessEventType.reversal) {
        orderReversalEffect += effect;
      }
      final order = orderById[event.subjectId];
      if (order != null) {
        orderCashRows.add(
          OrderCashEventRow(order: order, event: event, cashEffect: effect),
        );
      }
    }
    final debtRows = <DebtCollectionRow>[];
    var debtCollections = Money.zero;
    var debtPrincipal = Money.zero;
    var debtInterest = Money.zero;
    var receivablesPrincipal = Money.zero;
    var receivablesInterest = Money.zero;

    for (final debt in debts) {
      receivablesPrincipal += debt.principalOutstanding;
      receivablesInterest += debt.interestOutstanding;
      for (final payment in debt.payments) {
        if (!period.contains(payment.paidAt)) continue;
        debtRows.add(DebtCollectionRow(debt: debt, payment: payment));
        debtCollections += payment.amount;
        debtPrincipal += payment.principalApplied;
        debtInterest += payment.interestApplied;
      }
    }
    final debtCollectionEvents = eventList.where(
      (event) =>
          event.subject == BusinessEventSubject.debt &&
          event.type == BusinessEventType.collection,
    );
    if (debtCollectionEvents.isNotEmpty) {
      debtCollections = debtCollectionEvents
          .where((event) => _eventInPeriod(event, period))
          .fold(Money.zero, (sum, event) => sum + event.amount!);
    }

    final customRows = <CustomOrderCollectionRow>[];
    var customReceipts = Money.zero;
    var legacyCustomReceipts = Money.zero;
    for (final order in customOrders) {
      // Legacy aggregate money remains visible all-time, but no timestamp is
      // invented for bounded reports.
      if (!period.isBounded && order.unattributedPaymentAmount.isPositive) {
        customReceipts += order.unattributedPaymentAmount;
        legacyCustomReceipts += order.unattributedPaymentAmount;
      }
      for (final payment in order.payments) {
        if (!period.contains(payment.paidAt)) continue;
        customRows.add(
          CustomOrderCollectionRow(order: order, payment: payment),
        );
        customReceipts += payment.amount;
      }
    }
    final customCollectionEvents = eventList.where(
      (event) =>
          event.subject == BusinessEventSubject.customOrder &&
          event.type == BusinessEventType.collection,
    );
    if (customCollectionEvents.isNotEmpty) {
      customReceipts = customCollectionEvents
          .where((event) => _eventInPeriod(event, period))
          .fold(Money.zero, (sum, event) => sum + event.amount!);
      legacyCustomReceipts = customCollectionEvents
          .where(
            (event) =>
                event.provenance == BusinessEventProvenance.legacyUnknown &&
                _eventInPeriod(event, period),
          )
          .fold(Money.zero, (sum, event) => sum + event.amount!);
    }

    for (final order in recognized) {
      OrderDto.validateDomain(order);
    }
    final gross = recognized.fold(
      Money.zero,
      (sum, order) => sum + order.srpTotal,
    );
    final discounts = recognized.fold(
      Money.zero,
      (sum, order) => sum + order.totalDiscountAmount,
    );
    final net = recognized.fold(
      Money.zero,
      (sum, order) => sum + order.customerPayAmount,
    );

    return AccountingReport(
      recognizedOrders: recognized,
      debtPayments: debtRows,
      customOrderPayments: customRows,
      orderCashEvents: orderCashRows,
      legacyCustomOrderReceipts: legacyCustomReceipts,
      grossSales: gross,
      discounts: discounts,
      netSales: net,
      debtCollections: debtCollections,
      debtPrincipalCollections: debtPrincipal,
      debtInterestCollections: debtInterest,
      customOrderReceipts: customReceipts,
      orderPayments: orderPayments,
      orderRefunds: orderRefunds,
      orderReversalEffect: orderReversalEffect,
      netOrderCash: netOrderCash,
      receivablesPrincipal: receivablesPrincipal,
      receivablesInterest: receivablesInterest,
      resellerSummaries: _resellerSummary(recognized),
    );
  }

  OrderFinancialBreakdown orderBreakdown(Order order) =>
      OrderFinancialBreakdown(
        srpTotal: order.srpTotal,
        discount: order.totalDiscountAmount,
        customerPayTotal: order.customerPayAmount,
      );

  Money grossSales(
    List<Order> orders, {
    Iterable<BusinessEvent> businessEvents = const [],
  }) => summarize(
    orders: orders,
    debts: const [],
    businessEvents: businessEvents,
  ).grossSales;
  Money totalDiscounts(
    List<Order> orders, {
    Iterable<BusinessEvent> businessEvents = const [],
  }) => summarize(
    orders: orders,
    debts: const [],
    businessEvents: businessEvents,
  ).discounts;
  Money netSales(
    List<Order> orders, {
    Iterable<BusinessEvent> businessEvents = const [],
  }) => summarize(
    orders: orders,
    debts: const [],
    businessEvents: businessEvents,
  ).netSales;
  Money customizedOrderRevenue(
    List<Order> orders, {
    Iterable<BusinessEvent> businessEvents = const [],
  }) => summarize(
    orders: orders.where((order) => order.orderType == 'customized'),
    debts: const [],
    businessEvents: businessEvents,
  ).netSales;

  Money debtCollections(
    Iterable<CustomerDebt> debts, {
    DateTime? from,
    DateTime? to,
  }) => summarize(
    orders: const [],
    debts: debts,
    period: AccountingPeriod(from: from, to: to),
  ).debtCollections;

  List<ResellerAccountingSummary> resellerSummary(
    List<Order> orders, {
    Iterable<BusinessEvent> businessEvents = const [],
  }) => _resellerSummary(recognizedSales(orders, businessEvents));

  List<Order> filterByDateRange(
    List<Order> orders, {
    DateTime? from,
    DateTime? to,
  }) {
    final period = AccountingPeriod(from: from, to: to);
    return orders.where((order) => period.contains(order.orderDate)).toList();
  }

  bool isRecognizedSale(Order order, Iterable<BusinessEvent> businessEvents) =>
      businessEvents.any(
        (event) =>
            event.subject == BusinessEventSubject.order &&
            event.subjectId == order.id &&
            event.type == BusinessEventType.delivery,
      );

  List<Order> recognizedSales(
    Iterable<Order> orders,
    Iterable<BusinessEvent> businessEvents,
  ) => orders
      .where((order) => isRecognizedSale(order, businessEvents))
      .toList(growable: false);

  List<ResellerAccountingSummary> _resellerSummary(Iterable<Order> orders) {
    final byReseller = <String, List<Order>>{};
    for (final order in orders) {
      if (!order.isReseller) continue;
      byReseller.putIfAbsent(order.customerName, () => []).add(order);
    }
    return byReseller.entries.map((entry) {
      final resellerOrders = entry.value;
      final gross = resellerOrders.fold(
        Money.zero,
        (sum, order) => sum + order.srpTotal,
      );
      final discount = resellerOrders.fold(
        Money.zero,
        (sum, order) => sum + order.totalDiscountAmount,
      );
      final net = resellerOrders.fold(
        Money.zero,
        (sum, order) => sum + order.customerPayAmount,
      );
      final units = resellerOrders.fold(
        0,
        (sum, order) => sum + order.quantity,
      );
      return ResellerAccountingSummary(
        resellerName: entry.key,
        totalOrders: resellerOrders.length,
        grossSales: gross,
        totalDiscount: discount,
        netRevenue: net,
        averageDeduction: units == 0 ? Money.zero : discount.divide(units),
      );
    }).toList()..sort((a, b) => b.netRevenue.compareTo(a.netRevenue));
  }

  bool _eventInPeriod(BusinessEvent event, AccountingPeriod period) {
    final occurredAt = event.occurredAt;
    return occurredAt == null ? !period.isBounded : period.contains(occurredAt);
  }
}
