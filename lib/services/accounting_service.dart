import '../core/money.dart';
import '../models/custom_order_model.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../models/payment_method_model.dart';
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

class AccountingReport {
  AccountingReport({
    required Iterable<Order> recognizedOrders,
    required Iterable<DebtCollectionRow> debtPayments,
    required Iterable<CustomOrderCollectionRow> customOrderPayments,
    required this.legacyCustomOrderReceipts,
    required this.grossSales,
    required this.discounts,
    required this.netSales,
    required this.debtCollections,
    required this.debtPrincipalCollections,
    required this.debtInterestCollections,
    required this.customOrderReceipts,
    required this.receivablesPrincipal,
    required this.receivablesInterest,
    required Iterable<ResellerAccountingSummary> resellerSummaries,
  }) : recognizedOrders = List.unmodifiable(recognizedOrders),
       debtPayments = List.unmodifiable(debtPayments),
       customOrderPayments = List.unmodifiable(customOrderPayments),
       resellerSummaries = List.unmodifiable(resellerSummaries);

  final List<Order> recognizedOrders;
  final List<DebtCollectionRow> debtPayments;
  final List<CustomOrderCollectionRow> customOrderPayments;
  final Money legacyCustomOrderReceipts;
  final Money grossSales;
  final Money discounts;
  final Money netSales;
  final Money debtCollections;
  final Money debtPrincipalCollections;
  final Money debtInterestCollections;
  final Money customOrderReceipts;
  final Money receivablesPrincipal;
  final Money receivablesInterest;
  final List<ResellerAccountingSummary> resellerSummaries;

  Money get cashReceived => netSales + debtCollections + customOrderReceipts;
  Money get receivables => receivablesPrincipal + receivablesInterest;
  int get itemsSold =>
      recognizedOrders.fold(0, (sum, order) => sum + order.quantity);

  Money debtCollectionsFor(String debtId) => debtPayments
      .where((row) => row.debt.id == debtId)
      .fold(Money.zero, (sum, row) => sum + row.payment.amount);
}

/// Pure cash-basis accounting calculations shared by UI and exports.
class AccountingService {
  AccountingService._();
  static final AccountingService instance = AccountingService._();

  AccountingReport summarize({
    required Iterable<Order> orders,
    required Iterable<CustomerDebt> debts,
    Iterable<CustomOrder> customOrders = const [],
    AccountingPeriod period = const AccountingPeriod(),
  }) {
    final recognized = orders
        .where(isRecognizedSale)
        .where((order) => period.contains(order.orderDate))
        .toList(growable: false);
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
      legacyCustomOrderReceipts: legacyCustomReceipts,
      grossSales: gross,
      discounts: discounts,
      netSales: net,
      debtCollections: debtCollections,
      debtPrincipalCollections: debtPrincipal,
      debtInterestCollections: debtInterest,
      customOrderReceipts: customReceipts,
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

  Money grossSales(List<Order> orders) =>
      summarize(orders: orders, debts: const []).grossSales;
  Money totalDiscounts(List<Order> orders) =>
      summarize(orders: orders, debts: const []).discounts;
  Money netSales(List<Order> orders) =>
      summarize(orders: orders, debts: const []).netSales;
  Money customizedOrderRevenue(List<Order> orders) => summarize(
    orders: orders.where((order) => order.orderType == 'customized'),
    debts: const [],
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

  List<ResellerAccountingSummary> resellerSummary(List<Order> orders) =>
      _resellerSummary(orders.where(isRecognizedSale));

  List<Order> filterByDateRange(
    List<Order> orders, {
    DateTime? from,
    DateTime? to,
  }) {
    final period = AccountingPeriod(from: from, to: to);
    return orders.where((order) => period.contains(order.orderDate)).toList();
  }

  bool isRecognizedSale(Order order) =>
      order.status == OrderStatus.delivered &&
      order.paymentMethod != PaymentMethod.utang;

  List<Order> recognizedSales(Iterable<Order> orders) =>
      orders.where(isRecognizedSale).toList(growable: false);

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
}
