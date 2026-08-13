// ─────────────────────────────────────────────────────────────────────────────
// debt_repository.dart — Abstract DebtRepository interface
// Purpose : Defines the data-access contract for customer debts (utang).
//           DebtService and AppState depend only on this interface (DIP).
// ─────────────────────────────────────────────────────────────────────────────

import '../models/debt_model.dart';

abstract class DebtRepository {
  // Returns all active (non-deleted) debts for a given user, newest first
  Future<List<CustomerDebt>> getAll(String userId);

  // Persists a new debt record to storage
  Future<void> add(CustomerDebt debt, String userId);

  // Appends an immutable payment allocation and updates outstanding balances.
  Future<void> addPayment(String debtId, PaymentRecord payment);

  // Soft-deletes a debt (moves to Recycle Bin)
  Future<void> delete(String debtId, String userId);

  // ── Recycle Bin operations ────────────────────────────────────────────────

  // Returns all soft-deleted debts for the Recycle Bin screen
  Future<List<CustomerDebt>> getDeleted(String userId);

  // Restores a soft-deleted debt back to the active list
  Future<void> restore(String debtId, String userId);

  // Permanently removes a debt and its payments from storage (admin-only purge)
  Future<void> hardDelete(String debtId, String userId);
}
