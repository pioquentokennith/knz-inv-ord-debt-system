// ─────────────────────────────────────────────────────────────────────────────
// base_repository.dart — Abstract base for all local repositories
// Purpose : Provides shared database access and consistent error reporting.
//           Critical writes are always rethrown after reporting so callers never
//           mistake a failed persistence operation for success.
// OOP Pillars demonstrated:
//   • Abstraction  — abstract class; subclasses must define their own queries
//   • Encapsulation— shared db access is a protected member (not public)
//   • Inheritance  — all LocalXxxRepository classes extend this
//   • Polymorphism — safeCall<T> works for any return type via generics
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../core/domain_exceptions.dart';
import '../database/database_helper.dart';

abstract class BaseRepository {
  /// Shared database instance — inherited by all subclasses (Inheritance)
  // db is protected: accessible by subclasses but not exposed publicly
  final db = DatabaseHelper.instance;

  /// Reports read failures and propagates them so callers can preserve their
  /// last-known-good state instead of replacing it with a false empty result.
  /// [action]   — the async operation to execute
  Future<T> safeCall<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      if (e is DomainException) rethrow;
      throw DataReadException('Local data could not be loaded: $e');
    }
  }

  /// Runs a critical write and propagates any failure after reporting it.
  ///
  /// Repositories must use this for user-visible mutations. Swallowing a failed
  /// insert/update/delete lets upper layers update memory and show a false success
  /// message even though SQLite did not commit the change.
  Future<void> safeVoidCall(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
    }
  }

  /// Value-returning counterpart of [safeVoidCall] for critical mutations that
  /// must return their committed result (for example, an allocated order id).
  Future<T> safeWriteCall<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e, stackTrace) {
      _onError(e, stackTrace);
      rethrow;
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
