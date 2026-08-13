// ─────────────────────────────────────────────────────────────────────────────
// debt_service.dart — Debt business logic
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';
import '../core/money.dart';
import '../repositories/debt_repository.dart';

abstract class IDebtService {
  Future<List<CustomerDebt>> getAll(String userId);
  Future<String?> addPayment(
    String debtId,
    PaymentRecord payment,
    Money remainingBalance,
  );
  Future<void> deleteDebt(String debtId, String userId);
  Future<List<CustomerDebt>> getDeleted(String userId);
  Future<void> restoreDebt(String debtId, String userId);
  Future<void> hardDeleteDebt(String debtId, String userId);
}

class DebtService implements IDebtService {
  final DebtRepository _repo;

  DebtService(this._repo);

  @override
  Future<List<CustomerDebt>> getAll(String userId) => _repo.getAll(userId);

  @override
  Future<String?> addPayment(
    String debtId,
    PaymentRecord payment,
    Money remainingBalance,
  ) async {
    if (payment.amount <= 0) return 'Payment amount must be greater than zero';
    // NOTE: 'remainingBalance' here receives debt.totalWithInterest from app_state.addPayment,
    // so this ceiling correctly allows interest-inclusive payments.
    if (payment.amount > remainingBalance) {
      return 'Amount exceeds total due of ₱${remainingBalance.toStringAsFixed(2)}';
    }
    await _repo.addPayment(debtId, payment);
    return null;
  }

  @override
  Future<void> deleteDebt(String debtId, String userId) =>
      _repo.delete(debtId, userId);

  @override
  Future<List<CustomerDebt>> getDeleted(String userId) =>
      _repo.getDeleted(userId);

  @override
  Future<void> restoreDebt(String debtId, String userId) =>
      _repo.restore(debtId, userId);

  @override
  Future<void> hardDeleteDebt(String debtId, String userId) =>
      _repo.hardDelete(debtId, userId);
}
