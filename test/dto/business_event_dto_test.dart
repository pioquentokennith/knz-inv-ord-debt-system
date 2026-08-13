import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';

void main() {
  test('business event round-trips through local and cloud DTOs', () {
    final occurredAt = DateTime.utc(2026, 7, 10, 12, 30);
    final event = BusinessEvent(
      id: 'event-1',
      userId: 'owner-1',
      subject: BusinessEventSubject.order,
      subjectId: 'order-1',
      type: BusinessEventType.refund,
      amount: const Money.fromCentavos(1250),
      occurredAt: occurredAt,
      recordedAt: occurredAt.add(const Duration(minutes: 1)),
      reason: 'Damaged item',
      commandId: 'command-1',
      provenance: BusinessEventProvenance.native,
      sourceType: 'manual_refund',
      sourceId: 'refund-1',
    );

    final dto = BusinessEventDto.fromDomain(event);
    final local = BusinessEventDto.fromLocal(dto.toLocal()).toDomain();
    final cloud = BusinessEventDto.fromCloud(
      dto.toCloud(),
      userId: 'owner-1',
    ).toDomain();

    for (final restored in [local, cloud]) {
      expect(restored.id, event.id);
      expect(restored.userId, event.userId);
      expect(restored.subject, event.subject);
      expect(restored.subjectId, event.subjectId);
      expect(restored.type, event.type);
      expect(restored.amount, event.amount);
      expect(restored.occurredAt, event.occurredAt);
      expect(restored.recordedAt, event.recordedAt);
      expect(restored.reason, event.reason);
      expect(restored.provenance, event.provenance);
      expect(restored.sourceType, event.sourceType);
      expect(restored.sourceId, event.sourceId);
    }
  });

  test('event model rejects invalid subject and type combinations', () {
    expect(
      () => BusinessEvent(
        id: 'event-1',
        userId: 'owner-1',
        subject: BusinessEventSubject.debt,
        subjectId: 'debt-1',
        type: BusinessEventType.payment,
        amount: const Money.fromCentavos(100),
        occurredAt: DateTime.utc(2026),
        recordedAt: DateTime.utc(2026),
        commandId: 'command-1',
      ),
      throwsArgumentError,
    );
    expect(
      () => BusinessEvent(
        id: 'event-2',
        userId: 'owner-1',
        subject: BusinessEventSubject.order,
        subjectId: 'order-1',
        type: BusinessEventType.delivery,
        amount: const Money.fromCentavos(100),
        occurredAt: DateTime.utc(2026),
        recordedAt: DateTime.utc(2026),
        commandId: 'command-2',
      ),
      throwsArgumentError,
    );
  });

  test('ledger rejects a reversal with a different target amount', () {
    final timestamp = DateTime.utc(2026);
    final payment = BusinessEvent(
      id: 'payment',
      userId: 'owner',
      subject: BusinessEventSubject.order,
      subjectId: 'order',
      type: BusinessEventType.payment,
      amount: const Money.fromCentavos(1000),
      occurredAt: timestamp,
      recordedAt: timestamp,
      paymentMethod: 'cash_on_delivery',
      commandId: 'payment',
    );
    final reversal = BusinessEvent(
      id: 'reversal',
      userId: 'owner',
      subject: BusinessEventSubject.order,
      subjectId: 'order',
      type: BusinessEventType.reversal,
      amount: const Money.fromCentavos(999),
      occurredAt: timestamp,
      recordedAt: timestamp,
      relatedEventId: payment.id,
      reason: 'Correction',
      commandId: 'reversal',
    );

    expect(
      () => BusinessEventLedger.netCash([payment, reversal]),
      throwsStateError,
    );
  });
}
