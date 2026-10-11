import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../dto/activity_log_dto.dart';
import '../dto/business_event_dto.dart';
import '../dto/custom_order_dto.dart';
import '../dto/debt_dto.dart';
import '../dto/order_dto.dart';
import '../dto/product_dto.dart';
import '../dto/reseller_dto.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart' show outboxDependencyKeys;

class InboundSyncResult {
  const InboundSyncResult({
    required this.appliedCount,
    required this.conflictCount,
    this.changedCollections = const {},
  });

  final int appliedCount;
  final int conflictCount;
  final Set<String> changedCollections;
  bool get changed => appliedCount > 0;
}

class InboundSyncCoordinator {
  InboundSyncCoordinator({
    Future<Database> Function()? databaseProvider,
    FirestoreSync? cloud,
    Future<List<List<Map<String, dynamic>>>> Function(String userId)?
    remoteLoader,
    Future<void> Function(String, List<List<Map<String, dynamic>>>)?
    acknowledge,
    Future<bool> Function(String, String, String)? confirmMissing,
    DateTime Function()? now,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _cloud = cloud ?? FirestoreSync.instance,
       _remoteLoader = remoteLoader,
       _acknowledge = acknowledge,
       _confirmMissing = confirmMissing,
       _now = now ?? (() => DateTime.now().toUtc());

  static final instance = InboundSyncCoordinator();

  final Future<Database> Function() _databaseProvider;
  final FirestoreSync _cloud;
  final Future<List<List<Map<String, dynamic>>>> Function(String userId)?
  _remoteLoader;
  final Future<void> Function(String, List<List<Map<String, dynamic>>>)?
  _acknowledge;
  final Future<bool> Function(String, String, String)? _confirmMissing;
  final DateTime Function() _now;

  Future<InboundSyncResult> reconcile(String userId) async {
    final incoming =
        await (_remoteLoader?.call(userId) ?? _cloud.pendingInbound(userId));
    if (incoming.every((collection) => collection.isEmpty)) {
      return const InboundSyncResult(appliedCount: 0, conflictCount: 0);
    }
    final remote = [
      for (final collection in incoming)
        collection
            .where(
              (record) =>
                  record['_removed'] != true &&
                  !record.containsKey('_initial_ids'),
            )
            .toList(),
    ];

    // Decode the complete server snapshot before beginning SQLite mutation.
    final products = remote[0]
        .map((map) => _productRecord(map, userId))
        .toList(growable: false);
    final orders = remote[1]
        .map((map) => _orderRecord(map, userId))
        .toList(growable: false);
    final debts = remote[2]
        .map((map) => _debtRecord(map, userId))
        .toList(growable: false);
    final resellers = remote[3]
        .map((map) => _resellerRecord(map, userId))
        .toList(growable: false);
    final customOrders = remote[4]
        .map((map) => _customOrderRecord(map, userId))
        .toList(growable: false);
    final events = remote[5]
        .map((map) => BusinessEventDto.fromCloud(map, userId: userId).toLocal())
        .toList(growable: false);
    final logs = remote[6]
        .map((map) => ActivityLogDto.fromCloud(map, userId: userId).toLocal())
        .toList(growable: false);

    final database = await _databaseProvider();
    final removalsByTable = <String, List<Map<String, dynamic>>>{};
    for (var i = 0; i < 5; i++) {
      final table = FirestoreSync.inboundCollections[i];
      final candidates = <String, Map<String, dynamic>>{};
      for (final record in incoming[i].where(
        (record) => record['_removed'] == true,
      )) {
        candidates[record['id'] as String] = record;
      }
      final initial = incoming[i]
          .where((record) => record.containsKey('_initial_ids'))
          .firstOrNull;
      if (initial != null) {
        final serverIds = Set<String>.from(initial['_initial_ids'] as List)
          ..addAll(remote[i].map((record) => record['id'] as String));
        final synced = await database.query(
          table,
          columns: ['id', 'revision'],
          where: 'user_id = ? AND revision > 0',
          whereArgs: [userId],
        );
        for (final row in synced.where(
          (row) => !serverIds.contains(row['id']),
        )) {
          candidates[row['id'] as String] = {
            'id': row['id'],
            'user_id': userId,
            '_removed': true,
            '_observed_revision': row['revision'],
          };
        }
      }
      final confirmed = <Map<String, dynamic>>[];
      for (final record in candidates.values) {
        final verifier = _confirmMissing ?? _cloud.confirmRemoteMissing;
        if (await verifier(userId, table, record['id'] as String)) {
          confirmed.add(record);
        }
      }
      removalsByTable[table] = confirmed;
    }
    var applied = 0;
    var conflicts = 0;
    final changedCollections = <String>{};
    await database.transaction((txn) async {
      final protected = <String>{};
      for (final row in await txn.query(
        'sync_queue',
        where: 'user_id = ?',
        whereArgs: [userId],
      )) {
        protected.addAll(outboxDependencyKeys(row));
      }
      for (final row in await txn.query(
        'dead_letters',
        where: 'user_id = ? AND resolved_at IS NULL',
        whereArgs: [userId],
      )) {
        final key = row['aggregate_key'] as String;
        protected.addAll(
          outboxDependencyKeys({
            ...row,
            'data': row['payload'],
            'collection': key.split(':').first,
          }),
        );
      }
      for (final row in await txn.query(
        'sync_conflicts',
        columns: ['aggregate_key'],
        where: 'user_id = ? AND status = ?',
        whereArgs: [userId, 'open'],
      )) {
        protected.add(row['aggregate_key'] as String);
      }
      final productRows = await _parentLookup(
        txn,
        userId,
        'products',
        products,
      );
      for (final record in products) {
        final result = await _applyMutable(
          txn,
          userId,
          'products',
          record,
          protected,
          productRows,
        );
        applied += result.$1;
        conflicts += result.$2;
        if (result.$1 > 0) changedCollections.add('products');
      }
      final orderRows = await _parentLookup(txn, userId, 'orders', orders);
      for (final record in orders) {
        final result = await _applyOrder(
          txn,
          userId,
          record,
          protected,
          orderRows,
        );
        applied += result.$1;
        conflicts += result.$2;
        if (result.$1 > 0) changedCollections.add('orders');
      }
      final debtRows = await _parentLookup(txn, userId, 'debts', debts);
      for (final record in debts) {
        final result = await _applyDebt(
          txn,
          userId,
          record,
          protected,
          debtRows,
        );
        applied += result.$1;
        conflicts += result.$2;
        if (result.$1 > 0) changedCollections.add('debts');
      }
      final resellerRows = await _parentLookup(
        txn,
        userId,
        'resellers',
        resellers,
      );
      for (final record in resellers) {
        final result = await _applyMutable(
          txn,
          userId,
          'resellers',
          record,
          protected,
          resellerRows,
        );
        applied += result.$1;
        conflicts += result.$2;
        if (result.$1 > 0) changedCollections.add('resellers');
      }
      final customOrderRows = await _parentLookup(
        txn,
        userId,
        'custom_orders',
        customOrders,
      );
      for (final record in customOrders) {
        final result = await _applyCustomOrder(
          txn,
          userId,
          record,
          protected,
          customOrderRows,
        );
        applied += result.$1;
        conflicts += result.$2;
        if (result.$1 > 0) changedCollections.add('custom_orders');
      }
      final existingEventIds = (await _loadLocalRows(
        txn,
        userId,
        'business_events',
        events.map((event) => event['id'] as String),
        columns: const ['id'],
      )).keys.toSet();
      for (final event in events) {
        final id = event['id'] as String;
        if (existingEventIds.contains(id)) continue;
        await txn.insert(
          'business_events',
          event,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final inserted =
            Sqflite.firstIntValue(await txn.rawQuery('SELECT changes()')) ?? 0;
        applied += inserted;
        if (inserted > 0) {
          existingEventIds.add(id);
          changedCollections.add('business_events');
        }
      }
      for (final log in logs) {
        await txn.insert(
          'activity_logs',
          log,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        final inserted =
            Sqflite.firstIntValue(await txn.rawQuery('SELECT changes()')) ?? 0;
        applied += inserted;
        if (inserted > 0) changedCollections.add('activity_logs');
      }
      for (var i = 0; i < 5; i++) {
        final table = FirestoreSync.inboundCollections[i];
        final removals = removalsByTable[table]!;
        for (final removed in removals) {
          final id = removed['id'];
          final local = await txn.query(
            table,
            where: 'user_id = ? AND id = ?',
            whereArgs: [userId, id],
          );
          if (local.isEmpty) continue;
          if (removed.containsKey('_observed_revision') &&
              removed['_observed_revision'] != local.single['revision']) {
            continue;
          }
          if (protected.contains('$table:$id')) {
            await _recordConflict(
              txn,
              userId,
              table,
              _InboundRecord(removed),
              local,
              'remote_purge_with_pending_write',
            );
            conflicts++;
          } else {
            final deleted = await txn.delete(
              table,
              where: 'user_id = ? AND id = ?',
              whereArgs: [userId, id],
            );
            applied += deleted;
            if (deleted > 0) changedCollections.add(table);
          }
        }
      }
      final timestamp = _now().toUtc().toIso8601String();
      for (var index = 0; index < incoming.length; index++) {
        if (incoming[index].isEmpty) continue;
        final collection = FirestoreSync.inboundCollections[index];
        await txn.insert('sync_cursors', {
          'user_id': userId,
          'collection': collection,
          'cursor_value': timestamp,
          'updated_at': timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    if (_acknowledge != null) {
      await _acknowledge(userId, incoming);
    } else if (_remoteLoader == null) {
      _cloud.acknowledgeInbound(userId, incoming);
    }
    return InboundSyncResult(
      appliedCount: applied,
      conflictCount: conflicts,
      changedCollections: Set.unmodifiable(changedCollections),
    );
  }

  _InboundRecord _productRecord(Map<String, dynamic> map, String userId) {
    final local = ProductDto.fromCloud(map, userId: userId).toLocal();
    return _InboundRecord(_withMetadata(local, map));
  }

  _InboundRecord _resellerRecord(Map<String, dynamic> map, String userId) {
    final local = ResellerDto.fromCloud(map, userId: userId).toLocal();
    return _InboundRecord(_withMetadata(local, map));
  }

  _InboundRecord _orderRecord(Map<String, dynamic> map, String userId) {
    final dto = OrderDto.fromCloud(map, userId: userId);
    return _InboundRecord(
      _withMetadata(dto.toLocal(), map),
      children: dto.items.map((item) => item.toLocal()).toList(),
    );
  }

  _InboundRecord _debtRecord(Map<String, dynamic> map, String userId) {
    final dto = DebtDto.fromCloud(map, userId: userId);
    return _InboundRecord(
      _withMetadata(dto.toLocal(), map),
      children: dto.payments.map((payment) => payment.toLocal()).toList(),
    );
  }

  _InboundRecord _customOrderRecord(Map<String, dynamic> map, String userId) {
    final dto = CustomOrderDto.fromCloud(map, userId: userId);
    return _InboundRecord(
      _withMetadata(dto.toLocal(), map),
      children: dto.payments.map((payment) => payment.toLocal()).toList(),
    );
  }

  Map<String, dynamic> _withMetadata(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) => {
    ...local,
    'revision': remote['revision'] as int? ?? 0,
    'base_revision': remote['revision'] as int? ?? 0,
    'updated_at': remote['updated_at'] as String?,
    'writer_device_id': remote['writer_device_id'] as String?,
    'tombstone_revision': remote['tombstone_revision'] as int? ?? 0,
    'purge_state': 'none',
    if (local.containsKey('stock_deducted'))
      'number_state': remote['number_state'] as String? ?? 'legacy',
    if (local.containsKey('stock_deducted'))
      'provisional_order_id': remote['provisional_order_id'] as String?,
  };

  // All reads use the active transaction and owner. Deduplicate only lookup
  // IDs, not incoming records: original event/revision processing order matters.
  Future<Map<String, Map<String, Object?>>> _loadLocalRows(
    DatabaseExecutor txn,
    String userId,
    String table,
    Iterable<String> recordIds, {
    List<String>? columns,
  }) async {
    final ids = recordIds.toSet().toList(growable: false);
    final rowsById = <String, Map<String, Object?>>{};
    const chunkSize = 400; // Plus one owner parameter, below SQLite's limit.
    for (var offset = 0; offset < ids.length; offset += chunkSize) {
      final end = offset + chunkSize < ids.length
          ? offset + chunkSize
          : ids.length;
      final chunk = ids.sublist(offset, end);
      final rows = await txn.query(
        table,
        columns: columns,
        where:
            'user_id = ? AND id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: [userId, ...chunk],
      );
      for (final row in rows) {
        rowsById[row['id'] as String] = row;
      }
    }
    return rowsById;
  }

  Future<_InboundParentLookup> _parentLookup(
    DatabaseExecutor txn,
    String userId,
    String table,
    List<_InboundRecord> records,
  ) async => _InboundParentLookup(
    txn,
    userId,
    table,
    await _loadLocalRows(
      txn,
      userId,
      table,
      records.map((record) => record.data['id'] as String),
    ),
  );

  Future<(int, int)> _applyMutable(
    DatabaseExecutor txn,
    String userId,
    String table,
    _InboundRecord record,
    Set<String> protected,
    _InboundParentLookup parents,
  ) async {
    final id = record.data['id'] as String;
    final aggregate = '$table:$id';
    final localRows = await parents.read(id);
    if (protected.contains(aggregate)) {
      if (localRows.isEmpty ||
          _remoteRevision(record) > _localRevision(localRows)) {
        await _recordConflict(
          txn,
          userId,
          table,
          record,
          localRows,
          'pending_local_write',
        );
        return (0, 1);
      }
      return (0, 0);
    }
    if (localRows.isEmpty) {
      await txn.insert(table, record.data);
      parents.markWritten(id);
      return (1, 0);
    }
    final remoteRevision = _remoteRevision(record);
    final localRevision = _localRevision(localRows);
    if (remoteRevision > localRevision) {
      if (table == 'products') {
        record.data['image_path'] = localRows.single['image_path'];
      }
      await txn.update(
        table,
        record.data,
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
      );
      parents.markWritten(id);
      return (1, 0);
    }
    if (remoteRevision == 0 &&
        localRevision == 0 &&
        _legacyDiffers(localRows.single, record.data)) {
      await _recordConflict(
        txn,
        userId,
        table,
        record,
        localRows,
        'legacy_divergence',
      );
      return (0, 1);
    }
    return (0, 0);
  }

  Future<(int, int)> _applyOrder(
    DatabaseExecutor txn,
    String userId,
    _InboundRecord record,
    Set<String> protected,
    _InboundParentLookup parents,
  ) async {
    final result = await _applyMutable(
      txn,
      userId,
      'orders',
      record,
      protected,
      parents,
    );
    if (result.$1 == 0) return result;
    final id = record.data['id'] as String;
    await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id]);
    for (final child in record.children) {
      await txn.insert('order_items', child);
    }
    return result;
  }

  Future<(int, int)> _applyDebt(
    DatabaseExecutor txn,
    String userId,
    _InboundRecord record,
    Set<String> protected,
    _InboundParentLookup parents,
  ) async {
    final result = await _applyMutable(
      txn,
      userId,
      'debts',
      record,
      protected,
      parents,
    );
    if (result.$1 == 0) return result;
    final id = record.data['id'] as String;
    await txn.delete('payments', where: 'debt_id = ?', whereArgs: [id]);
    for (final child in record.children) {
      await txn.insert('payments', child);
    }
    return result;
  }

  Future<(int, int)> _applyCustomOrder(
    DatabaseExecutor txn,
    String userId,
    _InboundRecord record,
    Set<String> protected,
    _InboundParentLookup parents,
  ) async {
    final result = await _applyMutable(
      txn,
      userId,
      'custom_orders',
      record,
      protected,
      parents,
    );
    if (result.$1 == 0) return result;
    final id = record.data['id'] as String;
    await txn.delete(
      'custom_order_payments',
      where: 'custom_order_id = ?',
      whereArgs: [id],
    );
    for (final child in record.children) {
      await txn.insert('custom_order_payments', child);
    }
    return result;
  }

  int _remoteRevision(_InboundRecord record) =>
      record.data['revision'] as int? ?? 0;

  int _localRevision(List<Map<String, Object?>> rows) =>
      rows.single['revision'] as int? ?? 0;

  bool _legacyDiffers(Map<String, Object?> local, Map<String, dynamic> remote) {
    const ignored = {
      'revision',
      'base_revision',
      'updated_at',
      'writer_device_id',
      'tombstone_revision',
      'purge_state',
      'number_state',
      'provisional_order_id',
    };
    final comparableLocal = {
      for (final entry in local.entries)
        if (!ignored.contains(entry.key) && remote.containsKey(entry.key))
          entry.key: entry.value,
    };
    final comparableRemote = {
      for (final entry in remote.entries)
        if (!ignored.contains(entry.key) &&
            comparableLocal.containsKey(entry.key))
          entry.key: entry.value,
    };
    return jsonEncode(comparableLocal) != jsonEncode(comparableRemote);
  }

  Future<void> _recordConflict(
    DatabaseExecutor txn,
    String userId,
    String collection,
    _InboundRecord remote,
    List<Map<String, Object?>> localRows,
    String reason,
  ) async {
    final id = remote.data['id'] as String;
    await txn.insert('sync_conflicts', {
      'user_id': userId,
      'collection': collection,
      'doc_id': id,
      'aggregate_key': '$collection:$id',
      'local_revision': localRows.isEmpty ? 0 : _localRevision(localRows),
      'remote_revision': _remoteRevision(remote),
      'local_data': jsonEncode(localRows.isEmpty ? null : localRows.single),
      'remote_data': jsonEncode(remote.data),
      'reason': reason,
      'status': 'open',
      'created_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}

class _InboundRecord {
  const _InboundRecord(this.data, {this.children = const []});

  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> children;
}

/// Lives only within one reconciliation transaction. Duplicate incoming IDs
/// after a write must observe the actual row, including SQLite defaults, rather
/// than the prefetch or an approximated copy of the incoming payload.
class _InboundParentLookup {
  _InboundParentLookup(this.txn, this.userId, this.table, this.rows);

  final DatabaseExecutor txn;
  final String userId;
  final String table;
  final Map<String, Map<String, Object?>> rows;
  final Set<String> _written = {};

  void markWritten(String id) => _written.add(id);

  Future<List<Map<String, Object?>>> read(String id) async {
    if (_written.remove(id)) {
      final current = await txn.query(
        table,
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
        limit: 1,
      );
      if (current.isEmpty) {
        rows.remove(id);
      } else {
        rows[id] = current.single;
      }
    }
    final row = rows[id];
    return row == null ? const [] : [row];
  }
}
