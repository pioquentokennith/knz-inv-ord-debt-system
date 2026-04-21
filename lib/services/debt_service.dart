// ─────────────────────────────────────────────────────────────────────────────
// debt_service.dart — Debt (utang) business logic
// Purpose : Enforces payment validation rules before delegating storage to
//           DebtRepository. Prevents overpayment and zero-amount payments.
// Interface + Implementation (Abstraction + Polymorphism)
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';
import '../repositories/debt_repository.dart';

/// Abstract contract for debt/utang business logic (Abstraction).
/// AppState depends on this interface so tests can inject a stub.
abstract class IDebtService {
  // Returns all active debt records for the given user
  Future<List<CustomerDebt>> getAll(String userId);

  // Persists a new debt record to storage
  Future<void>    addDebt(CustomerDebt debt, String userId);

  // Validates the payment amount then records it against the debt
  // Returns null on success; returns an error message string on failure
  Future<String?> addPayment(String debtId, PaymentRecord payment, double remainingBalance);

  // Soft-deletes a debt (moves to Recycle Bin)
  Future<void>    deleteDebt(String debtId);

  // ── Recycle Bin operations ────────────────────────────────────────────────
  Future<List<CustomerDebt>> getDeleted(String userId);    // Returns soft-deleted debts
  Future<void>               restoreDebt(String debtId);  // Un-deletes a debt
  Future<void>               hardDeleteDebt(String debtId); // Permanent purge
}

/// Concrete implementation — all business logic for utang/credit.
class DebtService implements IDebtService {
  final DebtRepository _repo; // Depends on abstract interface (DIP)

  DebtService(this._repo);

  // Delegates directly to repo — no additional business logic needed
  @override
  Future<List<CustomerDebt>> getAll(String userId) => _repo.getAll(userId);

  // Delegates debt creation to the repo — validation happens in the calling dialog
  @override
  Future<void> addDebt(CustomerDebt debt, String userId) =>
      _repo.add(debt, userId);

  /// Validates the payment amount against business rules before saving.
  /// This prevents invalid payments from reaching the repository layer.
  @override
  Future<String?> addPayment(
      String debtId, PaymentRecord payment, double remainingBalance) async {
    // Rule 1: Payment must be a positive amount
    if (payment.amount <= 0) return 'Payment amount must be greater than zero';

    // Rule 2: Payment cannot exceed the remaining balance (no overpayment)
    if (payment.amount > remainingBalance) {
      return 'Amount exceeds remaining balance of ₱${remainingBalance.toStringAsFixed(2)}';
    }

    // Validation passed — persist the payment record
    await _repo.addPayment(debtId, payment);
    return null; // null = success
  }

  // Delegates soft-delete to the repository
  @override
  Future<void> deleteDebt(String debtId) => _repo.delete(debtId);

  // Delegates Recycle Bin operations to the repository
  @override
  Future<List<CustomerDebt>> getDeleted(String userId) => _repo.getDeleted(userId);

  @override
  Future<void> restoreDebt(String debtId) => _repo.restore(debtId);

  @override
  Future<void> hardDeleteDebt(String debtId) => _repo.hardDelete(debtId);
}
