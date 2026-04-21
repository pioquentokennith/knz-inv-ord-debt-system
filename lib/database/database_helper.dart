// ─────────────────────────────────────────────────────────────────────────────
// database_helper.dart — v5: Performance indexes
// Purpose : Singleton wrapper around the SQLite database.
//           Manages schema creation (v1) and all incremental migrations (v2–v5).
// Changes from v4:
//   • products  — added index on (user_id, is_deleted) for faster queries
//   • orders    — added index on (user_id, is_deleted) for faster queries
//   • debts     — added index on (user_id, is_deleted) for faster queries
//   • onUpgrade — v4→v5 migration adds the new indexes safely
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
      version: 5, // v5 — added indexes for performance
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'), // Enforce FK constraints
      onCreate: _onCreate,     // Called when DB is first created (fresh install)
      onUpgrade: _onUpgrade,   // Called when version number increases
    );
  }

  // Creates all tables and indexes for a brand-new database install (version 1 → 5)
  Future<void> _onCreate(Database db, int version) async {
    // users — one row per registered admin account
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,        -- Stored as SHA-256 hash (never plaintext)
        name TEXT NOT NULL,
        email TEXT,
        role TEXT NOT NULL DEFAULT 'Administrator',
        is_synced INTEGER NOT NULL DEFAULT 0, -- 1 = pushed to Firestore
        created_at TEXT NOT NULL
      )
    ''');

    // products — fragrance catalog entries owned by a user
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        stock_qty INTEGER NOT NULL DEFAULT 0,
        min_stock_level INTEGER NOT NULL DEFAULT 5, -- Triggers low-stock alert
        image_path TEXT,
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,          -- Foreign key to users.id (logical only)
        is_deleted INTEGER NOT NULL DEFAULT 0, -- 0 = active, 1 = in Recycle Bin
        deleted_at TEXT                 -- ISO-8601 timestamp of soft-delete
      )
    ''');

    // orders — customer purchase records
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,         -- Human-readable ID e.g. "KNZ-042"
        customer_name TEXT NOT NULL,
        total_amount REAL NOT NULL,
        status TEXT NOT NULL,           -- Pending/Processing/Shipped/Delivered/etc.
        order_date TEXT NOT NULL,
        notes TEXT,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');

    // order_items — line items for each order (one row per product per order)
    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,     -- Denormalized so name persists after product edits
        unit_price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');

    // debts — utang / credit records per customer
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        order_id TEXT NOT NULL,         -- Links debt to the originating order
        total_amount REAL NOT NULL,
        amount_paid REAL NOT NULL DEFAULT 0, -- Running total of all payments made
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');

    // payments — individual payment installments against a debt
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        debt_id TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_at TEXT NOT NULL,
        note TEXT,                      -- Optional note from collector
        FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE
      )
    ''');

    // activity_logs — audit trail of all user actions (add, update, delete, login)
    await db.execute('''
      CREATE TABLE activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        type TEXT NOT NULL,             -- e.g. 'auth', 'product', 'order', 'payment'
        timestamp TEXT NOT NULL,
        user_id TEXT NOT NULL
      )
    ''');

    // sync_queue — offline operations waiting to be pushed to Firestore
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,        -- e.g. 'save_product', 'soft_delete_order'
        collection TEXT NOT NULL,       -- Firestore collection name
        user_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,           -- Firestore document ID
        data TEXT NOT NULL,             -- JSON-encoded payload
        created_at TEXT NOT NULL
      )
    ''');

    // ── v5: Indexes — speed up WHERE clauses used in every getAll() call ────
    // Composite indexes on (user_id, is_deleted) cover the most common filter
    await db.execute('CREATE INDEX idx_products_user    ON products(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_orders_user      ON orders(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_order_items_order ON order_items(order_id)'); // JOIN key
    await db.execute('CREATE INDEX idx_debts_user       ON debts(user_id, is_deleted)');
    await db.execute('CREATE INDEX idx_payments_debt    ON payments(debt_id)');       // JOIN key
    await db.execute('CREATE INDEX idx_logs_user        ON activity_logs(user_id)');
  }

  // Incremental migrations — each block runs only once when upgrading from an older version
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: Added email and is_synced columns to users
    if (oldVersion < 2) {
      try { await db.execute('ALTER TABLE users ADD COLUMN email TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE users ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
    }
    // v2 → v3: Added sync_queue table for offline Firestore batching
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
    // v3 → v4: Added soft-delete columns to products, orders, and debts
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
        try { await db.execute(stmt); } catch (_) {} // Ignore if column already exists
      }
    }
    // v4 → v5: Added performance indexes for common WHERE / JOIN clauses
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
