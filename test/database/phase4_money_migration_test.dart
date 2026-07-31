import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('v10 money and debt ledger migrate to deterministic centavos', () async {
    final database = await _legacyDatabase();
    addTearDown(database.close);
    await database.insert('products', _product(price: 12.345));
    await database.insert('orders', _order());
    await database.insert('order_items', _item());
    await database.insert('debts', _debt(amountPaid: 100));
    await database.insert('payments', _payment(amount: 100));
    await database.insert('resellers', _reseller());
    await database.insert('custom_orders', _customOrder());

    await database.transaction(
      (txn) => DatabaseHelper.migrateToV11(
        txn,
        migrationTimestamp: DateTime.utc(2026, 1, 2),
      ),
    );

    expect((await database.query('products')).single['price_centavos'], 1235);
    final order = (await database.query('orders')).single;
    expect(order['total_amount_centavos'], 17000);
    expect(order['srp_total_centavos'], 20000);
    expect(order['deduction_per_item_centavos'], 3000);
    final debt = (await database.query('debts')).single;
    expect(debt['principal_original_centavos'], 10000);
    expect(debt['principal_outstanding_centavos'], 1000);
    expect(debt['interest_outstanding_centavos'], 0);
    expect(debt['last_accrual_timestamp'], '2026-01-02T00:00:00.000Z');
    expect(debt['status'], 'open');
    final payment = (await database.query('payments')).single;
    expect(payment['amount_centavos'], 10000);
    expect(payment['interest_applied_centavos'], 1000);
    expect(payment['principal_applied_centavos'], 9000);
    expect(
      (await database.query('resellers')).single['deduction_per_item_centavos'],
      3000,
    );
    final custom = (await database.query('custom_orders')).single;
    expect(custom['agreed_price_centavos'], 50000);
    expect(custom['deposit_paid_centavos'], 12550);
  });

  test('v11 migration rolls back an unmatched legacy paid aggregate', () async {
    final database = await _legacyDatabase();
    addTearDown(database.close);
    await database.insert('debts', _debt(amountPaid: 50));
    await database.insert('payments', _payment(amount: 40));

    await expectLater(
      database.transaction(
        (txn) => DatabaseHelper.migrateToV11(
          txn,
          migrationTimestamp: DateTime.utc(2026, 1, 2),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('amount_paid 5000 but payment rows total 4000'),
        ),
      ),
    );

    expect(await database.query('debts'), hasLength(1));
    expect(
      await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'debts_v10'",
      ),
      isEmpty,
    );
  });
}

Future<Database> _legacyDatabase() async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('PRAGMA foreign_keys = ON');
  for (final statement in _legacySchema) {
    await database.execute(statement);
  }
  return database;
}

const _legacySchema = [
  '''CREATE TABLE products (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT, category TEXT NOT NULL,
    price REAL NOT NULL, stock_qty INTEGER NOT NULL, min_stock_level INTEGER NOT NULL,
    image_path TEXT, created_at TEXT NOT NULL, user_id TEXT NOT NULL,
    is_deleted INTEGER NOT NULL, deleted_at TEXT)''',
  '''CREATE TABLE orders (
    id TEXT PRIMARY KEY, order_id TEXT NOT NULL, customer_name TEXT NOT NULL,
    total_amount REAL NOT NULL, status TEXT NOT NULL, order_date TEXT NOT NULL,
    notes TEXT, user_id TEXT NOT NULL, is_deleted INTEGER NOT NULL, deleted_at TEXT,
    payment_method TEXT, payment_reference TEXT, is_reseller INTEGER NOT NULL,
    discount_percent REAL NOT NULL, discounted_total REAL, order_type TEXT NOT NULL,
    stock_deducted INTEGER NOT NULL, stock_released_on_delete INTEGER NOT NULL)''',
  '''CREATE TABLE order_items (
    id TEXT PRIMARY KEY, order_id TEXT NOT NULL, product_id TEXT NOT NULL,
    product_name TEXT NOT NULL, unit_price REAL NOT NULL, srp_price REAL,
    quantity INTEGER NOT NULL,
    FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE)''',
  '''CREATE TABLE debts (
    id TEXT PRIMARY KEY, customer_name TEXT NOT NULL, order_id TEXT NOT NULL,
    total_amount REAL NOT NULL, amount_paid REAL NOT NULL, created_at TEXT NOT NULL,
    user_id TEXT NOT NULL, is_deleted INTEGER NOT NULL, deleted_at TEXT,
    interest_rate REAL NOT NULL, interest_type TEXT, interest_start_date TEXT)''',
  '''CREATE TABLE payments (
    id TEXT PRIMARY KEY, debt_id TEXT NOT NULL, amount REAL NOT NULL,
    paid_at TEXT NOT NULL, note TEXT,
    FOREIGN KEY(debt_id) REFERENCES debts(id) ON DELETE CASCADE)''',
  '''CREATE TABLE resellers (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, contact TEXT, discount_percent REAL NOT NULL,
    user_id TEXT NOT NULL, created_at TEXT NOT NULL, is_deleted INTEGER NOT NULL,
    deleted_at TEXT)''',
  '''CREATE TABLE custom_orders (
    id TEXT PRIMARY KEY, customer_name TEXT NOT NULL, contact TEXT,
    fragrance_specs TEXT NOT NULL, agreed_price REAL NOT NULL,
    deposit_paid REAL NOT NULL, delivery_date TEXT NOT NULL, status TEXT NOT NULL,
    terms TEXT, user_id TEXT NOT NULL, created_at TEXT NOT NULL,
    is_deleted INTEGER NOT NULL, deleted_at TEXT)''',
  '''CREATE TABLE sync_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT, operation TEXT NOT NULL,
    collection TEXT NOT NULL, user_id TEXT NOT NULL, doc_id TEXT NOT NULL,
    data TEXT NOT NULL, created_at TEXT NOT NULL, attempt_count INTEGER NOT NULL,
    next_attempt_at TEXT, last_attempt_at TEXT, last_error TEXT, status TEXT NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE, updated_at TEXT NOT NULL)''',
];

Map<String, Object?> _product({required double price}) => {
  'id': 'product-1',
  'name': 'Rose',
  'description': '',
  'category': 'Perfume',
  'price': price,
  'stock_qty': 3,
  'min_stock_level': 1,
  'image_path': null,
  'created_at': '2026-01-01T00:00:00.000Z',
  'user_id': 'user-1',
  'is_deleted': 0,
  'deleted_at': null,
};

Map<String, Object?> _order() => {
  'id': 'order-1',
  'order_id': 'KNZ-001',
  'customer_name': 'Customer',
  'total_amount': 200,
  'status': 'Utang',
  'order_date': '2026-01-01T00:00:00.000Z',
  'notes': null,
  'user_id': 'user-1',
  'is_deleted': 0,
  'deleted_at': null,
  'payment_method': null,
  'payment_reference': null,
  'is_reseller': 1,
  'discount_percent': 30,
  'discounted_total': 170,
  'order_type': 'regular',
  'stock_deducted': 1,
  'stock_released_on_delete': 0,
};

Map<String, Object?> _item() => {
  'id': 'item-1',
  'order_id': 'order-1',
  'product_id': 'product-1',
  'product_name': 'Rose',
  'unit_price': 170,
  'srp_price': 200,
  'quantity': 1,
};

Map<String, Object?> _debt({required double amountPaid}) => {
  'id': 'debt-1',
  'customer_name': 'Customer',
  'order_id': 'KNZ-001',
  'total_amount': 100,
  'amount_paid': amountPaid,
  'created_at': '2026-01-01T00:00:00.000Z',
  'user_id': 'user-1',
  'is_deleted': 0,
  'deleted_at': null,
  'interest_rate': 10,
  'interest_type': 'daily',
  'interest_start_date': '2026-01-01T00:00:00.000Z',
};

Map<String, Object?> _payment({required double amount}) => {
  'id': 'payment-1',
  'debt_id': 'debt-1',
  'amount': amount,
  'paid_at': '2026-01-02T00:00:00.000Z',
  'note': null,
};

Map<String, Object?> _reseller() => {
  'id': 'reseller-1',
  'name': 'Partner',
  'contact': null,
  'discount_percent': 30,
  'user_id': 'user-1',
  'created_at': '2026-01-01T00:00:00.000Z',
  'is_deleted': 0,
  'deleted_at': null,
};

Map<String, Object?> _customOrder() => {
  'id': 'custom-1',
  'customer_name': 'Customer',
  'contact': null,
  'fragrance_specs': 'Rose',
  'agreed_price': 500,
  'deposit_paid': 125.5,
  'delivery_date': '2026-02-01T00:00:00.000Z',
  'status': 'Pending',
  'terms': null,
  'user_id': 'user-1',
  'created_at': '2026-01-01T00:00:00.000Z',
  'is_deleted': 0,
  'deleted_at': null,
};
