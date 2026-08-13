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
import 'package:flutter/foundation.dart';

import '../core/domain_exceptions.dart';
import '../dto/activity_log_dto.dart';
import '../dto/business_event_dto.dart';
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
  CollectionReference _businessEvents(String uid) =>
      _tenant(uid).collection('business_events');
  CollectionReference _paymentCommands(String uid) =>
      _tenant(uid).collection('payment_commands');

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
    _copyRevisionMetadata(data, cloudData);
    await _revisionedWrite(
      _products(userId).doc(cloudData['id'] as String),
      cloudData,
    );
  }

  void _copyRevisionMetadata(
    Map<String, dynamic> source,
    Map<String, dynamic> target,
  ) {
    for (final key in const [
      'revision',
      'base_revision',
      'writer_device_id',
      'updated_at',
      'tombstone_revision',
      'purge_state',
    ]) {
      if (source.containsKey(key)) target[key] = source[key];
    }
  }

  Future<void> _revisionedWrite(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) async {
    final expected = data['base_revision'] as int? ?? 0;
    final resulting = data['revision'] as int? ?? expected + 1;
    if (resulting != expected + 1) {
      throw const FormatException('Revision must advance by exactly one.');
    }
    await _fs.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final remoteData = snapshot.data() as Map<String, dynamic>?;
      final remoteRevision = remoteData?['revision'] as int? ?? 0;
      if (remoteRevision != expected) {
        throw SyncConflictException(
          'Remote revision $remoteRevision does not match expected $expected.',
          remoteRevision: remoteRevision,
          remoteData: remoteData,
        );
      }
      transaction.set(reference, data, SetOptions(merge: true));
    });
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
    _copyRevisionMetadata(orderData, cloudData);
    final id = dto.id;
    await _revisionedWrite(_orders(userId).doc(id), cloudData);
  }

  Future<String> finalizeOrder(
    String userId,
    String commandId,
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> items,
    Map<String, int> quantities,
    Map<String, dynamic>? debtData,
  ) async {
    if (commandId.trim().isEmpty) {
      throw const FormatException('Order finalization command is required.');
    }
    final order = OrderDto.fromCloud({
      ...orderData,
      'items': items,
    }, userId: userId);
    final commandRef = _tenant(
      userId,
    ).collection('order_commands').doc(commandId);
    final counterRef = _tenant(userId).collection('counters').doc('orders');
    return _fs.runTransaction((transaction) async {
      final existingCommand = await transaction.get(commandRef);
      if (existingCommand.exists) {
        final data = existingCommand.data() as Map<String, dynamic>;
        if (data['order_doc_id'] != order.id) {
          throw StateError('Order command was reused for another order.');
        }
        return data['canonical_order_id'] as String;
      }

      final productSnapshots = <DocumentReference, DocumentSnapshot>{};
      for (final entry in quantities.entries) {
        if (entry.key.isEmpty || entry.value <= 0) {
          throw const FormatException(
            'Order contains an invalid stock quantity.',
          );
        }
        final reference = _products(userId).doc(entry.key);
        productSnapshots[reference] = await transaction.get(reference);
      }
      final counter = await transaction.get(counterRef);
      final lastValue = counter.exists
          ? ((counter.data() as Map<String, dynamic>)['last_value'] as int? ??
                0)
          : 0;
      final nextValue = lastValue + 1;
      final canonicalId = 'KNZ-${nextValue.toString().padLeft(6, '0')}';

      for (final entry in quantities.entries) {
        final reference = _products(userId).doc(entry.key);
        final snapshot = productSnapshots[reference]!;
        if (!snapshot.exists) {
          throw StateError('Cloud product ${entry.key} was not found.');
        }
        final data = snapshot.data() as Map<String, dynamic>;
        final stock = data['stock_qty'] as int? ?? 0;
        if (stock < entry.value) {
          throw StateError(
            'Cloud stock changed for ${data['name'] ?? entry.key}: '
            'need ${entry.value}, have $stock.',
          );
        }
        transaction.update(reference, {
          'stock_qty': stock - entry.value,
          'revision': (data['revision'] as int? ?? 0) + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      final cloudOrder = order.toCloud()
        ..['order_id'] = canonicalId
        ..['provisional_order_id'] = order.orderId
        ..['number_state'] = 'finalized'
        ..['revision'] = 1
        ..['base_revision'] = 0;
      transaction.set(_orders(userId).doc(order.id), cloudOrder);
      if (debtData != null) {
        final debt = Map<String, dynamic>.from(debtData)
          ..remove('_payments')
          ..['order_id'] = canonicalId
          ..['revision'] = 1
          ..['base_revision'] = 0;
        transaction.set(_debts(userId).doc(debt['id'] as String), debt);
      }
      transaction.set(counterRef, {
        'id': 'orders',
        'user_id': userId,
        'last_value': nextValue,
      });
      transaction.set(commandRef, {
        'id': commandId,
        'user_id': userId,
        'order_doc_id': order.id,
        'canonical_order_id': canonicalId,
        'sequence_value': nextValue,
      });
      return canonicalId;
    });
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
    _copyRevisionMetadata(debtData, cloudData);
    final id = dto.id;
    await _revisionedWrite(_debts(userId).doc(id), cloudData);
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
    final cloudData = dto.toCloud();
    _copyRevisionMetadata(data, cloudData);
    await _revisionedWrite(_resellers(userId).doc(dto.id), cloudData);
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
    final cloudData = dto.toCloud();
    _copyRevisionMetadata(data, cloudData);
    await _revisionedWrite(_customOrders(userId).doc(dto.id), cloudData);
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

  Future<void> saveBusinessEvent(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final dto = BusinessEventDto.fromCloud(data, userId: userId);
    final cloudData = dto.toCloud();
    final reference = _businessEvents(userId).doc(dto.id);
    await _fs.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      if (existing.exists) {
        final current = BusinessEventDto.fromCloud(
          existing.data()! as Map<String, dynamic>,
          userId: userId,
        ).toCloud();
        if (!mapEquals(current, cloudData)) {
          throw StateError('Cloud business event ${dto.id} is immutable.');
        }
        return;
      }
      transaction.set(reference, cloudData);
    });
  }

  Future<void> saveOrderWithEvent(
    String userId,
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> items,
    Map<String, dynamic> eventData,
  ) async {
    final order = OrderDto.fromCloud({
      ...orderData,
      'items': items,
    }, userId: userId);
    await _saveParentWithEvents(
      userId,
      _orders(userId).doc(order.id),
      order.toCloud(),
      [eventData],
    );
  }

  Future<void> saveDebtWithEvents(
    String userId,
    Map<String, dynamic> debtData,
    List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> events,
  ) async {
    final debt = DebtDto.fromCloud({
      ...debtData,
      'payments': payments,
    }, userId: userId);
    await _saveParentWithEvents(
      userId,
      _debts(userId).doc(debt.id),
      debt.toCloud(),
      events,
    );
  }

  Future<void> saveCustomOrderWithEvents(
    String userId,
    Map<String, dynamic> customOrderData,
    List<Map<String, dynamic>> payments,
    List<Map<String, dynamic>> events,
  ) async {
    final order = CustomOrderDto.fromCloud({
      ...customOrderData,
      'payments': payments,
    }, userId: userId);
    await _saveParentWithEvents(
      userId,
      _customOrders(userId).doc(order.id),
      order.toCloud(),
      events,
    );
  }

  Future<void> applyDebtPayment(
    String userId,
    Map<String, dynamic> debtData,
    Map<String, dynamic> paymentData,
    Map<String, dynamic> eventData,
  ) async {
    final debtId = debtData['id'] as String;
    final payment = PaymentDto.fromCloud(paymentData, debtId: debtId);
    final event = BusinessEventDto.fromCloud(eventData, userId: userId);
    final parent = DebtDto.fromCloud(debtData, userId: userId);
    await _applyPaymentCommand(
      userId: userId,
      commandId: event.commandId,
      parentReference: _debts(userId).doc(debtId),
      parentData: parent.toCloud(),
      paymentReference: _debts(
        userId,
      ).doc(debtId).collection('payments').doc(payment.id),
      paymentData: payment.toCloud(),
      event: event,
      expectedRevision: debtData['base_revision'] as int? ?? 0,
      resultingRevision: debtData['revision'] as int? ?? 1,
    );
  }

  Future<void> applyCustomOrderPayment(
    String userId,
    Map<String, dynamic> orderData,
    Map<String, dynamic> paymentData,
    Map<String, dynamic> eventData,
  ) async {
    final orderId = orderData['id'] as String;
    final payment = CustomOrderPaymentDto.fromCloud(
      paymentData,
      customOrderId: orderId,
    );
    final event = BusinessEventDto.fromCloud(eventData, userId: userId);
    final parent = CustomOrderDto.fromCloud(orderData, userId: userId);
    await _applyPaymentCommand(
      userId: userId,
      commandId: event.commandId,
      parentReference: _customOrders(userId).doc(orderId),
      parentData: parent.toCloud(),
      paymentReference: _customOrders(
        userId,
      ).doc(orderId).collection('payments').doc(payment.id),
      paymentData: payment.toCloud(),
      event: event,
      expectedRevision: orderData['base_revision'] as int? ?? 0,
      resultingRevision: orderData['revision'] as int? ?? 1,
    );
  }

  Future<void> _applyPaymentCommand({
    required String userId,
    required String commandId,
    required DocumentReference parentReference,
    required Map<String, dynamic> parentData,
    required DocumentReference paymentReference,
    required Map<String, dynamic> paymentData,
    required BusinessEventDto event,
    required int expectedRevision,
    required int resultingRevision,
  }) async {
    if (resultingRevision != expectedRevision + 1) {
      throw const FormatException('Payment revision must advance by one.');
    }
    final commandReference = _paymentCommands(userId).doc(commandId);
    final eventReference = _businessEvents(userId).doc(event.id);
    await _fs.runTransaction((transaction) async {
      final command = await transaction.get(commandReference);
      if (command.exists) {
        final existing = command.data() as Map<String, dynamic>;
        if (existing['payment_id'] != paymentData['id'] ||
            existing['parent_id'] != parentData['id']) {
          throw StateError('Payment command was reused with different data.');
        }
        return;
      }
      final parent = await transaction.get(parentReference);
      final remoteData = parent.data() as Map<String, dynamic>?;
      final remoteRevision = remoteData?['revision'] as int? ?? 0;
      if (!parent.exists || remoteRevision != expectedRevision) {
        throw SyncConflictException(
          'Payment parent revision changed remotely.',
          remoteRevision: remoteRevision,
          remoteData: remoteData,
        );
      }
      final payment = await transaction.get(paymentReference);
      final existingEvent = await transaction.get(eventReference);
      if (payment.exists || existingEvent.exists) {
        throw StateError('Payment or collection event already exists.');
      }
      final revisionedParent = <String, dynamic>{
        ...parentData,
        'base_revision': expectedRevision,
        'revision': resultingRevision,
      };
      transaction.set(
        parentReference,
        revisionedParent,
        SetOptions(merge: true),
      );
      transaction.set(paymentReference, paymentData);
      transaction.set(eventReference, event.toCloud());
      transaction.set(commandReference, {
        'id': commandId,
        'user_id': userId,
        'parent_id': parentData['id'],
        'payment_id': paymentData['id'],
        'event_id': event.id,
        'resulting_revision': resultingRevision,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getBusinessEvents(String userId) async {
    final snap = await _businessEvents(userId).get();
    return snap.docs
        .map(
          (doc) => BusinessEventDto.fromCloud(
            doc.data() as Map<String, dynamic>,
            userId: userId,
          ).toCloud(),
        )
        .toList(growable: false);
  }

  Future<void> _saveParentWithEvents(
    String userId,
    DocumentReference parent,
    Map<String, dynamic> parentData,
    List<Map<String, dynamic>> eventData,
  ) async {
    final events = eventData
        .map((data) => BusinessEventDto.fromCloud(data, userId: userId))
        .toList(growable: false);
    final references = [
      for (final event in events) _businessEvents(userId).doc(event.id),
    ];
    await _fs.runTransaction((transaction) async {
      final existing = <DocumentSnapshot>[];
      for (final reference in references) {
        existing.add(await transaction.get(reference));
      }
      transaction.set(parent, parentData, SetOptions(merge: true));
      for (var index = 0; index < events.length; index++) {
        final cloudData = events[index].toCloud();
        if (existing[index].exists) {
          final current = BusinessEventDto.fromCloud(
            existing[index].data()! as Map<String, dynamic>,
            userId: userId,
          ).toCloud();
          if (!mapEquals(current, cloudData)) {
            throw StateError(
              'Cloud business event ${events[index].id} is immutable.',
            );
          }
        } else {
          transaction.set(references[index], cloudData);
        }
      }
    });
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
}
