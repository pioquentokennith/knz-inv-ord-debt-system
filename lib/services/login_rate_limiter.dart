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
// Storage : In-memory only (Map). Resets when the app is restarted.
//           This is intentional — a local admin app does not need
//           persistent lockout across cold starts.
//
// Usage:
//   final limiter = LoginRateLimiter.instance;
//
//   // Before attempting login:
//   if (limiter.isLockedOut(username)) {
//     final secs = limiter.secondsRemaining(username);
//     // show "Too many attempts. Try again in Xs."
//     return;
//   }
//
//   // After a failed login:
//   limiter.recordFailure(username);
//
//   // After a successful login:
//   limiter.recordSuccess(username);
// ─────────────────────────────────────────────────────────────────────────────

class LoginRateLimiter {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final LoginRateLimiter instance = LoginRateLimiter._();
  LoginRateLimiter._();

  // ── Configuration ─────────────────────────────────────────────────────────
  /// Number of consecutive failures before lockout kicks in.
  static const int maxAttempts = 5;

  /// How long the lockout lasts after hitting [maxAttempts].
  static const Duration lockoutDuration = Duration(seconds: 30);

  // ── Internal state ────────────────────────────────────────────────────────
  // Both maps are keyed by lowercase username.
  final Map<String, int>      _failures  = {}; // consecutive failure count
  final Map<String, DateTime> _lockedAt  = {}; // when the lockout started

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns true if [username] is currently locked out.
  bool isLockedOut(String username) {
    final key = username.toLowerCase();
    if (_failures[key] == null || _failures[key]! < maxAttempts) return false;

    final lockedTime = _lockedAt[key];
    if (lockedTime == null) return false;

    final elapsed = DateTime.now().difference(lockedTime);
    if (elapsed >= lockoutDuration) {
      // Lockout has expired — clear state automatically
      _failures.remove(key);
      _lockedAt.remove(key);
      return false;
    }
    return true;
  }

  /// Seconds remaining in the current lockout for [username].
  /// Returns 0 if not locked out.
  int secondsRemaining(String username) {
    final key = username.toLowerCase();
    final lockedTime = _lockedAt[key];
    if (lockedTime == null) return 0;

    final elapsed = DateTime.now().difference(lockedTime);
    final remaining = lockoutDuration - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds + 1;
  }

  /// How many failed attempts have been recorded for [username].
  int failureCount(String username) => _failures[username.toLowerCase()] ?? 0;

  /// Call this after every failed login attempt for [username].
  /// Starts or extends the lockout if [maxAttempts] is reached.
  void recordFailure(String username) {
    final key = username.toLowerCase();
    final count = (_failures[key] ?? 0) + 1;
    _failures[key] = count;

    if (count >= maxAttempts) {
      // (Re-)start the lockout timer on every failure at or above the threshold.
      // This prevents a user from waiting 29 s, failing once more, and
      // getting only 1 s of extra lockout.
      _lockedAt[key] = DateTime.now();
    }
  }

  /// Call this after a successful login for [username].
  /// Resets the failure counter so the user starts fresh next time.
  void recordSuccess(String username) {
    final key = username.toLowerCase();
    _failures.remove(key);
    _lockedAt.remove(key);
  }

  /// Clears ALL lockout state. Useful for testing or admin override.
  void reset() {
    _failures.clear();
    _lockedAt.clear();
  }
}