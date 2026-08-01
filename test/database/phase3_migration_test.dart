import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('v10 reconciliation preserves rows and durable stock state', () async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await DatabaseHelper.createSchemaForTesting(database);

    await database.insert('products', {
      'id': 'product-1',
      'name': 'Rose',
      'description': '',
      'category': 'Perfume',
      'price_centavos': 10000,
      'stock_qty': 3,
      'min_stock_level': 1,
      'image_path': null,
      'created_at': '2026-01-01T00:00:00.000Z',
      'user_id': 'user-1',
      'is_deleted': 0,
      'deleted_at': null,
    });
    await database.insert('products', {
      'id': 'deleted-product',
      'name': 'Archived Rose',
      'description': '',
      'category': 'Perfume',
      'price_centavos': 9000,
      'stock_qty': 0,
      'min_stock_level': 1,
      'image_path': null,
      'created_at': '2025-12-01T00:00:00.000Z',
      'user_id': 'user-1',
      'is_deleted': 1,
      'deleted_at': '2026-01-04T00:00:00.000Z',
    });
    await database.insert('orders', {
      'id': 'cancelled-order',
      'order_id': 'KNZ-007',
      'customer_name': 'Cancelled Customer',
      'total_amount_centavos': 20000,
      'srp_total_centavos': 20000,
      'status': 'Cancelled',
      'order_date': '2026-01-01T00:00:00.000Z',
      'notes': null,
      'user_id': 'user-1',
      'is_deleted': 0,
      'deleted_at': null,
      'payment_method': null,
      'payment_reference': null,
      'is_reseller': 0,
      'deduction_per_item_centavos': 0,
      'discounted_total_centavos': null,
      'order_type': 'regular',
    });
    await database.insert('order_items', {
      'id': 'item-1',
      'order_id': 'cancelled-order',
      'product_id': 'product-1',
      'product_name': 'Rose',
      'unit_price_centavos': 10000,
      'srp_price_centavos': 10000,
      'quantity': 2,
    });
    await database.insert('orders', {
      'id': 'deleted-order',
      'order_id': 'KNZ-008',
      'customer_name': 'Deleted Customer',
      'total_amount_centavos': 10000,
      'srp_total_centavos': 10000,
      'status': 'Pending',
      'order_date': '2026-01-02T00:00:00.000Z',
      'notes': null,
      'user_id': 'user-1',
      'is_deleted': 1,
      'deleted_at': '2026-01-03T00:00:00.000Z',
      'payment_method': null,
      'payment_reference': null,
      'is_reseller': 0,
      'deduction_per_item_centavos': 0,
      'discounted_total_centavos': null,
      'order_type': 'regular',
    });
    await database.insert('sync_queue', {
      'operation': 'save_order',
      'collection': 'orders',
      'user_id': 'user-1',
      'doc_id': 'cancelled-order',
      'data': jsonEncode({'id': 'cancelled-order'}),
      'created_at': '2026-01-01T00:00:00.000Z',
      'attempt_count': 2,
      'next_attempt_at': null,
      'last_attempt_at': null,
      'last_error': 'offline',
      'status': 'pending',
      'idempotency_key': 'legacy-1',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await database.insert('debts', {
      'id': 'debt-1',
      'customer_name': 'Settled Customer',
      'order_id': 'KNZ-008',
      'principal_original_centavos': 10000,
      'principal_outstanding_centavos': 0,
      'interest_outstanding_centavos': 0,
      'created_at': '2026-01-02T00:00:00.000Z',
      'user_id': 'user-1',
      'is_deleted': 1,
      'deleted_at': '2026-01-04T00:00:00.000Z',
      'interest_rate_basis_points': 0,
      'interest_type': 'none',
      'interest_start_timestamp': '2026-01-02T00:00:00.000Z',
      'last_accrual_timestamp': '2026-01-03T00:00:00.000Z',
      'status': 'paid',
    });
    await database.insert('payments', {
      'id': 'payment-1',
      'debt_id': 'debt-1',
      'amount_centavos': 10000,
      'interest_applied_centavos': 0,
      'principal_applied_centavos': 10000,
      'paid_at': '2026-01-03T00:00:00.000Z',
      'payment_method': null,
      'reference': null,
      'note': null,
    });
    await database.insert('resellers', {
      'id': 'reseller-1',
      'name': 'Archived Partner',
      'contact': null,
      'deduction_per_item_centavos': 1000,
      'user_id': 'user-1',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_deleted': 1,
      'deleted_at': null,
    });
    await database.insert('custom_orders', {
      'id': 'custom-1',
      'customer_name': 'Archived Customer',
      'contact': null,
      'fragrance_specs': 'Rose',
      'agreed_price_centavos': 50000,
      'deposit_paid_centavos': 10000,
      'delivery_date': '2026-02-01T00:00:00.000Z',
      'status': 'Cancelled',
      'terms': null,
      'user_id': 'user-1',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_deleted': 1,
      'deleted_at': null,
    });

    await database.transaction(DatabaseHelper.migrateToV10);

    final product = (await database.query(
      'products',
      where: 'id = ?',
      whereArgs: ['product-1'],
    )).single;
    expect(product['stock_qty'], 5);
    final orders = await database.query('orders', orderBy: 'order_id');
    expect(orders[0]['stock_deducted'], 0);
    expect(orders[0]['stock_released_on_delete'], 0);
    expect(orders[1]['stock_deducted'], 0);
    expect(orders[1]['stock_released_on_delete'], 1);
    expect((await database.query('order_sequences')).single['last_value'], 8);

    final queue = await database.query('sync_queue', orderBy: 'id');
    expect(queue, hasLength(8));
    expect(queue.first['status'], 'pending');
    expect(queue.first['idempotency_key'], 'legacy-1');
    expect(queue[1]['operation'], 'save_product');
    expect(
      queue.skip(2).take(2).map((row) => row['operation']),
      everyElement('save_order'),
    );
    final snapshots = {
      for (final row in queue.skip(4))
        '${row['collection']}/${row['doc_id']}':
            jsonDecode(row['data'] as String) as Map<String, dynamic>,
    };
    expect(snapshots['products/deleted-product']?['name'], 'Archived Rose');
    expect(snapshots['debts/debt-1']?['_payments'], hasLength(1));
    expect(snapshots['resellers/reseller-1']?['name'], 'Archived Partner');
    expect(snapshots['custom_orders/custom-1']?['fragrance_specs'], 'Rose');

    final queueColumns = await database.rawQuery(
      'PRAGMA table_info(sync_queue)',
    );
    expect(
      queueColumns.map((column) => column['name']),
      containsAll(['status', 'last_attempt_at', 'idempotency_key']),
    );
  });
}
