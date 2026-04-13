// ─────────────────────────────────────────────────────────────────────────────
// base_repository.dart — Abstract base for all local repositories
// OOP Pillars demonstrated:
//   • Abstraction  — abstract class; subclasses must define their own queries
//   • Encapsulation— shared db access is a protected member (not public)
//   • Inheritance  — all LocalXxxRepository classes extend this
//   • Polymorphism — safeCall<T> works for any return type via generics
// ─────────────────────────────────────────────────────────────────────────────

import '../database/database_helper.dart';

abstract class BaseRepository {
  /// Shared database instance — inherited by all subclasses (Inheritance)
  final db = DatabaseHelper.instance;

  /// Generic safe-call wrapper — handles errors gracefully (Polymorphism via generics).
  /// [action]   — the async operation to execute
  /// [fallback] — the default value returned on failure
  Future<T> safeCall<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      return fallback;
    }
  }

  /// Wraps a void async action and swallows errors gracefully.
  /// Use only for non-critical side effects (e.g. logging, sync).
  Future<void> safeVoidCall(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
    }
  }

  /// Error hook — subclasses may override to plug in a crash reporter.
  /// Default behaviour: no-op (silent resilience for offline-first apps).
  /// Production: override and call FirebaseCrashlytics.instance.recordError().
  void _onError(Object error, StackTrace stackTrace) {
    // FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
}
