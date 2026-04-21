// ─────────────────────────────────────────────────────────────────────────────
// sync_queue.dart — Offline-first Firestore sync queue
// Purpose : Stores failed or deferred Firestore operations in SQLite while
//           offline, then automatically flushes them when connectivity returns.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/database_helper.dart';
import 'firestore_sync.dart';

// Singleton — one queue shared across all repositories in the app
class SyncQueue {
  SyncQueue._();
  static final SyncQueue instance = SyncQueue._();

  final _cloud = FirestoreSync.instance; // Firestore adapter used during flush
  StreamSubscription? _connectivitySub;  // Subscription to network change events
  bool _isOnline  = false;               // Current connectivity state
  bool _isSyncing = false;               // Guards against concurrent flush runs

  // Starts listening for connectivity changes; triggers flush when going online
  void startMonitoring() {
    _connectivitySub?.cancel(); // Cancel any previous subscription before re-subscribing
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      // isOnline = true if at least one connection type is not "none"
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (wasOffline && _isOnline) {
        // Just came back online — wait 2s for connection to stabilize before syncing
        Future.delayed(const Duration(seconds: 2), syncPending);
      }
    });

    // Also check current state immediately on startup so we don't wait for a change event
    Connectivity().checkConnectivity().then((results) {
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_isOnline) {
        // Already online at startup — flush any entries left from the last session
        Future.delayed(const Duration(seconds: 1), syncPending);
      }
    });
  }

  // Stops the connectivity listener (call on app teardown or test cleanup)
  void stopMonitoring() {
    _connectivitySub?.cancel();
  }

  // Whether the device currently has an active network connection
  bool get isOnline => _isOnline;

  // Appends a new pending operation to the SQLite sync_queue table
  Future<void> enqueue({
    required String operation,              // e.g. 'save_product', 'soft_delete_order'
    required String collection,             // Firestore collection name
    required String userId,                 // Owner of the document
    required String docId,                  // Firestore document ID
    required Map<String, dynamic> data,     // Operation payload — will be JSON-encoded
  }) async {
    final database = await DatabaseHelper.instance.database;
    await database.insert('sync_queue', {
      'operation':  operation,
      'collection': collection,
      'user_id':    userId,
      'doc_id':     docId,
      'data':       jsonEncode(data),        // Stored as JSON string in SQLite TEXT column
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // Processes all pending queue entries in FIFO order; removes each row on success
  Future<void> syncPending() async {
    if (_isSyncing || !_isOnline) return; // Prevent concurrent or offline flush
    _isSyncing = true;

    try {
      final database = await DatabaseHelper.instance.database;
      // Fetch all pending rows oldest-first to preserve operation ordering
      final pending = await database.query('sync_queue', orderBy: 'created_at ASC');

      for (final row in pending) {
        final operation = row['operation']  as String;
        final userId    = row['user_id']    as String;
        final docId     = row['doc_id']     as String;
        final data      = jsonDecode(row['data'] as String) as Map<String, dynamic>;
        final rowId     = row['id'] as int; // Primary key — used to delete row after success

        try {
          // Dispatch each operation to the matching FirestoreSync method
          switch (operation) {
            case 'save_user':
              // Sync a new or updated user account to Firestore
              await _cloud.saveUser(data);
              break;
            case 'save_product':
              // Sync a new or edited product document to Firestore
              await _cloud.saveProduct(userId, data);
              break;
            case 'soft_delete_product':
              // Mark a product as deleted in Firestore without removing the document
              await _cloud.softDeleteProduct(userId, docId, data['deleted_at'] as String);
              break;
            case 'delete_product':
              // Permanently remove a product document from Firestore
              await _cloud.deleteProduct(userId, docId);
              break;
            case 'save_order':
              // Sync a new order; extract the embedded items list from the payload
              final items = List<Map<String, dynamic>>.from(
                  jsonDecode(data['_items'] as String? ?? '[]'));
              final cleanData = Map<String, dynamic>.from(data)..remove('_items');
              await _cloud.saveOrder(userId, cleanData, items);
              break;
            case 'update_order_status':
              // Sync a status change (e.g. Pending → Delivered) to Firestore
              await _cloud.updateOrderStatus(userId, docId, data['status'] as String);
              break;
            case 'soft_delete_order':
              // Mark an order as deleted in Firestore (Recycle Bin)
              await _cloud.softDeleteOrder(userId, docId, data['deleted_at'] as String);
              break;
            case 'delete_order':
              // Permanently remove an order document from Firestore
              await _cloud.deleteOrder(userId, docId);
              break;
            case 'save_debt':
              // Sync a new debt record; extract the embedded payments list
              final payments = List<Map<String, dynamic>>.from(
                  jsonDecode(data['_payments'] as String? ?? '[]'));
              final cleanDebt = Map<String, dynamic>.from(data)..remove('_payments');
              await _cloud.saveDebt(userId, cleanDebt, payments);
              break;
            case 'update_debt_payment':
              // Sync a payment installment update (amount_paid + payments array)
              final payments2 = List<Map<String, dynamic>>.from(
                  jsonDecode(data['_payments'] as String? ?? '[]'));
              await _cloud.updateDebtPayment(
                  userId, docId,
                  (data['amount_paid'] as num).toDouble(),
                  payments2);
              break;
            case 'soft_delete_debt':
              // Mark a debt as deleted in Firestore without removing payment history
              await _cloud.softDeleteDebt(userId, docId, data['deleted_at'] as String);
              break;
            case 'delete_debt':
              // Permanently remove a debt document from Firestore
              await _cloud.deleteDebt(userId, docId);
              break;
            case 'save_log':
              // Sync an activity log entry to Firestore
              await _cloud.saveLog(userId, data);
              break;
            case 'update_user_password':
              // Sync a hashed password change to Firestore
              await _cloud.updateUserPassword(
                  data['username'] as String,
                  data['password'] as String);
              break;
          }

          // Remove the row from the queue after a successful Firestore write
          await database.delete('sync_queue', where: 'id = ?', whereArgs: [rowId]);

          // Mark user as synced in SQLite after a successful user save
          if (row['collection'] == 'users') {
            await database.update('users', {'is_synced': 1},
                where: 'id = ?', whereArgs: [docId]);
          }
        } catch (_) {
          // Keep the row in the queue — it will be retried on next syncPending() call
        }
      }
    } finally {
      _isSyncing = false; // Always release the lock even if an error occurs
    }
  }
}
