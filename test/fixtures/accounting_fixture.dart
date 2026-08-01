import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/payment_method_model.dart';

class AccountingFixture {
  AccountingFixture()
    : periodFrom = DateTime.utc(2026, 5, 1),
      periodTo = DateTime.utc(2026, 5, 31) {
    orders = [
      _order(
        id: 'paid',
        date: DateTime.utc(2026, 5, 1),
        srp: 10000,
        unitPrice: 9000,
        quantity: 2,
      ),
      _order(
        id: 'reseller',
        date: DateTime.utc(2026, 5, 31, 23, 59, 59),
        srp: 20000,
        unitPrice: 15000,
        quantity: 1,
        isReseller: true,
      ),
      _order(
        id: 'cancelled',
        date: DateTime.utc(2026, 5, 15),
        srp: 50000,
        unitPrice: 50000,
        quantity: 1,
        status: OrderStatus.cancelled,
      ),
      _order(
        id: 'utang',
        date: DateTime.utc(2026, 5, 15),
        srp: 30000,
        unitPrice: 30000,
        quantity: 1,
        paymentMethod: PaymentMethod.utang,
      ),
    ];

    debts = [
      CustomerDebt(
        id: 'debt-1',
        customerName: 'Credit Customer',
        orderId: 'utang',
        principalOriginal: const Money.fromCentavos(30000),
        principalOutstanding: const Money.fromCentavos(22000),
        interestOutstanding: const Money.fromCentavos(3000),
        createdAt: DateTime.utc(2026, 4, 1),
        payments: [
          PaymentRecord(
            id: 'debt-payment',
            amount: const Money.fromCentavos(10000),
            interestApplied: const Money.fromCentavos(2000),
            principalApplied: const Money.fromCentavos(8000),
            paidAt: DateTime.utc(2026, 5, 15),
          ),
        ],
        interestRateBasisPoints: 100,
        interestType: 'monthly',
        lastAccrualTimestamp: DateTime.utc(2026, 5, 1),
      ),
    ];

    customOrders = [
      CustomOrder(
        id: 'custom-1',
        customerName: 'Custom Customer',
        fragranceSpecs: 'Fixture scent',
        agreedPrice: const Money.fromCentavos(40000),
        depositPaid: const Money.fromCentavos(15000),
        payments: [
          CustomOrderPayment(
            id: 'custom-initial',
            customOrderId: 'custom-1',
            amount: const Money.fromCentavos(5000),
            paidAt: DateTime.utc(2026, 5, 1),
          ),
          CustomOrderPayment(
            id: 'custom-later',
            customOrderId: 'custom-1',
            amount: const Money.fromCentavos(7000),
            paidAt: DateTime.utc(2026, 5, 31, 23, 59, 59),
          ),
          CustomOrderPayment(
            id: 'custom-outside',
            customOrderId: 'custom-1',
            amount: const Money.fromCentavos(3000),
            paidAt: DateTime.utc(2026, 6, 1),
          ),
        ],
        deliveryDate: DateTime.utc(2026, 6, 30),
        userId: 'owner-1',
        createdAt: DateTime.utc(2026, 4, 20),
      ),
    ];
  }

  final DateTime periodFrom;
  final DateTime periodTo;
  late final List<Order> orders;
  late final List<CustomerDebt> debts;
  late final List<CustomOrder> customOrders;

  static Order _order({
    required String id,
    required DateTime date,
    required int srp,
    required int unitPrice,
    required int quantity,
    OrderStatus status = OrderStatus.delivered,
    PaymentMethod? paymentMethod = PaymentMethod.cashOnDelivery,
    bool isReseller = false,
  }) => Order(
    id: id,
    orderId: id,
    customerName: isReseller ? 'Fixture Reseller' : 'Fixture Customer',
    items: [
      OrderItem(
        id: 'item-$id',
        productId: 'product-$id',
        productName: 'Product $id',
        unitPrice: Money.fromCentavos(unitPrice),
        srpPrice: Money.fromCentavos(srp),
        quantity: quantity,
      ),
    ],
    totalAmount: Money.fromCentavos(unitPrice * quantity),
    status: status,
    orderDate: date,
    paymentMethod: paymentMethod,
    isReseller: isReseller,
    deductionPerItem: Money.fromCentavos(srp - unitPrice),
  );
}
