import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/services/session_timeout_service.dart';

void main() {
  final service = SessionTimeoutService.instance;

  tearDown(() {
    service.stop();
    service.timeoutDuration = const Duration(minutes: 10);
  });

  test('warns, resets on activity, and times out exactly once', () {
    fakeAsync((async) {
      var warnings = 0;
      var timeouts = 0;
      service.timeoutDuration = const Duration(minutes: 2);
      service.start(onWarning: () => warnings++, onTimeout: () => timeouts++);

      async.elapse(const Duration(minutes: 1));
      expect(warnings, 1);
      expect(timeouts, 0);

      service.bump();
      async.elapse(const Duration(minutes: 1));
      expect(warnings, 2);
      expect(timeouts, 0);

      async.elapse(const Duration(minutes: 1));
      expect(timeouts, 1);
      expect(service.isRunning, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(timeouts, 1);
    });
  });

  test('stop cancels warning and timeout callbacks', () {
    fakeAsync((async) {
      var called = false;
      service.timeoutDuration = const Duration(minutes: 2);
      service.start(
        onWarning: () => called = true,
        onTimeout: () => called = true,
      );

      service.stop();
      async.elapse(const Duration(minutes: 3));

      expect(called, isFalse);
      expect(service.secondsRemaining, 0);
    });
  });
}
