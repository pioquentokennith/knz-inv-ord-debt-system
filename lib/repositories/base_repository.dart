// ─────────────────────────────────────────────────────────────────────────────
// base_repository.dart — Abstract base for all local repositories
// Purpose : Provides shared database access and a generic error-handling wrapper
//           (safeCall / safeVoidCall) so every subclass gets consistent error
//           logging and Crashlytics reporting for free.
// OOP Pillars demonstrated:
//   • Abstraction  — abstract class; subclasses must define their own queries
//   • Encapsulation— shared db access is a protected member (not public)
//   • Inheritance  — all LocalXxxRepository classes extend this
//   • Polymorphism — safeCall<T> works for any return type via generics
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

abstract class BaseRepository {
  /// Shared database instance — inherited by all subclasses (Inheritance)
  // db is protected: accessible by subclasses but not exposed publicly
  final db = DatabaseHelper.instance;

  /// Generic safe-call wrapper — handles errors gracefully (Polymorphism via generics).
  /// [action]   — the async operation to execute
  /// [fallback] — the default value returned on failure
  // Returns fallback instead of throwing, so UI never crashes on DB errors
  Future<T> safeCall<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      return fallback; // Caller gets an empty list / null / false instead of a crash
    }
  }

  /// Wraps a void async action and swallows errors gracefully.
  /// Use only for non-critical side effects (e.g. logging, sync).
  // Void variant — used when there is no meaningful return value to fall back to
  Future<void> safeVoidCall(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
    }
  }

  /// Error hook — logs in debug, reports to Crashlytics in production.
  // Single error-handling point for all repository operations
  void _onError(Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      // In development: print full error + stack trace to the console
      debugPrint('[BaseRepository] ERROR: $error');
      debugPrint('[BaseRepository] STACK: $stackTrace');
    } else {
      // Production: report to Firebase Crashlytics for monitoring.
      // fatal: false because a failed DB query shouldn't crash the whole app
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
    }
  }
}
