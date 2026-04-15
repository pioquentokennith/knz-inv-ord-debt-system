// ─────────────────────────────────────────────────────────────────────────────
// firestore_sync.dart — Added soft-delete sync methods
// New methods:
//   • softDeleteProduct() — marks is_deleted=1 in Firestore (no hard delete)
//   • softDeleteOrder()   — same for orders
//   • softDeleteDebt()    — same for debts
// Existing hard-delete methods kept for permanent purge use-case only.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreSync {
  FirestoreSync._();
  static final FirestoreSync instance = FirestoreSync._();

  final _fs = FirebaseFirestore.instance;

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

  Future<void> saveUser(Map<String, dynamic> data) async {
    try {
      final username = data['username'] as String;
      await _users.doc(username).set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUser(String username) async {
    try {
      final doc = await _users.doc(username.toLowerCase()).get();
      if (!doc.exists) return null;
      return doc.data() as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<bool> usernameExistsCloud(String username) async {
    try {
      final doc = await _users.doc(username.toLowerCase()).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateUserPassword(String username, String newPassword) async {
    try {
      await _users.doc(username.toLowerCase()).update({'password': newPassword});
    } catch (_) {}
  }

  // ── PRODUCTS ──────────────────────────────────────────────────────────────

  Future<void> saveProduct(String userId, Map<String, dynamic> data) async {
    try {
      await _products(userId)
          .doc(data['id'] as String)
          .set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── NEW: Soft-delete product in Firestore ─────────────────────────────────
  Future<void> softDeleteProduct(String userId, String productId, String deletedAt) async {
    try {
      await _products(userId).doc(productId).update({
        'is_deleted': 1,
        'deleted_at': deletedAt,
      });
    } catch (_) {}
  }

  Future<void> deleteProduct(String userId, String productId) async {
    try {
      await _products(userId).doc(productId).delete();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getProducts(String userId) async {
    try {
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

  Future<void> saveOrder(
    String userId,
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final id    = orderData['id'] as String;
      final batch = _fs.batch();
      batch.set(
        _orders(userId).doc(id),
        {...orderData, 'items': items},
        SetOptions(merge: true),
      );
      await batch.commit();
    } catch (_) {}
  }

  Future<void> updateOrderStatus(
      String userId, String orderId, String status) async {
    try {
      await _orders(userId).doc(orderId).update({'status': status});
    } catch (_) {}
  }

  // ── NEW: Soft-delete order in Firestore ───────────────────────────────────
  Future<void> softDeleteOrder(String userId, String orderId, String deletedAt) async {
    try {
      await _orders(userId).doc(orderId).update({
        'is_deleted': 1,
        'deleted_at': deletedAt,
      });
    } catch (_) {}
  }

  Future<void> deleteOrder(String userId, String orderId) async {
    try {
      await _orders(userId).doc(orderId).delete();
    } catch (_) {}
  }

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
  Future<void> softDeleteDebt(String userId, String debtId, String deletedAt) async {
    try {
      await _debts(userId).doc(debtId).update({
        'is_deleted': 1,
        'deleted_at': deletedAt,
      });
    } catch (_) {}
  }

  Future<void> deleteDebt(String userId, String debtId) async {
    try {
      await _debts(userId).doc(debtId).delete();
    } catch (_) {}
  }

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

  Future<void> saveLog(String userId, Map<String, dynamic> data) async {
    try {
      await _logs(userId).doc(data['id'] as String).set(data);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getLogs(String userId) async {
    try {
      final snap = await _logs(userId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .get();
      return snap.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> hasCloudData(String username) async {
    try {
      final user = await getUser(username);
      return user != null;
    } catch (_) {
      return false;
    }
  }
}
