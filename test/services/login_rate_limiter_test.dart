import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/services/login_rate_limiter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final limiter = LoginRateLimiter.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LoginRateLimiter.init();
  });

  setUp(limiter.reset);
  tearDown(limiter.reset);

  test('locks a normalized account after five failures', () async {
    for (var attempt = 0; attempt < LoginRateLimiter.maxAttempts; attempt++) {
      await limiter.recordFailure(
        attempt.isEven ? 'Admin@Example.com' : 'admin@example.com',
      );
    }

    expect(
      limiter.failureCount('ADMIN@example.com'),
      LoginRateLimiter.maxAttempts,
    );
    expect(limiter.isLockedOut('admin@example.com'), isTrue);
    expect(
      limiter.secondsRemaining('admin@example.com'),
      inInclusiveRange(1, 30),
    );
  });

  test('a successful login clears persisted lockout state', () async {
    for (var attempt = 0; attempt < LoginRateLimiter.maxAttempts; attempt++) {
      await limiter.recordFailure('staff@example.com');
    }

    await limiter.recordSuccess('STAFF@example.com');

    expect(limiter.failureCount('staff@example.com'), 0);
    expect(limiter.isLockedOut('staff@example.com'), isFalse);
  });
}
