// ─────────────────────────────────────────────────────────────────────────────
// session_timeout_service.dart — Auto-logout on user inactivity
// Purpose : Tracks user activity and automatically logs out the session after
//           a configurable period of inactivity. Uses a pure Dart Timer so
//           there are no platform channel dependencies or plugin requirements.
//
// Design decisions:
//   • Pure Dart Timer — no platform channels, no plugins.
//   • Singleton so any widget can call bump() to reset the timer from anywhere.
//   • Callback-based: the caller (main_shell) provides an onTimeout handler
//     so this service stays free of BuildContext and navigation concerns.
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

// Singleton — one timer shared across all widgets in the app
class SessionTimeoutService {
  SessionTimeoutService._(); // Private constructor prevents external instantiation
  static final SessionTimeoutService instance = SessionTimeoutService._();

  /// How long the user must be inactive before auto-logout is triggered.
  /// Override before calling start() if a shorter or longer timeout is needed.
  Duration timeoutDuration = const Duration(minutes: 10);

  Timer?        _timer;     // Active inactivity countdown; null when not running
  VoidCallback? _onTimeout; // Called once when the timer fires

  /// Starts (or restarts) the inactivity timer.
  /// [onTimeout] is called exactly once when the configured duration elapses.
  /// Calling start() while already running resets the countdown to zero.
  void start({required VoidCallback onTimeout}) {
    _onTimeout = onTimeout;
    _resetTimer(); // Cancel any existing timer and start a fresh one
  }

  /// Resets the inactivity countdown — call this on any user activity event.
  /// Ignores the call if start() has not been called yet (timer is null).
  void bump() {
    if (_timer == null) return; // Session not started — ignore activity events
    _resetTimer();
  }

  /// Permanently stops the inactivity timer.
  /// Call this after logout so the timer does not fire on a signed-out session.
  void stop() {
    _timer?.cancel();
    _timer     = null;
    _onTimeout = null; // Clear the callback to prevent a stale reference
  }

  // Cancels the current timer and starts a new one from zero
  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(timeoutDuration, _handleTimeout);
  }

  // Fired by the Timer when the inactivity period expires
  void _handleTimeout() {
    _timer     = null;
    _onTimeout?.call();  // Trigger the caller-supplied logout callback
    _onTimeout = null;   // Clear after firing to prevent accidental double-fire
  }

  /// True if the service is currently monitoring for inactivity.
  bool get isRunning => _timer != null;
}
