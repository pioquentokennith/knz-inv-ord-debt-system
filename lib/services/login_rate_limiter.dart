// ─────────────────────────────────────────────────────────────────────────────
// login_rate_limiter.dart — Brute-force login protection
// Purpose : Tracks failed login attempts per username and enforces a temporary
//           lockout after too many consecutive failures.
//
// Rules (configurable via constants below):
//   • 5 consecutive wrong passwords → 30-second lockout
//   • Each additional failed attempt after lockout resets the timer
//   • Successful login clears the counter for that username
//
// Storage : SharedPreferences-backed (persistent across cold starts).
//           MINOR 1 FIX: Dati in-memory lang — nire-reset sa app restart.
//           Ngayon, nananatili ang lockout kahit i-close at buksan ulit ang app.
//
// Setup (one-time sa main.dart bago runApp):
//   await LoginRateLimiter.init();
//
// Usage:
//   final limiter = LoginRateLimiter.instance;
//
//   if (limiter.isLockedOut(username)) {
//     final secs = limiter.secondsRemaining(username);
//     // show "Too many attempts. Try again in Xs."
//     return;
//   }
//   await limiter.recordFailure(username);  // on failed login
//   await limiter.recordSuccess(username);  // on successful login
// ─────────────────────────────────────────────────────────────────────────────

import 'package:shared_preferences/shared_preferences.dart';

class LoginRateLimiter {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final LoginRateLimiter instance = LoginRateLimiter._();
  LoginRateLimiter._();

  // ── Configuration ─────────────────────────────────────────────────────────
  /// Number of consecutive failures before lockout kicks in.
  static const int maxAttempts = 5;

  /// How long the lockout lasts after hitting [maxAttempts].
  static const Duration lockoutDuration = Duration(seconds: 30);

  // ── SharedPreferences key prefixes ────────────────────────────────────────
  static const String _prefixFailures = 'lrl_failures_';
  static const String _prefixLockedAt = 'lrl_locked_at_';

  // ── Internal prefs instance ───────────────────────────────────────────────
  static SharedPreferences? _prefs;

  /// Call once at app startup (in main.dart) before using [instance].
  ///   await LoginRateLimiter.init();
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    assert(_prefs != null,
        'LoginRateLimiter.init() must be called before use.');
    return _prefs!;
  }

  // ── Private helpers ───────────────────────────────────────────────────────
  String _failKey(String key)   => '$_prefixFailures$key';
  String _lockKey(String key)   => '$_prefixLockedAt$key';

  int _getFailures(String key) => _p.getInt(_failKey(key)) ?? 0;

  DateTime? _getLockedAt(String key) {
    final ms = _p.getInt(_lockKey(key));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _setFailures(String key, int count) =>
      _p.setInt(_failKey(key), count);

  Future<void> _setLockedAt(String key, DateTime dt) =>
      _p.setInt(_lockKey(key), dt.millisecondsSinceEpoch);

  Future<void> _clearUser(String key) async {
    await _p.remove(_failKey(key));
    await _p.remove(_lockKey(key));
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns true if [username] is currently locked out.
  bool isLockedOut(String username) {
    final key = username.toLowerCase();
    if (_getFailures(key) < maxAttempts) return false;

    final lockedTime = _getLockedAt(key);
    if (lockedTime == null) return false;

    final elapsed = DateTime.now().difference(lockedTime);
    if (elapsed >= lockoutDuration) {
      // Lockout expired — clear persisted state (fire & forget)
      _clearUser(key);
      return false;
    }
    return true;
  }

  /// Seconds remaining in the current lockout for [username].
  /// Returns 0 if not locked out.
  int secondsRemaining(String username) {
    final key = username.toLowerCase();
    final lockedTime = _getLockedAt(key);
    if (lockedTime == null) return 0;

    final elapsed = DateTime.now().difference(lockedTime);
    final remaining = lockoutDuration - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds + 1;
  }

  /// How many failed attempts have been recorded for [username].
  int failureCount(String username) => _getFailures(username.toLowerCase());

  /// Call after every failed login attempt.
  /// Starts or extends the lockout when [maxAttempts] is reached.
  Future<void> recordFailure(String username) async {
    final key   = username.toLowerCase();
    final count = _getFailures(key) + 1;
    await _setFailures(key, count);

    if (count >= maxAttempts) {
      // Re-start lockout timer on every failure at/above threshold.
      // Prevents user from waiting 29s, failing once more, and getting
      // only 1s of extra lockout.
      await _setLockedAt(key, DateTime.now());
    }
  }

  /// Call after a successful login. Resets failure counter.
  Future<void> recordSuccess(String username) =>
      _clearUser(username.toLowerCase());

  /// Clears ALL lockout state. Useful for testing or admin override.
  Future<void> reset() async {
    final keys = _p
        .getKeys()
        .where((k) =>
            k.startsWith(_prefixFailures) || k.startsWith(_prefixLockedAt))
        .toList();
    for (final k in keys) {
      await _p.remove(k);
    }
  }
}