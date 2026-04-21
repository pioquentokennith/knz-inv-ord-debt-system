// ─────────────────────────────────────────────────────────────────────────────
// firestore_sync.dart — Firestore read/write adapter
// Purpose : Thin wrapper around FirebaseFirestore that maps local data models
//           to Firestore documents. All methods swallow exceptions silently so
//           a Firestore outage never crashes the offline-first local layer.
// Added soft-delete sync methods:
//   • softDeleteProduct() — marks is_deleted=1 in Firestore (no hard delete)
//   • softDeleteOrder()   — same for orders
//   • softDeleteDebt()    — same for debts
// Existing hard-delete methods kept for permanent purge use-case only.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

// Singleton — one Firestore adapter per app session
class FirestoreSync {
  FirestoreSync._(); // Private constructor prevents external instantiation
  static final FirestoreSync instance = FirestoreSync._(); // Shared instance

  // Lazy getter — only accessed during actual sync, not at construction time.
  // This prevents Firebase-not-initialized crashes during unit tests.
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Collection references (helpers for building Firestore paths) ──────────
  CollectionReference get _users => _fs.collection('users');
  CollectionReference _products(String uid) =>
      _fs.collection('users').doc(uid).collection('products');
  CollectionReference _orders(String uid) =>
      _fs.collection('users').doc(uid).collection('orders');
  CollectionReference _debts(String uid) =>
      _fs.collection('users').doc(uid).collection('debts');
  CollectionReference _logs(String uid) =>
      _fs.collection('users').doc(uid).collection('activity_logs');

  // ── USER ──────────────────────────────────────────────────────────────────

  // Upserts a user document in Firestore (merge: true preserves existing fields)
  Future<void> saveUser(Map<String, dynamic> data) async {
    try {
      final username = data['username'] as String;
      await _users.doc(username).set(data, SetOptions(merge: true));
    } catch (_) {} // Silently fail — offline or permission error
  }

  // Fetches a user document by username; returns null if not found or offline
  Future<Map<String, dynamic>?> getUser(String username) async {
    try {
      final doc = await _users.doc(username.toLowerCase()).get();
      if (!doc.exists) return null;
      return doc.data() as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Checks if a username already exists in Firestore (duplicate check on register)
  Future<bool> usernameExistsCloud(String username) async {
    try {
      final doc = await _users.doc(username.toLowerCase()).get();
      return doc.exists;
    } catch (_) {
      return false; // Assume not exists on error to allow local registration
    }
  }

  // Updates only the password field for a user (used after password reset)
  Future<void> updateUserPassword(String username, String newPassword) async {
    try {
      await _users.doc(username.toLowerCase()).update({'password': newPassword});
    } catch (_) {}
  }

  // ── PRODUCTS ──────────────────────────────────────────────────────────────

  // Upserts a product document in the user's products subcollection
  Future<void> saveProduct(String userId, Map<String, dynamic> data) async {
    try {
      await _products(userId)
          .doc(data['id'] as String)
          .set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── NEW: Soft-delete product in Firestore ─────────────────────────────────
  // Sets is_deleted=1 and records deleted_at timestamp without removing the document
  Future<void> softDeleteProduct(String userId, String productId, String deletedAt) async {
    try {
      await _products(userId).doc(productId).update({
        'is_deleted': 1,
        'deleted_at': deletedAt,
      });
    } catch (_) {}
  }

  // Permanently removes a product document from Firestore (admin purge only)
  Future<void> deleteProduct(String userId, String productId) async {
    try {
      await _products(userId).doc(productId).delete();
    } catch (_) {}
  }

  // Fetches all active (non-deleted) products for a user, newest first
  Future<List<Map<String, dynamic>>> getProducts(String userId) async {
    try {
      // Preferred: use Firestore composite index for the filter
      final snap = await _products(userId)
          .where('is_deleted', isEqualTo: 0)
          .orderBy('created_at', descending: true)
          .get();
      return snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
    } catch (_) {
      // Fallback without filter if index not yet created
      try {
        final snap = await _products(userId)
            .orderBy('created_at', descending: true)
            .get();
        // Filter client-side when index is missing
        return snap.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .where((d) => (d['is_deleted'] as int? ?? 0) == 0)
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  // ── ORDERS ────────────────────────────────────────────────────────────────

  // Upserts an order document together with its line items in a single batch write
  Future<void> saveOrder(
    String userId,
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final id    = orderData['id'] as String;
      final batch = _fs.batch(); // Atomic write — items and order saved together
      batch.set(
        _orders(userId).doc(id),
        {...orderData, 'items': items}, // Embed items as a Firestore array field
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (_) {}
  }

  // Updates only the status field of an order document
  Future<void> updateOrderStatus(
      String userId, String orderId, String status) async {
    try {
      await _orders(userId).doc(orderId).update({'status': status});
    } catch (_) {}
  }

  // ── NEW: Soft-delete order in Firestore ───────────────────────────────────
  // Sets is_deleted=1 so the order is excluded from active queries
  Future<void> softDeleteOrder(String userId, String orderId, String deletedAt) async {
    try {
      await _orders(userId).doc(orderId).update({
        'is_deleted': 1,
        'deleted_at': deletedAt,
      });
    } catch (_) {}
  }

  // Permanently removes an order document from Firestore
  Future<void> deleteOrder(String userId, String orderId) async {
    try {
      await _orders(userId).doc(orderId).delete();
    } catch (_) {}
  }

  // Fetches all active orders; filters out soft-deleted records client-side
  Future<List<Map<String, dynamic>>> getOrders(String userId) async {
    try {
      final snap = await _orders(userId)
          .orderBy('order_date', descending: true)
          .get();
      return snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .where((d) => (d['is_deleted'] as int? ?? 0) == 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── DEBTS ─────────────────────────────────────────────────────────────────

  // Upserts a debt document with its embedded payments array
  Future<void> saveDebt(
    String userId,
    Map<String, dynamic> debtData,
    List<Map<String, dynamic>> payments,
  ) async {
    try {
      final id = debtData['id'] as String;
      await _debts(userId).doc(id).set(
            {...debtData, 'payments': payments},
            SetOptions(merge: true),
          );
    } catch (_) {}
  }

  // Updates amount_paid and the payments array after a new installment is recorded
  Future<void> updateDebtPayment(
    String userId,
    String debtId,
    double amountPaid,
    List<Map<String, dynamic>> payments,
  ) async {
    try {
      await _debts(userId).doc(debtId).update({
        'amount_paid': amountPaid,
        'payments':    payments,
      });
    } catch (_) {}
  }

  // ── NEW: Soft-delete debt in Firestore ────────────────────────────────────
  // Marks debt as deleted without removing its payment history
  Future<void> softDeleteDebt(String userId, String debtId, String deletedAt) async {
    try {
      await _debts(userId).doc(debtId).update({
        'is_deleted': 1,
        'deleted_at': deletedAt,
      });
    } catch (_) {}
  }

  // Permanently removes a debt document from Firestore
  Future<void> deleteDebt(String userId, String debtId) async {
    try {
      await _debts(userId).doc(debtId).delete();
    } catch (_) {}
  }

  // Fetches all active debts; filters out soft-deleted records client-side
  Future<List<Map<String, dynamic>>> getDebts(String userId) async {
    try {
      final snap = await _debts(userId)
          .orderBy('created_at', descending: true)
          .get();
      return snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .where((d) => (d['is_deleted'] as int? ?? 0) == 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── ACTIVITY LOGS ─────────────────────────────────────────────────────────

  // Saves a single activity log entry to Firestore using the log's UUID as document ID
  Future<void> saveLog(String userId, Map<String, dynamic> data) async {
    try {
      await _logs(userId).doc(data['id'] as String).set(data);
    } catch (_) {}
  }

  // Fetches the 500 most recent activity logs for a user
  Future<List<Map<String, dynamic>>> getLogs(String userId) async {
    try {
      final snap = await _logs(userId)
          .orderBy('timestamp', descending: true)
          .limit(500) // Cap at 500 to limit bandwidth
          .get();
      return snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Checks if a user document exists in Firestore (used to detect cloud data on login)
  Future<bool> hasCloudData(String username) async {
    try {
      final user = await getUser(username);
      return user != null;
    } catch (_) {
      return false;
    }
  }
}
