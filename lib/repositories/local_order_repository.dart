// ─────────────────────────────────────────────────────────────────────────────
// local_order_repository.dart — SQLite-backed order repository
// Purpose : Manages order and order_items CRUD against local SQLite with
//           automatic Firestore sync via SyncQueue (offline-first).
// Changes:
//   • getAll()           — filters WHERE is_deleted = 0
//   • delete()           — soft-delete only (is_deleted=1, deleted_at=now)
//   • getDeleted()       — Recycle Bin for orders
//   • restore()          — un-delete an order
//   • hardDelete()       — permanent purge
//   • getNextOrderNumber — queries ALL orders (including deleted) to prevent ID reuse
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/order_model.dart';
import 'base_repository.dart';
import 'order_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

// Concrete SQLite + Firestore implementation of OrderRepository
class LocalOrderRepository extends BaseRepository implements OrderRepository {
  final _uuid  = const Uuid();           // UUID generator for item IDs without one
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  // Returns all active orders for a user using a JOIN query (N+1 fix)
  // PRIORITY 3: Optional fromDate/toDate adds a WHERE order_date BETWEEN clause.
  @override
  Future<List<Order>> getAll(String userId, {DateTime? fromDate, DateTime? toDate}) => safeCall(() async {
    final database = await db.database;

    // Build WHERE clause — always filter by user + not-deleted; optionally by date range
    String where = 'user_id = ? AND is_deleted = 0';
    final List<dynamic> whereArgs = [userId];
    if (fromDate != null) {
      where += ' AND order_date >= ?';
      whereArgs.add(fromDate.millisecondsSinceEpoch);
    }
    if (toDate != null) {
      where += ' AND order_date <= ?';
      whereArgs.add(toDate.millisecondsSinceEpoch);
    }

    // Fetch only non-deleted orders first (basic query for cloud fallback check)
    final orderMaps = await database.query('orders',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'order_date DESC');

    // Local is empty and online — restore orders from Firestore
    if (orderMaps.isEmpty && _queue.isOnline) {
      final cloudOrders = await _cloud.getOrders(userId);
      for (final o in cloudOrders) {
        // Skip cloud orders that are also soft-deleted in Firestore
        if ((o['is_deleted'] as int? ?? 0) == 1) continue;
        try {
          final exists = await database.query('orders',
              where: 'id = ?', whereArgs: [o['id']]);
          if (exists.isNotEmpty) continue; // Already cached locally
          await database.insert('orders', {
            'id':            o['id'],
            'order_id':      o['order_id'],
            'customer_name': o['customer_name'],
            'total_amount':  o['total_amount'],
            'status':        o['status'],
            'order_date':    o['order_date'],
            'notes':         o['notes'],
            'user_id':       userId,
            'is_deleted':    0,
            'deleted_at':    null,
          });
          // Insert each line item linked to this order
          final items = List<Map<String, dynamic>>.from(o['items'] ?? []);
          for (final item in items) {
            try {
              await database.insert('order_items', {
                'id':           item['id'] ?? _uuid.v4(),
                'order_id':     o['id'],
                'product_id':   item['product_id'],
                'product_name': item['product_name'],
                'unit_price':   item['unit_price'],
                'quantity':     item['quantity'],
              });
            } catch (_) {}
          }
        } catch (_) {}
      }
    }

    // FIX N+1: Single JOIN query instead of one query per order for items
    // PRIORITY 3: Build date-range clause for JOIN query if params provided
    String joinWhere = 'o.user_id = ? AND o.is_deleted = 0';
    final List<dynamic> joinArgs = [userId];
    if (fromDate != null) {
      joinWhere += ' AND o.order_date >= ?';
      joinArgs.add(fromDate.millisecondsSinceEpoch);
    }
    if (toDate != null) {
      joinWhere += ' AND o.order_date <= ?';
      joinArgs.add(toDate.millisecondsSinceEpoch);
    }

    // This replaces the old pattern of looping and querying order_items per order
    final joinRows = await database.rawQuery('''
      SELECT
        o.id          AS o_id,
        o.order_id    AS o_order_id,
        o.customer_name AS o_customer_name,
        o.total_amount  AS o_total_amount,
        o.status        AS o_status,
        o.order_date    AS o_order_date,
        o.notes         AS o_notes,
        oi.id           AS oi_id,
        oi.product_id   AS oi_product_id,
        oi.product_name AS oi_product_name,
        oi.unit_price   AS oi_unit_price,
        oi.quantity     AS oi_quantity
      FROM orders o
      LEFT JOIN order_items oi ON oi.order_id = o.id
      WHERE $joinWhere
      ORDER BY o.order_date DESC
    ''', joinArgs);

    // Group flat JOIN rows back into Order objects with their OrderItem lists
    final ordersMap = <String, Map<String, dynamic>>{};
    final itemsMap  = <String, List<OrderItem>>{};
    for (final row in joinRows) {
      final oid = row['o_id'] as String;
      // putIfAbsent ensures we only create the order entry once per unique order ID
      ordersMap.putIfAbsent(oid, () => {
        'id':            row['o_id'],
        'order_id':      row['o_order_id'],
        'customer_name': row['o_customer_name'],
        'total_amount':  row['o_total_amount'],
        'status':        row['o_status'],
        'order_date':    row['o_order_date'],
        'notes':         row['o_notes'],
      });
      // oi_id is null when the LEFT JOIN finds no matching order_items row
      if (row['oi_id'] != null) {
        itemsMap.putIfAbsent(oid, () => []).add(_itemFromMap({
          'id':           row['oi_id'],
          'product_id':   row['oi_product_id'],
          'product_name': row['oi_product_name'],
          'unit_price':   row['oi_unit_price'],
          'quantity':     row['oi_quantity'],
        }));
      }
    }
    // Assemble each order with its corresponding items list
    return ordersMap.entries
        .map((e) => _orderFromMap(e.value, itemsMap[e.key] ?? []))
        .toList();
  }, []);

  // Returns all soft-deleted orders for the Recycle Bin screen (JOIN query)
  @override
  Future<List<Order>> getDeleted(String userId) => safeCall(() async {
    final database = await db.database;
    // Same JOIN pattern as getAll() but filters is_deleted = 1
    final joinRows = await database.rawQuery('''
      SELECT
        o.id            AS o_id,
        o.order_id      AS o_order_id,
        o.customer_name AS o_customer_name,
        o.total_amount  AS o_total_amount,
        o.status        AS o_status,
        o.order_date    AS o_order_date,
        o.notes         AS o_notes,
        oi.id           AS oi_id,
        oi.product_id   AS oi_product_id,
        oi.product_name AS oi_product_name,
        oi.unit_price   AS oi_unit_price,
        oi.quantity     AS oi_quantity
      FROM orders o
      LEFT JOIN order_items oi ON oi.order_id = o.id
      WHERE o.user_id = ? AND o.is_deleted = 1
      ORDER BY o.order_date DESC
    ''', [userId]);

    final ordersMap = <String, Map<String, dynamic>>{};
    final itemsMap  = <String, List<OrderItem>>{};
    for (final row in joinRows) {
      final oid = row['o_id'] as String;
      ordersMap.putIfAbsent(oid, () => {
        'id':            row['o_id'],
        'order_id':      row['o_order_id'],
        'customer_name': row['o_customer_name'],
        'total_amount':  row['o_total_amount'],
        'status':        row['o_status'],
        'order_date':    row['o_order_date'],
        'notes':         row['o_notes'],
      });
      if (row['oi_id'] != null) {
        itemsMap.putIfAbsent(oid, () => []).add(_itemFromMap({
          'id':           row['oi_id'],
          'product_id':   row['oi_product_id'],
          'product_name': row['oi_product_name'],
          'unit_price':   row['oi_unit_price'],
          'quantity':     row['oi_quantity'],
        }));
      }
    }
    return ordersMap.entries
        .map((e) => _orderFromMap(e.value, itemsMap[e.key] ?? []))
        .toList();
  }, []);

  // Restores a soft-deleted order back to active and re-syncs it to Firestore
  @override
  Future<void> restore(String orderId) => safeVoidCall(() async {
    final database = await db.database;
    // Clear the soft-delete flags
    await database.update(
      'orders',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ?',
      whereArgs: [orderId],
    );

    // Re-sync the order and its items to Firestore
    final rows = await database.query('orders',
        where: 'id = ?', whereArgs: [orderId]);
    if (rows.isNotEmpty) {
      final userId = rows.first['user_id'] as String;
      final itemMaps = await database.query('order_items',
          where: 'order_id = ?', whereArgs: [orderId]);
      final itemsData = itemMaps.map((i) => _itemFromMap(i)).map((i) => _itemToMap(i, orderId)).toList();
      final orderData = Map<String, dynamic>.from(rows.first);
      if (_queue.isOnline) {
        await _cloud.saveOrder(userId, orderData, itemsData);
      } else {
        await _queue.enqueue(
          operation: 'save_order', collection: 'orders',
          userId: userId, docId: orderId,
          data: {...orderData, '_items': jsonEncode(itemsData)},
        );
      }
    }
  });

  // Inserts a new order and its line items in a single atomic SQLite transaction
  @override
  Future<void> add(Order order, String userId) => safeVoidCall(() async {
    final database = await db.database;
    // Transaction ensures both the order row and all item rows are saved atomically
    await database.transaction((txn) async {
      await txn.insert('orders', _orderToMap(order, userId));
      for (final item in order.items) {
        await txn.insert('order_items', _itemToMap(item, order.id));
      }
    });

    // Build Firestore payload with embedded items array
    final itemsData = order.items.map((i) => _itemToMap(i, order.id)).toList();
    final orderData = _orderToMap(order, userId);

    if (_queue.isOnline) {
      await _cloud.saveOrder(userId, orderData, itemsData);
    } else {
      // Embed items inside the queue data using a '_items' key (decoded on flush)
      await _queue.enqueue(
        operation:  'save_order',
        collection: 'orders',
        userId:     userId,
        docId:      order.id,
        data:       {...orderData, '_items': jsonEncode(itemsData)},
      );
    }
  });

  // Updates the status column of a single order and syncs the change to Firestore
  @override
  Future<void> updateStatus(String orderId, OrderStatus status) => safeVoidCall(() async {
    final database = await db.database;
    await database.update('orders', {'status': status.displayName},
        where: 'id = ?', whereArgs: [orderId]);

    // Retrieve userId from the row so we can address the correct Firestore document
    final existing = await database.query('orders',
        where: 'id = ?', whereArgs: [orderId]);
    if (existing.isNotEmpty) {
      final userId = existing.first['user_id'] as String;
      if (_queue.isOnline) {
        await _cloud.updateOrderStatus(userId, orderId, status.displayName);
      } else {
        await _queue.enqueue(
          operation:  'update_order_status',
          collection: 'orders',
          userId:     userId,
          docId:      orderId,
          data:       {'status': status.displayName},
        );
      }
    }
  });

  // Soft-deletes an order: sets is_deleted=1 and records deleted_at timestamp
  @override
  Future<void> delete(String orderId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('orders',
        where: 'id = ?', whereArgs: [orderId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';
    final now = DateTime.now().toIso8601String();

    // Mark as deleted — data and items are preserved for Recycle Bin recovery
    await database.update(
      'orders',
      {'is_deleted': 1, 'deleted_at': now},
      where: 'id = ?',
      whereArgs: [orderId],
    );

    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.softDeleteOrder(userId, orderId, now);
      } else {
        await _queue.enqueue(
          operation:  'soft_delete_order',
          collection: 'orders',
          userId:     userId,
          docId:      orderId,
          data:       {'id': orderId, 'is_deleted': 1, 'deleted_at': now},
        );
      }
    }
  });

  // Permanently removes an order and its items from SQLite and Firestore
  @override
  Future<void> hardDelete(String orderId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('orders',
        where: 'id = ?', whereArgs: [orderId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';

    // ON DELETE CASCADE on order_items ensures items are removed with the order
    await database.delete('orders', where: 'id = ?', whereArgs: [orderId]);

    if (userId.isNotEmpty) {
      if (_queue.isOnline) {
        await _cloud.deleteOrder(userId, orderId);
      } else {
        await _queue.enqueue(
          operation:  'delete_order',
          collection: 'orders',
          userId:     userId,
          docId:      orderId,
          data:       {'id': orderId},
        );
      }
    }
  });

  // Queries ALL orders (including soft-deleted) to compute the next order number
  // This prevents ID gaps or reuse if a deleted order had the highest number
  @override
  Future<int> getNextOrderNumber(String userId) => safeCall(() async {
    final database = await db.database;
    // Extract the numeric suffix from order_id (e.g. 'KNZ-042' → 42) and return max+1
    final result = await database.rawQuery(
        'SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 AS next_num '
        'FROM orders WHERE user_id = ?',
        [userId]);
    return (result.first['next_num'] as int? ?? 1);
  }, 1);

  // ── Private mapping helpers ───────────────────────────────────────────────

  // Converts an Order model to a SQLite column map (excludes items — stored separately)
  Map<String, dynamic> _orderToMap(Order o, String userId) => {
    'id':            o.id,
    'order_id':      o.orderId,
    'customer_name': o.customerName,
    'total_amount':  o.totalAmount,
    'status':        o.status.displayName,
    'order_date':    o.orderDate.toIso8601String(),
    'notes':         o.notes,
    'user_id':       userId,
    'is_deleted':    0,
    'deleted_at':    null,
  };

  // Converts an OrderItem model to a SQLite column map for the order_items table
  Map<String, dynamic> _itemToMap(OrderItem item, String orderId) => {
    'id':           item.id.isEmpty ? _uuid.v4() : item.id, // Generate ID if missing
    'order_id':     orderId,
    'product_id':   item.productId,
    'product_name': item.productName,
    'unit_price':   item.unitPrice,
    'quantity':     item.quantity,
  };

  // Assembles an Order model from a flat column map and its pre-fetched items list
  Order _orderFromMap(Map<String, dynamic> m, List<OrderItem> items) => Order(
    id:           m['id']            as String,
    orderId:      m['order_id']      as String,
    customerName: m['customer_name'] as String,
    items:        items,
    totalAmount:  (m['total_amount'] as num).toDouble(),
    status:       OrderStatusExtension.fromString(m['status'] as String),
    orderDate:    DateTime.parse(m['order_date'] as String),
    notes:        m['notes']         as String?,
  );

  // Converts a raw SQLite row map into an OrderItem model instance
  OrderItem _itemFromMap(Map<String, dynamic> m) => OrderItem(
    id:          m['id']           as String? ?? _uuid.v4(),
    productId:   m['product_id']   as String,
    productName: m['product_name'] as String,
    unitPrice:   (m['unit_price']  as num).toDouble(),
    quantity:    m['quantity']     as int,
  );
}
