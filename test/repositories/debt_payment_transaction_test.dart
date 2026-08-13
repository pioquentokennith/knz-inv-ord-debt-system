import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/repositories/local_debt_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Outbox implements SyncOutbox {
  var nextKey = 0;
  var fail = false;

  @override
  bool get isOnline => false;

  @override
  Future<int> enqueue({
    required String operation,
    required String collection,
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
    DatabaseExecutor? executor,
  }) {
    if (executor == null) throw StateError('Transaction required.');
    if (fail) throw StateError('simulated outbox failure');
    final now = DateTime.utc(2026).toIso8601String();
    return executor.insert('sync_queue', {
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
      'idempotency_key': 'debt-${nextKey++}',
      'updated_at': now,
    });
  }

  @override
  void requestSync() {}
}

void main() {
  sqfliteFfiInit();
  final start = DateTime.utc(2026, 1, 1);
  late Database database;
  late DateTime now;
  late LocalDebtRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(database);
    now = start;
    repository = LocalDebtRepository(
      databaseProvider: () async => database,
      queue: _Outbox(),
      now: () => now,
    );
  });

  tearDown(() => database.close());

  test(
    'payment allocation, debt state, history, and outbox commit together',
    () async {
      await repository.add(
        CustomerDebt(
          id: 'debt-1',
          customerName: 'Customer',
          orderId: 'KNZ-001',
          principalOriginal: const Money.fromCentavos(10000),
          principalOutstanding: const Money.fromCentavos(10000),
          interestOutstanding: const Money.fromCentavos(1000),
          createdAt: start,
        ),
        'user-1',
      );

      await repository.addPayment(
        'debt-1',
        PaymentRecord(
          id: 'payment-1',
          amount: const Money.fromCentavos(10000),
          paidAt: start,
          paymentMethod: 'Cash',
        ),
      );

      final debt = (await database.query('debts')).single;
      expect(debt['principal_outstanding_centavos'], 1000);
      expect(debt['interest_outstanding_centavos'], 0);
      expect(debt['status'], 'open');
      final payment = (await database.query('payments')).single;
      expect(payment['interest_applied_centavos'], 1000);
      expect(payment['principal_applied_centavos'], 9000);
      final queued = await database.query('sync_queue', orderBy: 'id');
      final payload = jsonDecode(queued.last['data'] as String);
      expect(payload['_debt']['principal_outstanding_centavos'], 1000);
      expect(
        payload['_debt']['_payments'].single['interest_applied_centavos'],
        1000,
      );
      expect(payload['_payment']['interest_applied_centavos'], 1000);
      expect(payload['_event']['event_type'], 'collection');
      final event = (await database.query('business_events')).single;
      expect(event['subject_type'], 'debt');
      expect(event['amount_centavos'], 10000);
    },
  );

  test(
    'elapsed accrual persists once and does not recalculate history',
    () async {
      await repository.add(
        CustomerDebt(
          id: 'debt-1',
          customerName: 'Customer',
          orderId: 'KNZ-001',
          principalOriginal: const Money.fromCentavos(10000),
          principalOutstanding: const Money.fromCentavos(10000),
          createdAt: start,
          interestRateBasisPoints: 1000,
          interestType: 'daily',
        ),
        'user-1',
      );
      now = start.add(const Duration(days: 1));

      await repository.getAll('user-1');
      await repository.getAll('user-1');

      final debt = (await database.query('debts')).single;
      expect(debt['interest_outstanding_centavos'], 1000);
      expect(debt['last_accrual_timestamp'], '2026-01-02T00:00:00.000Z');
    },
  );

  test('outbox failure rolls back payment allocation and history', () async {
    final outbox = _Outbox();
    repository = LocalDebtRepository(
      databaseProvider: () async => database,
      queue: outbox,
      now: () => now,
    );
    await repository.add(
      CustomerDebt(
        id: 'debt-1',
        customerName: 'Customer',
        orderId: 'KNZ-001',
        principalOriginal: const Money.fromCentavos(10000),
        principalOutstanding: const Money.fromCentavos(10000),
        createdAt: start,
      ),
      'user-1',
    );
    outbox.fail = true;

    await expectLater(
      repository.addPayment(
        'debt-1',
        PaymentRecord(
          id: 'payment-1',
          amount: const Money.fromCentavos(2500),
          paidAt: start,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final debt = (await database.query('debts')).single;
    expect(debt['principal_outstanding_centavos'], 10000);
    expect(await database.query('payments'), isEmpty);
    expect(await database.query('sync_queue'), hasLength(1));
  });
}
