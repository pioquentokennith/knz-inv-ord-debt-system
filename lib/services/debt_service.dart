// ─────────────────────────────────────────────────────────────────────────────
// debt_service.dart — Debt business logic  (v6: computeTotalWithInterest added)
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';
import '../core/money.dart';
import '../repositories/debt_repository.dart';

abstract class IDebtService {
  Future<List<CustomerDebt>> getAll(String userId);
  Future<void> addDebt(CustomerDebt debt, String userId);
  Future<String?> addPayment(
    String debtId,
    PaymentRecord payment,
    Money remainingBalance,
  );
  Future<void> deleteDebt(String debtId);
  Future<List<CustomerDebt>> getDeleted(String userId);
  Future<void> restoreDebt(String debtId);
  Future<void> hardDeleteDebt(String debtId);

  // v6 — Feature 4
  /// Returns principal remaining + accrued interest.
  Money computeTotalWithInterest(CustomerDebt debt);
}

class DebtService implements IDebtService {
  final DebtRepository _repo;

  DebtService(this._repo);

  @override
  Future<List<CustomerDebt>> getAll(String userId) => _repo.getAll(userId);

  @override
  Future<void> addDebt(CustomerDebt debt, String userId) =>
      _repo.add(debt, userId);

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
  Future<void> deleteDebt(String debtId) => _repo.delete(debtId);

  @override
  Future<List<CustomerDebt>> getDeleted(String userId) =>
      _repo.getDeleted(userId);

  @override
  Future<void> restoreDebt(String debtId) => _repo.restore(debtId);

  @override
  Future<void> hardDeleteDebt(String debtId) => _repo.hardDelete(debtId);

  // ── v6: Feature 4 ─────────────────────────────────────────────────────────

  /// Pure computation — delegates to the model's accruedInterest getter.
  /// Kept in the service so callers never depend on model internals directly.
  @override
  Money computeTotalWithInterest(CustomerDebt debt) => debt.totalWithInterest;
}
