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

class InboundSyncResult {
  const InboundSyncResult({
    required this.appliedCount,
    required this.conflictCount,
  });

  final int appliedCount;
  final int conflictCount;
  bool get changed => appliedCount > 0;
}

class InboundSyncCoordinator {
  InboundSyncCoordinator({
    Future<Database> Function()? databaseProvider,
    FirestoreSync? cloud,
    Future<List<List<Map<String, dynamic>>>> Function(String userId)?
    remoteLoader,
    DateTime Function()? now,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _cloud = cloud ?? FirestoreSync.instance,
       _remoteLoader = remoteLoader,
       _now = now ?? (() => DateTime.now().toUtc());

  static final instance = InboundSyncCoordinator();

  final Future<Database> Function() _databaseProvider;
  final FirestoreSync _cloud;
  final Future<List<List<Map<String, dynamic>>>> Function(String userId)?
  _remoteLoader;
  final DateTime Function() _now;

  Future<InboundSyncResult> reconcile(String userId) async {
    final remote =
        await (_remoteLoader?.call(userId) ??
            Future.wait<List<Map<String, dynamic>>>([
              _cloud.getProducts(userId),
              _cloud.getOrders(userId),
              _cloud.getDebts(userId),
              _cloud.getResellers(userId),
              _cloud.getCustomOrders(userId),
              _cloud.getBusinessEvents(userId),
              _cloud.getLogs(userId),
            ]));

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
    var applied = 0;
    var conflicts = 0;
    await database.transaction((txn) async {
      for (final record in products) {
        final result = await _applyMutable(txn, userId, 'products', record);
        applied += result.$1;
        conflicts += result.$2;
      }
      for (final record in orders) {
        final result = await _applyOrder(txn, userId, record);
        applied += result.$1;
        conflicts += result.$2;
      }
      for (final record in debts) {
        final result = await _applyDebt(txn, userId, record);
        applied += result.$1;
        conflicts += result.$2;
      }
      for (final record in resellers) {
        final result = await _applyMutable(txn, userId, 'resellers', record);
        applied += result.$1;
        conflicts += result.$2;
      }
      for (final record in customOrders) {
        final result = await _applyCustomOrder(txn, userId, record);
        applied += result.$1;
        conflicts += result.$2;
      }
      for (final event in events) {
        applied +=
            await txn.insert(
                  'business_events',
                  event,
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                ) >
                0
            ? 1
            : 0;
      }
      for (final log in logs) {
        applied +=
            await txn.insert(
                  'activity_logs',
                  log,
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                ) >
                0
            ? 1
            : 0;
      }
      final timestamp = _now().toUtc().toIso8601String();
      for (final collection in const [
        'products',
        'orders',
        'debts',
        'resellers',
        'custom_orders',
        'business_events',
        'activity_logs',
      ]) {
        await txn.insert('sync_cursors', {
          'user_id': userId,
          'collection': collection,
          'cursor_value': timestamp,
          'updated_at': timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    return InboundSyncResult(appliedCount: applied, conflictCount: conflicts);
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
    if (local.containsKey('order_id'))
      'number_state': remote['number_state'] as String? ?? 'legacy',
    if (local.containsKey('order_id'))
      'provisional_order_id': remote['provisional_order_id'] as String?,
  };

  Future<(int, int)> _applyMutable(
    DatabaseExecutor txn,
    String userId,
    String table,
    _InboundRecord record,
  ) async {
    final id = record.data['id'] as String;
    final aggregate = '$table:$id';
    final pending = await txn.query(
      'sync_queue',
      columns: const ['id'],
      where: 'user_id = ? AND aggregate_key = ?',
      whereArgs: [userId, aggregate],
      limit: 1,
    );
    final localRows = await txn.query(
      table,
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
      limit: 1,
    );
    if (pending.isNotEmpty) {
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
  ) async {
    final result = await _applyMutable(txn, userId, 'orders', record);
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
  ) async {
    final result = await _applyMutable(txn, userId, 'debts', record);
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
  ) async {
    final result = await _applyMutable(txn, userId, 'custom_orders', record);
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
