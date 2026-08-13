import '../core/money.dart';

enum BusinessEventSubject { order, debt, customOrder }

extension BusinessEventSubjectExtension on BusinessEventSubject {
  String get storageKey => switch (this) {
    BusinessEventSubject.order => 'order',
    BusinessEventSubject.debt => 'debt',
    BusinessEventSubject.customOrder => 'custom_order',
  };

  static BusinessEventSubject fromStorage(String value) => switch (value) {
    'order' => BusinessEventSubject.order,
    'debt' => BusinessEventSubject.debt,
    'custom_order' => BusinessEventSubject.customOrder,
    _ => throw FormatException('Unknown business event subject: $value'),
  };
}

enum BusinessEventType { payment, delivery, refund, reversal, collection }

extension BusinessEventTypeExtension on BusinessEventType {
  String get storageKey => name;

  static BusinessEventType fromStorage(String value) =>
      BusinessEventType.values.firstWhere(
        (type) => type.storageKey == value,
        orElse: () =>
            throw FormatException('Unknown business event type: $value'),
      );
}

enum BusinessEventProvenance {
  native,
  legacyExact,
  legacyInferred,
  legacyUnknown,
}

extension BusinessEventProvenanceExtension on BusinessEventProvenance {
  String get storageKey => switch (this) {
    BusinessEventProvenance.native => 'native',
    BusinessEventProvenance.legacyExact => 'legacy_exact',
    BusinessEventProvenance.legacyInferred => 'legacy_inferred',
    BusinessEventProvenance.legacyUnknown => 'legacy_unknown',
  };

  static BusinessEventProvenance fromStorage(String value) => switch (value) {
    'native' => BusinessEventProvenance.native,
    'legacy_exact' => BusinessEventProvenance.legacyExact,
    'legacy_inferred' => BusinessEventProvenance.legacyInferred,
    'legacy_unknown' => BusinessEventProvenance.legacyUnknown,
    _ => throw FormatException('Unknown event provenance: $value'),
  };
}

/// Immutable accounting and lifecycle fact.
class BusinessEvent {
  BusinessEvent({
    required this.id,
    required this.userId,
    required this.subject,
    required this.subjectId,
    required this.type,
    this.amount,
    this.occurredAt,
    required this.recordedAt,
    this.paymentMethod,
    this.reference,
    this.relatedEventId,
    this.reason,
    required this.commandId,
    this.provenance = BusinessEventProvenance.native,
    this.sourceType,
    this.sourceId,
  }) {
    if (id.trim().isEmpty ||
        userId.trim().isEmpty ||
        subjectId.trim().isEmpty ||
        commandId.trim().isEmpty) {
      throw ArgumentError('Business event identity cannot be blank.');
    }
    final requiresAmount = type != BusinessEventType.delivery;
    if (requiresAmount != (amount != null) ||
        (amount != null && !amount!.isPositive)) {
      throw ArgumentError(
        requiresAmount
            ? 'This business event requires a positive amount.'
            : 'Delivery events cannot contain an amount.',
      );
    }
    if (provenance == BusinessEventProvenance.native && occurredAt == null) {
      throw ArgumentError('Native events require an occurrence timestamp.');
    }
    if ((sourceType == null) != (sourceId == null)) {
      throw ArgumentError('Event source type and source id must be paired.');
    }
    if (type == BusinessEventType.collection &&
        subject == BusinessEventSubject.order) {
      throw ArgumentError('Collection events require a debt or custom order.');
    }
    if (type != BusinessEventType.collection &&
        subject != BusinessEventSubject.order) {
      throw ArgumentError('This event type requires a standard order.');
    }
    if (type == BusinessEventType.reversal) {
      if (relatedEventId?.trim().isEmpty ?? true) {
        throw ArgumentError('A reversal must reference its target event.');
      }
      if (reason?.trim().isEmpty ?? true) {
        throw ArgumentError('A reversal reason is required.');
      }
    } else if (relatedEventId != null) {
      throw ArgumentError('Only reversal events may reference another event.');
    }
    if (type == BusinessEventType.refund && (reason?.trim().isEmpty ?? true)) {
      throw ArgumentError('A refund reason is required.');
    }
  }

  final String id;
  final String userId;
  final BusinessEventSubject subject;
  final String subjectId;
  final BusinessEventType type;
  final Money? amount;
  final DateTime? occurredAt;
  final DateTime recordedAt;
  final String? paymentMethod;
  final String? reference;
  final String? relatedEventId;
  final String? reason;
  final String commandId;
  final BusinessEventProvenance provenance;
  final String? sourceType;
  final String? sourceId;

  bool get isFinancial => type != BusinessEventType.delivery;
}

class BusinessEventLedger {
  const BusinessEventLedger._();

  static Money cashEffect(
    BusinessEvent event,
    Map<String, BusinessEvent> eventsById,
  ) {
    final amount = event.amount ?? Money.zero;
    return switch (event.type) {
      BusinessEventType.payment || BusinessEventType.collection => amount,
      BusinessEventType.refund => -amount,
      BusinessEventType.delivery => Money.zero,
      BusinessEventType.reversal => _reversalEffect(event, eventsById),
    };
  }

  static Money netCash(Iterable<BusinessEvent> events) {
    final list = events.toList(growable: false);
    final byId = {for (final event in list) event.id: event};
    return list.fold(Money.zero, (sum, event) => sum + cashEffect(event, byId));
  }

  static Money _reversalEffect(
    BusinessEvent reversal,
    Map<String, BusinessEvent> eventsById,
  ) {
    final target = eventsById[reversal.relatedEventId];
    if (target == null ||
        (target.type != BusinessEventType.payment &&
            target.type != BusinessEventType.refund)) {
      throw StateError('Reversal target is missing or unsupported.');
    }
    final targetEffect = target.type == BusinessEventType.payment
        ? target.amount!
        : -target.amount!;
    if (reversal.amount != target.amount) {
      throw StateError('Reversal amount does not match its target.');
    }
    return -targetEffect;
  }
}
