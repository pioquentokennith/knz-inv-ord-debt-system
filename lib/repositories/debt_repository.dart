import '../models/debt_model.dart';

abstract class DebtRepository {
  Future<List<CustomerDebt>> getAll(String userId);
  Future<void> add(CustomerDebt debt, String userId);
  Future<void> addPayment(String debtId, PaymentRecord payment);
  Future<void> delete(String debtId);

  // Recycle-bin operations
  Future<List<CustomerDebt>> getDeleted(String userId);
  Future<void> restore(String debtId);
  Future<void> hardDelete(String debtId);
}
