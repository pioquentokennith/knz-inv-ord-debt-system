// ─────────────────────────────────────────────────────────────────────────────
// sync_queue.dart
// Handles offline-first sync queue — nag-queue ng pending operations
// kapag walang internet, tapos auto-sync kapag bumalik ang connection
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/database_helper.dart';
import 'firestore_sync.dart';

class SyncQueue {
  SyncQueue._();
  static final SyncQueue instance = SyncQueue._();

  final _cloud = FirestoreSync.instance;
  StreamSubscription? _connectivitySub;
  bool _isOnline = false;
  bool _isSyncing = false;

  // ── Start monitoring internet connection ───────────────────────────────────
  void startMonitoring() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);

      // Kapag bumalik ang internet, i-sync sa background
      if (wasOffline && _isOnline) {
        // Delay ng 2 seconds para ma-stabilize ang connection bago mag-sync
        Future.delayed(const Duration(seconds: 2), syncPending);
      }
    });

    // Check current connectivity status
    Connectivity().checkConnectivity().then((results) {
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      // Kung may pending syncs at online na, sync agad
      if (_isOnline) {
        Future.delayed(const Duration(seconds: 1), syncPending);
      }
    });
  }

  void stopMonitoring() {
    _connectivitySub?.cancel();
  }

  bool get isOnline => _isOnline;

  // ── Add to queue (kapag walang internet) ──────────────────────────────────
  Future<void> enqueue({
    required String operation,   // 'save_user', 'save_product', etc.
    required String collection,  // 'users', 'products', etc.
    required String userId,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    final database = await DatabaseHelper.instance.database;
    await database.insert('sync_queue', {
      'operation':  operation,
      'collection': collection,
      'user_id':    userId,
      'doc_id':     docId,
      'data':       jsonEncode(data),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // ── Process all pending syncs ──────────────────────────────────────────────
  Future<void> syncPending() async {
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;

    try {
      final database = await DatabaseHelper.instance.database;
      final pending = await database.query('sync_queue', orderBy: 'created_at ASC');

      for (final row in pending) {
        final operation  = row['operation']  as String;
        final collection = row['collection'] as String;
        final userId     = row['user_id']    as String;
        final docId      = row['doc_id']     as String;
        final data       = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        final rowId      = row['id'] as int;

        try {
          switch (operation) {
            case 'save_user':
              await _cloud.saveUser(data);
              break;
            case 'save_product':
              await _cloud.saveProduct(userId, data);
              break;
            case 'delete_product':
              await _cloud.deleteProduct(userId, docId);
              break;
            case 'save_order':
              final items = List<Map<String, dynamic>>.from(
                  jsonDecode(data['_items'] as String? ?? '[]'));
              final cleanData = Map<String, dynamic>.from(data)..remove('_items');
              await _cloud.saveOrder(userId, cleanData, items);
              break;
            case 'update_order_status':
              await _cloud.updateOrderStatus(userId, docId, data['status'] as String);
              break;
            case 'delete_order':
              await _cloud.deleteOrder(userId, docId);
              break;
            case 'save_debt':
              final payments = List<Map<String, dynamic>>.from(
                  jsonDecode(data['_payments'] as String? ?? '[]'));
              final cleanDebt = Map<String, dynamic>.from(data)..remove('_payments');
              await _cloud.saveDebt(userId, cleanDebt, payments);
              break;
            case 'update_debt_payment':
              final payments2 = List<Map<String, dynamic>>.from(
                  jsonDecode(data['_payments'] as String? ?? '[]'));
              await _cloud.updateDebtPayment(
                  userId, docId,
                  (data['amount_paid'] as num).toDouble(),
                  payments2);
              break;
            case 'delete_debt':
              await _cloud.deleteDebt(userId, docId);
              break;
            case 'save_log':
              await _cloud.saveLog(userId, data);
              break;
            case 'update_user_password':
              await _cloud.updateUserPassword(
                  data['username'] as String,
                  data['password'] as String);
              break;
          }

          // Remove from queue after successful sync
          await database.delete('sync_queue',
              where: 'id = ?', whereArgs: [rowId]);

          // Mark as synced sa users table kung applicable
          if (collection == 'users') {
            await database.update('users', {'is_synced': 1},
                where: 'id = ?', whereArgs: [docId]);
          }
        } catch (_) {
          // Keep in queue kung may error — try ulit next time
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
