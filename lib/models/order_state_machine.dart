import '../core/domain_exceptions.dart';
import 'order_model.dart';

class OrderStateMachine {
  const OrderStateMachine._();

  static const Map<OrderStatus, Set<OrderStatus>> _allowed = {
    OrderStatus.pending: {
      OrderStatus.processing,
      OrderStatus.utang,
      OrderStatus.cancelled,
    },
    OrderStatus.processing: {
      OrderStatus.shipped,
      OrderStatus.utang,
      OrderStatus.cancelled,
    },
    OrderStatus.shipped: {
      OrderStatus.delivered,
      OrderStatus.utang,
      OrderStatus.cancelled,
    },
    OrderStatus.cancelled: {OrderStatus.pending},
    OrderStatus.utang: {OrderStatus.delivered},
    OrderStatus.delivered: <OrderStatus>{},
  };

  static void validateInitial(OrderStatus status, {required bool hasDebt}) {
    if (status == OrderStatus.delivered) {
      throw const InvalidOrderTransitionException(
        'New orders must record delivery through the delivery workflow.',
      );
    }
    if (status == OrderStatus.utang && !hasDebt) {
      throw InvalidOrderTransitionException(
        'A new Utang order requires a debt ledger.',
      );
    }
    if (status != OrderStatus.utang && hasDebt) {
      throw InvalidOrderTransitionException(
        'Only a new Utang order can start with a debt ledger.',
      );
    }
  }

  static Set<OrderStatus> allowedTransitions(OrderStatus current) =>
      Set<OrderStatus>.unmodifiable(_allowed[current] ?? const {});

  static void validate(
    OrderStatus current,
    OrderStatus next, {
    required bool hasOpenDebt,
  }) {
    if (current == next || !(_allowed[current]?.contains(next) ?? false)) {
      throw InvalidOrderTransitionException(
        'Order cannot move from ${current.displayName} to ${next.displayName}.',
      );
    }
    if (next == OrderStatus.cancelled && hasOpenDebt) {
      throw const OpenDebtException(
        'Settle the linked debt before cancelling this order.',
      );
    }
    if (current == OrderStatus.utang &&
        next == OrderStatus.delivered &&
        hasOpenDebt) {
      throw const OpenDebtException(
        'Settle the linked debt before marking this order as delivered.',
      );
    }
  }
}
