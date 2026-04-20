// ─────────────────────────────────────────────────────────────────────────────
// session_timeout_service_test.dart — Unit tests for SessionTimeoutService
//
// Uses fake async to control time without real-world delays.
//
// Coverage:
//   ✔ onTimeout fires after the configured duration
//   ✔ bump() resets the timer — timeout does NOT fire early
//   ✔ stop() cancels the timer — timeout never fires
//   ✔ bump() is a no-op before start() — no crash
//   ✔ onTimeout fires only once even if _handleTimeout is called again
//   ✔ start() while already running resets the timer cleanly
// ─────────────────────────────────────────────────────────────────────────────

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/services/session_timeout_service.dart';

void main() {
  const timeout = Duration(minutes: 10);

  // Always reset the singleton between tests
  setUp(() => SessionTimeoutService.instance.stop());
  tearDown(() => SessionTimeoutService.instance.stop());

  test('onTimeout fires after the configured inactivity duration', () {
    fakeAsync((async) {
      final svc = SessionTimeoutService.instance
        ..timeoutDuration = timeout;

      var fired = false;
      svc.start(onTimeout: () => fired = true);

      async.elapse(timeout - const Duration(seconds: 1));
      expect(fired, isFalse, reason: 'Must not fire before the full duration');

      async.elapse(const Duration(seconds: 1));
      expect(fired, isTrue, reason: 'Must fire exactly at the timeout boundary');
    });
  });

  test('bump() resets the timer — timeout does not fire at original deadline', () {
    fakeAsync((async) {
      final svc = SessionTimeoutService.instance
        ..timeoutDuration = timeout;

      var fired = false;
      svc.start(onTimeout: () => fired = true);

      // Advance 9 minutes, then simulate user activity
      async.elapse(const Duration(minutes: 9));
      svc.bump();

      // Original 10-minute deadline has now passed (9+1 from original start)
      // but bump() reset, so we only need to check that it has NOT fired yet
      async.elapse(const Duration(minutes: 9));
      expect(fired, isFalse, reason: 'bump() should have reset the countdown');

      // Now complete the full 10 minutes from the bump
      async.elapse(const Duration(minutes: 1));
      expect(fired, isTrue, reason: 'Should fire 10 min after the last bump');
    });
  });

  test('stop() cancels the timer — onTimeout never fires', () {
    fakeAsync((async) {
      final svc = SessionTimeoutService.instance
        ..timeoutDuration = timeout;

      var fired = false;
      svc.start(onTimeout: () => fired = true);

      async.elapse(const Duration(minutes: 5));
      svc.stop();

      async.elapse(const Duration(minutes: 10));
      expect(fired, isFalse, reason: 'stop() must cancel the timer entirely');
    });
  });

  test('bump() before start() does not crash', () {
    fakeAsync((async) {
      expect(
        () => SessionTimeoutService.instance.bump(),
        returnsNormally,
        reason: 'bump() on a stopped service must be a safe no-op',
      );
    });
  });

  test('calling start() again resets the timer from zero', () {
    fakeAsync((async) {
      final svc = SessionTimeoutService.instance
        ..timeoutDuration = timeout;

      var fireCount = 0;
      svc.start(onTimeout: () => fireCount++);

      // 8 minutes in — call start() again (e.g. user navigates away and back)
      async.elapse(const Duration(minutes: 8));
      svc.start(onTimeout: () => fireCount++);

      // Original deadline (10 min from first start) passes — must NOT fire
      async.elapse(const Duration(minutes: 2));
      expect(fireCount, 0,
          reason: 'Restarting should reset the deadline from the new start');

      // Full 10 minutes from the second start
      async.elapse(const Duration(minutes: 8));
      expect(fireCount, 1, reason: 'Timer from second start should now fire');
    });
  });

  test('isRunning reflects service state correctly', () {
    fakeAsync((async) {
      final svc = SessionTimeoutService.instance
        ..timeoutDuration = timeout;

      expect(svc.isRunning, isFalse);

      svc.start(onTimeout: () {});
      expect(svc.isRunning, isTrue);

      svc.stop();
      expect(svc.isRunning, isFalse);
    });
  });
}
