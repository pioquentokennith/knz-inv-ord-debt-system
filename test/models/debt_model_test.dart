import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/debt_model.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1);

  CustomerDebt debt({
    int principal = 10000,
    int interest = 0,
    int rateBasisPoints = 0,
    String interestType = 'none',
    DateTime? dueDate,
  }) => CustomerDebt(
    id: 'debt-1',
    customerName: 'Customer',
    orderId: 'KNZ-001',
    principalOriginal: Money.fromCentavos(principal),
    principalOutstanding: Money.fromCentavos(principal),
    interestOutstanding: Money.fromCentavos(interest),
    createdAt: start,
    interestRateBasisPoints: rateBasisPoints,
    interestType: interestType,
    interestStartTimestamp: start,
    lastAccrualTimestamp: start,
    dueDate: dueDate,
  );

  PaymentRecord payment(int centavos, DateTime paidAt, {String id = 'p-1'}) =>
      PaymentRecord(
        id: id,
        amount: Money.fromCentavos(centavos),
        paidAt: paidAt,
      );

  test('mandatory regression allocates interest before principal', () {
    final result = debt(interest: 1000).allocatePayment(payment(10000, start));

    expect(result.payment.interestApplied.centavos, 1000);
    expect(result.payment.principalApplied.centavos, 9000);
    expect(result.debt.principalOutstanding.centavos, 1000);
    expect(result.debt.interestOutstanding.centavos, 0);
    expect(result.debt.isPaid, isFalse);
  });

  test('no-interest debt allocates payment entirely to principal', () {
    final result = debt().allocatePayment(payment(2500, start));

    expect(result.payment.interestApplied, Money.zero);
    expect(result.payment.principalApplied.centavos, 2500);
    expect(result.debt.principalOutstanding.centavos, 7500);
  });

  test('partial payment leaves both components auditable', () {
    final result = debt(interest: 750).allocatePayment(payment(500, start));

    expect(result.payment.interestApplied.centavos, 500);
    expect(result.payment.principalApplied, Money.zero);
    expect(result.debt.interestOutstanding.centavos, 250);
    expect(result.debt.principalOutstanding.centavos, 10000);
  });

  test('repeated accrual advances from the persisted timestamp only', () {
    final original = debt(rateBasisPoints: 1000, interestType: 'daily');
    final dayOne = original.accrueTo(start.add(const Duration(days: 1)));
    final repeated = dayOne.accrueTo(start.add(const Duration(days: 1)));
    final dayTwo = repeated.accrueTo(start.add(const Duration(days: 2)));

    expect(dayOne.interestOutstanding.centavos, 1000);
    expect(repeated.interestOutstanding.centavos, 1000);
    expect(dayTwo.interestOutstanding.centavos, 2000);
  });

  test('accrual after partial payment uses remaining principal', () {
    final dayOne = debt(
      rateBasisPoints: 1000,
      interestType: 'daily',
    ).accrueTo(start.add(const Duration(days: 1)));
    final paid = dayOne.allocatePayment(
      payment(6000, start.add(const Duration(days: 1))),
    );
    final dayTwo = paid.debt.accrueTo(start.add(const Duration(days: 2)));

    expect(paid.payment.interestApplied.centavos, 1000);
    expect(paid.payment.principalApplied.centavos, 5000);
    expect(dayTwo.principalOutstanding.centavos, 5000);
    expect(dayTwo.interestOutstanding.centavos, 500);
  });

  test('interest rounds half-up to one centavo deterministically', () {
    final accrued = debt(
      principal: 333,
      rateBasisPoints: 150,
      interestType: 'daily',
    ).accrueTo(start.add(const Duration(days: 1)));

    expect(accrued.interestOutstanding.centavos, 5);
  });

  test('weekly interest accrues only on complete 7-day boundaries', () {
    final original = debt(
      principal: 100000,
      rateBasisPoints: 200,
      interestType: 'weekly',
      dueDate: start.add(const Duration(days: 30)),
    );
    final beforeWeek = original.accrueTo(
      start
          .add(const Duration(days: 7))
          .subtract(const Duration(microseconds: 1)),
    );
    expect(beforeWeek.interestOutstanding, Money.zero);
    expect(beforeWeek.lastAccrualTimestamp, start);

    final weekOne = beforeWeek.accrueTo(start.add(const Duration(days: 7)));
    expect(weekOne.interestOutstanding.centavos, 2000);
    final repeated = weekOne.accrueTo(start.add(const Duration(days: 7)));
    expect(repeated.interestOutstanding.centavos, 2000);
    final dayThirteen = repeated.accrueTo(start.add(const Duration(days: 13)));
    expect(dayThirteen.interestOutstanding.centavos, 2000);
    expect(
      dayThirteen.lastAccrualTimestamp,
      start.add(const Duration(days: 7)),
    );

    // Catching up several periods uses simple interest, not compounding.
    final weekThree = dayThirteen.accrueTo(start.add(const Duration(days: 21)));
    expect(weekThree.interestOutstanding.centavos, 6000);
    expect(weekThree.lastAccrualTimestamp, start.add(const Duration(days: 21)));
  });

  test(
    'weekly partial payments preserve the schedule and use remaining principal',
    () {
      final original = debt(
        principal: 100000,
        rateBasisPoints: 200,
        interestType: 'weekly',
      );
      final paid = original.allocatePayment(
        payment(52000, start.add(const Duration(days: 10))),
      );
      expect(paid.payment.interestApplied.centavos, 2000);
      expect(paid.payment.principalApplied.centavos, 50000);
      expect(
        paid.debt.lastAccrualTimestamp,
        start.add(const Duration(days: 7)),
      );
      final weekTwo = paid.debt.accrueTo(start.add(const Duration(days: 14)));
      expect(weekTwo.principalOutstanding.centavos, 50000);
      expect(weekTwo.interestOutstanding.centavos, 1000);

      final settled = weekTwo
          .allocatePayment(
            payment(51000, start.add(const Duration(days: 14)), id: 'p-2'),
          )
          .debt;
      expect(settled.isPaid, isTrue);
      expect(
        settled.accrueTo(start.add(const Duration(days: 70))).totalOutstanding,
        Money.zero,
      );
    },
  );

  test('weekly initial payment reduces the first period interest', () {
    final paid = debt(
      principal: 100000,
      rateBasisPoints: 200,
      interestType: 'weekly',
    ).allocatePayment(payment(50000, start)).debt;
    expect(
      paid
          .accrueTo(start.add(const Duration(days: 7)))
          .interestOutstanding
          .centavos,
      1000,
    );
  });

  test(
    'weekly rounding is half-up per period and zero rates accrue nothing',
    () {
      final original = debt(
        principal: 105,
        rateBasisPoints: 1000,
        interestType: 'weekly',
      );
      expect(
        original
            .accrueTo(start.add(const Duration(days: 14)))
            .interestOutstanding
            .centavos,
        22,
      );
      final zeroRate = debt(interestType: 'weekly');
      expect(
        zeroRate
            .accrueTo(start.add(const Duration(days: 14)))
            .interestOutstanding,
        Money.zero,
      );
    },
  );

  test('monthly interest still uses complete 30-day periods', () {
    final original = debt(rateBasisPoints: 200, interestType: 'monthly');
    expect(
      original
          .accrueTo(start.add(const Duration(days: 29)))
          .interestOutstanding,
      Money.zero,
    );
    expect(
      original
          .accrueTo(start.add(const Duration(days: 30)))
          .interestOutstanding
          .centavos,
      200,
    );
  });

  test('overpayment is rejected without creating a payment history entry', () {
    final original = debt();

    expect(
      () => original.allocatePayment(payment(10001, start)),
      throwsStateError,
    );
    expect(original.payments, isEmpty);
  });

  test('complete settlement requires zero principal and zero interest', () {
    final result = debt(interest: 1000).allocatePayment(payment(11000, start));

    expect(result.debt.principalOutstanding, Money.zero);
    expect(result.debt.interestOutstanding, Money.zero);
    expect(result.debt.status, DebtStatus.paid);
    expect(result.debt.isPaid, isTrue);
    expect(
      () => result.debt.payments.add(payment(1, start, id: 'p-2')),
      throwsUnsupportedError,
    );
  });

  test('explicit due date becomes due on the selected local calendar day', () {
    final datedDebt = debt(dueDate: DateTime.utc(2026, 1, 8));

    expect(datedDebt.isDueAt(DateTime(2026, 1, 7, 23, 59)), isFalse);
    expect(datedDebt.isDueAt(DateTime(2026, 1, 8)), isTrue);
    expect(datedDebt.isOverdueAt(DateTime(2026, 1, 8, 23, 59)), isFalse);
    expect(datedDebt.isOverdueAt(DateTime(2026, 1, 9)), isTrue);
  });

  test('legacy debt without a due date never invents an overdue date', () {
    final legacyDebt = debt();

    expect(legacyDebt.dueDate, isNull);
    expect(legacyDebt.isDueAt(DateTime(2036)), isFalse);
    expect(legacyDebt.isOverdueAt(DateTime(2036)), isFalse);
  });
}
