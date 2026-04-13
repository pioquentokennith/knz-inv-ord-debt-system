// ─────────────────────────────────────────────────────────────────────────────
// debt_service.dart — Interface + Implementation (Abstraction + Polymorphism)
// IDebtService defines the contract; DebtService implements it.
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';
import '../repositories/debt_repository.dart';

/// Abstract contract for debt/utang business logic (Abstraction).
abstract class IDebtService {
  Future<List<CustomerDebt>> getAll(String userId);
  Future<void>    addDebt(CustomerDebt debt, String userId);
  Future<String?> addPayment(String debtId, PaymentRecord payment, double remainingBalance);
  Future<void>    deleteDebt(String debtId);
}

/// Concrete implementation — all business logic for utang/credit.
class DebtService implements IDebtService {
  final DebtRepository _repo;

  DebtService(this._repo);

  @override
  Future<List<CustomerDebt>> getAll(String userId) => _repo.getAll(userId);

  @override
  Future<void> addDebt(CustomerDebt debt, String userId) =>
      _repo.add(debt, userId);

  /// Validates payment amount then records it (Encapsulation of business rule).
  @override
  Future<String?> addPayment(
      String debtId, PaymentRecord payment, double remainingBalance) async {
    if (payment.amount <= 0) return 'Payment amount must be greater than zero';
    if (payment.amount > remainingBalance) {
      return 'Amount exceeds remaining balance of ₱${remainingBalance.toStringAsFixed(2)}';
    }
    await _repo.addPayment(debtId, payment);
    return null;
  }

  @override
  Future<void> deleteDebt(String debtId) => _repo.delete(debtId);
}
