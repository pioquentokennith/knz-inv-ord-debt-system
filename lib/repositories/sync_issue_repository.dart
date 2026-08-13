import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';

class SyncIssue {
  const SyncIssue({
    required this.id,
    required this.kind,
    required this.aggregateKey,
    required this.reason,
    required this.createdAt,
    required this.payload,
    this.operation,
  });

  final int id;
  final String kind;
  final String aggregateKey;
  final String reason;
  final DateTime createdAt;
  final String payload;
  final String? operation;
}

class SyncIssueRepository {
  SyncIssueRepository({Future<Database> Function()? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => DatabaseHelper.instance.database);

  final Future<Database> Function() _databaseProvider;

  Future<List<SyncIssue>> getOpen(String userId) async {
    final database = await _databaseProvider();
    final conflicts = await database.query(
      'sync_conflicts',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'open'],
      orderBy: 'created_at DESC',
    );
    final deadLetters = await database.query(
      'dead_letters',
      where: 'user_id = ? AND resolved_at IS NULL',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return [
      ...conflicts.map(
        (row) => SyncIssue(
          id: row['id'] as int,
          kind: 'conflict',
          aggregateKey: row['aggregate_key'] as String,
          reason: row['reason'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          payload: jsonEncode({
            'local': _decode(row['local_data']),
            'remote': _decode(row['remote_data']),
          }),
        ),
      ),
      ...deadLetters.map(
        (row) => SyncIssue(
          id: row['id'] as int,
          kind: 'dead_letter',
          aggregateKey: row['aggregate_key'] as String,
          reason: row['last_error'] as String,
          createdAt: DateTime.parse(row['created_at'] as String),
          payload: row['payload'] as String,
          operation: row['operation'] as String,
        ),
      ),
    ]..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  Future<void> resolve(SyncIssue issue, String userId) async {
    final database = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = issue.kind == 'conflict'
        ? await database.update(
            'sync_conflicts',
            {'status': 'resolved', 'resolved_at': now},
            where: 'id = ? AND user_id = ? AND status = ?',
            whereArgs: [issue.id, userId, 'open'],
          )
        : await database.update(
            'dead_letters',
            {'resolved_at': now},
            where: 'id = ? AND user_id = ? AND resolved_at IS NULL',
            whereArgs: [issue.id, userId],
          );
    if (changed != 1) throw StateError('Sync issue was already resolved.');
  }

  Future<void> retryDeadLetter(SyncIssue issue, String userId) async {
    if (issue.kind != 'dead_letter' || issue.operation == null) {
      throw StateError('Only dead-letter operations can be retried.');
    }
    final decoded = jsonDecode(issue.payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Dead-letter payload is not a JSON object.');
    }
    final separator = issue.aggregateKey.indexOf(':');
    if (separator <= 0 || separator == issue.aggregateKey.length - 1) {
      throw const FormatException('Dead-letter aggregate key is invalid.');
    }
    final collection = issue.aggregateKey.substring(0, separator);
    final documentId = issue.aggregateKey.substring(separator + 1);
    final database = await _databaseProvider();
    final now = DateTime.now().toUtc().toIso8601String();
    final operationId = const Uuid().v4();
    await database.transaction((txn) async {
      final unresolved = await txn.query(
        'dead_letters',
        columns: const ['id'],
        where: 'id = ? AND user_id = ? AND resolved_at IS NULL',
        whereArgs: [issue.id, userId],
        limit: 1,
      );
      if (unresolved.isEmpty) {
        throw StateError('Dead-letter operation was already resolved.');
      }
      await txn.insert('sync_queue', {
        'operation': issue.operation,
        'collection': collection,
        'user_id': userId,
        'doc_id': documentId,
        'data': jsonEncode(decoded),
        'created_at': now,
        'attempt_count': 0,
        'status': 'pending',
        'idempotency_key': operationId,
        'updated_at': now,
        'operation_id': operationId,
        'aggregate_key': issue.aggregateKey,
        'expected_revision': decoded['base_revision'] as int?,
        'resulting_revision': decoded['revision'] as int?,
        'device_id': decoded['writer_device_id'] as String?,
      });
      await txn.update(
        'dead_letters',
        {'resolved_at': now},
        where: 'id = ? AND user_id = ? AND resolved_at IS NULL',
        whereArgs: [issue.id, userId],
      );
    });
  }

  dynamic _decode(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } on FormatException {
      return value;
    }
  }
}
