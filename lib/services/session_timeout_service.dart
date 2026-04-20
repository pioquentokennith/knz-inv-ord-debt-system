// ─────────────────────────────────────────────────────────────────────────────
// session_timeout_service.dart — Auto-logout on user inactivity
//
// Design:
//   • Pure Dart Timer — no platform channels, no plugins.
//   • Singleton so any widget can call bump() to reset the timer.
//   • Callback-based: the caller (main_shell) provides an onTimeout handler
//     so the service itself stays free of BuildContext and navigation.
//   • Configurable timeout via [timeoutDuration] (default: 10 minutes).
//   • Call start() after login, stop() after logout.
//   • Call bump() on any user interaction (touch, scroll, key press).
//
// Usage in MainShell:
//   SessionTimeoutService.instance.start(onTimeout: () {
//     AppState().logout();
//     Navigator.pushReplacement(...LoginScreen);
//   });
//   // In GestureDetector wrapping the whole shell body:
//   onTap: () => SessionTimeoutService.instance.bump(),
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:ui' show VoidCallback;

class SessionTimeoutService {
  SessionTimeoutService._();
  static final SessionTimeoutService instance = SessionTimeoutService._();

  /// How long the user must be inactive before auto-logout is triggered.
  /// Override before calling start() if a different timeout is needed.
  Duration timeoutDuration = const Duration(minutes: 10);

  Timer?       _timer;
  VoidCallback? _onTimeout;

  /// Starts (or restarts) the inactivity timer.
  /// [onTimeout] is called once when the timer fires.
  /// Calling start() while already running resets the timer.
  void start({required VoidCallback onTimeout}) {
    _onTimeout = onTimeout;
    _resetTimer();
  }

  /// Resets the inactivity timer — call this on any user activity event.
  void bump() {
    if (_timer == null) return; // not started — ignore
    _resetTimer();
  }

  /// Permanently stops the timer (call after logout).
  void stop() {
    _timer?.cancel();
    _timer    = null;
    _onTimeout = null;
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(timeoutDuration, _handleTimeout);
  }

  void _handleTimeout() {
    _timer    = null;
    _onTimeout?.call();
    _onTimeout = null; // prevent double-fire
  }

  /// True if the service is currently watching for inactivity.
  bool get isRunning => _timer != null;
}
