import '../models/business_event_model.dart';

abstract class BusinessEventRepository {
  Future<List<BusinessEvent>> getAll(String userId);

  Future<List<BusinessEvent>> getForSubject(
    String userId,
    BusinessEventSubject subject,
    String subjectId,
  );
}
