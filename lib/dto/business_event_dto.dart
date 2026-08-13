import '../core/money.dart';
import '../models/business_event_model.dart';
import 'dto_reader.dart';

class BusinessEventDto {
  static const currentVersion = 1;

  BusinessEventDto({
    required this.id,
    required this.userId,
    required this.subjectType,
    required this.subjectId,
    required this.eventType,
    required this.amountCentavos,
    required this.occurredAt,
    required this.recordedAt,
    required this.paymentMethod,
    required this.reference,
    required this.relatedEventId,
    required this.reason,
    required this.commandId,
    required this.provenance,
    required this.sourceType,
    required this.sourceId,
  }) {
    BusinessEvent(
      id: id,
      userId: userId,
      subject: BusinessEventSubjectExtension.fromStorage(subjectType),
      subjectId: subjectId,
      type: BusinessEventTypeExtension.fromStorage(eventType),
      amount: amountCentavos == null
          ? null
          : Money.fromCentavos(amountCentavos!),
      occurredAt: occurredAt,
      recordedAt: recordedAt,
      paymentMethod: paymentMethod,
      reference: reference,
      relatedEventId: relatedEventId,
      reason: reason,
      commandId: commandId,
      provenance: BusinessEventProvenanceExtension.fromStorage(provenance),
      sourceType: sourceType,
      sourceId: sourceId,
    );
  }

  final String id;
  final String userId;
  final String subjectType;
  final String subjectId;
  final String eventType;
  final int? amountCentavos;
  final DateTime? occurredAt;
  final DateTime recordedAt;
  final String? paymentMethod;
  final String? reference;
  final String? relatedEventId;
  final String? reason;
  final String commandId;
  final String provenance;
  final String? sourceType;
  final String? sourceId;

  factory BusinessEventDto.fromDomain(BusinessEvent event) => BusinessEventDto(
    id: event.id,
    userId: event.userId,
    subjectType: event.subject.storageKey,
    subjectId: event.subjectId,
    eventType: event.type.storageKey,
    amountCentavos: event.amount?.centavos,
    occurredAt: event.occurredAt?.toUtc(),
    recordedAt: event.recordedAt.toUtc(),
    paymentMethod: event.paymentMethod,
    reference: event.reference,
    relatedEventId: event.relatedEventId,
    reason: event.reason,
    commandId: event.commandId,
    provenance: event.provenance.storageKey,
    sourceType: event.sourceType,
    sourceId: event.sourceId,
  );

  factory BusinessEventDto.fromLocal(Map<String, dynamic> map) => _fromMap(map);

  factory BusinessEventDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static BusinessEventDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
  }) {
    final r = DtoReader(map, 'BusinessEvent');
    r.version(currentVersion);
    return BusinessEventDto(
      id: r.string(const ['id']),
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
      subjectType: r.string(const ['subject_type', 'subjectType']),
      subjectId: r.string(const ['subject_id', 'subjectId']),
      eventType: r.string(const ['event_type', 'eventType']),
      amountCentavos: r.optionalInteger(const [
        'amount_centavos',
        'amountCentavos',
      ]),
      occurredAt: r.optionalDate(const ['occurred_at', 'occurredAt']),
      recordedAt: r.date(const ['recorded_at', 'recordedAt']),
      paymentMethod: r.optionalString(const [
        'payment_method',
        'paymentMethod',
      ]),
      reference: r.optionalString(const ['reference']),
      relatedEventId: r.optionalString(const [
        'related_event_id',
        'relatedEventId',
      ]),
      reason: r.optionalString(const ['reason']),
      commandId: r.string(const ['command_id', 'commandId']),
      provenance: r.string(const ['provenance'], defaultValue: 'native'),
      sourceType: r.optionalString(const ['source_type', 'sourceType']),
      sourceId: r.optionalString(const ['source_id', 'sourceId']),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'user_id': userId,
    'subject_type': subjectType,
    'subject_id': subjectId,
    'event_type': eventType,
    'amount_centavos': amountCentavos,
    'occurred_at': occurredAt?.toUtc().toIso8601String(),
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'payment_method': paymentMethod,
    'reference': reference,
    'related_event_id': relatedEventId,
    'reason': reason,
    'command_id': commandId,
    'provenance': provenance,
    'source_type': sourceType,
    'source_id': sourceId,
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  BusinessEvent toDomain() => BusinessEvent(
    id: id,
    userId: userId,
    subject: BusinessEventSubjectExtension.fromStorage(subjectType),
    subjectId: subjectId,
    type: BusinessEventTypeExtension.fromStorage(eventType),
    amount: amountCentavos == null ? null : Money.fromCentavos(amountCentavos!),
    occurredAt: occurredAt,
    recordedAt: recordedAt,
    paymentMethod: paymentMethod,
    reference: reference,
    relatedEventId: relatedEventId,
    reason: reason,
    commandId: commandId,
    provenance: BusinessEventProvenanceExtension.fromStorage(provenance),
    sourceType: sourceType,
    sourceId: sourceId,
  );
}
