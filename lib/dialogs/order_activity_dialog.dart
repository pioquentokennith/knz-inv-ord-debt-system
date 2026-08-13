import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/business_event_model.dart';
import '../models/order_model.dart';
import '../models/order_state_machine.dart';
import '../models/payment_method_model.dart';
import '../widgets/shared_widgets.dart';

class OrderActivityDialog extends StatelessWidget {
  const OrderActivityDialog({super.key, required this.order});

  final Order order;

  static Future<void> show(BuildContext context, Order order) =>
      showDialog<void>(
        context: context,
        builder: (_) => OrderActivityDialog(order: order),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppState(),
    builder: (context, _) {
      final state = AppState();
      final events = state.eventsForOrder(order.id)
        ..sort(
          (a, b) => (b.occurredAt ?? b.recordedAt).compareTo(
            a.occurredAt ?? a.recordedAt,
          ),
        );
      final collected = BusinessEventLedger.netCash(events);
      final balance = (order.customerPayAmount - collected).max(Money.zero);
      final reversedIds = events
          .where((event) => event.type == BusinessEventType.reversal)
          .map((event) => event.relatedEventId)
          .whereType<String>()
          .toSet();
      final hasDebt = state.debts.any((debt) => debt.orderId == order.orderId);
      final canDeliver = OrderStateMachine.allowedTransitions(
        order.status,
      ).contains(OrderStatus.delivered);

      return AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '${order.orderId} Activity',
          style: const TextStyle(color: AppColors.white),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _Amount(label: 'ORDER', value: order.customerPayAmount),
                    _Amount(label: 'NET COLLECTED', value: collected),
                    _Amount(label: 'BALANCE', value: balance),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: Key('order-${order.id}-payment'),
                      onPressed: hasDebt || !balance.isPositive
                          ? null
                          : () => _recordPayment(context, order, balance),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(hasDebt ? 'Use Utang Payment' : 'Payment'),
                    ),
                    OutlinedButton.icon(
                      key: Key('order-${order.id}-delivery'),
                      onPressed: canDeliver
                          ? () => _recordDelivery(context, order)
                          : null,
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text('Delivery'),
                    ),
                    OutlinedButton.icon(
                      key: Key('order-${order.id}-refund'),
                      onPressed: collected.isPositive
                          ? () => _issueRefund(context, order, collected)
                          : null,
                      icon: const Icon(Icons.currency_exchange),
                      label: const Text('Refund'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'EVENT HISTORY',
                  style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                if (events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'No payment or delivery events recorded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.whiteTertiary),
                    ),
                  )
                else
                  ...events.map(
                    (event) => _EventTile(
                      event: event,
                      canReverse:
                          (event.type == BusinessEventType.payment ||
                              event.type == BusinessEventType.refund) &&
                          !reversedIds.contains(event.id),
                      onReverse: () => _reverse(context, order, event),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );

  Future<void> _recordPayment(
    BuildContext context,
    Order order,
    Money balance,
  ) async {
    final amount = TextEditingController(text: balance.toStringAsFixed(2));
    final reference = TextEditingController();
    var method = PaymentMethod.cashOnDelivery;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Record Payment',
            style: TextStyle(color: AppColors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('order-payment-amount'),
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: PaymentMethod.values
                    .where((value) => value != PaymentMethod.utang)
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.displayName),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => method = value ?? method),
              ),
              if (method.requiresReference)
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(labelText: 'Reference'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !context.mounted) return;
    final parsed = Money.tryParse(amount.text);
    if (parsed == null || !parsed.isPositive || parsed > balance) {
      KnzToast.error(context, 'Enter an amount up to ${balance.format()}.');
      return;
    }
    if (method.requiresReference && reference.text.trim().isEmpty) {
      KnzToast.error(context, 'A payment reference is required.');
      return;
    }
    try {
      await AppState().recordOrderPayment(
        orderId: order.id,
        amount: parsed,
        method: method,
        reference: reference.text,
      );
      if (context.mounted) KnzToast.success(context, 'Payment recorded.');
    } catch (error) {
      if (context.mounted) KnzToast.error(context, _message(error));
    }
  }

  Future<void> _recordDelivery(BuildContext context, Order order) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Record Delivery?',
      message:
          'This records the delivery time for ${order.orderId}. It does not record payment.',
      confirmLabel: 'Record Delivery',
      icon: Icons.local_shipping_outlined,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await AppState().recordOrderDelivery(order.id);
      if (context.mounted) KnzToast.success(context, 'Delivery recorded.');
    } catch (error) {
      if (context.mounted) KnzToast.error(context, _message(error));
    }
  }

  Future<void> _issueRefund(
    BuildContext context,
    Order order,
    Money collected,
  ) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final submitted = await _moneyReasonDialog(
      context,
      title: 'Issue Refund',
      amount: amount,
      reason: reason,
      confirmLabel: 'Refund',
    );
    if (!submitted || !context.mounted) return;
    final parsed = Money.tryParse(amount.text);
    if (parsed == null || !parsed.isPositive || parsed > collected) {
      KnzToast.error(context, 'Enter an amount up to ${collected.format()}.');
      return;
    }
    if (reason.text.trim().isEmpty) {
      KnzToast.error(context, 'A refund reason is required.');
      return;
    }
    try {
      await AppState().issueOrderRefund(
        orderId: order.id,
        amount: parsed,
        reason: reason.text.trim(),
      );
      if (context.mounted) KnzToast.success(context, 'Refund recorded.');
    } catch (error) {
      if (context.mounted) KnzToast.error(context, _message(error));
    }
  }

  Future<void> _reverse(
    BuildContext context,
    Order order,
    BusinessEvent target,
  ) async {
    final reason = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Reverse Event',
          style: TextStyle(color: AppColors.white),
        ),
        content: TextField(
          key: const Key('order-reversal-reason'),
          controller: reason,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (submitted != true || !context.mounted) return;
    if (reason.text.trim().isEmpty) {
      KnzToast.error(context, 'A reversal reason is required.');
      return;
    }
    try {
      await AppState().reverseOrderEvent(
        orderId: order.id,
        target: target,
        reason: reason.text.trim(),
      );
      if (context.mounted) KnzToast.success(context, 'Reversal recorded.');
    } catch (error) {
      if (context.mounted) KnzToast.error(context, _message(error));
    }
  }

  Future<bool> _moneyReasonDialog(
    BuildContext context, {
    required String title,
    required TextEditingController amount,
    required TextEditingController reason,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title, style: const TextStyle(color: AppColors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  String _message(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Invalid argument(s): ', '');
}

class _Amount extends StatelessWidget {
  const _Amount({required this.label, required this.value});

  final String label;
  final Money value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceElevated,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 10),
        ),
        Text(
          value.format(),
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.canReverse,
    required this.onReverse,
  });

  final BusinessEvent event;
  final bool canReverse;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    final timestamp = event.occurredAt ?? event.recordedAt;
    final signed = switch (event.type) {
      BusinessEventType.payment || BusinessEventType.collection => event.amount,
      BusinessEventType.refund => event.amount == null ? null : -event.amount!,
      _ => null,
    };
    return ListTile(
      key: Key('event-${event.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon(event.type), color: AppColors.gold),
      title: Text(
        event.type.name.toUpperCase(),
        style: const TextStyle(color: AppColors.white, fontSize: 13),
      ),
      subtitle: Text(
        '${DateFormat('MMM d, yyyy h:mm a').format(timestamp.toLocal())}'
        '${event.reason == null ? '' : ' • ${event.reason}'}',
        style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (signed != null)
            Text(
              signed.format(),
              style: const TextStyle(color: AppColors.whiteSecondary),
            ),
          if (canReverse)
            IconButton(
              tooltip: 'Reverse event',
              onPressed: onReverse,
              icon: const Icon(Icons.undo, color: AppColors.error),
            ),
        ],
      ),
    );
  }

  IconData _icon(BusinessEventType type) => switch (type) {
    BusinessEventType.payment => Icons.payments_outlined,
    BusinessEventType.delivery => Icons.local_shipping_outlined,
    BusinessEventType.refund => Icons.currency_exchange,
    BusinessEventType.reversal => Icons.undo,
    BusinessEventType.collection => Icons.savings_outlined,
  };
}
