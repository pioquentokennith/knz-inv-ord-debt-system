// ─────────────────────────────────────────────────────────────────────────────
// local_debt_repository.dart — SQLite-backed debt (utang) repository
// Purpose : Manages customer debt records and payment installments against
//           local SQLite with automatic Firestore sync via SyncQueue.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import '../models/debt_model.dart';
import 'base_repository.dart';
import 'debt_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

// Concrete SQLite + Firestore implementation of DebtRepository
class LocalDebtRepository extends BaseRepository implements DebtRepository {
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  // Returns all active (non-deleted) debts with their payment records (JOIN query)
  @override
  Future<List<CustomerDebt>> getAll(String userId) => safeCall(() async {
    final database = await db.database;
    // Basic query used only for cloud fallback check
    final debtMaps = await database.query('debts',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC');

    // Local is empty and online — restore debts from Firestore
    if (debtMaps.isEmpty && _queue.isOnline) {
      final cloudDebts = await _cloud.getDebts(userId);
      for (final d in cloudDebts) {
        try {
          // Check first to avoid duplicate entries on partial sync
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
          // Insert each payment record linked to this debt
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

    // FIX N+1: Single JOIN query instead of one query per debt for payments
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
      WHERE d.user_id = ? AND d.is_deleted = 0
      ORDER BY d.created_at DESC, p.paid_at ASC
    ''', [userId]);

    // Group flat JOIN rows back into CustomerDebt objects with their PaymentRecord lists
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
      // p_id is null when LEFT JOIN finds no matching payments row
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

  // Inserts a new debt record and any initial payments in a single transaction
  @override
  Future<void> add(CustomerDebt debt, String userId) => safeVoidCall(() async {
    final database = await db.database;
    // Atomic: if any insert fails, neither the debt nor its payments are saved
    await database.transaction((txn) async {
      await txn.insert('debts', _debtToMap(debt, userId));
      for (final payment in debt.payments) {
        await txn.insert('payments', _paymentToMap(payment, debt.id));
      }
    });

    // Sync to Firestore with embedded payments array
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

  // Appends a payment installment to a debt and updates the running amount_paid total
  @override
  Future<void> addPayment(String debtId, PaymentRecord payment) => safeVoidCall(() async {
    final database = await db.database;

    // Atomic: payment insert and amount_paid update happen together
    await database.transaction((txn) async {
      await txn.insert('payments', _paymentToMap(payment, debtId));
      // Read the current amount_paid and increment it by the new payment amount
      final debtMaps = await txn.query('debts',
          where: 'id = ?', whereArgs: [debtId]);
      if (debtMaps.isNotEmpty) {
        final current = (debtMaps.first['amount_paid'] as num).toDouble();
        await txn.update('debts', {'amount_paid': current + payment.amount},
            where: 'id = ?', whereArgs: [debtId]);
      }
    });

    // Fetch updated debt row to build Firestore sync payload
    final debtMaps = await database.query('debts',
        where: 'id = ?', whereArgs: [debtId]);
    if (debtMaps.isNotEmpty) {
      final userId     = debtMaps.first['user_id']     as String;
      final amountPaid = (debtMaps.first['amount_paid'] as num).toDouble();
      // Fetch all payments to send the full list in the Firestore update
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

  // Soft-deletes a debt: sets is_deleted=1 and records deleted_at timestamp
  @override
  Future<void> delete(String debtId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('debts',
        where: 'id = ?', whereArgs: [debtId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';
    final now = DateTime.now().toIso8601String();

    // Soft-delete — preserves payment history for Recycle Bin recovery
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

  // Returns all soft-deleted debts for the Recycle Bin screen (JOIN query)
  @override
  Future<List<CustomerDebt>> getDeleted(String userId) => safeCall(() async {
    final database = await db.database;
    // Same JOIN pattern as getAll() but filters is_deleted = 1
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

  // Restores a soft-deleted debt back to active and re-syncs it to Firestore
  @override
  Future<void> restore(String debtId) => safeVoidCall(() async {
    final database = await db.database;
    // Clear soft-delete flags
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
        await _cloud.saveDebt(userId, data, []); // Payments synced separately
      } else {
        await _queue.enqueue(
          operation: 'save_debt', collection: 'debts',
          userId: userId, docId: debtId, data: data,
        );
      }
    }
  });

  // Permanently removes a debt and its payments from SQLite and Firestore
  @override
  Future<void> hardDelete(String debtId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('debts',
        where: 'id = ?', whereArgs: [debtId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';

    // ON DELETE CASCADE on payments ensures all payment rows are removed with the debt
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

  // ── Private mapping helpers ───────────────────────────────────────────────

  // Converts a CustomerDebt model to a SQLite column map
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

  // Converts a PaymentRecord model to a SQLite column map for the payments table
  Map<String, dynamic> _paymentToMap(PaymentRecord p, String debtId) => {
    'id':      p.id,
    'debt_id': debtId,
    'amount':  p.amount,
    'paid_at': p.paidAt.toIso8601String(),
    'note':    p.note,
  };

  // Assembles a CustomerDebt model from a flat column map and its payments list
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

  // Converts a raw SQLite row map into a PaymentRecord model instance
  PaymentRecord _paymentFromMap(Map<String, dynamic> m) => PaymentRecord(
    id:     m['id']    as String,
    amount: (m['amount'] as num).toDouble(),
    paidAt: DateTime.parse(m['paid_at'] as String),
    note:   m['note']  as String?,
  );
}
