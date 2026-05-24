// ─────────────────────────────────────────────────────────────────────────────
// database_helper.dart — v6: Resellers, custom_orders, v6 column additions
// Purpose : Singleton wrapper around the SQLite database.
// Changes from v5:
//   • orders     — added payment_method, payment_reference, is_reseller,
//                  discount_percent, discounted_total, order_type
//   • resellers  — NEW table for reseller entities
//   • custom_orders — NEW table (Feature 5, referenced here for completeness)
//   • onUpgrade  — v5→v6 migration block
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Singleton — only one database connection is ever open per app session
class DatabaseHelper {
  DatabaseHelper._(); // Private constructor prevents direct instantiation
  static final DatabaseHelper instance = DatabaseHelper._(); // Shared instance
  static Database? _db; // Cached opened database; null until first access

  // Lazy getter — opens the database on first access, reuses it thereafter
  Future<Database> get database async {
    _db ??= await _initDb(); // Initialize only once
    return _db!;
  }

  // Opens (or creates) the SQLite file and runs onCreate / onUpgrade as needed
  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath(); // Platform-specific DB directory
    final path = join(dbPath, 'knz_scent.db'); // Full file path

    return await openDatabase(
      path,
      version: 7, // v7 — srp_price added to order_items for sales table accuracy
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Creates all tables for a brand-new install (version 1 → 6)
  Future<void> _onCreate(Database db, int version) async {
    // users
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        name TEXT NOT NULL,
        email TEXT,
        role TEXT NOT NULL DEFAULT 'Administrator',
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // products
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        stock_qty INTEGER NOT NULL DEFAULT 0,
        min_stock_level INTEGER NOT NULL DEFAULT 5,
        image_path TEXT,
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');

    // orders — includes v6 payment + reseller + order-type columns
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,
        order_date TEXT NOT NULL,
        notes TEXT,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        payment_method TEXT,
        payment_reference TEXT,
        is_reseller INTEGER NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        discounted_total REAL,
        order_type TEXT NOT NULL DEFAULT 'regular'
      )
    ''');

    // order_items
    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        srp_price REAL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');

    // debts
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        order_id TEXT NOT NULL,
        total_amount REAL NOT NULL,
        amount_paid REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        interest_rate REAL NOT NULL DEFAULT 0,
        interest_type TEXT DEFAULT 'none',
        interest_start_date TEXT
      )
    ''');

    // payments
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        debt_id TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_at TEXT NOT NULL,
        note TEXT,
        FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE
      )
    ''');

    // activity_logs
    await db.execute('''
      CREATE TABLE activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        user_id TEXT NOT NULL
      )
    ''');

    // sync_queue
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        collection TEXT NOT NULL,
        user_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // resellers (v6)
    await db.execute('''
      CREATE TABLE resellers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        contact TEXT,
        discount_percent REAL NOT NULL DEFAULT 0,
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // custom_orders (v6 — Feature 5 placeholder, fully used in Phase 3)
    await db.execute('''
      CREATE TABLE custom_orders (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        contact TEXT,
        fragrance_specs TEXT NOT NULL,
        agreed_price REAL NOT NULL,
        deposit_paid REAL NOT NULL DEFAULT 0,
        delivery_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Pending',
        terms TEXT,
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ── v5/v6 indexes ─────────────────────────────────────────────────────
    await db.execute('CREATE INDEX idx_products_user       ON products(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_orders_user         ON orders(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_order_items_order   ON order_items(order_id)');
    await db.execute('CREATE INDEX idx_debts_user          ON debts(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_payments_debt       ON payments(debt_id)');
    await db.execute('CREATE INDEX idx_logs_user           ON activity_logs(user_id)');
    await db.execute('CREATE INDEX idx_resellers_user      ON resellers(user_id, is_deleted)');
  }

  // Incremental migrations
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute('ALTER TABLE users ADD COLUMN email TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE users ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operation TEXT NOT NULL,
            collection TEXT NOT NULL,
            user_id TEXT NOT NULL,
            doc_id TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      for (final stmt in [
        'ALTER TABLE products ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE products ADD COLUMN deleted_at TEXT',
        'ALTER TABLE orders  ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE orders  ADD COLUMN deleted_at TEXT',
        'ALTER TABLE debts   ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE debts   ADD COLUMN deleted_at TEXT',
      ]) { try { await db.execute(stmt); } catch (_) {} }
    }
    if (oldVersion < 5) {
      for (final stmt in [
        'CREATE INDEX IF NOT EXISTS idx_products_user       ON products(user_id, is_deleted)',
        'CREATE INDEX IF NOT EXISTS idx_orders_user         ON orders(user_id, is_deleted)',
        'CREATE INDEX IF NOT EXISTS idx_order_items_order   ON order_items(order_id)',
        'CREATE INDEX IF NOT EXISTS idx_debts_user          ON debts(user_id, is_deleted)',
        'CREATE INDEX IF NOT EXISTS idx_payments_debt       ON payments(debt_id)',
        'CREATE INDEX IF NOT EXISTS idx_logs_user           ON activity_logs(user_id)',
      ]) { try { await db.execute(stmt); } catch (_) {} }
    }
    // ── v5 → v6 ─────────────────────────────────────────────────────────────
    if (oldVersion < 6) {
      // Extend orders with payment + reseller + order-type columns
      for (final stmt in [
        'ALTER TABLE orders ADD COLUMN payment_method TEXT',
        'ALTER TABLE orders ADD COLUMN payment_reference TEXT',
        'ALTER TABLE orders ADD COLUMN is_reseller INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE orders ADD COLUMN discount_percent REAL NOT NULL DEFAULT 0',
        'ALTER TABLE orders ADD COLUMN discounted_total REAL',
        "ALTER TABLE orders ADD COLUMN order_type TEXT NOT NULL DEFAULT 'regular'",
        // Extend debts with interest columns
        'ALTER TABLE debts ADD COLUMN interest_rate REAL NOT NULL DEFAULT 0',
        "ALTER TABLE debts ADD COLUMN interest_type TEXT DEFAULT 'none'",
        'ALTER TABLE debts ADD COLUMN interest_start_date TEXT',
      ]) { try { await db.execute(stmt); } catch (_) {} }

      // New tables
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS resellers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            contact TEXT,
            discount_percent REAL NOT NULL DEFAULT 0,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_resellers_user ON resellers(user_id, is_deleted)'
        );
      } catch (_) {}

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS custom_orders (
            id TEXT PRIMARY KEY,
            customer_name TEXT NOT NULL,
            contact TEXT,
            fragrance_specs TEXT NOT NULL,
            agreed_price REAL NOT NULL,
            deposit_paid REAL NOT NULL DEFAULT 0,
            delivery_date TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'Pending',
            terms TEXT,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    // ── v6 → v7 ─────────────────────────────────────────────────────────────
    if (oldVersion < 7) {
      // Add srp_price to order_items so Sales Table can show both SRP and actual price
      try { await db.execute('ALTER TABLE order_items ADD COLUMN srp_price REAL'); } catch (_) {}
    }
  }
}
