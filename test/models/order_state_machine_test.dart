import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/domain_exceptions.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/order_state_machine.dart';

void main() {
  test('new orders require explicit delivery and preserve debt pairing', () {
    for (final status in OrderStatus.values.where(
      (status) =>
          status != OrderStatus.utang && status != OrderStatus.delivered,
    )) {
      expect(
        () => OrderStateMachine.validateInitial(status, hasDebt: false),
        returnsNormally,
      );
    }
    expect(
      () => OrderStateMachine.validateInitial(
        OrderStatus.delivered,
        hasDebt: false,
      ),
      throwsA(isA<InvalidOrderTransitionException>()),
    );
    expect(
      () => OrderStateMachine.validateInitial(OrderStatus.utang, hasDebt: true),
      returnsNormally,
    );
    expect(
      () =>
          OrderStateMachine.validateInitial(OrderStatus.utang, hasDebt: false),
      throwsA(isA<InvalidOrderTransitionException>()),
    );
    expect(
      () =>
          OrderStateMachine.validateInitial(OrderStatus.pending, hasDebt: true),
      throwsA(isA<InvalidOrderTransitionException>()),
    );
  });

  test(
    'allows only the documented forward lifecycle and cancellation restore',
    () {
      expect(OrderStateMachine.allowedTransitions(OrderStatus.pending), {
        OrderStatus.processing,
        OrderStatus.utang,
        OrderStatus.cancelled,
      });
      expect(
        () => OrderStateMachine.validate(
          OrderStatus.pending,
          OrderStatus.processing,
          hasOpenDebt: false,
        ),
        returnsNormally,
      );
      expect(
        () => OrderStateMachine.validate(
          OrderStatus.cancelled,
          OrderStatus.pending,
          hasOpenDebt: false,
        ),
        returnsNormally,
      );
      expect(
        () => OrderStateMachine.validate(
          OrderStatus.pending,
          OrderStatus.delivered,
          hasOpenDebt: false,
        ),
        throwsA(isA<InvalidOrderTransitionException>()),
      );
    },
  );

  test('open debt blocks cancellation and Utang delivery', () {
    expect(
      () => OrderStateMachine.validate(
        OrderStatus.processing,
        OrderStatus.cancelled,
        hasOpenDebt: true,
      ),
      throwsA(isA<OpenDebtException>()),
    );
    expect(
      () => OrderStateMachine.validate(
        OrderStatus.utang,
        OrderStatus.delivered,
        hasOpenDebt: true,
      ),
      throwsA(isA<OpenDebtException>()),
    );
  });
}
