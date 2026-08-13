import 'package:sqflite/sqflite.dart';

import '../core/domain_exceptions.dart';
import '../database/database_helper.dart';
import '../dto/business_event_dto.dart';
import '../dto/debt_dto.dart';
import '../models/business_event_model.dart';
import '../models/debt_model.dart';
import 'base_repository.dart';
import 'debt_repository.dart';
import 'firestore_sync.dart';
import 'local_business_event_repository.dart';
import 'sync_queue.dart';

/// SQLite-backed debt repository with persisted accrual and payment allocation.
class LocalDebtRepository extends BaseRepository implements DebtRepository {
  LocalDebtRepository({
    Future<Database> Function()? databaseProvider,
    SyncOutbox? queue,
    FirestoreSync? cloud,
    DateTime Function()? now,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _queue = queue ?? SyncQueue.instance,
       _cloud = cloud ?? FirestoreSync.instance,
       _now = now ?? (() => DateTime.now().toUtc());

  final Future<Database> Function() _databaseProvider;
  final SyncOutbox _queue;
  final FirestoreSync _cloud;
  final DateTime Function() _now;

  @override
  Future<List<CustomerDebt>> getAll(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    final partition = await database.query(
      'debts',
      columns: const ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (partition.isEmpty && _queue.isOnline) {
      await _restoreCloudPartition(database, userId);
    }
    final debts = await _accrueAndLoad(database, userId, _now());
    _queue.requestSync();
    return debts;
  });

  @override
  Future<void> add(CustomerDebt debt, String userId) => safeVoidCall(() async {
    _validateNewDebt(debt, userId);
    final database = await _databaseProvider();
    final dto = DebtDto.fromDomain(debt, userId: userId);
    final debtData = dto.toLocal();
    final payments = dto.payments.map((payment) => payment.toLocal()).toList();
    await database.transaction((txn) async {
      if (await txn.insert('debts', debtData) <= 0) {
        throw StateError('Debt was not inserted.');
      }
      for (final payment in payments) {
        if (await txn.insert('payments', payment) <= 0) {
          throw StateError('Debt payment was not inserted.');
        }
      }
      final events = <BusinessEvent>[];
      for (final payment in debt.payments) {
        final event = _collectionEvent(userId, debt.id, payment);
        await insertBusinessEvent(txn, event);
        events.add(event);
      }
      await _queue.enqueue(
        operation: events.isEmpty ? 'save_debt' : 'save_debt_with_events',
        collection: 'debts',
        userId: userId,
        docId: debt.id,
        data: events.isEmpty
            ? _outboxPayload(dto)
            : {
                '_debt': _outboxPayload(dto),
                '_events': events
                    .map(
                      (event) => BusinessEventDto.fromDomain(event).toCloud(),
                    )
                    .toList(growable: false),
              },
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  @override
  Future<void> addPayment(String debtId, PaymentRecord payment) =>
      safeVoidCall(() async {
        if (debtId.trim().isEmpty) throw ArgumentError('Debt id is required.');
        if (!payment.amount.isPositive || payment.isAllocated) {
          throw ArgumentError(
            'A new payment must be positive and not already allocated.',
          );
        }
        final database = await _databaseProvider();
        await database.transaction((txn) async {
          final debt = await _loadOne(txn, debtId, isDeleted: false);
          final allocation = debt.allocatePayment(payment);
          final updatedDebt = allocation.debt;
          final changed = await txn.update(
            'debts',
            _debtStateMap(updatedDebt),
            where: 'id = ? AND is_deleted = 0',
            whereArgs: [debtId],
          );
          if (changed != 1) {
            throw StateError('Debt changed while recording payment: $debtId');
          }
          if (await txn.insert(
                'payments',
                PaymentDto.fromDomain(allocation.payment, debtId).toLocal(),
              ) <=
              0) {
            throw StateError('Payment was not inserted.');
          }
          final allPayments = await txn.query(
            'payments',
            where: 'debt_id = ?',
            whereArgs: [debtId],
            orderBy: 'paid_at ASC, id ASC',
          );
          final owner = await _ownerFor(txn, debtId);
          final event = _collectionEvent(owner, debtId, allocation.payment);
          await insertBusinessEvent(txn, event);
          final fullDto = DebtDto.fromLocal(
            DebtDto.fromDomain(updatedDebt, userId: owner).toLocal(),
            allPayments.map(Map<String, dynamic>.from).toList(),
          );
          await _queue.enqueue(
            operation: 'apply_debt_payment',
            collection: 'debts',
            userId: owner,
            docId: debtId,
            data: {
              '_debt': _outboxPayload(fullDto),
              '_payment': PaymentDto.fromDomain(
                allocation.payment,
                debtId,
              ).toCloud(),
              '_event': BusinessEventDto.fromDomain(event).toCloud(),
            },
            executor: txn,
          );
        });
        _queue.requestSync();
      });

  BusinessEvent _collectionEvent(
    String userId,
    String debtId,
    PaymentRecord payment,
  ) => BusinessEvent(
    id: 'debt-collection-${payment.id}',
    userId: userId,
    subject: BusinessEventSubject.debt,
    subjectId: debtId,
    type: BusinessEventType.collection,
    amount: payment.amount,
    occurredAt: payment.paidAt,
    recordedAt: payment.paidAt,
    paymentMethod: payment.paymentMethod,
    reference: payment.reference,
    reason: payment.note,
    commandId: 'debt-collection-${payment.id}',
    sourceType: 'debt_payment',
    sourceId: payment.id,
  );

  @override
  Future<void> delete(String debtId, String userId) =>
      _setDeleted(debtId, userId, deleted: true);

  @override
  Future<List<CustomerDebt>> getDeleted(String userId) => safeCall(() async {
    final database = await _databaseProvider();
    return _loadDebts(database, userId, isDeleted: true);
  });

  @override
  Future<void> restore(String debtId, String userId) =>
      _setDeleted(debtId, userId, deleted: false);

  @override
  Future<void> hardDelete(
    String debtId,
    String userId,
  ) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final debt = await _loadOne(txn, debtId, isDeleted: true, userId: userId);
      _requireSettled(debt);
      await _queue.enqueue(
        operation: 'delete_debt',
        collection: 'debts',
        userId: userId,
        docId: debtId,
        data: {'id': debtId},
        executor: txn,
      );
      if (await txn.update(
            'debts',
            {'purge_state': 'pending'},
            where:
                'id = ? AND user_id = ? AND is_deleted = 1 AND purge_state = ?',
            whereArgs: [debtId, userId, 'none'],
          ) !=
          1) {
        throw StateError('Failed to queue debt purge: $debtId');
      }
    });
    _queue.requestSync();
  });

  Future<void> _setDeleted(
    String debtId,
    String userId, {
    required bool deleted,
  }) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final debt = await _loadOne(
        txn,
        debtId,
        isDeleted: !deleted,
        userId: userId,
      );
      _requireSettled(debt);
      final deletedAt = deleted ? _now().toIso8601String() : null;
      if (await txn.update(
            'debts',
            {'is_deleted': deleted ? 1 : 0, 'deleted_at': deletedAt},
            where: 'id = ? AND is_deleted = ?',
            whereArgs: [debtId, deleted ? 0 : 1],
          ) !=
          1) {
        throw StateError('Debt state changed before it could be updated.');
      }
      final payments = await txn.query(
        'payments',
        where: 'debt_id = ?',
        whereArgs: [debtId],
        orderBy: 'paid_at ASC, id ASC',
      );
      final payload = {
        ...DebtDto.fromDomain(debt, userId: userId).toLocal(),
        'is_deleted': deleted ? 1 : 0,
        'deleted_at': deletedAt,
      };
      final dto = DebtDto.fromLocal(
        payload,
        payments.map(Map<String, dynamic>.from).toList(),
      );
      await _queue.enqueue(
        operation: deleted ? 'soft_delete_debt' : 'save_debt',
        collection: 'debts',
        userId: userId,
        docId: debtId,
        data: _outboxPayload(dto),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  Future<List<CustomerDebt>> _accrueAndLoad(
    Database database,
    String userId,
    DateTime timestamp,
  ) async {
    await database.transaction((txn) async {
      final rows = await txn.query(
        'debts',
        columns: const ['id'],
        where: 'user_id = ? AND is_deleted = 0',
        whereArgs: [userId],
      );
      for (final row in rows) {
        final debt = await _loadOne(txn, row['id'] as String, isDeleted: false);
        final accrued = debt.accrueTo(timestamp);
        if (accrued.lastAccrualTimestamp == debt.lastAccrualTimestamp &&
            accrued.interestOutstanding == debt.interestOutstanding) {
          continue;
        }
        await txn.update(
          'debts',
          _debtStateMap(accrued),
          where: 'id = ? AND is_deleted = 0',
          whereArgs: [debt.id],
        );
        final payments = await txn.query(
          'payments',
          where: 'debt_id = ?',
          whereArgs: [debt.id],
          orderBy: 'paid_at ASC, id ASC',
        );
        await _queue.enqueue(
          operation: 'save_debt',
          collection: 'debts',
          userId: userId,
          docId: debt.id,
          data: _outboxPayload(
            DebtDto.fromLocal(
              DebtDto.fromDomain(accrued, userId: userId).toLocal(),
              payments.map(Map<String, dynamic>.from).toList(),
            ),
          ),
          executor: txn,
        );
      }
    });
    return _loadDebts(database, userId, isDeleted: false);
  }

  Future<List<CustomerDebt>> _loadDebts(
    DatabaseExecutor database,
    String userId, {
    required bool isDeleted,
  }) async {
    final rows = await database.query(
      'debts',
      columns: const ['id'],
      where: 'user_id = ? AND is_deleted = ?',
      whereArgs: [userId, isDeleted ? 1 : 0],
      orderBy: 'created_at DESC',
    );
    final result = <CustomerDebt>[];
    for (final row in rows) {
      result.add(
        await _loadOne(database, row['id'] as String, isDeleted: isDeleted),
      );
    }
    return result;
  }

  Future<CustomerDebt> _loadOne(
    DatabaseExecutor database,
    String debtId, {
    required bool isDeleted,
    String? userId,
  }) async {
    final where = userId == null
        ? 'id = ? AND is_deleted = ?'
        : 'id = ? AND user_id = ? AND is_deleted = ?';
    final whereArgs = userId == null
        ? <Object?>[debtId, isDeleted ? 1 : 0]
        : <Object?>[debtId, userId, isDeleted ? 1 : 0];
    final rows = await database.query(
      'debts',
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        '${isDeleted ? 'Deleted' : 'Active'} debt not found: $debtId',
      );
    }
    final paymentRows = await database.query(
      'payments',
      where: 'debt_id = ?',
      whereArgs: [debtId],
      orderBy: 'paid_at ASC, id ASC',
    );
    return DebtDto.fromLocal(
      Map<String, dynamic>.from(rows.single),
      paymentRows.map((row) => Map<String, dynamic>.from(row)).toList(),
    ).toDomain();
  }

  Future<String> _ownerFor(DatabaseExecutor database, String debtId) async {
    final rows = await database.query(
      'debts',
      columns: const ['user_id'],
      where: 'id = ?',
      whereArgs: [debtId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Debt owner not found: $debtId');
    return rows.single['user_id'] as String;
  }

  Future<void> _restoreCloudPartition(Database database, String userId) async {
    final cloudDebts = await _cloud.getDebts(userId);
    await database.transaction((txn) async {
      for (final cloudDebt in cloudDebts) {
        final dto = DebtDto.fromCloud(cloudDebt, userId: userId);
        await txn.insert(
          'debts',
          dto.toLocal(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        for (final payment in dto.payments) {
          await txn.insert(
            'payments',
            payment.toLocal(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
  }

  void _validateNewDebt(CustomerDebt debt, String userId) {
    if (debt.id.trim().isEmpty || userId.trim().isEmpty) {
      throw ArgumentError('Debt id and user id are required.');
    }
    if (!debt.principalOriginal.isPositive ||
        debt.principalOutstanding.isNegative ||
        debt.interestOutstanding.isNegative) {
      throw ArgumentError('Debt balances are invalid.');
    }
    for (final payment in debt.payments) {
      if (!payment.isAllocated) {
        throw ArgumentError('Persisted debt payments must be allocated.');
      }
    }
  }

  void _requireSettled(CustomerDebt debt) {
    if (!debt.isPaid) {
      throw const OpenDebtException(
        'Settle this debt before deleting its ledger.',
      );
    }
  }

  Map<String, dynamic> _debtStateMap(CustomerDebt debt) => {
    'principal_outstanding_centavos': debt.principalOutstanding.centavos,
    'interest_outstanding_centavos': debt.interestOutstanding.centavos,
    'last_accrual_timestamp': debt.lastAccrualTimestamp.toIso8601String(),
    'status': debt.status.storageKey,
  };

  Map<String, dynamic> _outboxPayload(DebtDto dto) {
    final payload = dto.toCloud();
    payload['_payments'] = payload.remove('payments');
    return payload;
  }
}
