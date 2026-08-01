// ─────────────────────────────────────────────────────────────────────────────
// firestore_sync.dart — Firestore read/write adapter
// Purpose : Thin wrapper around FirebaseFirestore that maps local data models
//           to Firestore documents. Remote failures deliberately propagate to
//           SyncQueue, which keeps the durable outbox row for a later retry.
// Added soft-delete sync methods:
//   • softDeleteProduct() — marks is_deleted=1 in Firestore (no hard delete)
//   • softDeleteOrder()   — same for orders
//   • softDeleteDebt()    — same for debts
// Existing hard-delete methods kept for permanent purge use-case only.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../dto/activity_log_dto.dart';
import '../dto/custom_order_dto.dart';
import '../dto/debt_dto.dart';
import '../dto/order_dto.dart';
import '../dto/product_dto.dart';
import '../dto/reseller_dto.dart';

// Singleton — one Firestore adapter per app session
class FirestoreSync {
  FirestoreSync._(); // Private constructor prevents external instantiation
  static final FirestoreSync instance = FirestoreSync._(); // Shared instance

  // Lazy getter — only accessed during actual sync, not at construction time.
  // This prevents Firebase-not-initialized crashes during unit tests.
  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  // ── Collection references (helpers for building Firestore paths) ──────────
  CollectionReference get _users => _fs.collection('users');
  DocumentReference _tenant(String uid) {
    final principal = FirebaseAuth.instance.currentUser;
    if (principal == null || principal.isAnonymous || principal.uid != uid) {
      throw StateError('Cloud session is not authorized for local user $uid.');
    }
    return _users.doc(uid);
  }

  CollectionReference _products(String uid) =>
      _tenant(uid).collection('products');
  CollectionReference _orders(String uid) => _tenant(uid).collection('orders');
  CollectionReference _debts(String uid) => _tenant(uid).collection('debts');
  CollectionReference _logs(String uid) =>
      _tenant(uid).collection('activity_logs');
  CollectionReference _resellers(String uid) =>
      _tenant(uid).collection('resellers');
  CollectionReference _customOrders(String uid) =>
      _tenant(uid).collection('custom_orders');

  // ── USER ──────────────────────────────────────────────────────────────────

  // Upserts a user document in Firestore (merge: true preserves existing fields)
  Future<void> saveUser(Map<String, dynamic> data) async {
    throw UnsupportedError(
      'User profiles and access state are writable only by the trusted backend.',
    );
  }

  // Fetches a user document by Firebase UID; returns null only when absent.
  // Network and permission failures propagate to the caller.
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _tenant(uid).get();
    if (!doc.exists) return null;
    return doc.data() as Map<String, dynamic>;
  }

  // Checks if a username already exists in Firestore (duplicate check on register)
  Future<bool> usernameExistsCloud(String username) async {
    throw UnsupportedError('Username reservations are backend-only.');
  }

  // Updates only the password field for a user (used after password reset)
  Future<void> updateUserPassword(String username, String newPassword) async {
    throw UnsupportedError(
      'Credential verifiers are managed only by the authentication backend.',
    );
  }

  // ── PRODUCTS ──────────────────────────────────────────────────────────────

  // Upserts a product document in the user's products subcollection
  Future<void> saveProduct(String userId, Map<String, dynamic> data) async {
    final cloudData = ProductDto.fromCloud(data, userId: userId).toCloud();
    final imagePath = cloudData['image_path'] as String?;
    if (imagePath != null && !_isPortableImageReference(imagePath)) {
      cloudData['image_path'] = null;
    }
    await _products(
      userId,
    ).doc(cloudData['id'] as String).set(cloudData, SetOptions(merge: true));
  }

  // ── NEW: Soft-delete product in Firestore ─────────────────────────────────
  // Sets is_deleted=1 and records deleted_at timestamp without removing the document
  Future<void> softDeleteProduct(
    String userId,
    Map<String, dynamic> data,
  ) async {
    await saveProduct(userId, {...data, 'user_id': userId, 'is_deleted': 1});
  }

  // Permanently removes a product document from Firestore (admin purge only)
  Future<void> deleteProduct(String userId, String productId) async {
    await _products(userId).doc(productId).delete();
  }

  // Fetches all active (non-deleted) products for a user, newest first
  Future<List<Map<String, dynamic>>> getProducts(String userId) async {
    final snap = await _products(userId).get();
    return snap.docs
        .map(
          (doc) => ProductDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList();
  }

  // ── ORDERS ────────────────────────────────────────────────────────────────

  // Upserts an order document together with its line items in a single batch write
  Future<void> saveOrder(
    String userId,
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> items,
  ) async {
    final dto = OrderDto.fromCloud({
      ...orderData,
      'items': items,
    }, userId: userId);
    final cloudData = dto.toCloud();
    final id = dto.id;
    final batch = _fs.batch(); // Atomic write — items and order saved together
    batch.set(_orders(userId).doc(id), cloudData, SetOptions(merge: true));
    await batch.commit();
  }

  // ── NEW: Soft-delete order in Firestore ───────────────────────────────────
  // Sets is_deleted=1 so the order is excluded from active queries
  Future<void> softDeleteOrder(
    String userId,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> items,
  ) async {
    await saveOrder(userId, {
      ...data,
      'user_id': userId,
      'is_deleted': 1,
    }, items);
  }

  // Permanently removes an order document from Firestore
  Future<void> deleteOrder(String userId, String orderId) async {
    await _orders(userId).doc(orderId).delete();
  }

  // Fetches active records and tombstones for complete local restore.
  Future<List<Map<String, dynamic>>> getOrders(String userId) async {
    final snap = await _orders(userId).get();
    return snap.docs
        .map(
          (doc) => OrderDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList();
  }

  // ── DEBTS ─────────────────────────────────────────────────────────────────

  // Upserts a debt document with its embedded payments array
  Future<void> saveDebt(
    String userId,
    Map<String, dynamic> debtData,
    List<Map<String, dynamic>> payments,
  ) async {
    final dto = DebtDto.fromCloud({
      ...debtData,
      'payments': payments,
    }, userId: userId);
    final cloudData = dto.toCloud();
    final id = dto.id;
    await _debts(userId).doc(id).set(cloudData, SetOptions(merge: true));
  }

  // ── NEW: Soft-delete debt in Firestore ────────────────────────────────────
  // Marks debt as deleted without removing its payment history
  Future<void> softDeleteDebt(
    String userId,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> payments,
  ) async {
    await saveDebt(userId, {
      ...data,
      'user_id': userId,
      'is_deleted': 1,
    }, payments);
  }

  // Permanently removes a debt document from Firestore
  Future<void> deleteDebt(String userId, String debtId) async {
    await _debts(userId).doc(debtId).delete();
  }

  // Fetches active records and tombstones for complete local restore.
  Future<List<Map<String, dynamic>>> getDebts(String userId) async {
    final snap = await _debts(userId).get();
    return snap.docs
        .map(
          (doc) => DebtDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList();
  }

  Future<void> saveReseller(String userId, Map<String, dynamic> data) async {
    final dto = ResellerDto.fromCloud(data, userId: userId);
    await _resellers(
      userId,
    ).doc(dto.id).set(dto.toCloud(), SetOptions(merge: true));
  }

  Future<void> softDeleteReseller(
    String userId,
    Map<String, dynamic> data,
  ) async {
    await saveReseller(userId, {...data, 'user_id': userId, 'is_deleted': 1});
  }

  Future<void> deleteReseller(String userId, String resellerId) async {
    await _resellers(userId).doc(resellerId).delete();
  }

  Future<List<Map<String, dynamic>>> getResellers(String userId) async {
    final snap = await _resellers(userId).get();
    return snap.docs
        .map(
          (doc) => ResellerDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList();
  }

  Future<void> saveCustomOrder(
    String userId,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> payments,
  ) async {
    final dto = CustomOrderDto.fromCloud({
      ...data,
      'payments': payments,
    }, userId: userId);
    await _customOrders(
      userId,
    ).doc(dto.id).set(dto.toCloud(), SetOptions(merge: true));
  }

  Future<void> softDeleteCustomOrder(
    String userId,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> payments,
  ) async {
    await saveCustomOrder(userId, {
      ...data,
      'user_id': userId,
      'is_deleted': 1,
    }, payments);
  }

  Future<void> deleteCustomOrder(String userId, String customOrderId) async {
    await _customOrders(userId).doc(customOrderId).delete();
  }

  Future<List<Map<String, dynamic>>> getCustomOrders(String userId) async {
    final snap = await _customOrders(userId).get();
    return snap.docs
        .map(
          (doc) => CustomOrderDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList();
  }

  // ── ACTIVITY LOGS ─────────────────────────────────────────────────────────

  // Saves a single activity log entry to Firestore using the log's UUID as document ID
  Future<void> saveLog(String userId, Map<String, dynamic> data) async {
    final dto = ActivityLogDto.fromCloud(data, userId: userId);
    await _logs(userId).doc(dto.id).set(dto.toCloud());
  }

  // Fetches the 500 most recent activity logs for a user
  Future<List<Map<String, dynamic>>> getLogs(String userId) async {
    final snap = await _logs(userId)
        .orderBy('timestamp', descending: true)
        .limit(500) // Cap at 500 to limit bandwidth
        .get();
    return snap.docs
        .map(
          (doc) => ActivityLogDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList();
  }

  // Checks if a user document exists in Firestore (used to detect cloud data on login)
  Future<bool> hasCloudData(String uid) async {
    final user = await getUser(uid);
    return user != null;
  }

  bool _isPortableImageReference(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }
}
