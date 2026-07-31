import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/domain_exceptions.dart';
import 'package:knz_scent_admin/repositories/base_repository.dart';

class _ReadRepository extends BaseRepository {
  Future<List<String>> failingRead() =>
      safeCall(() => throw StateError('database unavailable'));
}

void main() {
  test(
    'repository read failure is not converted to a false empty dataset',
    () async {
      await expectLater(
        _ReadRepository().failingRead(),
        throwsA(
          isA<DataReadException>().having(
            (error) => error.message,
            'message',
            contains('database unavailable'),
          ),
        ),
      );
    },
  );
}
