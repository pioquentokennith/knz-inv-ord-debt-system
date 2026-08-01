// ─────────────────────────────────────────────────────────────────────────────
// sync_queue.dart — Durable Firestore transactional outbox
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import 'firestore_sync.dart';

abstract interface class SyncOutbox {
  bool get isOnline;

  Future<int> enqueue({
    required String operation,
    required String collection,
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
    DatabaseExecutor? executor,
  });

  void requestSync();
}

class SyncStatus {
  const SyncStatus({
    required this.pendingCount,
    required this.failedCount,
    this.lastError,
  });

  const SyncStatus.empty() : this(pendingCount: 0, failedCount: 0);

  final int pendingCount;
  final int failedCount;
  final String? lastError;

  bool get hasFailures => failedCount > 0;
  bool get hasPending => pendingCount > 0;
}

class SyncProcessResult {
  const SyncProcessResult({
    required this.completedCount,
    this.failedRowId,
    this.error,
  });

  const SyncProcessResult.skipped() : this(completedCount: 0);

  final int completedCount;
  final int? failedRowId;
  final Object? error;

  bool get succeeded => error == null;
}

typedef OutboxDispatch = Future<void> Function(Map<String, Object?> row);

/// Testable durable processor. Connectivity only triggers this processor; a row
/// is removed exclusively after [dispatch] confirms remote success.
class OutboxProcessor {
  OutboxProcessor({
    required Future<Database> Function() databaseProvider,
    required OutboxDispatch dispatch,
    DateTime Function()? now,
  }) : _databaseProvider = databaseProvider,
       _dispatch = dispatch,
       _now = now ?? (() => DateTime.now().toUtc());

  final Future<Database> Function() _databaseProvider;
  final OutboxDispatch _dispatch;
  final DateTime Function() _now;

  Future<SyncProcessResult> processUser(
    String userId, {
    bool Function()? shouldContinue,
  }) async {
    final database = await _databaseProvider();
    final pending = await database.query(
      'sync_queue',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
      limit: 100,
    );
    var completed = 0;

    for (final row in pending) {
      if (shouldContinue != null && !shouldContinue()) break;
      final now = _now().toUtc();
      final nextAttempt = row['next_attempt_at'] as String?;
      final retryAt = nextAttempt == null
          ? null
          : DateTime.tryParse(nextAttempt)?.toUtc();
      if (retryAt != null && retryAt.isAfter(now)) break;

      final rowId = row['id'] as int;
      final claimed = await database.update(
        'sync_queue',
        {
          'status': 'syncing',
          'last_attempt_at': now.toIso8601String(),
          'last_error': null,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [rowId, userId],
      );
      if (claimed != 1) {
        throw StateError('Outbox row $rowId changed before it could be sent.');
      }

      try {
        await _dispatch(Map<String, Object?>.from(row));
        final deleted = await database.delete(
          'sync_queue',
          where: 'id = ? AND user_id = ?',
          whereArgs: [rowId, userId],
        );
        if (deleted != 1) {
          throw StateError(
            'Remote sync succeeded but outbox row $rowId was not completed.',
          );
        }
        completed++;
      } catch (error) {
        await _recordFailure(database, row, error, now);
        return SyncProcessResult(
          completedCount: completed,
          failedRowId: rowId,
          error: error,
        );
      }
    }
    return SyncProcessResult(completedCount: completed);
  }

  Future<void> _recordFailure(
    Database database,
    Map<String, Object?> row,
    Object error,
    DateTime now,
  ) async {
    final attempts = (row['attempt_count'] as int? ?? 0) + 1;
    final errorText = error.toString();
    final changed = await database.update(
      'sync_queue',
      {
        'status': 'failed',
        'attempt_count': attempts,
        'last_attempt_at': now.toIso8601String(),
        'next_attempt_at': now
            .add(SyncQueue.retryDelayForAttempt(attempts))
            .toIso8601String(),
        'last_error': errorText.length <= 2000
            ? errorText
            : errorText.substring(0, 2000),
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    if (changed != 1) {
      throw StateError('Failed to persist outbox error for row ${row['id']}.');
    }
  }
}

/// Persists remote mutations in SQLite and retries them until Firestore confirms
/// success. A queue row is never removed after a failed remote operation.
class SyncQueue implements SyncOutbox {
  SyncQueue._();
  static final SyncQueue instance = SyncQueue._();

  static const int _maxBackoffSeconds = 60 * 60;

  final _cloud = FirestoreSync.instance;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  bool _isOnline = false;
  bool _isSyncing = false;
  bool _isMonitoring = false;
  int _sessionGeneration = 0;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  Stream<SyncStatus> get statusStream => _statusController.stream;

  Future<void> startMonitoring() async {
    final generation = ++_sessionGeneration;
    _isMonitoring = true;
    await _connectivitySub?.cancel();
    if (!_isMonitoring || generation != _sessionGeneration) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _handleConnectivity,
      onError: (Object _, StackTrace __) => unawaited(stopMonitoring()),
    );
    await _readInitialConnectivity();
  }

  Future<void> _readInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    _handleConnectivity(results);
  }

  void _handleConnectivity(List<ConnectivityResult> results) {
    if (!_isMonitoring) return;
    final wasOnline = _isOnline;
    _isOnline = results.any((result) => result != ConnectivityResult.none);

    if (!_isOnline) {
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }

    if (!wasOnline) {
      _scheduleSync(const Duration(seconds: 1));
    } else {
      requestSync();
    }
  }

  Future<void> stopMonitoring() async {
    _isMonitoring = false;
    _sessionGeneration++;
    final subscription = _connectivitySub;
    _connectivitySub = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _isOnline = false;
    await subscription?.cancel();
  }

  @override
  bool get isOnline => _isMonitoring && _isOnline;

  /// Adds a remote operation to the outbox.
  ///
  /// Pass the caller's SQLite transaction as [executor] so the local mutation
  /// and its remote intent commit atomically.
  @override
  Future<int> enqueue({
    required String operation,
    required String collection,
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final rowId = await database.insert('sync_queue', {
      'operation': operation,
      'collection': collection,
      'user_id': userId,
      'doc_id': docId,
      'data': jsonEncode(data),
      'created_at': now,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_attempt_at': null,
      'last_error': null,
      'status': 'pending',
      'idempotency_key': const Uuid().v4(),
      'updated_at': now,
    });
    if (rowId <= 0) throw StateError('Sync outbox row was not inserted.');
    return rowId;
  }

  /// Requests an immediate best-effort flush without making a repository write
  /// wait for network I/O.
  @override
  void requestSync() {
    if (!_isMonitoring) return;
    if (Firebase.apps.isEmpty) return;
    final principal = FirebaseAuth.instance.currentUser;
    if (principal != null && !principal.isAnonymous) {
      unawaited(_emitStatus(principal.uid));
    }
    if (!_isOnline) return;
    _scheduleSync(Duration.zero);
  }

  void _scheduleSync(Duration delay) {
    if (!_isMonitoring || !_isOnline) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_runScheduledSync()));
  }

  Future<void> _runScheduledSync() async {
    final generation = _sessionGeneration;
    try {
      await syncPending();
    } catch (error) {
      if (_isMonitoring && generation == _sessionGeneration) {
        _statusController.add(
          SyncStatus(
            pendingCount: 0,
            failedCount: 1,
            lastError: 'Synchronization could not run: $error',
          ),
        );
      }
    }
  }

  Future<SyncProcessResult> syncPending() async {
    if (!_isMonitoring || _isSyncing || !_isOnline) {
      return const SyncProcessResult.skipped();
    }
    if (Firebase.apps.isEmpty) return const SyncProcessResult.skipped();
    final principal = FirebaseAuth.instance.currentUser;
    // Anonymous bootstrap sessions may call OTP functions but are never allowed
    // to flush tenant data. Cloud account login must bind the Firebase UID to
    // the local user ID first.
    if (principal == null || principal.isAnonymous) {
      return const SyncProcessResult.skipped();
    }
    final principalUid = principal.uid;
    final generation = _sessionGeneration;
    _isSyncing = true;
    _retryTimer?.cancel();
    _retryTimer = null;

    try {
      final processor = OutboxProcessor(
        databaseProvider: () => DatabaseHelper.instance.database,
        dispatch: _dispatch,
      );
      final result = await processor.processUser(
        principalUid,
        shouldContinue: () => _sameSession(principalUid, generation),
      );
      if (_sameSession(principalUid, generation)) {
        await _emitStatus(principalUid);
      }
      return result;
    } finally {
      _isSyncing = false;
      if (_sameSession(principalUid, generation)) {
        await _scheduleNextDurableRetry();
      }
    }
  }

  Future<void> _dispatch(Map<String, Object?> row) async {
    final operation = row['operation'] as String;
    final userId = row['user_id'] as String;
    final docId = row['doc_id'] as String;
    final decoded = jsonDecode(row['data'] as String);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Outbox payload is not a JSON object.');
    }
    final data = decoded;

    switch (operation) {
      case 'save_user':
        data
          ..remove('password')
          ..remove('passwordHash')
          ..remove('password_hash')
          ..remove('salt')
          ..remove('verifier');
        await _cloud.saveUser(data);
        break;
      case 'save_product':
        await _cloud.saveProduct(userId, data);
        break;
      case 'soft_delete_product':
        await _cloud.softDeleteProduct(userId, data);
        break;
      case 'delete_product':
        await _cloud.deleteProduct(userId, docId);
        break;
      case 'save_order':
        final orderItems = _decodeEmbeddedMaps(data.remove('_items'));
        await _cloud.saveOrder(userId, data, orderItems);
        break;
      case 'create_order':
        final order = _decodeEmbeddedMap(data['_order'], '_order');
        final products = _decodeEmbeddedMaps(data['_products']);
        final debtValue = data['_debt'];
        for (final product in products) {
          await _cloud.saveProduct(userId, product);
        }
        if (debtValue != null) {
          final debt = _decodeEmbeddedMap(debtValue, '_debt');
          final payments = _decodeEmbeddedMaps(debt.remove('_payments'));
          await _cloud.saveDebt(userId, debt, payments);
        }
        final orderItems = _decodeEmbeddedMaps(order.remove('_items'));
        await _cloud.saveOrder(userId, order, orderItems);
        break;
      case 'soft_delete_order':
        final deletedOrderItems = _decodeEmbeddedMaps(data.remove('_items'));
        await _cloud.softDeleteOrder(userId, data, deletedOrderItems);
        break;
      case 'delete_order':
        await _cloud.deleteOrder(userId, docId);
        break;
      case 'save_debt':
        final debtPayments = _decodeEmbeddedMaps(data.remove('_payments'));
        await _cloud.saveDebt(userId, data, debtPayments);
        break;
      case 'soft_delete_debt':
        final deletedDebtPayments = _decodeEmbeddedMaps(
          data.remove('_payments'),
        );
        await _cloud.softDeleteDebt(userId, data, deletedDebtPayments);
        break;
      case 'delete_debt':
        await _cloud.deleteDebt(userId, docId);
        break;
      case 'save_reseller':
        await _cloud.saveReseller(userId, data);
        break;
      case 'soft_delete_reseller':
        await _cloud.softDeleteReseller(userId, data);
        break;
      case 'delete_reseller':
        await _cloud.deleteReseller(userId, docId);
        break;
      case 'save_custom_order':
        final customPayments = _decodeEmbeddedMaps(data.remove('_payments'));
        await _cloud.saveCustomOrder(userId, data, customPayments);
        break;
      case 'soft_delete_custom_order':
        final deletedCustomPayments = _decodeEmbeddedMaps(
          data.remove('_payments'),
        );
        await _cloud.softDeleteCustomOrder(userId, data, deletedCustomPayments);
        break;
      case 'delete_custom_order':
        await _cloud.deleteCustomOrder(userId, docId);
        break;
      case 'save_log':
        await _cloud.saveLog(userId, data);
        break;
      case 'update_user_password':
        throw UnsupportedError(
          'Legacy credential outbox rows are quarantined and require owner review.',
        );
      default:
        throw StateError('Unknown sync operation: $operation');
    }
  }

  List<Map<String, dynamic>> _decodeEmbeddedMaps(Object? encoded) {
    final Object? decoded = encoded is String ? jsonDecode(encoded) : encoded;
    if (decoded == null) return <Map<String, dynamic>>[];
    if (decoded is! List) {
      throw const FormatException(
        'Embedded outbox payload is not a JSON list.',
      );
    }
    return decoded
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Map<String, dynamic> _decodeEmbeddedMap(Object? encoded, String field) {
    final Object? decoded = encoded is String ? jsonDecode(encoded) : encoded;
    if (decoded is! Map) {
      throw FormatException('$field outbox payload is not a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Exponential retry schedule capped at one hour.
  static Duration retryDelayForAttempt(int attempt) {
    final exponent = (attempt - 1).clamp(0, 10).toInt();
    final seconds = math.min(_maxBackoffSeconds, 5 * (1 << exponent));
    return Duration(seconds: seconds);
  }

  bool _sameSession(String uid, int generation) {
    final current = FirebaseAuth.instance.currentUser;
    return generation == _sessionGeneration &&
        _isMonitoring &&
        current != null &&
        !current.isAnonymous &&
        current.uid == uid;
  }

  Future<SyncStatus> statusForUser(String userId) async {
    final database = await DatabaseHelper.instance.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        COUNT(*) AS pending_count,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed_count
      FROM sync_queue
      WHERE user_id = ?
    ''',
      [userId],
    );
    final lastFailure = await database.query(
      'sync_queue',
      columns: const ['last_error'],
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'failed'],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    return SyncStatus(
      pendingCount: (rows.single['pending_count'] as num?)?.toInt() ?? 0,
      failedCount: (rows.single['failed_count'] as num?)?.toInt() ?? 0,
      lastError: lastFailure.isEmpty
          ? null
          : lastFailure.single['last_error'] as String?,
    );
  }

  Future<void> retryFailed(String userId) async {
    final database = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await database.update(
      'sync_queue',
      {'status': 'pending', 'next_attempt_at': null, 'updated_at': now},
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'failed'],
    );
    await _emitStatus(userId);
    requestSync();
  }

  Future<void> _emitStatus(String userId) async {
    final generation = _sessionGeneration;
    final status = await statusForUser(userId);
    if (_sameSession(userId, generation)) _statusController.add(status);
  }

  Future<void> _scheduleNextDurableRetry() async {
    if (!_isMonitoring || !_isOnline) return;
    if (Firebase.apps.isEmpty) return;
    final principal = FirebaseAuth.instance.currentUser;
    if (principal == null || principal.isAnonymous) return;
    final database = await DatabaseHelper.instance.database;
    final rows = await database.query(
      'sync_queue',
      columns: const ['next_attempt_at'],
      where: 'user_id = ?',
      whereArgs: [principal.uid],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    final value = rows.single['next_attempt_at'] as String?;
    if (value == null) {
      _scheduleSync(Duration.zero);
      return;
    }

    final retryAt = DateTime.tryParse(value)?.toUtc();
    if (retryAt == null) {
      _scheduleSync(const Duration(seconds: 5));
      return;
    }
    final remaining = retryAt.difference(DateTime.now().toUtc());
    _scheduleSync(remaining.isNegative ? Duration.zero : remaining);
  }
}
