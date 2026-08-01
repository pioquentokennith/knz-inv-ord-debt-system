import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/domain_exceptions.dart';
import '../database/database_helper.dart';
import '../dto/debt_dto.dart';
import '../dto/order_dto.dart';
import '../dto/product_dto.dart';
import '../models/debt_model.dart';
import '../models/order_model.dart';
import '../models/order_state_machine.dart';
import 'base_repository.dart';
import 'firestore_sync.dart';
import 'order_repository.dart';
import 'sync_queue.dart';

/// SQLite-backed order repository with a durable Firestore outbox.
class LocalOrderRepository extends BaseRepository implements OrderRepository {
  LocalOrderRepository({
    Future<Database> Function()? databaseProvider,
    SyncOutbox? queue,
    Uuid? uuid,
    this.commitHook,
  }) : _databaseProvider =
           databaseProvider ?? (() => DatabaseHelper.instance.database),
       _queue = queue ?? SyncQueue.instance,
       _uuid = uuid ?? const Uuid();

  final Future<Database> Function() _databaseProvider;
  final SyncOutbox _queue;
  final Uuid _uuid;
  final Future<void> Function(OrderCommitStage stage)? commitHook;
  final _cloud = FirestoreSync.instance;

  @override
  Future<List<Order>> getAll(
    String userId, {
    DateTime? fromDate,
    DateTime? toDate,
  }) => safeCall(() async {
    final database = await _databaseProvider();
    final where = <String>['user_id = ?', 'is_deleted = 0'];
    final args = <Object?>[userId];
    if (fromDate != null) {
      where.add('order_date >= ?');
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      where.add('order_date <= ?');
      args.add(toDate.toIso8601String());
    }
    final localRows = await database.query(
      'orders',
      columns: const ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (localRows.isEmpty && _queue.isOnline) {
      final cloudOrders = await _cloud.getOrders(userId);
      await database.transaction((txn) async {
        for (final cloudOrder in cloudOrders) {
          final dto = OrderDto.fromCloud(cloudOrder, userId: userId);
          final orderId = dto.id;
          final existing = await txn.query(
            'orders',
            columns: const ['id'],
            where: 'id = ?',
            whereArgs: [orderId],
            limit: 1,
          );
          if (existing.isNotEmpty) continue;

          await txn.insert('orders', dto.toLocal());
          await _ensureSequenceAtLeast(txn, userId, dto.orderId);

          for (final item in dto.items) {
            await txn.insert('order_items', item.toLocal());
          }
        }
      });
    }

    return _loadOrders(
      userId,
      isDeleted: false,
      fromDate: fromDate,
      toDate: toDate,
    );
  });

  @override
  Future<List<Order>> getDeleted(String userId) =>
      safeCall(() => _loadOrders(userId, isDeleted: true));

  @override
  Future<void> add(Order order, String userId) async {
    await addWithInventory(order, userId);
  }

  @override
  Future<OrderCreationResult> addWithInventory(
    Order order,
    String userId, {
    CustomerDebt? debt,
  }) => safeWriteCall(() async {
    _validateOrder(order, userId);
    if (debt != null) _validateDebt(debt);
    OrderStateMachine.validateInitial(order.status, hasDebt: debt != null);
    final database = await _databaseProvider();
    late Order savedOrder;
    var created = false;
    await database.transaction((txn) async {
      final replay = await _findByCommand(txn, userId, order.commandId!);
      if (replay != null) {
        savedOrder = replay;
        return;
      }
      final normalized = _normalizeItems(order);
      savedOrder = await _insertOrder(txn, normalized, userId);
      created = true;
      await _checkpoint(OrderCommitStage.orderAndItemsInserted);
      final productSnapshots = normalized.status == OrderStatus.cancelled
          ? <Map<String, dynamic>>[]
          : await _adjustInventory(
              txn,
              userId,
              _aggregateQuantities(normalized.items),
              deduct: true,
              enqueueSnapshots: false,
            );
      await _checkpoint(OrderCommitStage.inventoryAdjusted);
      DebtDto? debtDto;
      if (debt != null) {
        debtDto = await _insertDebt(
          txn,
          debt,
          savedOrder.orderId,
          userId,
          enqueueSnapshot: false,
        );
      }
      await _queueOrderCreation(
        txn,
        savedOrder,
        productSnapshots,
        debtDto,
        userId,
      );
      await _checkpoint(OrderCommitStage.outboxCreated);
    });
    _queue.requestSync();
    return OrderCreationResult(order: savedOrder, created: created);
  });

  @override
  Future<void> updateStatus(
    String orderId,
    OrderStatus status,
  ) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'orders',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [orderId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Active order not found: $orderId');
      }
      final row = rows.single;
      final current = OrderStatusExtension.fromString(row['status'] as String);
      if (status == OrderStatus.utang) {
        throw const InvalidOrderTransitionException(
          'Use the Utang workflow so the debt ledger is created atomically.',
        );
      }
      final hasOpenDebt = await _hasOpenDebt(txn, row);
      OrderStateMachine.validate(current, status, hasOpenDebt: hasOpenDebt);

      var stockDeducted = (row['stock_deducted'] as num?)?.toInt() != 0;
      if (status == OrderStatus.cancelled && stockDeducted) {
        final itemRows = await txn.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        await _adjustInventory(
          txn,
          row['user_id'] as String,
          _aggregateMapQuantities(itemRows),
          deduct: false,
        );
        stockDeducted = false;
      } else if (current == OrderStatus.cancelled &&
          status == OrderStatus.pending &&
          !stockDeducted) {
        final itemRows = await txn.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        await _adjustInventory(
          txn,
          row['user_id'] as String,
          _aggregateMapQuantities(itemRows),
          deduct: true,
        );
        stockDeducted = true;
      }

      final changed = await txn.update(
        'orders',
        {'status': status.displayName, 'stock_deducted': stockDeducted ? 1 : 0},
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [orderId],
      );
      if (changed != 1) {
        throw StateError('Failed to update order status: $orderId');
      }
      final itemRows = await txn.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'id ASC',
      );
      final updatedOrder = Map<String, dynamic>.from(row)
        ..['status'] = status.displayName
        ..['stock_deducted'] = stockDeducted ? 1 : 0;
      final dto = OrderDto.fromLocal(
        updatedOrder,
        itemRows.map(Map<String, dynamic>.from).toList(),
      );
      await _queue.enqueue(
        // Queue a complete upsert so a missing remote document heals
        // instead of retrying a partial Firestore update forever.
        operation: 'save_order',
        collection: 'orders',
        userId: row['user_id'] as String,
        docId: orderId,
        data: _orderOutboxPayload(dto),
        executor: txn,
      );
    });
    _queue.requestSync();
  });

  @override
  Future<void> markAsUtang(String orderId, CustomerDebt debt) =>
      safeVoidCall(() async {
        _validateDebt(debt);
        final database = await _databaseProvider();
        await database.transaction((txn) async {
          final orderRows = await txn.query(
            'orders',
            where: 'id = ? AND is_deleted = 0',
            whereArgs: [orderId],
            limit: 1,
          );
          if (orderRows.isEmpty) {
            throw StateError('Active order not found: $orderId');
          }

          final orderRow = Map<String, dynamic>.from(orderRows.single);
          final userId = orderRow['user_id'] as String?;
          if (userId == null || userId.isEmpty) {
            throw StateError('Order $orderId has no owning user.');
          }
          final humanOrderId = orderRow['order_id'] as String;
          if (debt.orderId != humanOrderId) {
            throw ArgumentError.value(
              debt.orderId,
              'debt.orderId',
              'Debt must reference order $humanOrderId.',
            );
          }

          final existingDebts = await txn.query(
            'debts',
            columns: const ['id'],
            where: 'user_id = ? AND order_id = ? AND is_deleted = 0',
            whereArgs: [userId, humanOrderId],
            limit: 1,
          );
          if (existingDebts.isNotEmpty) {
            throw StateError(
              'Order $humanOrderId already has an active debt ledger.',
            );
          }
          final reusedDebtId = await txn.query(
            'debts',
            columns: const ['id'],
            where: 'id = ?',
            whereArgs: [debt.id],
            limit: 1,
          );
          if (reusedDebtId.isNotEmpty) {
            throw StateError('Debt id already exists: ${debt.id}');
          }
          OrderStateMachine.validate(
            OrderStatusExtension.fromString(orderRow['status'] as String),
            OrderStatus.utang,
            hasOpenDebt: false,
          );

          final changed = await txn.update(
            'orders',
            {'status': OrderStatus.utang.displayName},
            where: 'id = ? AND user_id = ? AND is_deleted = 0',
            whereArgs: [orderId, userId],
          );
          if (changed != 1) {
            throw StateError('Failed to mark order $orderId as utang.');
          }

          final itemRows = await txn.query(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [orderId],
            orderBy: 'id ASC',
          );
          final updatedOrder = Map<String, dynamic>.from(orderRow)
            ..['status'] = OrderStatus.utang.displayName;
          final dto = OrderDto.fromLocal(
            updatedOrder,
            itemRows.map(Map<String, dynamic>.from).toList(),
          );
          await _queue.enqueue(
            operation: 'save_order',
            collection: 'orders',
            userId: userId,
            docId: orderId,
            data: _orderOutboxPayload(dto),
            executor: txn,
          );
          await _insertDebt(txn, debt, humanOrderId, userId);
        });
        _queue.requestSync();
      });

  @override
  Future<void> delete(String orderId) =>
      _setDeleted(orderId, deleted: true, adjustInventory: false);

  @override
  Future<void> deleteWithInventory(String orderId) =>
      _setDeleted(orderId, deleted: true, adjustInventory: true);

  @override
  Future<void> restore(String orderId) =>
      _setDeleted(orderId, deleted: false, adjustInventory: false);

  @override
  Future<void> restoreWithInventory(String orderId) =>
      _setDeleted(orderId, deleted: false, adjustInventory: true);

  @override
  Future<void> hardDelete(String orderId) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final rows = await txn.query(
        'orders',
        columns: const ['user_id', 'order_id'],
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [orderId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Deleted order not found: $orderId');
      }
      if (await _hasOpenDebt(txn, rows.single)) {
        throw const OpenDebtException(
          'Settle the linked debt before permanently deleting this order.',
        );
      }
      await _queue.enqueue(
        operation: 'delete_order',
        collection: 'orders',
        userId: rows.single['user_id'] as String,
        docId: orderId,
        data: {'id': orderId},
        executor: txn,
      );
      final deleted = await txn.delete(
        'orders',
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [orderId],
      );
      if (deleted != 1) {
        throw StateError('Failed to permanently delete order: $orderId');
      }
    });
    _queue.requestSync();
  });

  Future<void> _setDeleted(
    String orderId, {
    required bool deleted,
    required bool adjustInventory,
  }) => safeVoidCall(() async {
    final database = await _databaseProvider();
    await database.transaction((txn) async {
      final snapshot = await _requireOrder(txn, orderId, isDeleted: !deleted);
      final userId = snapshot.order['user_id'] as String;
      if (deleted && await _hasOpenDebt(txn, snapshot.order)) {
        throw const OpenDebtException(
          'Settle the linked debt before deleting this order.',
        );
      }

      final wasStockDeducted =
          (snapshot.order['stock_deducted'] as num?)?.toInt() != 0;
      final releasedOnDelete =
          (snapshot.order['stock_released_on_delete'] as num?)?.toInt() != 0;
      var stockDeducted = wasStockDeducted;
      var releaseMarker = releasedOnDelete;
      if (adjustInventory && deleted && wasStockDeducted) {
        await _adjustInventory(
          txn,
          userId,
          _aggregateMapQuantities(snapshot.items),
          deduct: false,
        );
        stockDeducted = false;
        releaseMarker = true;
      } else if (adjustInventory && !deleted && releasedOnDelete) {
        await _adjustInventory(
          txn,
          userId,
          _aggregateMapQuantities(snapshot.items),
          deduct: true,
        );
        stockDeducted = true;
        releaseMarker = false;
      }

      final deletedAt = deleted
          ? DateTime.now().toUtc().toIso8601String()
          : null;
      final changed = await txn.update(
        'orders',
        {
          'is_deleted': deleted ? 1 : 0,
          'deleted_at': deletedAt,
          'stock_deducted': stockDeducted ? 1 : 0,
          'stock_released_on_delete': releaseMarker ? 1 : 0,
        },
        where: 'id = ? AND is_deleted = ?',
        whereArgs: [orderId, deleted ? 0 : 1],
      );
      if (changed != 1) {
        throw StateError(
          'Order state changed while ${deleted ? 'deleting' : 'restoring'} '
          '$orderId.',
        );
      }

      if (deleted) {
        final deletedData = Map<String, dynamic>.from(snapshot.order)
          ..['is_deleted'] = 1
          ..['deleted_at'] = deletedAt
          ..['stock_deducted'] = stockDeducted ? 1 : 0
          ..['stock_released_on_delete'] = releaseMarker ? 1 : 0;
        await _queue.enqueue(
          operation: 'soft_delete_order',
          collection: 'orders',
          userId: userId,
          docId: orderId,
          data: _orderOutboxPayload(
            OrderDto.fromLocal(deletedData, snapshot.items),
          ),
          executor: txn,
        );
      } else {
        final restoredData = Map<String, dynamic>.from(snapshot.order)
          ..['is_deleted'] = 0
          ..['deleted_at'] = null
          ..['stock_deducted'] = stockDeducted ? 1 : 0
          ..['stock_released_on_delete'] = releaseMarker ? 1 : 0;
        await _queue.enqueue(
          operation: 'save_order',
          collection: 'orders',
          userId: userId,
          docId: orderId,
          data: _orderOutboxPayload(
            OrderDto.fromLocal(restoredData, snapshot.items),
          ),
          executor: txn,
        );
      }
    });
    _queue.requestSync();
  });

  Future<Order> _insertOrder(
    DatabaseExecutor txn,
    Order order,
    String userId,
  ) async {
    final normalized = _normalizeItems(order);
    final nextNumber = await _allocateOrderNumber(txn, userId);
    final saved = normalized.copyWith(
      orderId: 'KNZ-${nextNumber.toString().padLeft(3, '0')}',
    );
    final dto = OrderDto.fromDomain(
      saved,
      userId: userId,
      stockDeducted: saved.status != OrderStatus.cancelled,
    );
    final orderData = dto.toLocal();
    final itemData = dto.items.map((item) => item.toLocal()).toList();

    final orderRow = await txn.insert('orders', orderData);
    if (orderRow <= 0) throw StateError('Order row was not inserted.');
    for (final item in itemData) {
      final itemRow = await txn.insert('order_items', item);
      if (itemRow <= 0) {
        throw StateError('An order line item was not inserted.');
      }
    }
    return saved;
  }

  Future<Order?> _findByCommand(
    DatabaseExecutor txn,
    String userId,
    String commandId,
  ) async {
    final rows = await txn.query(
      'orders',
      where: 'user_id = ? AND command_id = ?',
      whereArgs: [userId, commandId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final itemRows = await txn.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [rows.single['id']],
      orderBy: 'id ASC',
    );
    return OrderDto.fromLocal(
      Map<String, dynamic>.from(rows.single),
      itemRows.map(Map<String, dynamic>.from).toList(),
    ).toDomain();
  }

  Future<void> _queueOrderCreation(
    DatabaseExecutor txn,
    Order order,
    List<Map<String, dynamic>> productSnapshots,
    DebtDto? debt,
    String userId,
  ) async {
    final orderPayload = _orderOutboxPayload(
      OrderDto.fromDomain(
        order,
        userId: userId,
        stockDeducted: order.status != OrderStatus.cancelled,
      ),
    );
    await _queue.enqueue(
      operation: 'create_order',
      collection: 'orders',
      userId: userId,
      docId: order.id,
      data: {
        'command_id': order.commandId,
        '_order': orderPayload,
        '_products': productSnapshots,
        if (debt != null) '_debt': _debtOutboxPayload(debt),
      },
      executor: txn,
    );
  }

  Future<DebtDto> _insertDebt(
    DatabaseExecutor txn,
    CustomerDebt debt,
    String finalOrderId,
    String userId, {
    bool enqueueSnapshot = true,
  }) async {
    final normalizedDebt = CustomerDebt(
      id: debt.id,
      customerName: debt.customerName,
      orderId: finalOrderId,
      principalOriginal: debt.principalOriginal,
      principalOutstanding: debt.principalOutstanding,
      interestOutstanding: debt.interestOutstanding,
      createdAt: debt.createdAt,
      payments: debt.payments,
      interestRateBasisPoints: debt.interestRateBasisPoints,
      interestType: debt.interestType,
      interestStartTimestamp: debt.interestStartTimestamp,
      lastAccrualTimestamp: debt.lastAccrualTimestamp,
      dueDate: debt.dueDate,
      status: debt.status,
    );
    final dto = DebtDto.fromDomain(normalizedDebt, userId: userId);
    final debtData = dto.toLocal();
    final payments = dto.payments.map((payment) => payment.toLocal()).toList();

    final debtRow = await txn.insert('debts', debtData);
    if (debtRow <= 0) throw StateError('Debt row was not inserted.');
    for (final payment in payments) {
      final paymentRow = await txn.insert('payments', payment);
      if (paymentRow <= 0) throw StateError('Debt payment was not inserted.');
    }
    if (enqueueSnapshot) {
      await _queue.enqueue(
        operation: 'save_debt',
        collection: 'debts',
        userId: userId,
        docId: debt.id,
        data: _debtOutboxPayload(dto),
        executor: txn,
      );
    }
    return dto;
  }

  Future<List<Map<String, dynamic>>> _adjustInventory(
    DatabaseExecutor txn,
    String userId,
    Map<String, int> quantities, {
    required bool deduct,
    bool enqueueSnapshots = true,
  }) async {
    final snapshots = <Map<String, dynamic>>[];
    for (final entry in quantities.entries) {
      if (entry.key.isEmpty || entry.value <= 0) {
        throw StateError('Order contains an invalid product quantity.');
      }
      final rows = await txn.query(
        'products',
        where: deduct
            ? 'id = ? AND user_id = ? AND is_deleted = 0'
            : 'id = ? AND user_id = ?',
        whereArgs: [entry.key, userId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError(
          'Product ${entry.key} is missing or unavailable for this user.',
        );
      }
      final row = Map<String, dynamic>.from(rows.single);
      final currentStock = (row['stock_qty'] as num).toInt();
      final nextStock = deduct
          ? currentStock - entry.value
          : currentStock + entry.value;
      if (deduct && nextStock < 0) {
        throw StockShortageException(
          productId: entry.key,
          productName: row['name'] as String,
          requiredQuantity: entry.value,
          availableQuantity: currentStock,
        );
      }

      final changed = deduct
          ? await txn.rawUpdate(
              'UPDATE products SET stock_qty = stock_qty - ? '
              'WHERE id = ? AND user_id = ? AND is_deleted = 0 '
              'AND stock_qty >= ?',
              [entry.value, entry.key, userId, entry.value],
            )
          : await txn.rawUpdate(
              'UPDATE products SET stock_qty = stock_qty + ? '
              'WHERE id = ? AND user_id = ?',
              [entry.value, entry.key, userId],
            );
      if (changed != 1) {
        final latest = await txn.query(
          'products',
          columns: const ['name', 'stock_qty'],
          where: 'id = ? AND user_id = ?',
          whereArgs: [entry.key, userId],
          limit: 1,
        );
        if (deduct && latest.isNotEmpty) {
          throw StockShortageException(
            productId: entry.key,
            productName: latest.single['name'] as String,
            requiredQuantity: entry.value,
            availableQuantity: (latest.single['stock_qty'] as num).toInt(),
          );
        }
        throw StateError(
          'Inventory changed while updating product ${entry.key}.',
        );
      }

      row['stock_qty'] = nextStock;
      final snapshot = ProductDto.fromLocal(row).toCloud();
      snapshots.add(snapshot);
      if (enqueueSnapshots) {
        await _queue.enqueue(
          operation: 'save_product',
          collection: 'products',
          userId: userId,
          docId: entry.key,
          data: snapshot,
          executor: txn,
        );
      }
    }
    return snapshots;
  }

  Future<_OrderSnapshot> _requireOrder(
    DatabaseExecutor txn,
    String orderId, {
    required bool isDeleted,
  }) async {
    final rows = await txn.query(
      'orders',
      where: 'id = ? AND is_deleted = ?',
      whereArgs: [orderId, isDeleted ? 1 : 0],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        '${isDeleted ? 'Deleted' : 'Active'} order not found: $orderId',
      );
    }
    final itemRows = await txn.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    return _OrderSnapshot(
      Map<String, dynamic>.from(rows.single),
      itemRows.map((row) => Map<String, dynamic>.from(row)).toList(),
    );
  }

  Future<int> _allocateOrderNumber(
    DatabaseExecutor database,
    String userId,
  ) async {
    await database.rawInsert(
      '''
      INSERT OR IGNORE INTO order_sequences(user_id, last_value)
      SELECT ?, COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0)
      FROM orders WHERE user_id = ?
    ''',
      [userId, userId],
    );
    final changed = await database.rawUpdate(
      'UPDATE order_sequences SET last_value = last_value + 1 '
      'WHERE user_id = ?',
      [userId],
    );
    if (changed != 1) {
      throw StateError('Failed to allocate the next order number.');
    }
    final result = await database.query(
      'order_sequences',
      columns: const ['last_value'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return (result.single['last_value'] as num).toInt();
  }

  Future<void> _ensureSequenceAtLeast(
    DatabaseExecutor database,
    String userId,
    String readableId,
  ) async {
    final parsed = int.tryParse(readableId.replaceFirst('KNZ-', ''));
    if (parsed == null || parsed < 0) return;
    await database.rawInsert(
      'INSERT OR IGNORE INTO order_sequences(user_id, last_value) VALUES(?, ?)',
      [userId, parsed],
    );
    await database.rawUpdate(
      'UPDATE order_sequences SET last_value = MAX(last_value, ?) '
      'WHERE user_id = ?',
      [parsed, userId],
    );
  }

  Future<List<Order>> _loadOrders(
    String userId, {
    required bool isDeleted,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final database = await _databaseProvider();
    final where = <String>['o.user_id = ?', 'o.is_deleted = ?'];
    final args = <Object?>[userId, isDeleted ? 1 : 0];
    if (fromDate != null) {
      where.add('o.order_date >= ?');
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      where.add('o.order_date <= ?');
      args.add(toDate.toIso8601String());
    }

    final rows = await database.query(
      'orders',
      where: where
          .map((condition) => condition.replaceFirst('o.', ''))
          .join(' AND '),
      whereArgs: args,
      orderBy: 'order_date DESC',
    );
    final result = <Order>[];
    for (final row in rows) {
      final itemRows = await database.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      result.add(
        OrderDto.fromLocal(
          Map<String, dynamic>.from(row),
          itemRows.map(Map<String, dynamic>.from).toList(),
        ).toDomain(),
      );
    }
    return result;
  }

  Future<void> _checkpoint(OrderCommitStage stage) async {
    final hook = commitHook;
    if (hook != null) await hook(stage);
  }

  Future<bool> _hasOpenDebt(
    DatabaseExecutor txn,
    Map<String, Object?> orderRow,
  ) async {
    final humanOrderId = orderRow['order_id'] as String?;
    final userId = orderRow['user_id'] as String?;
    if (humanOrderId == null || userId == null) {
      throw StateError('Order debt ownership metadata is incomplete.');
    }
    final debts = await txn.query(
      'debts',
      columns: const [
        'principal_outstanding_centavos',
        'interest_outstanding_centavos',
      ],
      where: 'user_id = ? AND order_id = ?',
      whereArgs: [userId, humanOrderId],
    );
    for (final row in debts) {
      final principal = row['principal_outstanding_centavos'] as int;
      final interest = row['interest_outstanding_centavos'] as int;
      if (principal != 0 || interest != 0) return true;
    }
    return false;
  }

  Order _normalizeItems(Order order) => order.copyWith(
    items: order.items
        .map(
          (item) => OrderItem(
            id: item.id.isEmpty ? _uuid.v4() : item.id,
            productId: item.productId,
            productName: item.productName,
            unitPrice: item.unitPrice,
            srpPrice: item.srpPrice,
            quantity: item.quantity,
          ),
        )
        .toList(),
  );

  Map<String, int> _aggregateQuantities(List<OrderItem> items) {
    final quantities = <String, int>{};
    for (final item in items) {
      quantities.update(
        item.productId,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    return quantities;
  }

  Map<String, int> _aggregateMapQuantities(List<Map<String, dynamic>> items) {
    final quantities = <String, int>{};
    for (final item in items) {
      final productId = item['product_id'] as String;
      final quantity = (item['quantity'] as num).toInt();
      quantities.update(
        productId,
        (value) => value + quantity,
        ifAbsent: () => quantity,
      );
    }
    return quantities;
  }

  void _validateOrder(Order order, String userId) {
    if (order.id.isEmpty) throw ArgumentError('Order id is required.');
    if (userId.isEmpty) throw ArgumentError('User id is required.');
    if (order.commandId?.trim().isEmpty ?? true) {
      throw ArgumentError('Order command id is required.');
    }
    if (order.items.isEmpty) {
      throw ArgumentError('Order needs at least one item.');
    }
    if (order.totalAmount.isNegative) {
      throw ArgumentError.value(order.totalAmount, 'order.totalAmount');
    }
    final itemIds = <String>{};
    for (final item in order.items) {
      if (item.productId.isEmpty) {
        throw ArgumentError('Every order item needs a product id.');
      }
      if (item.quantity <= 0) {
        throw ArgumentError.value(item.quantity, 'item.quantity');
      }
      if (item.unitPrice.isNegative || item.srpPrice.isNegative) {
        throw ArgumentError(
          'Order item prices must be finite and non-negative.',
        );
      }
      if (item.id.isNotEmpty && !itemIds.add(item.id)) {
        throw ArgumentError('Order item ids must be unique.');
      }
    }
  }

  void _validateDebt(CustomerDebt debt) {
    if (debt.id.isEmpty) throw ArgumentError('Debt id is required.');
    if (!debt.totalAmount.isPositive) {
      throw ArgumentError.value(debt.totalAmount, 'debt.totalAmount');
    }
    if (debt.interestRateBasisPoints < 0) {
      throw ArgumentError.value(
        debt.interestRateBasisPoints,
        'debt.interestRateBasisPoints',
      );
    }
    if (!const {'none', 'daily', 'monthly'}.contains(debt.interestType)) {
      throw ArgumentError.value(debt.interestType, 'debt.interestType');
    }
    final paymentIds = <String>{};
    for (final payment in debt.payments) {
      if (payment.id.isEmpty || !paymentIds.add(payment.id)) {
        throw ArgumentError('Debt payment ids must be non-empty and unique.');
      }
      if (!payment.amount.isPositive || !payment.isAllocated) {
        throw ArgumentError.value(payment.amount, 'payment.amount');
      }
    }
  }

  Map<String, dynamic> _orderOutboxPayload(OrderDto dto) {
    final payload = dto.toCloud();
    payload['_items'] = payload.remove('items');
    return payload;
  }

  Map<String, dynamic> _debtOutboxPayload(DebtDto dto) {
    final payload = dto.toCloud();
    payload['_payments'] = payload.remove('payments');
    return payload;
  }
}

class _OrderSnapshot {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>> items;

  const _OrderSnapshot(this.order, this.items);
}

enum OrderCommitStage {
  orderAndItemsInserted,
  inventoryAdjusted,
  outboxCreated,
}
