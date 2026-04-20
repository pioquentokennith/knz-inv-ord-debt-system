import 'dart:convert';
import '../models/debt_model.dart';
import 'base_repository.dart';
import 'debt_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class LocalDebtRepository extends BaseRepository implements DebtRepository {
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  @override
  Future<List<CustomerDebt>> getAll(String userId) => safeCall(() async {
    final database = await db.database;
    final debtMaps = await database.query('debts',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC');

    if (debtMaps.isEmpty && _queue.isOnline) {
      final cloudDebts = await _cloud.getDebts(userId);
      for (final d in cloudDebts) {
        try {
          // Check muna kung mayroon na para iwas duplicate
          final existing = await database.query('debts',
              where: 'id = ?', whereArgs: [d['id']]);
          if (existing.isNotEmpty) continue;

          await database.insert('debts', {
            'id':            d['id'],
            'customer_name': d['customer_name'],
            'order_id':      d['order_id'],
            'total_amount':  d['total_amount'],
            'amount_paid':   d['amount_paid'],
            'created_at':    d['created_at'],
            'user_id':       userId,
          });
          final payments = List<Map<String, dynamic>>.from(d['payments'] ?? []);
          for (final p in payments) {
            try {
              await database.insert('payments', {
                'id':      p['id'],
                'debt_id': d['id'],
                'amount':  p['amount'],
                'paid_at': p['paid_at'],
                'note':    p['note'],
              });
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    // FIX N+1: single JOIN query instead of 1 query per debt
    final joinRows = await database.rawQuery('''
      SELECT
        d.id            AS d_id,
        d.customer_name AS d_customer_name,
        d.order_id      AS d_order_id,
        d.total_amount  AS d_total_amount,
        d.amount_paid   AS d_amount_paid,
        d.created_at    AS d_created_at,
        p.id            AS p_id,
        p.amount        AS p_amount,
        p.paid_at       AS p_paid_at,
        p.note          AS p_note
      FROM debts d
      LEFT JOIN payments p ON p.debt_id = d.id
      WHERE d.user_id = ? AND (d.is_deleted IS NULL OR d.is_deleted = 0)
      ORDER BY d.created_at DESC, p.paid_at ASC
    ''', [userId]);

    final debtsMap    = <String, Map<String, dynamic>>{};
    final paymentsMap = <String, List<PaymentRecord>>{};
    for (final row in joinRows) {
      final did = row['d_id'] as String;
      debtsMap.putIfAbsent(did, () => {
        'id':            row['d_id'],
        'customer_name': row['d_customer_name'],
        'order_id':      row['d_order_id'],
        'total_amount':  row['d_total_amount'],
        'amount_paid':   row['d_amount_paid'],
        'created_at':    row['d_created_at'],
      });
      if (row['p_id'] != null) {
        paymentsMap.putIfAbsent(did, () => []).add(_paymentFromMap({
          'id':      row['p_id'],
          'amount':  row['p_amount'],
          'paid_at': row['p_paid_at'],
          'note':    row['p_note'],
        }));
      }
    }
    return debtsMap.entries
        .map((e) => _debtFromMap(e.value, paymentsMap[e.key] ?? []))
        .toList();
  }, []);

  @override
  Future<void> add(CustomerDebt debt, String userId) => safeVoidCall(() async {
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.insert('debts', _debtToMap(debt, userId));
      for (final payment in debt.payments) {
        await txn.insert('payments', _paymentToMap(payment, debt.id));
      }
    });

    final paymentsData = debt.payments.map((p) => _paymentToMap(p, debt.id)).toList();
    final debtData = _debtToMap(debt, userId);

    if (_queue.isOnline) {
      await _cloud.saveDebt(userId, debtData, paymentsData);
    } else {
      await _queue.enqueue(
        operation:  'save_debt',
        collection: 'debts',
        userId:     userId,
        docId:      debt.id,
        data:       {...debtData, '_payments': jsonEncode(paymentsData)},
      );
    }
  });

  @override
  Future<void> addPayment(String debtId, PaymentRecord payment) => safeVoidCall(() async {
    final database = await db.database;

    await database.transaction((txn) async {
      await txn.insert('payments', _paymentToMap(payment, debtId));
      final debtMaps = await txn.query('debts',
          where: 'id = ?', whereArgs: [debtId]);
      if (debtMaps.isNotEmpty) {
        final current = (debtMaps.first['amount_paid'] as num).toDouble();
        await txn.update('debts', {'amount_paid': current + payment.amount},
            where: 'id = ?', whereArgs: [debtId]);
      }
    });

    final debtMaps = await database.query('debts',
        where: 'id = ?', whereArgs: [debtId]);
    if (debtMaps.isNotEmpty) {
      final userId     = debtMaps.first['user_id']     as String;
      final amountPaid = (debtMaps.first['amount_paid'] as num).toDouble();
      final allPayments = await database.query('payments',
          where: 'debt_id = ?', whereArgs: [debtId]);
      final paymentsData = allPayments
          .map((p) => _paymentToMap(_paymentFromMap(p), debtId))
          .toList();

      if (_queue.isOnline) {
        await _cloud.updateDebtPayment(userId, debtId, amountPaid, paymentsData);
      } else {
        await _queue.enqueue(
          operation:  'update_debt_payment',
          collection: 'debts',
          userId:     userId,
          docId:      debtId,
          data:       {
            'amount_paid': amountPaid,
            '_payments':   jsonEncode(paymentsData),
          },
        );
      }
    }
  });

  // ── Soft-delete (replaces hard delete) — FIX: debts now consistent with orders/products ──
  @override
  Future<void> delete(String debtId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('debts',
        where: 'id = ?', whereArgs: [debtId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';
    final now = DateTime.now().toIso8601String();

    // Soft-delete — mark as deleted, preserve data for RecycleBin
    await database.update(
      'debts',
      {'is_deleted': 1, 'deleted_at': now},
      where: 'id = ?',
      whereArgs: [debtId],
    );

    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.softDeleteDebt(userId, debtId, now);
      } else {
        await _queue.enqueue(
          operation:  'soft_delete_debt',
          collection: 'debts',
          userId:     userId,
          docId:      debtId,
          data:       {'id': debtId, 'is_deleted': 1, 'deleted_at': now},
        );
      }
    }
  });

  // ── NEW: Get soft-deleted debts (Recycle Bin) ─────────────────────────────
  Future<List<CustomerDebt>> getDeleted(String userId) => safeCall(() async {
    final database = await db.database;
    final joinRows = await database.rawQuery('''
      SELECT
        d.id            AS d_id,
        d.customer_name AS d_customer_name,
        d.order_id      AS d_order_id,
        d.total_amount  AS d_total_amount,
        d.amount_paid   AS d_amount_paid,
        d.created_at    AS d_created_at,
        p.id            AS p_id,
        p.amount        AS p_amount,
        p.paid_at       AS p_paid_at,
        p.note          AS p_note
      FROM debts d
      LEFT JOIN payments p ON p.debt_id = d.id
      WHERE d.user_id = ? AND d.is_deleted = 1
      ORDER BY d.created_at DESC, p.paid_at ASC
    ''', [userId]);

    final debtsMap    = <String, Map<String, dynamic>>{};
    final paymentsMap = <String, List<PaymentRecord>>{};
    for (final row in joinRows) {
      final did = row['d_id'] as String;
      debtsMap.putIfAbsent(did, () => {
        'id':            row['d_id'],
        'customer_name': row['d_customer_name'],
        'order_id':      row['d_order_id'],
        'total_amount':  row['d_total_amount'],
        'amount_paid':   row['d_amount_paid'],
        'created_at':    row['d_created_at'],
      });
      if (row['p_id'] != null) {
        paymentsMap.putIfAbsent(did, () => []).add(_paymentFromMap({
          'id':      row['p_id'],
          'amount':  row['p_amount'],
          'paid_at': row['p_paid_at'],
          'note':    row['p_note'],
        }));
      }
    }
    return debtsMap.entries
        .map((e) => _debtFromMap(e.value, paymentsMap[e.key] ?? []))
        .toList();
  }, []);

  // ── NEW: Restore a soft-deleted debt ──────────────────────────────────────
  Future<void> restore(String debtId) => safeVoidCall(() async {
    final database = await db.database;
    await database.update(
      'debts',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ?',
      whereArgs: [debtId],
    );

    final rows = await database.query('debts', where: 'id = ?', whereArgs: [debtId]);
    if (rows.isNotEmpty) {
      final userId = rows.first['user_id'] as String;
      final data   = Map<String, dynamic>.from(rows.first);
      if (_queue.isOnline) {
        await _cloud.saveDebt(userId, data, []);
      } else {
        await _queue.enqueue(
          operation: 'save_debt', collection: 'debts',
          userId: userId, docId: debtId, data: data,
        );
      }
    }
  });

  // ── Hard delete (permanent purge — admin only) ────────────────────────────
  Future<void> hardDelete(String debtId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('debts',
        where: 'id = ?', whereArgs: [debtId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';

    await database.delete('debts', where: 'id = ?', whereArgs: [debtId]);

    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.deleteDebt(userId, debtId);
      } else {
        await _queue.enqueue(
          operation:  'delete_debt',
          collection: 'debts',
          userId:     userId,
          docId:      debtId,
          data:       {'id': debtId},
        );
      }
    }
  });

  Map<String, dynamic> _debtToMap(CustomerDebt d, String userId) => {
    'id':            d.id,
    'customer_name': d.customerName,
    'order_id':      d.orderId,
    'total_amount':  d.totalAmount,
    'amount_paid':   d.amountPaid,
    'created_at':    d.createdAt.toIso8601String(),
    'user_id':       userId,
    'is_deleted':    0,
    'deleted_at':    null,
  };

  Map<String, dynamic> _paymentToMap(PaymentRecord p, String debtId) => {
    'id':      p.id,
    'debt_id': debtId,
    'amount':  p.amount,
    'paid_at': p.paidAt.toIso8601String(),
    'note':    p.note,
  };

  CustomerDebt _debtFromMap(Map<String, dynamic> m, List<PaymentRecord> payments) =>
      CustomerDebt(
        id:           m['id']            as String,
        customerName: m['customer_name'] as String,
        orderId:      m['order_id']      as String,
        totalAmount:  (m['total_amount'] as num).toDouble(),
        amountPaid:   (m['amount_paid']  as num).toDouble(),
        createdAt:    DateTime.parse(m['created_at'] as String),
        payments:     payments,
      );

  PaymentRecord _paymentFromMap(Map<String, dynamic> m) => PaymentRecord(
    id:     m['id']    as String,
    amount: (m['amount'] as num).toDouble(),
    paidAt: DateTime.parse(m['paid_at'] as String),
    note:   m['note']  as String?,
  );
}
