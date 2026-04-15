// ─────────────────────────────────────────────────────────────────────────────
// local_order_repository.dart — Soft-delete support
// Changes:
//   • getAll()     — filters WHERE is_deleted = 0
//   • delete()     — soft-delete only (is_deleted=1, deleted_at=now)
//   • getDeleted() — NEW: Recycle Bin for orders
//   • restore()    — NEW: un-delete an order
//   • hardDelete() — NEW: permanent purge
//   • getNextOrderNumber() — now queries ALL orders (including deleted)
//                            to prevent order ID reuse
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/order_model.dart';
import 'base_repository.dart';
import 'order_repository.dart';
import 'firestore_sync.dart';
import 'sync_queue.dart';

class LocalOrderRepository extends BaseRepository implements OrderRepository {
  final _uuid  = const Uuid();
  final _cloud = FirestoreSync.instance;
  final _queue = SyncQueue.instance;

  @override
  Future<List<Order>> getAll(String userId) => safeCall(() async {
    final database = await db.database;
    // Only return non-deleted orders
    final orderMaps = await database.query('orders',
        where: 'user_id = ? AND is_deleted = 0',
        whereArgs: [userId],
        orderBy: 'order_date DESC');

    if (orderMaps.isEmpty && _queue.isOnline) {
      final cloudOrders = await _cloud.getOrders(userId);
      for (final o in cloudOrders) {
        // Skip cloud orders that are soft-deleted
        if ((o['is_deleted'] as int? ?? 0) == 1) continue;
        try {
          final exists = await database.query('orders',
              where: 'id = ?', whereArgs: [o['id']]);
          if (exists.isNotEmpty) continue;
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

    final allOrders = await database.query('orders',
        where: 'user_id = ? AND is_deleted = 0',
        whereArgs: [userId],
        orderBy: 'order_date DESC');
    final orders = <Order>[];
    for (final orderMap in allOrders) {
      final itemMaps = await database.query('order_items',
          where: 'order_id = ?', whereArgs: [orderMap['id']]);
      orders.add(_orderFromMap(orderMap, itemMaps.map(_itemFromMap).toList()));
    }
    return orders;
  }, []);

  // ── NEW: Get soft-deleted orders (Recycle Bin) ────────────────────────────
  Future<List<Order>> getDeleted(String userId) => safeCall(() async {
    final database = await db.database;
    final orderMaps = await database.query('orders',
        where: 'user_id = ? AND is_deleted = 1',
        whereArgs: [userId],
        orderBy: 'deleted_at DESC');
    final orders = <Order>[];
    for (final orderMap in orderMaps) {
      final itemMaps = await database.query('order_items',
          where: 'order_id = ?', whereArgs: [orderMap['id']]);
      orders.add(_orderFromMap(orderMap, itemMaps.map(_itemFromMap).toList()));
    }
    return orders;
  }, []);

  // ── NEW: Restore a soft-deleted order ─────────────────────────────────────
  Future<void> restore(String orderId) => safeVoidCall(() async {
    final database = await db.database;
    await database.update(
      'orders',
      {'is_deleted': 0, 'deleted_at': null},
      where: 'id = ?',
      whereArgs: [orderId],
    );

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

  @override
  Future<void> add(Order order, String userId) => safeVoidCall(() async {
    final database = await db.database;
    await database.transaction((txn) async {
      await txn.insert('orders', _orderToMap(order, userId));
      for (final item in order.items) {
        await txn.insert('order_items', _itemToMap(item, order.id));
      }
    });

    final itemsData = order.items.map((i) => _itemToMap(i, order.id)).toList();
    final orderData = _orderToMap(order, userId);

    if (_queue.isOnline) {
      await _cloud.saveOrder(userId, orderData, itemsData);
    } else {
      await _queue.enqueue(
        operation:  'save_order',
        collection: 'orders',
        userId:     userId,
        docId:      order.id,
        data:       {...orderData, '_items': jsonEncode(itemsData)},
      );
    }
  });

  @override
  Future<void> updateStatus(String orderId, OrderStatus status) => safeVoidCall(() async {
    final database = await db.database;
    await database.update('orders', {'status': status.displayName},
        where: 'id = ?', whereArgs: [orderId]);

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

  // ── Soft-delete (replaces hard delete) ────────────────────────────────────
  @override
  Future<void> delete(String orderId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('orders',
        where: 'id = ?', whereArgs: [orderId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';
    final now = DateTime.now().toIso8601String();

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

  // ── Hard delete (permanent purge — admin only) ────────────────────────────
  Future<void> hardDelete(String orderId) => safeVoidCall(() async {
    final database = await db.database;
    final existing = await database.query('orders',
        where: 'id = ?', whereArgs: [orderId]);
    final userId = existing.isNotEmpty ? existing.first['user_id'] as String : '';

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

  // ── getNextOrderNumber queries ALL orders (inc. deleted) to prevent ID reuse
  @override
  Future<int> getNextOrderNumber(String userId) => safeCall(() async {
    final database = await db.database;
    final result = await database.rawQuery(
        'SELECT COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0) + 1 AS next_num '
        'FROM orders WHERE user_id = ?',
        [userId]);
    return (result.first['next_num'] as int? ?? 1);
  }, 1);

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

  Map<String, dynamic> _itemToMap(OrderItem item, String orderId) => {
    'id':           item.id.isEmpty ? _uuid.v4() : item.id,
    'order_id':     orderId,
    'product_id':   item.productId,
    'product_name': item.productName,
    'unit_price':   item.unitPrice,
    'quantity':     item.quantity,
  };

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

  OrderItem _itemFromMap(Map<String, dynamic> m) => OrderItem(
    id:          m['id']           as String? ?? _uuid.v4(),
    productId:   m['product_id']   as String,
    productName: m['product_name'] as String,
    unitPrice:   (m['unit_price']  as num).toDouble(),
    quantity:    m['quantity']     as int,
  );
}
