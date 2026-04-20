// stub_debt_repository.dart — In-memory stub for DebtRepository
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/repositories/debt_repository.dart';

class StubDebtRepository implements DebtRepository {
  final Map<String, CustomerDebt> store   = {};
  final Map<String, CustomerDebt> deleted = {};

  @override Future<List<CustomerDebt>> getAll(String userId) async => store.values.toList();
  @override Future<void> add(CustomerDebt debt, String userId) async { store[debt.id] = debt; }
  @override Future<void> addPayment(String debtId, PaymentRecord payment) async {
    final d = store[debtId];
    if (d == null) return;
    store[debtId] = CustomerDebt(
      id:           d.id,
      customerName: d.customerName,
      orderId:      d.orderId,
      totalAmount:  d.totalAmount,
      amountPaid:   d.amountPaid + payment.amount,
      createdAt:    d.createdAt,
      payments:     [...d.payments, payment],
    );
  }
  @override Future<void> delete(String debtId) async {
    final d = store.remove(debtId);
    if (d != null) deleted[debtId] = d;
  }
  @override Future<List<CustomerDebt>> getDeleted(String userId) async => deleted.values.toList();
  @override Future<void> restore(String debtId) async {
    final d = deleted.remove(debtId);
    if (d != null) store[debtId] = d;
  }
  @override Future<void> hardDelete(String debtId) async {
    store.remove(debtId);
    deleted.remove(debtId);
  }

  void seed(CustomerDebt debt) => store[debt.id] = debt;
  void clear() { store.clear(); deleted.clear(); }
  int get count        => store.length;
  int get deletedCount => deleted.length;
  CustomerDebt? findById(String id) => store[id];
}
