// ─────────────────────────────────────────────────────────────────────────────
// debt_service_test.dart — Integration tests for DebtService
//
// Coverage:
//   ✔ addDebt   — debt stored in repo
//   ✔ getAll    — returns all active debts
//   ✔ addPayment — valid payment accepted, amount_paid updated
//   ✔ addPayment — zero payment rejected
//   ✔ addPayment — overpayment rejected
//   ✔ addPayment — exact full payment accepted (boundary case)
//   ✔ deleteDebt — soft-delete cycle
//   ✔ getDeleted / restoreDebt / hardDeleteDebt — full recycle-bin cycle
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'stubs/stub_debt_repository.dart';
import 'stubs/stub_services.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

CustomerDebt _debt({
  String id           = 'debt-1',
  String customerName = 'Ben Santos',
  String orderId      = 'KNZ-001',
  double totalAmount  = 1000.0,
  double amountPaid   = 0.0,
}) =>
    CustomerDebt(
      id:           id,
      customerName: customerName,
      orderId:      orderId,
      totalAmount:  totalAmount,
      amountPaid:   amountPaid,
      createdAt:    DateTime(2025, 6, 1),
    );

PaymentRecord _payment({
  String id     = 'pay-1',
  double amount = 250.0,
}) =>
    PaymentRecord(
      id:     id,
      amount: amount,
      paidAt: DateTime(2025, 6, 15),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late StubDebtRepository repo;
  late StubDebtService    service;

  setUp(() {
    repo    = StubDebtRepository();
    service = StubDebtService(repo);
  });

  group('DebtService — addDebt()', () {
    test('stores debt in repo', () async {
      await service.addDebt(_debt(), 'u1');

      expect(repo.count, 1);
    });

    test('getAll returns stored debts', () async {
      await service.addDebt(_debt(id: 'debt-a'), 'u1');
      await service.addDebt(_debt(id: 'debt-b'), 'u1');

      final debts = await service.getAll('u1');

      expect(debts.length, 2);
    });
  });

  group('DebtService — addPayment()', () {
    test('valid partial payment is accepted and amount_paid increases', () async {
      await service.addDebt(_debt(totalAmount: 1000, amountPaid: 0), 'u1');

      final error = await service.addPayment(
        'debt-1', _payment(amount: 250), 1000.0,
      );

      expect(error, isNull);
      final stored = repo.findById('debt-1')!;
      expect(stored.amountPaid, 250.0);
    });

    test('zero payment is rejected', () async {
      await service.addDebt(_debt(), 'u1');

      final error = await service.addPayment(
        'debt-1', _payment(amount: 0), 1000.0,
      );

      expect(error, 'Payment amount must be greater than zero');
      expect(repo.findById('debt-1')!.amountPaid, 0.0,
          reason: 'amount_paid must be unchanged on rejection');
    });

    test('negative payment is rejected', () async {
      await service.addDebt(_debt(), 'u1');

      final error = await service.addPayment(
        'debt-1', _payment(amount: -100), 1000.0,
      );

      expect(error, 'Payment amount must be greater than zero');
    });

    test('overpayment is rejected', () async {
      await service.addDebt(_debt(totalAmount: 1000, amountPaid: 700), 'u1');

      final error = await service.addPayment(
        'debt-1', _payment(amount: 500), 300.0, // remaining = 300
      );

      expect(error, contains('exceeds remaining balance'));
      expect(repo.findById('debt-1')!.amountPaid, 700.0,
          reason: 'amount_paid must be unchanged on overpayment');
    });

    test('exact full payment (boundary) is accepted', () async {
      await service.addDebt(_debt(totalAmount: 1000, amountPaid: 750), 'u1');

      final error = await service.addPayment(
        'debt-1', _payment(amount: 250), 250.0, // paying exactly remaining
      );

      expect(error, isNull);
      expect(repo.findById('debt-1')!.amountPaid, 1000.0);
    });

    test('multiple sequential payments accumulate correctly', () async {
      await service.addDebt(_debt(totalAmount: 1000, amountPaid: 0), 'u1');

      await service.addPayment('debt-1', _payment(id: 'p1', amount: 300), 1000.0);
      await service.addPayment('debt-1', _payment(id: 'p2', amount: 400), 700.0);
      await service.addPayment('debt-1', _payment(id: 'p3', amount: 300), 300.0);

      final stored = repo.findById('debt-1')!;
      expect(stored.amountPaid, 1000.0);
      expect(stored.payments.length, 3);
      expect(stored.isPaid, isTrue);
    });
  });

  group('DebtService — Recycle Bin', () {
    test('deleteDebt soft-deletes and moves to deleted bucket', () async {
      await service.addDebt(_debt(), 'u1');

      await service.deleteDebt('debt-1');

      expect(repo.count, 0);
      expect(repo.deletedCount, 1);
    });

    test('getDeleted returns the soft-deleted debt', () async {
      await service.addDebt(_debt(), 'u1');
      await service.deleteDebt('debt-1');

      final deleted = await service.getDeleted('u1');

      expect(deleted.length, 1);
      expect(deleted.first.id, 'debt-1');
    });

    test('restoreDebt moves debt back to active', () async {
      await service.addDebt(_debt(), 'u1');
      await service.deleteDebt('debt-1');

      await service.restoreDebt('debt-1');

      expect(repo.count, 1);
      expect(repo.deletedCount, 0);
    });

    test('hardDeleteDebt purges from both stores', () async {
      await service.addDebt(_debt(), 'u1');
      await service.deleteDebt('debt-1');

      await service.hardDeleteDebt('debt-1');

      expect(repo.count, 0);
      expect(repo.deletedCount, 0);
    });
  });
}
