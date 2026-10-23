// ─────────────────────────────────────────────────────────────────────────────
// sync_queue.dart — Durable Firestore transactional outbox
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../core/domain_exceptions.dart';
import 'firestore_sync.dart';
import 'revisioned_replay.dart';

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

Set<String> outboxDependencyKeys(Map<String, Object?> row) =>
    _OutboxWork.keys(row);

// Shared by dispatch and wake-up scheduling so neither can spin on a ready
// revision whose prerequisite is delayed. Scan in bounded SQLite pages; only
// the next 100 runnable payloads are retained.
class _OutboxWork {
  final rows = <Map<String, Object?>>[];
  final dependencyKeys = <int, Set<String>>{};
  DateTime? nextAttempt;

  static Set<String> keys(Map<String, Object?> row) {
    final result = <String>{
      row['aggregate_key'] as String? ??
          '${row['collection']}:${row['doc_id']}',
    };
    try {
      final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      final order =
          data['_order'] ?? (row['collection'] == 'orders' ? data : null);
      if (order is Map) {
        if (order['order_id'] != null) {
          result.add('order_number:${order['order_id']}');
        }
        final encoded = order['_items'] ?? order['items'];
        final items = encoded is String ? jsonDecode(encoded) : encoded;
        if (items is List) {
          for (final item in items.whereType<Map>()) {
            if (item['product_id'] != null) {
              result.add('products:${item['product_id']}');
            }
          }
        }
      }
      final debt =
          data['_debt'] ?? (row['collection'] == 'debts' ? data : null);
      if (debt is Map) {
        if (debt['id'] != null) result.add('debts:${debt['id']}');
        if (debt['order_id'] != null) {
          result.add('order_number:${debt['order_id']}');
        }
      }
    } catch (_) {
      // Malformed payloads must reach the normal permanent-failure classifier.
    }
    return result;
  }

  static Future<_OutboxWork> load(
    Database database,
    String uid,
    DateTime now,
  ) async {
    final work = _OutboxWork();
    final waitingUntil = <String, DateTime>{};
    var lastId = 0;
    while (true) {
      final page = await database.query(
        'sync_queue',
        where: 'user_id = ? AND id > ?',
        whereArgs: [uid, lastId],
        orderBy: 'id ASC',
        limit: 200,
      );
      for (final row in page) {
        lastId = row['id'] as int;
        final dependencies = keys(row);
        var readyAt =
            DateTime.tryParse(
              row['next_attempt_at'] as String? ?? '',
            )?.toUtc() ??
            now;
        for (final key in dependencies) {
          final earlier = waitingUntil[key];
          if (earlier != null && earlier.isAfter(readyAt)) readyAt = earlier;
        }
        for (final key in dependencies) {
          waitingUntil[key] = readyAt;
        }
        if (work.nextAttempt == null || readyAt.isBefore(work.nextAttempt!)) {
          work.nextAttempt = readyAt;
        }
        if (!readyAt.isAfter(now) && work.rows.length < 100) {
          work.rows.add(row);
          work.dependencyKeys[lastId] = dependencies;
        }
      }
      if (page.length < 200) return work;
    }
  }
}

/// Testable durable processor. Connectivity only triggers this processor; a row
/// is removed exclusively after [dispatch] confirms remote success.
class OutboxProcessor {
  static const _revisionedOperations = {
    'save_product',
    'soft_delete_product',
    'save_reseller',
    'soft_delete_reseller',
    'save_order',
    'soft_delete_order',
    'save_debt',
    'soft_delete_debt',
    'save_custom_order',
    'soft_delete_custom_order',
  };
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
    await _recoverDetachedConflicts(database, userId, shouldContinue);
    final work = await _OutboxWork.load(database, userId, _now().toUtc());
    final pending = work.rows;
    var completed = 0;
    int? firstFailedRowId;
    Object? firstError;
    final blockedAggregates = <String>{};

    for (final row in pending) {
      if (shouldContinue != null && !shouldContinue()) break;
      final dependencyKeys = work.dependencyKeys[row['id'] as int]!;
      if (dependencyKeys.any(blockedAggregates.contains)) {
        blockedAggregates.addAll(dependencyKeys);
        continue;
      }
      final now = _now().toUtc();
      final nextAttempt = row['next_attempt_at'] as String?;
      final retryAt = nextAttempt == null
          ? null
          : DateTime.tryParse(nextAttempt)?.toUtc();
      if (retryAt != null && retryAt.isAfter(now)) {
        blockedAggregates.addAll(dependencyKeys);
        continue;
      }

      final rowId = row['id'] as int;
      final conflicts = await _matchingConflicts(database, row);
      final replayOnly =
          _revisionedOperations.contains(row['operation']) &&
          (row['status'] == 'conflict' ||
              row['conflict_id'] != null ||
              conflicts.isNotEmpty);
      if (shouldContinue != null && !shouldContinue()) break;
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
        await _dispatch({...row, 'replay_only': replayOnly});
        // A remote commit may complete after logout/account switch. Leave its
        // durable intent for a retry under the original authenticated session.
        if (shouldContinue != null && !shouldContinue()) break;
        await database.transaction((txn) async {
          await _completeConfirmedPurge(txn, row);
          await _acknowledgeRevision(txn, row);
          if (replayOnly) {
            for (final conflict in await _matchingConflicts(txn, row)) {
              // Remove only the exact historical operation just confirmed by
              // the live cloud transaction. Never restore its business payload.
              await txn.delete(
                'sync_conflicts',
                where: 'id = ? AND user_id = ? AND status = ?',
                whereArgs: [conflict['id'], userId, 'open'],
              );
            }
          }
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
        if (shouldContinue != null && !shouldContinue()) break;
        final failureClass = _classify(error);
        await _recordFailure(database, row, error, now, failureClass);
        firstFailedRowId ??= rowId;
        firstError ??= error;
        if (failureClass == 'authorization') break;
        blockedAggregates.addAll(dependencyKeys);
      }
    }
    return SyncProcessResult(
      completedCount: completed,
      failedRowId: firstFailedRowId,
      error: firstError,
    );
  }

  /// The old concurrent runner could record a conflict AFTER its other caller
  /// had deleted the successful outbox row. Recover these product/reseller
  /// remnants only by a fresh read-only replay check, never by replaying a write.
  Future<void> _recoverDetachedConflicts(
    Database database,
    String uid,
    bool Function()? shouldContinue,
  ) async {
    final conflicts = await database.query(
      'sync_conflicts',
      where: 'user_id = ? AND status = ? AND collection IN (?, ?)',
      whereArgs: [uid, 'open', 'products', 'resellers'],
    );
    for (final conflict in conflicts) {
      if (shouldContinue != null && !shouldContinue()) return;
      Future<bool> hasPending(DatabaseExecutor executor) async =>
          (await executor.query(
            'sync_queue',
            columns: const ['id'],
            where: 'user_id = ? AND collection = ? AND doc_id = ?',
            whereArgs: [uid, conflict['collection'], conflict['doc_id']],
            limit: 1,
          )).isNotEmpty;
      if (await hasPending(database)) continue;
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(conflict['local_data'] as String);
        if (decoded is! Map<String, dynamic>) continue;
        data = decoded;
      } on FormatException {
        continue;
      }
      if (data['id'] != conflict['doc_id'] ||
          data['user_id'] != uid ||
          data['base_revision'] != conflict['local_revision'] ||
          !RevisionedReplay.isExact(data, data)) {
        continue;
      }
      final row = <String, Object?>{
        'operation': conflict['collection'] == 'products'
            ? 'save_product'
            : 'save_reseller',
        'collection': conflict['collection'],
        'doc_id': conflict['doc_id'],
        'user_id': uid,
        'data': conflict['local_data'],
        'replay_only': true,
        'resulting_revision': data['revision'],
      };
      try {
        if (shouldContinue != null && !shouldContinue()) return;
        await _dispatch(row);
      } on SyncConflictException {
        continue; // Current cloud no longer matches: preserve genuine conflict.
      } on FormatException {
        continue; // Unrecognized legacy payload requires manual review.
      }
      if (shouldContinue != null && !shouldContinue()) return;
      await database.transaction((txn) async {
        // A new local edit may have been queued while the cloud read awaited.
        if (await hasPending(txn)) return;
        await _acknowledgeRevision(txn, row);
        await txn.delete(
          'sync_conflicts',
          where:
              'id = ? AND user_id = ? AND collection = ? AND doc_id = ? '
              'AND status = ? AND local_data = ?',
          whereArgs: [
            conflict['id'],
            uid,
            conflict['collection'],
            conflict['doc_id'],
            'open',
            conflict['local_data'],
          ],
        );
      });
    }
  }

  Future<List<Map<String, Object?>>> _matchingConflicts(
    DatabaseExecutor executor,
    Map<String, Object?> row,
  ) async {
    final candidates = await executor.query(
      'sync_conflicts',
      where:
          'user_id = ? AND collection = ? AND doc_id = ? '
          'AND aggregate_key = ? AND local_revision = ? AND status = ?',
      whereArgs: [
        row['user_id'],
        row['collection'],
        row['doc_id'],
        row['aggregate_key'] ?? '${row['collection']}:${row['doc_id']}',
        row['expected_revision'] ?? 0,
        'open',
      ],
    );
    return candidates.where((conflict) {
      try {
        return RevisionedReplay.sameValues(
          jsonDecode(row['data'] as String),
          jsonDecode(conflict['local_data'] as String),
        );
      } on FormatException {
        return false;
      }
    }).toList();
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
      await database.transaction((txn) async {
        await txn.insert('sync_conflicts', {
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
        // INSERT OR IGNORE can leave an older link null (or report a previous
        // insert's ID). Recover the link from exact scoped operation identity.
        final matches = await _matchingConflicts(txn, row);
        await txn.update(
          'sync_queue',
          {
            'status': 'conflict',
            'error_class': failureClass,
            'conflict_id': matches.isEmpty ? null : matches.single['id'],
            'attempt_count': attempts,
            'last_attempt_at': now.toIso8601String(),
            'last_error': errorText,
            'updated_at': now.toIso8601String(),
            'next_attempt_at': now
                .add(SyncQueue.retryDelayForAttempt(attempts))
                .toIso8601String(),
          },
          where: 'id = ? AND user_id = ?',
          whereArgs: [row['id'], row['user_id']],
        );
      });
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
    if (error is FormatException || error is UnsupportedError) {
      return 'permanent';
    }
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
  @visibleForTesting
  SyncQueue.forTesting({
    required Future<Database> Function() databaseProvider,
    required String? Function() currentUid,
    OutboxDispatch? dispatch,
    FirestoreSync? cloud,
  }) : _databaseOverride = databaseProvider,
       _uidOverride = currentUid,
       _dispatchOverride = dispatch,
       _cloudOverride = cloud {
    _isMonitoring = true;
    _isOnline = true;
  }
  static final SyncQueue instance = SyncQueue._();

  static const int _maxBackoffSeconds = 60 * 60;

  Future<Database> Function()? _databaseOverride;
  String? Function()? _uidOverride;
  OutboxDispatch? _dispatchOverride;
  FirestoreSync? _cloudOverride;
  FirestoreSync get _cloud => _cloudOverride ?? FirestoreSync.instance;
  Future<Database> _database() =>
      _databaseOverride?.call() ?? DatabaseHelper.instance.database;
  String? get _currentUid {
    if (_uidOverride != null) return _uidOverride!();
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? null : user.uid;
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  bool _isOnline = false;
  bool _isSyncing = false;
  bool _syncRequested = false;
  bool _isMonitoring = false;
  int _sessionGeneration = 0;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  Future<bool> Function(String uid)? _authorizationGate;
  Future<void> Function(String uid)? _afterSuccessfulSync;
  Future<void> Function(String uid, Set<String> collections)? _afterLocalSync;
  final _locallyChangedCollections = <String>{};

  Stream<SyncStatus> get statusStream => _statusController.stream;

  void setAuthorizationGate(Future<bool> Function(String uid) gate) {
    _authorizationGate = gate;
  }

  void setAfterSuccessfulSync(Future<void> Function(String uid) callback) {
    _afterSuccessfulSync = callback;
  }

  /// Publishes local changes committed by outbound sync, independently of
  /// whether the rest of the batch or subsequent inbound reconciliation succeeds.
  void setAfterLocalSync(
    Future<void> Function(String uid, Set<String> collections) callback,
  ) {
    _afterLocalSync = callback;
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
    await _cloud.stopInbound();
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
    // Order creation also advances stock and creates an optional debt. Record
    // those implicit revisions in the durable command so later offline writes
    // do not assume only the order aggregate changed.
    final stockRevisions = <String, int>{};
    if (operation == 'create_order') {
      final order = _decodeEmbeddedMap(data['_order'], '_order');
      if (order['status'] != 'Cancelled') {
        for (final item in _decodeEmbeddedMaps(order['_items'])) {
          final productId = item['product_id'] as String;
          stockRevisions[productId] =
              await _nextExpectedRevision(
                database,
                'products',
                productId,
                userId,
                'products:$productId',
              ) +
              1;
        }
      }
    }
    final revisionedData = <String, dynamic>{
      ...data,
      if (operation == 'create_order') '_stock_revisions': stockRevisions,
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
    var revision = rows.isEmpty ? 0 : rows.single['revision'] as int? ?? 0;
    final queued = await executor.query(
      'sync_queue',
      columns: const [
        'operation',
        'aggregate_key',
        'resulting_revision',
        'data',
      ],
      where: 'user_id = ? AND (aggregate_key = ? OR operation = ?)',
      whereArgs: [userId, aggregateKey, 'create_order'],
      orderBy: 'id ASC',
    );
    for (final row in queued) {
      if (row['aggregate_key'] == aggregateKey) {
        revision = math.max(revision, row['resulting_revision'] as int? ?? 0);
      } else if (row['operation'] == 'create_order') {
        final data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        if (collection == 'debts' &&
            data['_debt'] != null &&
            _decodeEmbeddedMap(data['_debt'], '_debt')['id'] == docId) {
          revision = math.max(revision, 1);
        } else if (collection == 'products') {
          final stocks = data['_stock_revisions'] as Map?;
          if (stocks?[docId] case final int planned) {
            revision = math.max(revision, planned);
          } else if (stocks == null) {
            final order = _decodeEmbeddedMap(data['_order'], '_order');
            if (order['status'] != 'Cancelled' &&
                _decodeEmbeddedMaps(
                  order['_items'],
                ).any((item) => item['product_id'] == docId)) {
              revision++;
            }
          }
        }
      }
    }
    return revision;
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

  /// Upgrade only unsent legacy commands. Already attempted/conflicted writes
  /// remain available for explicit review rather than guessing their outcome.
  /// No business values or schema are changed; only missing own-write revision
  /// dependencies are recorded in the existing durable payloads.
  Future<void> _prepareLegacyOrderCommands(
    DatabaseExecutor txn,
    String uid,
  ) async {
    final rows = await txn.query(
      'sync_queue',
      where: 'user_id = ?',
      whereArgs: [uid],
      orderBy: 'id ASC',
    );
    final projected = <String, int>{};
    final implicit = <String, int>{};
    Future<int> current(String table, String id) async {
      final key = '$table:$id';
      final local = await txn.query(
        table,
        columns: ['revision'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, uid],
      );
      return math.max(
        projected[key] ?? 0,
        local.isEmpty ? 0 : local.single['revision'] as int? ?? 0,
      );
    }

    for (final row in rows) {
      Map<String, dynamic> data;
      try {
        data = jsonDecode(row['data'] as String) as Map<String, dynamic>;
      } catch (_) {
        continue; // Let the normal processor classify malformed payloads.
      }
      final key =
          row['aggregate_key'] as String? ??
          '${row['collection']}:${row['doc_id']}';
      final base = row['expected_revision'] as int? ?? 0;
      var result = row['resulting_revision'] as int? ?? base + 1;
      final expected = projected[key] ?? base;
      final unsent =
          (row['attempt_count'] as int? ?? 0) == 0 &&
          row['status'] == 'pending';
      if (unsent &&
          result == base + 1 &&
          expected > base &&
          expected - base <= (implicit[key] ?? 0)) {
        result = expected + 1;
        data.addAll({'base_revision': expected, 'revision': result});
        await txn.update(
          'sync_queue',
          {
            'expected_revision': expected,
            'resulting_revision': result,
            'data': jsonEncode(data),
          },
          where: 'id = ? AND user_id = ?',
          whereArgs: [row['id'], uid],
        );
      }
      projected[key] = math.max(projected[key] ?? 0, result);
      if (row['operation'] != 'create_order') continue;
      final stocks = data['_stock_revisions'] as Map?;
      if (stocks != null) {
        for (final entry in stocks.entries) {
          final stockKey = 'products:${entry.key}';
          projected[stockKey] = math.max(
            projected[stockKey] ?? 0,
            entry.value as int,
          );
        }
        continue;
      }
      if (!unsent) continue;
      final order = _decodeEmbeddedMap(data['_order'], '_order');
      final planned = <String, int>{};
      if (order['status'] != 'Cancelled') {
        final ids = _decodeEmbeddedMaps(
          order['_items'],
        ).map((item) => item['product_id'] as String).toSet();
        for (final id in ids) {
          final stockKey = 'products:$id';
          planned[id] = await current('products', id) + 1;
          projected[stockKey] = planned[id]!;
          implicit[stockKey] = (implicit[stockKey] ?? 0) + 1;
        }
      }
      if (data['_debt'] != null) {
        final id = _decodeEmbeddedMap(data['_debt'], '_debt')['id'] as String;
        projected['debts:$id'] = math.max(await current('debts', id), 1);
        implicit['debts:$id'] = (implicit['debts:$id'] ?? 0) + 1;
      }
      data['_stock_revisions'] = planned;
      await txn.update(
        'sync_queue',
        {'data': jsonEncode(data)},
        where: 'id = ? AND user_id = ?',
        whereArgs: [row['id'], uid],
      );
    }
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
    if (_isSyncing) {
      _syncRequested = true;
      return;
    }
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
    final principalUid = _currentUid;
    // Anonymous sessions are never allowed to flush tenant data. Cloud account
    // login must bind the Firebase UID to the local user ID first.
    if (principalUid == null) {
      return const SyncProcessResult.skipped();
    }
    final generation = _sessionGeneration;
    // Acquire before authorization yields. All returns and failures below
    // release through finally; a second caller cannot enter during revalidation.
    _isSyncing = true;
    _syncRequested = false;
    var authorized = false;
    try {
      final authorizationGate = _authorizationGate;
      if (authorizationGate != null && !await authorizationGate(principalUid)) {
        // A network/token refresh failure must not strand the queue until the
        // network interface changes again. This retries verification, not login.
        if (_sameSession(principalUid, generation)) {
          _scheduleSync(const Duration(seconds: 30));
        }
        return const SyncProcessResult.skipped();
      }
      if (!_sameSession(principalUid, generation)) {
        return const SyncProcessResult.skipped();
      }
      authorized = true;
      _locallyChangedCollections.clear();
      _cloud.onInboundChanged = requestSync;
      _retryTimer?.cancel();
      _retryTimer = null;

      final database = await _database();
      await database.transaction(
        (txn) => _prepareLegacyOrderCommands(txn, principalUid),
      );
      if (!_sameSession(principalUid, generation)) {
        return const SyncProcessResult.skipped();
      }
      final processor = OutboxProcessor(
        databaseProvider: _database,
        dispatch: _dispatchOverride ?? _dispatch,
      );
      final result = await processor.processUser(
        principalUid,
        shouldContinue: () => _sameSession(principalUid, generation),
      );
      if (_sameSession(principalUid, generation)) {
        if (_locallyChangedCollections.isNotEmpty) {
          // A screen refresh failure must not turn acknowledged cloud writes
          // back into failed outbox operations.
          try {
            await _afterLocalSync?.call(
              principalUid,
              Set.unmodifiable(_locallyChangedCollections),
            );
          } catch (error) {
            if (kDebugMode) debugPrint('[SyncQueue] local refresh: $error');
          }
        }
        if (!_sameSession(principalUid, generation)) return result;
        await _emitStatus(principalUid);
        if (result.succeeded) await _afterSuccessfulSync?.call(principalUid);
      }
      return result;
    } finally {
      try {
        if (authorized && _sameSession(principalUid, generation)) {
          await _scheduleNextDurableRetry();
        }
      } finally {
        _isSyncing = false;
        if (_syncRequested && _sameSession(principalUid, generation)) {
          _syncRequested = false;
          _scheduleSync(const Duration(milliseconds: 250));
        }
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
    final replayOnly = row['replay_only'] == true;
    if (data['user_id'] != null && data['user_id'] != userId ||
        data['id'] != null && data['id'] != docId) {
      throw StateError(
        'Outbox UID/document identity does not match its payload.',
      );
    }

    // An offline conversion/payment snapshot may still reference the temporary
    // number after its order command finalized. Resolve that immutable identity
    // from the owner's local order, including when the cloud debt is new.
    Future<void> canonicalizeDebt(Map<String, dynamic> debt) async {
      final number = debt['order_id'];
      if (number is! String || !number.startsWith('TMP-')) return;
      final database = await _database();
      final orders = await database.query(
        'orders',
        columns: ['order_id'],
        where: 'user_id = ? AND provisional_order_id = ? AND number_state = ?',
        whereArgs: [userId, number, 'finalized'],
        limit: 1,
      );
      if (orders.isNotEmpty) debt['order_id'] = orders.single['order_id'];
    }

    if (data['_debt'] != null) {
      final debt = _decodeEmbeddedMap(data['_debt'], '_debt');
      await canonicalizeDebt(debt);
      data['_debt'] = debt;
    } else if (row['collection'] == 'debts') {
      await canonicalizeDebt(data);
    }

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
        await _cloud.saveProduct(userId, data, replayOnly: replayOnly);
        break;
      case 'soft_delete_product':
        await _cloud.softDeleteProduct(userId, data, replayOnly: replayOnly);
        break;
      case 'delete_product':
        await _cloud.deleteProduct(userId, docId);
        break;
      case 'save_order':
        final orderItems = _decodeEmbeddedMaps(data.remove('_items'));
        await _cloud.saveOrder(
          userId,
          data,
          orderItems,
          replayOnly: replayOnly,
        );
        break;
      case 'save_order_with_event':
        final order = _decodeEmbeddedMap(data['_order'], '_order');
        _copyQueueRevisionMetadata(data, order);
        final event = _decodeEmbeddedMap(data['_event'], '_event');
        final orderItems = _decodeEmbeddedMaps(order.remove('_items'));
        await _cloud.saveOrderWithEvent(userId, order, orderItems, event);
        break;
      case 'create_order':
        final order = _decodeEmbeddedMap(data['_order'], '_order');
        _copyQueueRevisionMetadata(data, order);
        final debtValue = data['_debt'];
        final orderItems = _decodeEmbeddedMaps(order.remove('_items'));
        final quantities = <String, int>{};
        for (final item
            in order['status'] == 'Cancelled'
                ? <Map<String, dynamic>>[]
                : orderItems) {
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
        final database = await _database();
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
          final stockRevisions = data['_stock_revisions'] as Map? ?? const {};
          for (final entry in stockRevisions.entries) {
            final revision = entry.value as int;
            // Only acknowledge the planned revision, never overwrite newer
            // local stock or adopt a remote writer's unseen business data.
            await txn.update(
              'products',
              {'revision': revision, 'base_revision': revision},
              where: 'id = ? AND user_id = ? AND revision < ?',
              whereArgs: [entry.key, userId, revision],
            );
          }
        });
        _locallyChangedCollections.addAll({'orders', 'debts'});
        break;
      case 'soft_delete_order':
        final deletedOrderItems = _decodeEmbeddedMaps(data.remove('_items'));
        await _cloud.softDeleteOrder(
          userId,
          data,
          deletedOrderItems,
          replayOnly: replayOnly,
        );
        break;
      case 'delete_order':
        await _cloud.deleteOrder(userId, docId);
        break;
      case 'save_debt':
        final debtPayments = _decodeEmbeddedMaps(data.remove('_payments'));
        await _cloud.saveDebt(
          userId,
          data,
          debtPayments,
          replayOnly: replayOnly,
        );
        break;
      case 'save_debt_with_events':
        final debt = _decodeEmbeddedMap(data['_debt'], '_debt');
        _copyQueueRevisionMetadata(data, debt);
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
        await _cloud.softDeleteDebt(
          userId,
          data,
          deletedDebtPayments,
          replayOnly: replayOnly,
        );
        break;
      case 'delete_debt':
        await _cloud.deleteDebt(userId, docId);
        break;
      case 'save_reseller':
        await _cloud.saveReseller(userId, data, replayOnly: replayOnly);
        break;
      case 'soft_delete_reseller':
        await _cloud.softDeleteReseller(userId, data, replayOnly: replayOnly);
        break;
      case 'delete_reseller':
        await _cloud.deleteReseller(userId, docId);
        break;
      case 'save_custom_order':
        final customPayments = _decodeEmbeddedMaps(data.remove('_payments'));
        await _cloud.saveCustomOrder(
          userId,
          data,
          customPayments,
          replayOnly: replayOnly,
        );
        break;
      case 'save_custom_order_with_events':
        final customOrder = _decodeEmbeddedMap(
          data['_custom_order'],
          '_custom_order',
        );
        _copyQueueRevisionMetadata(data, customOrder);
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
        await _cloud.softDeleteCustomOrder(
          userId,
          data,
          deletedCustomPayments,
          replayOnly: replayOnly,
        );
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
    return generation == _sessionGeneration &&
        _isMonitoring &&
        _currentUid == uid;
  }

  Future<SyncStatus> statusForUser(String userId) async {
    final database = await _database();
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
    final principalUid = _currentUid;
    if (principalUid == null) return;
    final generation = _sessionGeneration;
    final database = await _database();
    final work = await _OutboxWork.load(
      database,
      principalUid,
      DateTime.now().toUtc(),
    );
    if (!_sameSession(principalUid, generation)) return;
    if (work.nextAttempt == null) {
      // Revalidate access and recover failed listener startup even while idle.
      _scheduleSync(const Duration(minutes: 1));
      return;
    }
    final remaining = work.nextAttempt!.difference(DateTime.now().toUtc());
    _scheduleSync(remaining.isNegative ? Duration.zero : remaining);
  }
}
