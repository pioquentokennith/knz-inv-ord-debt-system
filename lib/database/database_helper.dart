// ─────────────────────────────────────────────────────────────────────────────
// database_helper.dart — v5: Performance indexes
// Changes from v4:
//   • products  — added index on (user_id, is_deleted) for faster queries
//   • orders    — added index on (user_id, is_deleted) for faster queries
//   • debts     — added index on (user_id, is_deleted) for faster queries
//   • onUpgrade — v4→v5 migration adds the new indexes safely
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'knz_scent.db');

    return await openDatabase(
      path,
      version: 5, // v5 — added indexes for performance
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
        deleted_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');

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
        deleted_at TEXT
      )
    ''');

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

    await db.execute('''
      CREATE TABLE activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        user_id TEXT NOT NULL
      )
    ''');

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

    // ── v5: Indexes — speed up WHERE clauses used in every getAll() call ────
    await db.execute('CREATE INDEX idx_products_user    ON products(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_orders_user      ON orders(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_order_items_order ON order_items(order_id)');
    await db.execute('CREATE INDEX idx_debts_user       ON debts(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_payments_debt    ON payments(debt_id)');
    await db.execute('CREATE INDEX idx_logs_user        ON activity_logs(user_id)');
  }

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
      // Soft-delete columns — safe to run on any existing DB
      for (final stmt in [
        'ALTER TABLE products ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE products ADD COLUMN deleted_at TEXT',
        'ALTER TABLE orders  ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE orders  ADD COLUMN deleted_at TEXT',
        'ALTER TABLE debts   ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE debts   ADD COLUMN deleted_at TEXT',
      ]) {
        try { await db.execute(stmt); } catch (_) {}
      }
    }
    if (oldVersion < 5) {
      // Add performance indexes — CREATE INDEX IF NOT EXISTS is safe to repeat
      for (final stmt in [
        'CREATE INDEX IF NOT EXISTS idx_products_user    ON products(user_id, is_deleted)',
        'CREATE INDEX IF NOT EXISTS idx_orders_user      ON orders(user_id, is_deleted)',
        'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)',
        'CREATE INDEX IF NOT EXISTS idx_debts_user       ON debts(user_id, is_deleted)',
        'CREATE INDEX IF NOT EXISTS idx_payments_debt    ON payments(debt_id)',
        'CREATE INDEX IF NOT EXISTS idx_logs_user        ON activity_logs(user_id)',
      ]) {
        try { await db.execute(stmt); } catch (_) {}
      }
    }
  }
}