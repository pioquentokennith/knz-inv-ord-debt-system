// ─────────────────────────────────────────────────────────────────────────────
// sync_queue.dart — Durable Firestore transactional outbox
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../core/domain_exceptions.dart';
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
    this.conflictCount = 0,
    this.deadLetterCount = 0,
    this.lastError,
  });

  const SyncStatus.empty() : this(pendingCount: 0, failedCount: 0);

  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final int deadLetterCount;
  final String? lastError;

  bool get hasFailures => failedCount > 0;
  bool get hasPending => pendingCount > 0;
  bool get requiresReview => conflictCount > 0 || deadLetterCount > 0;
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
    int? firstFailedRowId;
    Object? firstError;
    final blockedAggregates = <String>{};

    for (final row in pending) {
      if (shouldContinue != null && !shouldContinue()) break;
      final aggregateKey =
          row['aggregate_key'] as String? ??
          '${row['collection']}:${row['doc_id']}';
      if (blockedAggregates.contains(aggregateKey)) continue;
      final now = _now().toUtc();
      final nextAttempt = row['next_attempt_at'] as String?;
      final retryAt = nextAttempt == null
          ? null
          : DateTime.tryParse(nextAttempt)?.toUtc();
      if (retryAt != null && retryAt.isAfter(now)) {
        blockedAggregates.add(aggregateKey);
        continue;
      }

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
        await database.transaction((txn) async {
          await _completeConfirmedPurge(txn, row);
          await _acknowledgeRevision(txn, row);
          final deleted = await txn.delete(
            'sync_queue',
            where: 'id = ? AND user_id = ?',
            whereArgs: [rowId, userId],
          );
          if (deleted != 1) {
            throw StateError(
              'Remote sync succeeded but outbox row $rowId was not completed.',
            );
          }
        });
        completed++;
      } catch (error) {
        final failureClass = _classify(error);
        await _recordFailure(database, row, error, now, failureClass);
        firstFailedRowId ??= rowId;
        firstError ??= error;
        if (failureClass == 'authorization') break;
        blockedAggregates.add(aggregateKey);
      }
    }
    return SyncProcessResult(
      completedCount: completed,
      failedRowId: firstFailedRowId,
      error: firstError,
    );
  }

  Future<void> _completeConfirmedPurge(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    const tables = {
      'delete_product': 'products',
      'delete_order': 'orders',
      'delete_debt': 'debts',
      'delete_reseller': 'resellers',
      'delete_custom_order': 'custom_orders',
    };
    final table = tables[row['operation']];
    if (table == null) return;
    final deleted = await executor.delete(
      table,
      where: 'id = ? AND user_id = ? AND is_deleted = 1 AND purge_state = ?',
      whereArgs: [row['doc_id'], row['user_id'], 'pending'],
    );
    if (deleted != 1) {
      throw StateError('Confirmed purge target is missing or changed.');
    }
  }

  Future<void> _acknowledgeRevision(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    const tables = {
      'products': 'products',
      'orders': 'orders',
      'debts': 'debts',
      'resellers': 'resellers',
      'custom_orders': 'custom_orders',
    };
    final table = tables[row['collection']];
    final resultingRevision = row['resulting_revision'] as int?;
    if (table == null || resultingRevision == null) return;
    await executor.update(
      table,
      {'revision': resultingRevision, 'base_revision': resultingRevision},
      where: 'id = ? AND user_id = ? AND revision < ?',
      whereArgs: [row['doc_id'], row['user_id'], resultingRevision],
    );
  }

  Future<void> _recordFailure(
    Database database,
    Map<String, Object?> row,
    Object error,
    DateTime now,
    String failureClass,
  ) async {
    final attempts = (row['attempt_count'] as int? ?? 0) + 1;
    final errorText = error.toString();
    if (failureClass == 'conflict') {
      final conflict = error as SyncConflictException;
      final conflictId = await database.insert('sync_conflicts', {
        'user_id': row['user_id'],
        'collection': row['collection'],
        'doc_id': row['doc_id'],
        'aggregate_key':
            row['aggregate_key'] ?? '${row['collection']}:${row['doc_id']}',
        'local_revision': row['expected_revision'] ?? 0,
        'remote_revision': conflict.remoteRevision,
        'local_data': row['data'],
        'remote_data': conflict.remoteData == null
            ? null
            : jsonEncode(conflict.remoteData),
        'reason': conflict.message,
        'status': 'open',
        'created_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await database.update(
        'sync_queue',
        {
          'status': 'conflict',
          'error_class': failureClass,
          'conflict_id': conflictId == 0 ? null : conflictId,
          'attempt_count': attempts,
          'last_attempt_at': now.toIso8601String(),
          'last_error': errorText,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      return;
    }
    if (failureClass == 'permanent') {
      await database.transaction((txn) async {
        await txn.insert('dead_letters', {
          'queue_row_id': row['id'],
          'user_id': row['user_id'],
          'operation': row['operation'],
          'aggregate_key':
              row['aggregate_key'] ?? '${row['collection']}:${row['doc_id']}',
          'payload': row['data'],
          'error_class': failureClass,
          'last_error': errorText,
          'attempt_count': attempts,
          'created_at': now.toIso8601String(),
        });
        await txn.delete('sync_queue', where: 'id = ?', whereArgs: [row['id']]);
      });
      return;
    }
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
        'error_class': failureClass,
      },
      where: 'id = ?',
      whereArgs: [row['id']],
    );
    if (changed != 1) {
      throw StateError('Failed to persist outbox error for row ${row['id']}.');
    }
  }

  String _classify(Object error) {
    if (error is SyncConflictException) return 'conflict';
    if (error is FormatException || error is UnsupportedError)
      return 'permanent';
    if (error is FirebaseException) {
      if ({'permission-denied', 'unauthenticated'}.contains(error.code)) {
        return 'authorization';
      }
      if ({
        'invalid-argument',
        'failed-precondition',
        'not-found',
      }.contains(error.code)) {
        return 'permanent';
      }
    }
    return 'transient';
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
  Future<bool> Function(String uid)? _authorizationGate;
  Future<void> Function(String uid)? _afterSuccessfulSync;

  Stream<SyncStatus> get statusStream => _statusController.stream;

  void setAuthorizationGate(Future<bool> Function(String uid) gate) {
    _authorizationGate = gate;
  }

  void setAfterSuccessfulSync(Future<void> Function(String uid) callback) {
    _afterSuccessfulSync = callback;
  }

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
    final operationId = const Uuid().v4();
    final deviceId = await _deviceId(database, now);
    final aggregateKey = '$collection:$docId';
    final expectedRevision = await _nextExpectedRevision(
      database,
      collection,
      docId,
      userId,
      aggregateKey,
    );
    final resultingRevision = expectedRevision + 1;
    final revisionedData = <String, dynamic>{
      ...data,
      'base_revision': expectedRevision,
      'revision': resultingRevision,
      'writer_device_id': deviceId,
      'updated_at': now,
    };
    final rowId = await database.insert('sync_queue', {
      'operation': operation,
      'collection': collection,
      'user_id': userId,
      'doc_id': docId,
      'data': jsonEncode(revisionedData),
      'created_at': now,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_attempt_at': null,
      'last_error': null,
      'status': 'pending',
      'idempotency_key': operationId,
      'updated_at': now,
      'operation_id': operationId,
      'aggregate_key': aggregateKey,
      'expected_revision': expectedRevision,
      'resulting_revision': resultingRevision,
      'device_id': deviceId,
    });
    if (rowId <= 0) throw StateError('Sync outbox row was not inserted.');
    return rowId;
  }

  Future<int> _nextExpectedRevision(
    DatabaseExecutor executor,
    String collection,
    String docId,
    String userId,
    String aggregateKey,
  ) async {
    final queued = await executor.query(
      'sync_queue',
      columns: const ['resulting_revision'],
      where: 'user_id = ? AND aggregate_key = ?',
      whereArgs: [userId, aggregateKey],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (queued.isNotEmpty) {
      return queued.single['resulting_revision'] as int? ?? 0;
    }
    const entityTables = {
      'products': 'products',
      'orders': 'orders',
      'debts': 'debts',
      'resellers': 'resellers',
      'custom_orders': 'custom_orders',
    };
    final table = entityTables[collection];
    if (table == null) return 0;
    final rows = await executor.query(
      table,
      columns: const ['revision'],
      where: 'id = ? AND user_id = ?',
      whereArgs: [docId, userId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.single['revision'] as int? ?? 0;
  }

  Future<String> _deviceId(DatabaseExecutor executor, String now) async {
    final rows = await executor.query(
      'device_identity',
      columns: const ['device_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.single['device_id'] as String;
    final generated = const Uuid().v4().replaceAll('-', '');
    final id = generated.substring(0, 8).toUpperCase();
    await executor.insert('device_identity', {
      'singleton_id': 1,
      'device_id': id,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    final created = await executor.query(
      'device_identity',
      columns: const ['device_id'],
      where: 'singleton_id = 1',
      limit: 1,
    );
    return created.single['device_id'] as String;
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
    // Anonymous sessions are never allowed to flush tenant data. Cloud account
    // login must bind the Firebase UID to the local user ID first.
    if (principal == null || principal.isAnonymous) {
      return const SyncProcessResult.skipped();
    }
    final principalUid = principal.uid;
    final generation = _sessionGeneration;
    final authorizationGate = _authorizationGate;
    if (authorizationGate != null && !await authorizationGate(principalUid)) {
      return const SyncProcessResult.skipped();
    }
    if (!_sameSession(principalUid, generation)) {
      return const SyncProcessResult.skipped();
    }
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
        if (result.succeeded) await _afterSuccessfulSync?.call(principalUid);
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
      case 'save_order_with_event':
        final order = _decodeEmbeddedMap(data['_order'], '_order');
        final event = _decodeEmbeddedMap(data['_event'], '_event');
        final orderItems = _decodeEmbeddedMaps(order.remove('_items'));
        await _cloud.saveOrderWithEvent(userId, order, orderItems, event);
        break;
      case 'create_order':
        final order = _decodeEmbeddedMap(data['_order'], '_order');
        final debtValue = data['_debt'];
        final orderItems = _decodeEmbeddedMaps(order.remove('_items'));
        final quantities = <String, int>{};
        for (final item in orderItems) {
          final productId = item['product_id'] as String;
          quantities.update(
            productId,
            (value) => value + (item['quantity'] as int),
            ifAbsent: () => item['quantity'] as int,
          );
        }
        final debt = debtValue == null
            ? null
            : _decodeEmbeddedMap(debtValue, '_debt');
        final provisionalId = order['order_id'] as String;
        final canonicalId = await _cloud.finalizeOrder(
          userId,
          data['command_id'] as String,
          order,
          orderItems,
          quantities,
          debt,
        );
        final database = await DatabaseHelper.instance.database;
        await database.transaction((txn) async {
          final changed = await txn.update(
            'orders',
            {
              'order_id': canonicalId,
              'number_state': 'finalized',
              'revision': 1,
              'base_revision': 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'id = ? AND user_id = ? AND order_id = ?',
            whereArgs: [docId, userId, provisionalId],
          );
          if (changed != 1) {
            final existing = await txn.query(
              'orders',
              columns: const ['order_id'],
              where: 'id = ? AND user_id = ?',
              whereArgs: [docId, userId],
              limit: 1,
            );
            if (existing.isEmpty ||
                existing.single['order_id'] != canonicalId) {
              throw StateError(
                'Finalized order could not be reconciled locally.',
              );
            }
          }
          await txn.update(
            'debts',
            {'order_id': canonicalId, 'revision': 1, 'base_revision': 1},
            where: 'user_id = ? AND order_id = ?',
            whereArgs: [userId, provisionalId],
          );
        });
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
      case 'save_debt_with_events':
        final debt = _decodeEmbeddedMap(data['_debt'], '_debt');
        final events = _decodeEmbeddedMaps(data['_events']);
        final debtPayments = _decodeEmbeddedMaps(debt.remove('_payments'));
        await _cloud.saveDebtWithEvents(userId, debt, debtPayments, events);
        break;
      case 'apply_debt_payment':
        final debt = _decodeEmbeddedMap(data['_debt'], '_debt');
        _copyQueueRevisionMetadata(data, debt);
        await _cloud.applyDebtPayment(
          userId,
          debt,
          _decodeEmbeddedMap(data['_payment'], '_payment'),
          _decodeEmbeddedMap(data['_event'], '_event'),
        );
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
      case 'save_custom_order_with_events':
        final customOrder = _decodeEmbeddedMap(
          data['_custom_order'],
          '_custom_order',
        );
        final events = _decodeEmbeddedMaps(data['_events']);
        final customPayments = _decodeEmbeddedMaps(
          customOrder.remove('_payments'),
        );
        await _cloud.saveCustomOrderWithEvents(
          userId,
          customOrder,
          customPayments,
          events,
        );
        break;
      case 'apply_custom_order_payment':
        final customOrder = _decodeEmbeddedMap(
          data['_custom_order'],
          '_custom_order',
        );
        _copyQueueRevisionMetadata(data, customOrder);
        await _cloud.applyCustomOrderPayment(
          userId,
          customOrder,
          _decodeEmbeddedMap(data['_payment'], '_payment'),
          _decodeEmbeddedMap(data['_event'], '_event'),
        );
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
      case 'save_business_event':
        await _cloud.saveBusinessEvent(userId, data);
        break;
      case 'update_user_password':
        throw UnsupportedError(
          'Legacy credential outbox rows are quarantined and require owner review.',
        );
      default:
        throw StateError('Unknown sync operation: $operation');
    }
  }

  void _copyQueueRevisionMetadata(
    Map<String, dynamic> source,
    Map<String, dynamic> target,
  ) {
    for (final key in const [
      'base_revision',
      'revision',
      'writer_device_id',
      'updated_at',
    ]) {
      target[key] = source[key];
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
    final conflictRows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM sync_conflicts '
      'WHERE user_id = ? AND status = ?',
      [userId, 'open'],
    );
    final deadLetterRows = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM dead_letters '
      'WHERE user_id = ? AND resolved_at IS NULL',
      [userId],
    );
    return SyncStatus(
      pendingCount: (rows.single['pending_count'] as num?)?.toInt() ?? 0,
      failedCount: (rows.single['failed_count'] as num?)?.toInt() ?? 0,
      conflictCount: (conflictRows.single['count'] as num?)?.toInt() ?? 0,
      deadLetterCount: (deadLetterRows.single['count'] as num?)?.toInt() ?? 0,
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

  Future<void> emitCurrentStatus(String userId) => _emitStatus(userId);

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
