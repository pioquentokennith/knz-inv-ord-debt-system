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

    final allDebts = await database.query('debts',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC');
    final debts = <CustomerDebt>[];
    for (final debtMap in allDebts) {
      final paymentMaps = await database.query('payments',
          where: 'debt_id = ?', whereArgs: [debtMap['id']], orderBy: 'paid_at ASC');
      debts.add(_debtFromMap(debtMap, paymentMaps.map(_paymentFromMap).toList()));
    }
    return debts;
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

  @override
  Future<void> delete(String debtId) => safeVoidCall(() async {
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
