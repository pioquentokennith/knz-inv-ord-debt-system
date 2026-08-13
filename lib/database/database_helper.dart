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

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../core/money.dart';
import '../dto/activity_log_dto.dart';
import '../dto/business_event_dto.dart';
import '../dto/custom_order_dto.dart';
import '../dto/debt_dto.dart';
import '../dto/order_dto.dart';
import '../dto/product_dto.dart';
import '../dto/reseller_dto.dart';

// Singleton — only one database connection is ever open per app session
class DatabaseHelper {
  DatabaseHelper._(); // Private constructor prevents direct instantiation
  static final DatabaseHelper instance = DatabaseHelper._(); // Shared instance
  static Database? _db; // Cached opened database; null until first access
  static const schemaVersion = 17;

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
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.rawQuery('PRAGMA secure_delete = ON');
  }

  // Creates all tables for a brand-new install (version 1 → 6)
  static Future<void> _onCreate(Database db, int version) async {
    // users
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        firebase_uid TEXT UNIQUE,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'Staff',
        account_status TEXT NOT NULL DEFAULT 'pending',
        is_active INTEGER NOT NULL DEFAULT 0,
        legacy_owner_key TEXT,
        migration_state TEXT NOT NULL DEFAULT 'mapped',
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
        price_centavos INTEGER NOT NULL DEFAULT 0 CHECK (price_centavos >= 0),
        stock_qty INTEGER NOT NULL DEFAULT 0,
        min_stock_level INTEGER NOT NULL DEFAULT 5,
        image_path TEXT,
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        revision INTEGER NOT NULL DEFAULT 0,
        base_revision INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        writer_device_id TEXT,
        tombstone_revision INTEGER NOT NULL DEFAULT 0,
        purge_state TEXT NOT NULL DEFAULT 'none'
      )
    ''');

    // orders — includes v6 payment + reseller + order-type columns
    await db.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        total_amount_centavos INTEGER NOT NULL CHECK (total_amount_centavos >= 0),
        srp_total_centavos INTEGER NOT NULL CHECK (srp_total_centavos >= 0),
        status TEXT NOT NULL,
        order_date TEXT NOT NULL,
        notes TEXT,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        payment_method TEXT,
        payment_reference TEXT,
        is_reseller INTEGER NOT NULL DEFAULT 0,
        deduction_per_item_centavos INTEGER NOT NULL DEFAULT 0 CHECK (deduction_per_item_centavos >= 0),
        discounted_total_centavos INTEGER CHECK (discounted_total_centavos >= 0),
        customer_pay_amount_centavos INTEGER NOT NULL DEFAULT 0 CHECK (customer_pay_amount_centavos >= 0),
        order_type TEXT NOT NULL DEFAULT 'regular',
        stock_deducted INTEGER NOT NULL DEFAULT 1,
        stock_released_on_delete INTEGER NOT NULL DEFAULT 0,
        command_id TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        revision INTEGER NOT NULL DEFAULT 0,
        base_revision INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        writer_device_id TEXT,
        tombstone_revision INTEGER NOT NULL DEFAULT 0,
        purge_state TEXT NOT NULL DEFAULT 'none',
        number_state TEXT NOT NULL DEFAULT 'legacy',
        provisional_order_id TEXT,
        UNIQUE (user_id, order_id)
      )
    ''');

    // order_items
    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price_centavos INTEGER NOT NULL CHECK (unit_price_centavos >= 0),
        srp_price_centavos INTEGER CHECK (srp_price_centavos >= 0),
        quantity INTEGER NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');

    // debts
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        order_id TEXT NOT NULL,
        principal_original_centavos INTEGER NOT NULL CHECK (principal_original_centavos >= 0),
        principal_outstanding_centavos INTEGER NOT NULL CHECK (principal_outstanding_centavos >= 0),
        interest_outstanding_centavos INTEGER NOT NULL DEFAULT 0 CHECK (interest_outstanding_centavos >= 0),
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        interest_rate_basis_points INTEGER NOT NULL DEFAULT 0 CHECK (interest_rate_basis_points >= 0),
        interest_type TEXT DEFAULT 'none',
        interest_start_timestamp TEXT NOT NULL,
        last_accrual_timestamp TEXT NOT NULL,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'paid')),
        schema_version INTEGER NOT NULL DEFAULT 1,
        revision INTEGER NOT NULL DEFAULT 0,
        base_revision INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        writer_device_id TEXT,
        tombstone_revision INTEGER NOT NULL DEFAULT 0,
        purge_state TEXT NOT NULL DEFAULT 'none'
      )
    ''');

    // payments
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        debt_id TEXT NOT NULL,
        amount_centavos INTEGER NOT NULL CHECK (amount_centavos > 0),
        interest_applied_centavos INTEGER NOT NULL DEFAULT 0 CHECK (interest_applied_centavos >= 0),
        principal_applied_centavos INTEGER NOT NULL DEFAULT 0 CHECK (principal_applied_centavos >= 0),
        paid_at TEXT NOT NULL,
        payment_method TEXT,
        reference TEXT,
        note TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        CHECK (amount_centavos = interest_applied_centavos + principal_applied_centavos),
        FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE
      )
    ''');

    // activity_logs
    await db.execute('''
      CREATE TABLE activity_logs (
        id TEXT PRIMARY KEY,
        message TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        user_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL DEFAULT 1
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
        created_at TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        last_attempt_at TEXT,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        idempotency_key TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL,
        operation_id TEXT,
        aggregate_key TEXT,
        expected_revision INTEGER,
        resulting_revision INTEGER,
        device_id TEXT,
        error_class TEXT,
        conflict_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE order_sequences (
        user_id TEXT PRIMARY KEY,
        last_value INTEGER NOT NULL DEFAULT 0 CHECK (last_value >= 0)
      )
    ''');

    // resellers (v6)
    await db.execute('''
      CREATE TABLE resellers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        contact TEXT,
        deduction_per_item_centavos INTEGER NOT NULL DEFAULT 0 CHECK (deduction_per_item_centavos >= 0),
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        revision INTEGER NOT NULL DEFAULT 0,
        base_revision INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        writer_device_id TEXT,
        tombstone_revision INTEGER NOT NULL DEFAULT 0,
        purge_state TEXT NOT NULL DEFAULT 'none'
      )
    ''');

    // custom_orders (v6 — Feature 5 placeholder, fully used in Phase 3)
    await db.execute('''
      CREATE TABLE custom_orders (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        contact TEXT,
        fragrance_specs TEXT NOT NULL,
        agreed_price_centavos INTEGER NOT NULL CHECK (agreed_price_centavos >= 0),
        deposit_paid_centavos INTEGER NOT NULL DEFAULT 0 CHECK (deposit_paid_centavos >= 0),
        delivery_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Pending',
        terms TEXT,
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        revision INTEGER NOT NULL DEFAULT 0,
        base_revision INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT,
        writer_device_id TEXT,
        tombstone_revision INTEGER NOT NULL DEFAULT 0,
        purge_state TEXT NOT NULL DEFAULT 'none'
      )
    ''');

    await db.execute('''
      CREATE TABLE custom_order_payments (
        id TEXT PRIMARY KEY,
        custom_order_id TEXT NOT NULL,
        amount_centavos INTEGER NOT NULL CHECK (amount_centavos > 0),
        paid_at TEXT NOT NULL,
        note TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (custom_order_id) REFERENCES custom_orders (id) ON DELETE CASCADE
      )
    ''');

    await _createBusinessEventsSchema(db);

    await _createTrustedDeviceSchema(db);
    await _createSynchronizationSchema(db);

    // ── v5/v6 indexes ─────────────────────────────────────────────────────
    await db.execute(
      'CREATE INDEX idx_products_user       ON products(user_id, is_deleted)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_users_firebase_uid ON users(firebase_uid) '
      'WHERE firebase_uid IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX idx_orders_user         ON orders(user_id, is_deleted)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_orders_user_order_id ON orders(user_id, order_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_orders_user_command_id '
      'ON orders(user_id, command_id) WHERE command_id IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX idx_order_items_order   ON order_items(order_id)',
    );
    await db.execute(
      'CREATE INDEX idx_debts_user          ON debts(user_id, is_deleted)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_debts_user_order_id ON debts(user_id, order_id)',
    );
    await db.execute(
      'CREATE INDEX idx_payments_debt       ON payments(debt_id)',
    );
    await db.execute(
      'CREATE INDEX idx_logs_user           ON activity_logs(user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_resellers_user      ON resellers(user_id, is_deleted)',
    );
    await db.execute(
      'CREATE INDEX idx_custom_orders_user ON custom_orders(user_id, is_deleted)',
    );
    await db.execute(
      'CREATE INDEX idx_custom_order_payments_order '
      'ON custom_order_payments(custom_order_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sync_queue_due ON sync_queue(next_attempt_at, created_at)',
    );
    await db.execute(
      'CREATE INDEX idx_sync_queue_status ON sync_queue(user_id, status, id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_sync_queue_idempotency '
      'ON sync_queue(idempotency_key)',
    );
    await _verifySchema(db);
  }

  // Incremental migrations. Every statement is allowed to fail the upgrade so
  // SQLite rolls the transaction back instead of accepting a partial schema.
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) =>
      _upgrade(db, oldVersion, newVersion);

  static Future<void> _upgrade(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        collection TEXT NOT NULL,
        user_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        last_attempt_at TEXT,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        idempotency_key TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS resellers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        contact TEXT,
        discount_percent REAL NOT NULL DEFAULT 0,
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
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
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');

    // Checking PRAGMA first makes the migration idempotent and also repairs
    // databases left partially upgraded by older catch-and-ignore migrations.
    await _addColumnIfMissing(db, 'users', 'email', 'email TEXT');
    await _addColumnIfMissing(
      db,
      'users',
      'is_synced',
      'is_synced INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'products',
      'is_deleted',
      'is_deleted INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'products', 'deleted_at', 'deleted_at TEXT');
    await _addColumnIfMissing(
      db,
      'orders',
      'is_deleted',
      'is_deleted INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'orders', 'deleted_at', 'deleted_at TEXT');
    await _addColumnIfMissing(
      db,
      'orders',
      'payment_method',
      'payment_method TEXT',
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'payment_reference',
      'payment_reference TEXT',
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'is_reseller',
      'is_reseller INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'discount_percent',
      'discount_percent REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'discounted_total',
      'discounted_total REAL',
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'order_type',
      "order_type TEXT NOT NULL DEFAULT 'regular'",
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'stock_deducted',
      'stock_deducted INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'stock_released_on_delete',
      'stock_released_on_delete INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'debts',
      'is_deleted',
      'is_deleted INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'debts', 'deleted_at', 'deleted_at TEXT');
    await _addColumnIfMissing(
      db,
      'debts',
      'interest_rate',
      'interest_rate REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'debts',
      'interest_type',
      "interest_type TEXT DEFAULT 'none'",
    );
    await _addColumnIfMissing(
      db,
      'debts',
      'interest_start_date',
      'interest_start_date TEXT',
    );
    await _addColumnIfMissing(db, 'order_items', 'srp_price', 'srp_price REAL');
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'attempt_count',
      'attempt_count INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'next_attempt_at',
      'next_attempt_at TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'last_attempt_at',
      'last_attempt_at TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'last_error',
      'last_error TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'updated_at',
      'updated_at TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'status',
      "status TEXT NOT NULL DEFAULT 'pending'",
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'idempotency_key',
      'idempotency_key TEXT',
    );
    await _addColumnIfMissing(db, 'resellers', 'deleted_at', 'deleted_at TEXT');
    await _addColumnIfMissing(
      db,
      'custom_orders',
      'deleted_at',
      'deleted_at TEXT',
    );
    await db.execute(
      'UPDATE sync_queue SET updated_at = created_at '
      'WHERE updated_at IS NULL',
    );
    await db.execute(
      "UPDATE sync_queue SET status = 'pending' "
      "WHERE status IS NULL OR status NOT IN ('pending', 'syncing', 'failed')",
    );
    final queueRows = await db.query(
      'sync_queue',
      columns: const ['id'],
      where: 'idempotency_key IS NULL OR idempotency_key = ?',
      whereArgs: [''],
    );
    for (final row in queueRows) {
      await db.update(
        'sync_queue',
        {'idempotency_key': 'legacy-${row['id']}'},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_sequences (
        user_id TEXT PRIMARY KEY,
        last_value INTEGER NOT NULL DEFAULT 0 CHECK (last_value >= 0)
      )
    ''');

    if (oldVersion < 10) {
      await migrateToV10(db);
    }
    if (oldVersion < 11) {
      await migrateToV11(db);
    }
    if (oldVersion < 12) {
      await migrateToV12(db);
    }
    if (oldVersion < 13) {
      await migrateToV13(db);
    }
    if (oldVersion < 14) {
      await migrateToV14(db);
    }
    if (oldVersion < 15) {
      await migrateToV15(db);
    }

    for (final statement in [
      'CREATE INDEX IF NOT EXISTS idx_products_user ON products(user_id, is_deleted)',
      'CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id, is_deleted)',
      'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)',
      'CREATE INDEX IF NOT EXISTS idx_debts_user ON debts(user_id, is_deleted)',
      'CREATE INDEX IF NOT EXISTS idx_payments_debt ON payments(debt_id)',
      'CREATE INDEX IF NOT EXISTS idx_logs_user ON activity_logs(user_id)',
      'CREATE INDEX IF NOT EXISTS idx_resellers_user ON resellers(user_id, is_deleted)',
      'CREATE INDEX IF NOT EXISTS idx_custom_orders_user ON custom_orders(user_id, is_deleted)',
      'CREATE INDEX IF NOT EXISTS idx_custom_order_payments_order ON custom_order_payments(custom_order_id)',
      'CREATE INDEX IF NOT EXISTS idx_business_events_user_time ON business_events(user_id, occurred_at, recorded_at)',
      'CREATE INDEX IF NOT EXISTS idx_business_events_subject ON business_events(user_id, subject_type, subject_id, occurred_at)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_business_events_user_command ON business_events(user_id, command_id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_business_events_source ON business_events(user_id, source_type, source_id) WHERE source_type IS NOT NULL AND source_id IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_due ON sync_queue(next_attempt_at, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(user_id, status, id)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sync_queue_idempotency ON sync_queue(idempotency_key)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_user_command_id ON orders(user_id, command_id) WHERE command_id IS NOT NULL',
    ]) {
      await db.execute(statement);
    }

    final duplicateOrderIds = await db.rawQuery('''
      SELECT user_id, order_id, COUNT(*) AS duplicate_count
      FROM orders
      GROUP BY user_id, order_id
      HAVING COUNT(*) > 1
      LIMIT 5
    ''');
    if (duplicateOrderIds.isNotEmpty) {
      throw StateError(
        'Cannot enforce unique order IDs; duplicate rows require repair: '
        '$duplicateOrderIds',
      );
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_user_order_id '
      'ON orders(user_id, order_id)',
    );

    final duplicateDebtOrders = await db.rawQuery('''
      SELECT user_id, order_id, COUNT(*) AS duplicate_count
      FROM debts
      GROUP BY user_id, order_id
      HAVING COUNT(*) > 1
      LIMIT 5
    ''');
    if (duplicateDebtOrders.isNotEmpty) {
      throw StateError(
        'Cannot enforce one debt per order; duplicate rows require repair: '
        '$duplicateDebtOrders',
      );
    }
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_debts_user_order_id '
      'ON debts(user_id, order_id)',
    );

    if (oldVersion < 9) {
      await migrateUsersToV9(db);
    }
    if (oldVersion < 16) {
      await migrateToV16(db);
    }
    if (oldVersion < 17) {
      await migrateToV17(db);
    }

    await _verifySchema(db);
  }

  /// Adds explicit optional due dates without assigning dates to legacy debts.
  static Future<void> migrateToV14(DatabaseExecutor db) =>
      _addColumnIfMissing(db, 'debts', 'due_date', 'due_date TEXT');

  static Future<void> migrateToV16(DatabaseExecutor db) =>
      _createTrustedDeviceSchema(db);

  static Future<void> migrateToV17(DatabaseExecutor db) async {
    for (final table in const [
      'products',
      'orders',
      'debts',
      'resellers',
      'custom_orders',
    ]) {
      await _addColumnIfMissing(
        db,
        table,
        'revision',
        'revision INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        table,
        'base_revision',
        'base_revision INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(db, table, 'updated_at', 'updated_at TEXT');
      await _addColumnIfMissing(
        db,
        table,
        'writer_device_id',
        'writer_device_id TEXT',
      );
      await _addColumnIfMissing(
        db,
        table,
        'tombstone_revision',
        'tombstone_revision INTEGER NOT NULL DEFAULT 0',
      );
      await _addColumnIfMissing(
        db,
        table,
        'purge_state',
        "purge_state TEXT NOT NULL DEFAULT 'none'",
      );
    }
    await _addColumnIfMissing(
      db,
      'orders',
      'number_state',
      "number_state TEXT NOT NULL DEFAULT 'legacy'",
    );
    await _addColumnIfMissing(
      db,
      'orders',
      'provisional_order_id',
      'provisional_order_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'operation_id',
      'operation_id TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'aggregate_key',
      'aggregate_key TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'expected_revision',
      'expected_revision INTEGER',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'resulting_revision',
      'resulting_revision INTEGER',
    );
    await _addColumnIfMissing(db, 'sync_queue', 'device_id', 'device_id TEXT');
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'error_class',
      'error_class TEXT',
    );
    await _addColumnIfMissing(
      db,
      'sync_queue',
      'conflict_id',
      'conflict_id INTEGER',
    );
    await _createSynchronizationSchema(db);
    await db.execute(
      'UPDATE sync_queue SET operation_id = idempotency_key '
      'WHERE operation_id IS NULL',
    );
    await db.execute(
      "UPDATE sync_queue SET aggregate_key = collection || ':' || doc_id "
      'WHERE aggregate_key IS NULL',
    );
  }

  static Future<void> _createSynchronizationSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_identity (
        singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
        device_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        collection TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        aggregate_key TEXT NOT NULL,
        local_revision INTEGER NOT NULL,
        remote_revision INTEGER NOT NULL,
        local_data TEXT NOT NULL,
        remote_data TEXT,
        reason TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open',
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        UNIQUE (user_id, aggregate_key, status)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        user_id TEXT NOT NULL,
        collection TEXT NOT NULL,
        cursor_value TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (user_id, collection)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS dead_letters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        queue_row_id INTEGER,
        user_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        aggregate_key TEXT NOT NULL,
        payload TEXT NOT NULL,
        error_class TEXT NOT NULL,
        last_error TEXT NOT NULL,
        attempt_count INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_user_status '
      'ON sync_conflicts(user_id, status, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_aggregate '
      'ON sync_queue(user_id, aggregate_key, id)',
    );
  }

  static Future<void> _createTrustedDeviceSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_auth_grants (
        uid TEXT PRIMARY KEY,
        state TEXT NOT NULL CHECK (state IN ('enabled', 'revoked')),
        generation INTEGER NOT NULL CHECK (generation > 0),
        enrolled_at TEXT NOT NULL,
        last_verified_at TEXT NOT NULL,
        access_generation INTEGER NOT NULL DEFAULT 1 CHECK (access_generation > 0),
        profile_digest TEXT NOT NULL,
        revoked_at TEXT,
        revocation_reason TEXT,
        FOREIGN KEY (uid) REFERENCES users (firebase_uid) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_runtime_state (
        singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
        last_active_uid TEXT,
        pending_firebase_signout_uid TEXT,
        operation_generation INTEGER NOT NULL DEFAULT 0 CHECK (operation_generation >= 0)
      )
    ''');
    await db.insert('auth_runtime_state', {
      'singleton_id': 1,
      'operation_generation': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Adds immutable business events and preserves exact legacy collections.
  static Future<void> migrateToV15(DatabaseExecutor db) async {
    await _createBusinessEventsSchema(db);
    final migrationTime = DateTime.now().toUtc().toIso8601String();

    Future<void> insertEvent(Map<String, dynamic> event) async {
      final dto = BusinessEventDto.fromLocal(event);
      final inserted = await db.insert(
        'business_events',
        dto.toLocal(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (inserted == 0) return;
      await db.insert('sync_queue', {
        'operation': 'save_business_event',
        'collection': 'business_events',
        'user_id': dto.userId,
        'doc_id': dto.id,
        'data': jsonEncode(dto.toCloud()),
        'created_at': migrationTime,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_attempt_at': null,
        'last_error': null,
        'status': 'pending',
        'idempotency_key': 'business-event:${dto.userId}:${dto.id}',
        'updated_at': migrationTime,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (final row in await db.query(
      'orders',
      where: 'status = ?',
      whereArgs: ['Delivered'],
    )) {
      final id = row['id'] as String;
      final userId = row['user_id'] as String;
      final orderDate = row['order_date'] as String;
      await insertEvent({
        'id': 'legacy-order-delivery-$id',
        'user_id': userId,
        'subject_type': 'order',
        'subject_id': id,
        'event_type': 'delivery',
        'amount_centavos': null,
        'occurred_at': orderDate,
        'recorded_at': orderDate,
        'payment_method': null,
        'reference': null,
        'related_event_id': null,
        'reason': null,
        'command_id': 'legacy-order-delivery-$id',
        'provenance': 'legacy_inferred',
        'source_type': 'order_delivery',
        'source_id': id,
        'schema_version': 1,
      });

      final linkedDebt = await db.query(
        'debts',
        columns: const ['id'],
        where: 'user_id = ? AND order_id = ?',
        whereArgs: [userId, row['order_id']],
        limit: 1,
      );
      final method = row['payment_method'] as String?;
      final amount = (row['customer_pay_amount_centavos'] as num).toInt();
      if (linkedDebt.isEmpty && method != 'utang' && amount > 0) {
        await insertEvent({
          'id': 'legacy-order-payment-$id',
          'user_id': userId,
          'subject_type': 'order',
          'subject_id': id,
          'event_type': 'payment',
          'amount_centavos': amount,
          'occurred_at': orderDate,
          'recorded_at': orderDate,
          'payment_method': method,
          'reference': row['payment_reference'],
          'related_event_id': null,
          'reason': null,
          'command_id': 'legacy-order-payment-$id',
          'provenance': 'legacy_inferred',
          'source_type': 'order_payment',
          'source_id': id,
          'schema_version': 1,
        });
      }
    }

    final debtPayments = await db.rawQuery('''
      SELECT p.*, d.user_id
      FROM payments p
      INNER JOIN debts d ON d.id = p.debt_id
    ''');
    for (final row in debtPayments) {
      final paymentId = row['id'] as String;
      final userId = row['user_id'] as String;
      final paidAt = row['paid_at'] as String;
      await insertEvent({
        'id': 'legacy-debt-collection-$paymentId',
        'user_id': userId,
        'subject_type': 'debt',
        'subject_id': row['debt_id'],
        'event_type': 'collection',
        'amount_centavos': row['amount_centavos'],
        'occurred_at': paidAt,
        'recorded_at': paidAt,
        'payment_method': row['payment_method'],
        'reference': row['reference'],
        'related_event_id': null,
        'reason': row['note'],
        'command_id': 'legacy-debt-collection-$paymentId',
        'provenance': 'legacy_exact',
        'source_type': 'debt_payment',
        'source_id': paymentId,
        'schema_version': 1,
      });
    }

    final customPayments = await db.rawQuery('''
      SELECT p.*, o.user_id
      FROM custom_order_payments p
      INNER JOIN custom_orders o ON o.id = p.custom_order_id
    ''');
    for (final row in customPayments) {
      final paymentId = row['id'] as String;
      final userId = row['user_id'] as String;
      final paidAt = row['paid_at'] as String;
      await insertEvent({
        'id': 'legacy-custom-collection-$paymentId',
        'user_id': userId,
        'subject_type': 'custom_order',
        'subject_id': row['custom_order_id'],
        'event_type': 'collection',
        'amount_centavos': row['amount_centavos'],
        'occurred_at': paidAt,
        'recorded_at': paidAt,
        'payment_method': null,
        'reference': null,
        'related_event_id': null,
        'reason': row['note'],
        'command_id': 'legacy-custom-collection-$paymentId',
        'provenance': 'legacy_exact',
        'source_type': 'custom_payment',
        'source_id': paymentId,
        'schema_version': 1,
      });
    }

    final customOrders = await db.query('custom_orders');
    for (final row in customOrders) {
      final id = row['id'] as String;
      final paid = (row['deposit_paid_centavos'] as num).toInt();
      final sumRows = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_centavos), 0) AS total '
        'FROM custom_order_payments WHERE custom_order_id = ?',
        [id],
      );
      final attributed = (sumRows.single['total'] as num).toInt();
      final residual = paid - attributed;
      if (residual <= 0) continue;
      final userId = row['user_id'] as String;
      await insertEvent({
        'id': 'legacy-custom-opening-$id',
        'user_id': userId,
        'subject_type': 'custom_order',
        'subject_id': id,
        'event_type': 'collection',
        'amount_centavos': residual,
        'occurred_at': null,
        'recorded_at': row['created_at'],
        'payment_method': null,
        'reference': null,
        'related_event_id': null,
        'reason': 'Legacy unattributed collection',
        'command_id': 'legacy-custom-opening-$id',
        'provenance': 'legacy_unknown',
        'source_type': 'custom_opening_balance',
        'source_id': id,
        'schema_version': 1,
      });
    }
  }

  static Future<void> _createBusinessEventsSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_events (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        subject_type TEXT NOT NULL CHECK (subject_type IN ('order', 'debt', 'custom_order')),
        subject_id TEXT NOT NULL,
        event_type TEXT NOT NULL CHECK (event_type IN ('payment', 'delivery', 'refund', 'reversal', 'collection')),
        amount_centavos INTEGER CHECK (amount_centavos IS NULL OR amount_centavos > 0),
        occurred_at TEXT,
        recorded_at TEXT NOT NULL,
        payment_method TEXT,
        reference TEXT,
        related_event_id TEXT,
        reason TEXT,
        command_id TEXT NOT NULL,
        provenance TEXT NOT NULL CHECK (provenance IN ('native', 'legacy_exact', 'legacy_inferred', 'legacy_unknown')),
        source_type TEXT,
        source_id TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        CHECK (
          (event_type = 'delivery' AND amount_centavos IS NULL)
          OR (event_type != 'delivery' AND amount_centavos > 0)
        ),
        CHECK (
          (event_type = 'collection' AND subject_type IN ('debt', 'custom_order'))
          OR (event_type != 'collection' AND subject_type = 'order')
        ),
        CHECK (
          (event_type = 'reversal' AND related_event_id IS NOT NULL)
          OR (event_type != 'reversal' AND related_event_id IS NULL)
        ),
        CHECK ((source_type IS NULL) = (source_id IS NULL)),
        FOREIGN KEY (related_event_id) REFERENCES business_events (id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_business_events_user_time '
      'ON business_events(user_id, occurred_at, recorded_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_business_events_subject '
      'ON business_events(user_id, subject_type, subject_id, occurred_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_business_events_user_command '
      'ON business_events(user_id, command_id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_business_events_source '
      'ON business_events(user_id, source_type, source_id) '
      'WHERE source_type IS NOT NULL AND source_id IS NOT NULL',
    );
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_business_events_no_update
      BEFORE UPDATE ON business_events
      BEGIN
        SELECT RAISE(ABORT, 'business events are immutable');
      END
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_business_events_no_delete
      BEFORE DELETE ON business_events
      BEGIN
        SELECT RAISE(ABORT, 'business events are immutable');
      END
    ''');
  }

  /// Adds monotonic readable order sequences and reconciles the previous stock
  /// behavior where active cancelled orders still held inventory.
  static Future<void> migrateToV10(DatabaseExecutor db) async {
    final now = DateTime.now().toUtc().toIso8601String();

    Future<void> enqueueSnapshot({
      required String operation,
      required String collection,
      required Object? userId,
      required Object? docId,
      required Map<String, dynamic> data,
    }) async {
      await db.insert('sync_queue', {
        'operation': operation,
        'collection': collection,
        'user_id': userId,
        'doc_id': docId,
        'data': jsonEncode(data),
        'created_at': now,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_attempt_at': null,
        'last_error': null,
        'status': 'pending',
        'idempotency_key': 'migration-v10-$collection-$userId-$docId',
        'updated_at': now,
      });
    }

    await db.execute('''
      INSERT INTO order_sequences(user_id, last_value)
      SELECT user_id,
             COALESCE(MAX(CAST(SUBSTR(order_id, 5) AS INTEGER)), 0)
      FROM orders
      GROUP BY user_id
      ON CONFLICT(user_id) DO UPDATE SET last_value =
        MAX(order_sequences.last_value, excluded.last_value)
    ''');

    await db.execute('''
      UPDATE orders
      SET stock_deducted = CASE WHEN is_deleted = 1 THEN 0 ELSE 1 END,
          stock_released_on_delete = CASE
            WHEN is_deleted = 1 AND LOWER(status) != 'cancelled' THEN 1
            ELSE 0
          END
    ''');

    final cancelledItems = await db.rawQuery('''
      SELECT o.id AS order_pk,
             o.user_id AS user_id,
             oi.product_id AS product_id,
             SUM(oi.quantity) AS quantity
      FROM orders o
      JOIN order_items oi ON oi.order_id = o.id
      WHERE o.is_deleted = 0
        AND LOWER(o.status) = 'cancelled'
        AND o.stock_deducted = 1
      GROUP BY o.id, o.user_id, oi.product_id
    ''');
    final migratedProductKeys = <String>{};
    for (final item in cancelledItems) {
      final productRows = await db.query(
        'products',
        where: 'id = ? AND user_id = ?',
        whereArgs: [item['product_id'], item['user_id']],
        limit: 1,
      );
      if (productRows.length != 1) {
        throw StateError(
          'Cannot reconcile cancelled order ${item['order_pk']}; product '
          '${item['product_id']} is missing.',
        );
      }
      final quantity = (item['quantity'] as num).toInt();
      final changed = await db.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty + ? '
        'WHERE id = ? AND user_id = ?',
        [quantity, item['product_id'], item['user_id']],
      );
      if (changed != 1) {
        throw StateError(
          'Cannot reconcile stock for cancelled order ${item['order_pk']}.',
        );
      }
      final updatedProduct = Map<String, dynamic>.from(productRows.single)
        ..['stock_qty'] =
            (productRows.single['stock_qty'] as num).toInt() + quantity;
      migratedProductKeys.add('${item['user_id']}\u0000${item['product_id']}');
      await db.insert('sync_queue', {
        'operation': 'save_product',
        'collection': 'products',
        'user_id': item['user_id'],
        'doc_id': item['product_id'],
        'data': jsonEncode(updatedProduct),
        'created_at': now,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_attempt_at': null,
        'last_error': null,
        'status': 'pending',
        'idempotency_key':
            'migration-v10-${item['user_id']}-'
            '${item['order_pk']}-${item['product_id']}',
        'updated_at': now,
      });
    }
    await db.execute('''
      UPDATE orders
      SET stock_deducted = 0,
          stock_released_on_delete = 0
      WHERE is_deleted = 0 AND LOWER(status) = 'cancelled'
    ''');

    final orders = await db.query('orders');
    for (final order in orders) {
      final items = await db.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [order['id']],
        orderBy: 'id ASC',
      );
      await enqueueSnapshot(
        operation: 'save_order',
        collection: 'orders',
        userId: order['user_id'],
        docId: order['id'],
        data: {...Map<String, dynamic>.from(order), '_items': items},
      );
    }

    for (final product in await db.query('products')) {
      if (migratedProductKeys.contains(
        '${product['user_id']}\u0000${product['id']}',
      )) {
        continue;
      }
      await enqueueSnapshot(
        operation: 'save_product',
        collection: 'products',
        userId: product['user_id'],
        docId: product['id'],
        data: Map<String, dynamic>.from(product),
      );
    }

    for (final debt in await db.query('debts')) {
      final payments = await db.query(
        'payments',
        where: 'debt_id = ?',
        whereArgs: [debt['id']],
        orderBy: 'paid_at ASC, id ASC',
      );
      await enqueueSnapshot(
        operation: 'save_debt',
        collection: 'debts',
        userId: debt['user_id'],
        docId: debt['id'],
        data: {...Map<String, dynamic>.from(debt), '_payments': payments},
      );
    }

    for (final reseller in await db.query('resellers')) {
      await enqueueSnapshot(
        operation: 'save_reseller',
        collection: 'resellers',
        userId: reseller['user_id'],
        docId: reseller['id'],
        data: Map<String, dynamic>.from(reseller),
      );
    }

    for (final customOrder in await db.query('custom_orders')) {
      await enqueueSnapshot(
        operation: 'save_custom_order',
        collection: 'custom_orders',
        userId: customOrder['user_id'],
        docId: customOrder['id'],
        data: Map<String, dynamic>.from(customOrder),
      );
    }
  }

  /// Rebuilds every money-bearing table with integer-centavo columns. Legacy
  /// debts are replayed in timestamp order; any ambiguous aggregate aborts the
  /// surrounding SQLite upgrade transaction.
  static Future<void> migrateToV11(
    DatabaseExecutor db, {
    DateTime? migrationTimestamp,
  }) async {
    final cutoff = (migrationTimestamp ?? DateTime.now()).toUtc();
    final cutoffText = cutoff.toIso8601String();

    for (final table in [
      'order_items',
      'orders',
      'payments',
      'debts',
      'products',
      'resellers',
      'custom_orders',
    ]) {
      await db.execute('ALTER TABLE $table RENAME TO ${table}_v10');
    }

    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        category TEXT NOT NULL,
        price_centavos INTEGER NOT NULL DEFAULT 0 CHECK (price_centavos >= 0),
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
        total_amount_centavos INTEGER NOT NULL CHECK (total_amount_centavos >= 0),
        srp_total_centavos INTEGER NOT NULL CHECK (srp_total_centavos >= 0),
        status TEXT NOT NULL,
        order_date TEXT NOT NULL,
        notes TEXT,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        payment_method TEXT,
        payment_reference TEXT,
        is_reseller INTEGER NOT NULL DEFAULT 0,
        deduction_per_item_centavos INTEGER NOT NULL DEFAULT 0 CHECK (deduction_per_item_centavos >= 0),
        discounted_total_centavos INTEGER CHECK (discounted_total_centavos >= 0),
        order_type TEXT NOT NULL DEFAULT 'regular',
        stock_deducted INTEGER NOT NULL DEFAULT 1,
        stock_released_on_delete INTEGER NOT NULL DEFAULT 0,
        UNIQUE (user_id, order_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        unit_price_centavos INTEGER NOT NULL CHECK (unit_price_centavos >= 0),
        srp_price_centavos INTEGER CHECK (srp_price_centavos >= 0),
        quantity INTEGER NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        order_id TEXT NOT NULL,
        principal_original_centavos INTEGER NOT NULL CHECK (principal_original_centavos >= 0),
        principal_outstanding_centavos INTEGER NOT NULL CHECK (principal_outstanding_centavos >= 0),
        interest_outstanding_centavos INTEGER NOT NULL DEFAULT 0 CHECK (interest_outstanding_centavos >= 0),
        created_at TEXT NOT NULL,
        user_id TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        interest_rate_basis_points INTEGER NOT NULL DEFAULT 0 CHECK (interest_rate_basis_points >= 0),
        interest_type TEXT NOT NULL DEFAULT 'none',
        interest_start_timestamp TEXT NOT NULL,
        last_accrual_timestamp TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'paid'))
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        debt_id TEXT NOT NULL,
        amount_centavos INTEGER NOT NULL CHECK (amount_centavos > 0),
        interest_applied_centavos INTEGER NOT NULL DEFAULT 0 CHECK (interest_applied_centavos >= 0),
        principal_applied_centavos INTEGER NOT NULL DEFAULT 0 CHECK (principal_applied_centavos >= 0),
        paid_at TEXT NOT NULL,
        payment_method TEXT,
        reference TEXT,
        note TEXT,
        CHECK (amount_centavos = interest_applied_centavos + principal_applied_centavos),
        FOREIGN KEY (debt_id) REFERENCES debts (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE resellers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        contact TEXT,
        deduction_per_item_centavos INTEGER NOT NULL DEFAULT 0 CHECK (deduction_per_item_centavos >= 0),
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE custom_orders (
        id TEXT PRIMARY KEY,
        customer_name TEXT NOT NULL,
        contact TEXT,
        fragrance_specs TEXT NOT NULL,
        agreed_price_centavos INTEGER NOT NULL CHECK (agreed_price_centavos >= 0),
        deposit_paid_centavos INTEGER NOT NULL DEFAULT 0 CHECK (deposit_paid_centavos >= 0),
        delivery_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'Pending',
        terms TEXT,
        user_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');

    for (final row in await db.query('products_v10')) {
      await db.insert('products', {
        'id': row['id'],
        'name': row['name'],
        'description': row['description'],
        'category': row['category'],
        'price_centavos': _legacyCentavos(row['price'], 'products.price'),
        'stock_qty': row['stock_qty'],
        'min_stock_level': row['min_stock_level'],
        'image_path': row['image_path'],
        'created_at': row['created_at'],
        'user_id': row['user_id'],
        'is_deleted': row['is_deleted'],
        'deleted_at': row['deleted_at'],
      });
    }

    for (final order in await db.query('orders_v10')) {
      final legacyItems = await db.query(
        'order_items_v10',
        where: 'order_id = ?',
        whereArgs: [order['id']],
        orderBy: 'id ASC',
      );
      var srpTotal = Money.zero;
      final convertedItems = <Map<String, Object?>>[];
      for (final item in legacyItems) {
        final unit = Money.fromCentavos(
          _legacyCentavos(item['unit_price'], 'order_items.unit_price'),
        );
        final srp = item['srp_price'] == null
            ? unit
            : Money.fromCentavos(
                _legacyCentavos(item['srp_price'], 'order_items.srp_price'),
              );
        srpTotal += srp * (item['quantity'] as num).toInt();
        convertedItems.add({
          'id': item['id'],
          'order_id': item['order_id'],
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'unit_price_centavos': unit.centavos,
          'srp_price_centavos': srp.centavos,
          'quantity': item['quantity'],
        });
      }
      final legacyTotal = Money.fromCentavos(
        _legacyCentavos(order['total_amount'], 'orders.total_amount'),
      );
      final discounted = order['discounted_total'] == null
          ? null
          : Money.fromCentavos(
              _legacyCentavos(
                order['discounted_total'],
                'orders.discounted_total',
              ),
            );
      final isReseller = (order['is_reseller'] as num?)?.toInt() == 1;
      final customerPay = isReseller && discounted != null
          ? discounted
          : legacyTotal;
      if (srpTotal.isZero) srpTotal = legacyTotal;
      await db.insert('orders', {
        'id': order['id'],
        'order_id': order['order_id'],
        'customer_name': order['customer_name'],
        'total_amount_centavos': customerPay.centavos,
        'srp_total_centavos': srpTotal.centavos,
        'status': order['status'],
        'order_date': order['order_date'],
        'notes': order['notes'],
        'user_id': order['user_id'],
        'is_deleted': order['is_deleted'],
        'deleted_at': order['deleted_at'],
        'payment_method': order['payment_method'],
        'payment_reference': order['payment_reference'],
        'is_reseller': order['is_reseller'],
        'deduction_per_item_centavos': _legacyCentavos(
          order['discount_percent'],
          'orders.discount_percent',
        ),
        'discounted_total_centavos': discounted?.centavos,
        'order_type': order['order_type'],
        'stock_deducted': order['stock_deducted'],
        'stock_released_on_delete': order['stock_released_on_delete'],
      });
      for (final item in convertedItems) {
        await db.insert('order_items', item);
      }
    }

    for (final debt in await db.query('debts_v10')) {
      final debtId = debt['id'] as String;
      final legacyPayments = await db.query(
        'payments_v10',
        where: 'debt_id = ?',
        whereArgs: [debtId],
        orderBy: 'paid_at ASC, id ASC',
      );
      final original = Money.fromCentavos(
        _legacyCentavos(debt['total_amount'], 'debts.total_amount'),
      );
      final aggregatePaid = Money.fromCentavos(
        _legacyCentavos(debt['amount_paid'], 'debts.amount_paid'),
      );
      final ledgerPaid = legacyPayments.fold<Money>(Money.zero, (sum, payment) {
        return sum +
            Money.fromCentavos(
              _legacyCentavos(payment['amount'], 'payments.amount'),
            );
      });
      if (aggregatePaid != ledgerPaid) {
        throw StateError(
          'Debt $debtId has amount_paid ${aggregatePaid.centavos} but payment '
          'rows total ${ledgerPaid.centavos} centavos.',
        );
      }
      final createdAt = DateTime.parse(debt['created_at'] as String).toUtc();
      final interestStart = debt['interest_start_date'] == null
          ? createdAt
          : DateTime.parse(debt['interest_start_date'] as String).toUtc();
      final interestType = debt['interest_type'] as String? ?? 'none';
      if (!const {'none', 'daily', 'monthly'}.contains(interestType)) {
        throw StateError(
          'Debt $debtId has invalid interest type $interestType.',
        );
      }
      final rateBasisPoints = _legacyCentavos(
        debt['interest_rate'],
        'debts.interest_rate',
      );
      var principal = original;
      var interest = Money.zero;
      var cursor = interestStart;
      final convertedPayments = <Map<String, Object?>>[];

      void accrueUntil(DateTime target) {
        if (target.isBefore(cursor)) return;
        if (interestType == 'none' ||
            rateBasisPoints == 0 ||
            principal.isZero) {
          cursor = target;
          return;
        }
        final period = interestType == 'daily'
            ? const Duration(days: 1)
            : const Duration(days: 30);
        final periods = target.difference(cursor).inSeconds ~/ period.inSeconds;
        if (periods == 0) return;
        final perPeriod = Money.fromCentavos(
          roundRatioHalfUp(principal.centavos * rateBasisPoints, 10000),
        );
        interest += perPeriod * periods;
        cursor = cursor.add(period * periods);
      }

      for (final payment in legacyPayments) {
        final paidAt = DateTime.parse(payment['paid_at'] as String).toUtc();
        if (paidAt.isAfter(cutoff)) {
          throw StateError('Debt $debtId has a future-dated payment.');
        }
        if (!paidAt.isBefore(interestStart)) accrueUntil(paidAt);
        final amount = Money.fromCentavos(
          _legacyCentavos(payment['amount'], 'payments.amount'),
        );
        if (amount.compareTo(principal + interest) > 0) {
          throw StateError('Debt $debtId contains an overpayment.');
        }
        final interestApplied = amount.min(interest);
        final principalApplied = amount - interestApplied;
        interest -= interestApplied;
        principal -= principalApplied;
        convertedPayments.add({
          'id': payment['id'],
          'debt_id': debtId,
          'amount_centavos': amount.centavos,
          'interest_applied_centavos': interestApplied.centavos,
          'principal_applied_centavos': principalApplied.centavos,
          'paid_at': paidAt.toIso8601String(),
          'payment_method': null,
          'reference': null,
          'note': payment['note'],
        });
      }
      if (cutoff.isBefore(cursor)) {
        throw StateError('Debt $debtId has accrual metadata after migration.');
      }
      accrueUntil(cutoff);
      await db.insert('debts', {
        'id': debtId,
        'customer_name': debt['customer_name'],
        'order_id': debt['order_id'],
        'principal_original_centavos': original.centavos,
        'principal_outstanding_centavos': principal.centavos,
        'interest_outstanding_centavos': interest.centavos,
        'created_at': createdAt.toIso8601String(),
        'user_id': debt['user_id'],
        'is_deleted': debt['is_deleted'],
        'deleted_at': debt['deleted_at'],
        'interest_rate_basis_points': rateBasisPoints,
        'interest_type': interestType,
        'interest_start_timestamp': interestStart.toIso8601String(),
        'last_accrual_timestamp': cursor.toIso8601String(),
        'status': (principal + interest).isZero ? 'paid' : 'open',
      });
      for (final payment in convertedPayments) {
        await db.insert('payments', payment);
      }
    }

    for (final row in await db.query('resellers_v10')) {
      await db.insert('resellers', {
        'id': row['id'],
        'name': row['name'],
        'contact': row['contact'],
        'deduction_per_item_centavos': _legacyCentavos(
          row['discount_percent'],
          'resellers.discount_percent',
        ),
        'user_id': row['user_id'],
        'created_at': row['created_at'],
        'is_deleted': row['is_deleted'],
        'deleted_at': row['deleted_at'],
      });
    }
    for (final row in await db.query('custom_orders_v10')) {
      await db.insert('custom_orders', {
        'id': row['id'],
        'customer_name': row['customer_name'],
        'contact': row['contact'],
        'fragrance_specs': row['fragrance_specs'],
        'agreed_price_centavos': _legacyCentavos(
          row['agreed_price'],
          'custom_orders.agreed_price',
        ),
        'deposit_paid_centavos': _legacyCentavos(
          row['deposit_paid'],
          'custom_orders.deposit_paid',
        ),
        'delivery_date': row['delivery_date'],
        'status': row['status'],
        'terms': row['terms'],
        'user_id': row['user_id'],
        'created_at': row['created_at'],
        'is_deleted': row['is_deleted'],
        'deleted_at': row['deleted_at'],
      });
    }

    for (final table in [
      'order_items_v10',
      'orders_v10',
      'payments_v10',
      'debts_v10',
      'products_v10',
      'resellers_v10',
      'custom_orders_v10',
    ]) {
      await db.execute('DROP TABLE $table');
    }

    Future<void> enqueueSnapshot(
      String operation,
      String collection,
      Map<String, Object?> row, {
      List<Map<String, Object?>>? children,
      String? childrenKey,
    }) async {
      final payload = Map<String, dynamic>.from(row);
      if (children != null && childrenKey != null) {
        payload[childrenKey] = children;
      }
      await db.insert('sync_queue', {
        'operation': operation,
        'collection': collection,
        'user_id': row['user_id'],
        'doc_id': row['id'],
        'data': jsonEncode(payload),
        'created_at': cutoffText,
        'attempt_count': 0,
        'next_attempt_at': null,
        'last_attempt_at': null,
        'last_error': null,
        'status': 'pending',
        'idempotency_key':
            'migration-v11-$collection-${row['user_id']}-${row['id']}',
        'updated_at': cutoffText,
      });
    }

    for (final row in await db.query('products')) {
      await enqueueSnapshot('save_product', 'products', row);
    }
    for (final row in await db.query('orders')) {
      await enqueueSnapshot(
        'save_order',
        'orders',
        row,
        children: await db.query(
          'order_items',
          where: 'order_id = ?',
          whereArgs: [row['id']],
          orderBy: 'id ASC',
        ),
        childrenKey: '_items',
      );
    }
    for (final row in await db.query('debts')) {
      await enqueueSnapshot(
        'save_debt',
        'debts',
        row,
        children: await db.query(
          'payments',
          where: 'debt_id = ?',
          whereArgs: [row['id']],
          orderBy: 'paid_at ASC, id ASC',
        ),
        childrenKey: '_payments',
      );
    }
    for (final row in await db.query('resellers')) {
      await enqueueSnapshot('save_reseller', 'resellers', row);
    }
    for (final row in await db.query('custom_orders')) {
      await enqueueSnapshot('save_custom_order', 'custom_orders', row);
    }
  }

  static int _legacyCentavos(Object? value, String field) {
    if (value is! num || !value.isFinite) {
      throw StateError('$field contains a non-finite or missing value: $value');
    }
    final money = Money.fromLegacyNumber(value);
    if (money.isNegative) {
      throw StateError('$field contains a negative value: $value');
    }
    return money.centavos;
  }

  static Future<void> migrateToV12(DatabaseExecutor db) async {
    for (final table in [
      'products',
      'orders',
      'order_items',
      'debts',
      'payments',
      'resellers',
      'custom_orders',
    ]) {
      await _addColumnIfMissing(
        db,
        table,
        'schema_version',
        'schema_version INTEGER NOT NULL DEFAULT 1',
      );
    }
    await _addColumnIfMissing(
      db,
      'orders',
      'customer_pay_amount_centavos',
      'customer_pay_amount_centavos INTEGER NOT NULL DEFAULT 0 '
          'CHECK (customer_pay_amount_centavos >= 0)',
    );
    await db.execute('''
      UPDATE orders
      SET customer_pay_amount_centavos =
        COALESCE(discounted_total_centavos, total_amount_centavos)
    ''');

    final duplicateOutboxKeys = await db.rawQuery('''
      SELECT idempotency_key, COUNT(*) AS duplicate_count
      FROM sync_queue
      GROUP BY idempotency_key
      HAVING idempotency_key IS NULL
         OR idempotency_key = ''
         OR COUNT(*) > 1
      LIMIT 5
    ''');
    if (duplicateOutboxKeys.isNotEmpty) {
      throw StateError(
        'Cannot enforce durable outbox uniqueness; invalid keys require repair: '
        '$duplicateOutboxKeys',
      );
    }
    await db.execute('ALTER TABLE sync_queue RENAME TO sync_queue_v11');
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation TEXT NOT NULL,
        collection TEXT NOT NULL,
        user_id TEXT NOT NULL,
        doc_id TEXT NOT NULL,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT,
        last_attempt_at TEXT,
        last_error TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        idempotency_key TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT INTO sync_queue(
        id, operation, collection, user_id, doc_id, data, created_at,
        attempt_count, next_attempt_at, last_attempt_at, last_error, status,
        idempotency_key, updated_at
      )
      SELECT
        id, operation, collection, user_id, doc_id, data, created_at,
        attempt_count, next_attempt_at, last_attempt_at, last_error, status,
        idempotency_key, updated_at
      FROM sync_queue_v11
    ''');
    await db.execute('DROP TABLE sync_queue_v11');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_order_payments (
        id TEXT PRIMARY KEY,
        custom_order_id TEXT NOT NULL,
        amount_centavos INTEGER NOT NULL CHECK (amount_centavos > 0),
        paid_at TEXT NOT NULL,
        note TEXT,
        schema_version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (custom_order_id) REFERENCES custom_orders (id) ON DELETE CASCADE
      )
    ''');

    final logColumns = await db.rawQuery('PRAGMA table_info(activity_logs)');
    if (logColumns.isEmpty) {
      throw StateError('Required table "activity_logs" is missing.');
    }
    final logId = logColumns.firstWhere((row) => row['name'] == 'id');
    if ((logId['type'] as String).toUpperCase() != 'TEXT') {
      await db.execute('''
        CREATE TABLE activity_logs_v12 (
          id TEXT PRIMARY KEY,
          message TEXT NOT NULL,
          type TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          user_id TEXT NOT NULL,
          schema_version INTEGER NOT NULL DEFAULT 1
        )
      ''');
      await db.execute('''
        INSERT INTO activity_logs_v12(
          id, message, type, timestamp, user_id, schema_version
        )
        SELECT CAST(id AS TEXT), message, type, timestamp, user_id, 1
        FROM activity_logs
      ''');
      await db.execute('DROP TABLE activity_logs');
      await db.execute('ALTER TABLE activity_logs_v12 RENAME TO activity_logs');
    } else {
      await _addColumnIfMissing(
        db,
        'activity_logs',
        'schema_version',
        'schema_version INTEGER NOT NULL DEFAULT 1',
      );
    }

    final duplicateDebtOrders = await db.rawQuery('''
      SELECT user_id, order_id, COUNT(*) AS duplicate_count
      FROM debts
      GROUP BY user_id, order_id
      HAVING COUNT(*) > 1
      LIMIT 5
    ''');
    if (duplicateDebtOrders.isNotEmpty) {
      throw StateError(
        'Cannot migrate to v12 with duplicate debt/order associations: '
        '$duplicateDebtOrders',
      );
    }

    final now = DateTime.now().toUtc().toIso8601String();
    Future<void> enqueue(
      String operation,
      String collection,
      String userId,
      String docId,
      Map<String, dynamic> data,
    ) => db.insert('sync_queue', {
      'operation': operation,
      'collection': collection,
      'user_id': userId,
      'doc_id': docId,
      'data': jsonEncode(data),
      'created_at': now,
      'attempt_count': 0,
      'next_attempt_at': null,
      'last_attempt_at': null,
      'last_error': null,
      'status': 'pending',
      'idempotency_key': 'migration-v12-$collection-$userId-$docId',
      'updated_at': now,
    });

    for (final row in await db.query('products')) {
      final dto = ProductDto.fromLocal(Map<String, dynamic>.from(row));
      await enqueue(
        'save_product',
        'products',
        dto.userId,
        dto.id,
        dto.toCloud(),
      );
    }
    for (final row in await db.query('orders')) {
      final items = await db.query(
        'order_items',
        where: 'order_id = ?',
        whereArgs: [row['id']],
        orderBy: 'id ASC',
      );
      final dto = OrderDto.fromLocal(
        Map<String, dynamic>.from(row),
        items.map(Map<String, dynamic>.from).toList(),
      );
      final payload = dto.toCloud();
      payload['_items'] = payload.remove('items');
      await db.update(
        'sync_queue',
        {
          'operation': 'save_order',
          'data': jsonEncode(payload),
          'updated_at': now,
        },
        where: 'doc_id = ? AND operation = ?',
        whereArgs: [dto.id, 'update_order_status'],
      );
      await enqueue('save_order', 'orders', dto.userId, dto.id, payload);
    }
    for (final row in await db.query('debts')) {
      final payments = await db.query(
        'payments',
        where: 'debt_id = ?',
        whereArgs: [row['id']],
        orderBy: 'paid_at ASC, id ASC',
      );
      final dto = DebtDto.fromLocal(
        Map<String, dynamic>.from(row),
        payments.map(Map<String, dynamic>.from).toList(),
      );
      final payload = dto.toCloud();
      payload['_payments'] = payload.remove('payments');
      await db.update(
        'sync_queue',
        {
          'operation': 'save_debt',
          'data': jsonEncode(payload),
          'updated_at': now,
        },
        where: 'doc_id = ? AND operation = ?',
        whereArgs: [dto.id, 'update_debt_payment'],
      );
      await enqueue('save_debt', 'debts', dto.userId, dto.id, payload);
    }
    for (final row in await db.query('resellers')) {
      final dto = ResellerDto.fromLocal(Map<String, dynamic>.from(row));
      await enqueue(
        'save_reseller',
        'resellers',
        dto.userId,
        dto.id,
        dto.toCloud(),
      );
    }
    for (final row in await db.query('custom_orders')) {
      final payments = await db.query(
        'custom_order_payments',
        where: 'custom_order_id = ?',
        whereArgs: [row['id']],
        orderBy: 'paid_at ASC, id ASC',
      );
      final dto = CustomOrderDto.fromLocal(
        Map<String, dynamic>.from(row),
        payments.map(Map<String, dynamic>.from).toList(),
      );
      final payload = dto.toCloud();
      payload['_payments'] = payload.remove('payments');
      await enqueue(
        'save_custom_order',
        'custom_orders',
        dto.userId,
        dto.id,
        payload,
      );
    }
    for (final row in await db.query('activity_logs')) {
      final dto = ActivityLogDto.fromLocal(Map<String, dynamic>.from(row));
      await enqueue(
        'save_log',
        'activity_logs',
        dto.userId,
        dto.id,
        dto.toCloud(),
      );
    }
  }

  /// Adds local per-user order-command replay protection. Legacy rows remain
  /// nullable because no historical command identity can be inferred safely.
  static Future<void> migrateToV13(DatabaseExecutor db) async {
    await _addColumnIfMissing(db, 'orders', 'command_id', 'command_id TEXT');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_user_command_id '
      'ON orders(user_id, command_id) WHERE command_id IS NOT NULL',
    );
  }

  /// Creates the current schema in an isolated test database.
  static Future<void> createSchemaForTesting(Database db) =>
      _onCreate(db, schemaVersion);

  /// Runs the production upgrade callback against a migration fixture.
  static Future<void> upgradeSchemaForTesting(
    Database db,
    int oldVersion,
    int newVersion,
  ) => db.transaction((txn) => _upgrade(txn, oldVersion, newVersion));

  static Future<Database> openDatabaseForTesting(
    String path, {
    DatabaseFactory? factory,
  }) => (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    ),
  );

  /// Removes device-side password authority while preserving every profile and
  /// leaving all legacy business partitions quarantined under their old owner key.
  static Future<void> migrateUsersToV9(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(users)');
    if (columns.isEmpty) throw StateError('Required table "users" is missing.');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('password') && names.contains('firebase_uid')) return;

    await db.execute('''
      CREATE TABLE users_v9 (
        id TEXT PRIMARY KEY,
        firebase_uid TEXT UNIQUE,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'Staff',
        account_status TEXT NOT NULL DEFAULT 'pending',
        is_active INTEGER NOT NULL DEFAULT 0,
        legacy_owner_key TEXT,
        migration_state TEXT NOT NULL DEFAULT 'unmapped',
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    final users = await db.query('users');
    for (final user in users) {
      final username = (user['username'] as String).trim().toLowerCase();
      await db.insert('users_v9', {
        'id': user['id'],
        'firebase_uid': null,
        'username': username,
        'name': user['name'],
        'email': (user['email'] as String? ?? '').trim().toLowerCase(),
        'role': user['role'] ?? 'Staff',
        'account_status': 'pending',
        'is_active': 0,
        'legacy_owner_key': username,
        'migration_state': 'unmapped',
        'is_synced': user['is_synced'] ?? 0,
        'created_at': user['created_at'],
      });
    }

    await db.execute('DROP TABLE users');
    await db.execute('ALTER TABLE users_v9 RENAME TO users');
    await db.execute(
      'CREATE UNIQUE INDEX idx_users_firebase_uid ON users(firebase_uid) '
      'WHERE firebase_uid IS NOT NULL',
    );

    final queued = await db.query('sync_queue', columns: ['id', 'data']);
    for (final row in queued) {
      final raw = row['data'] as String;
      try {
        final decoded = jsonDecode(raw);
        final scrubbed = _scrubCredentialFields(decoded);
        final encoded = jsonEncode(scrubbed);
        if (encoded != raw) {
          await db.update(
            'sync_queue',
            {'data': encoded},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      } on FormatException {
        throw StateError('Sync queue row ${row['id']} contains invalid JSON.');
      }
    }
  }

  static dynamic _scrubCredentialFields(dynamic value) {
    const forbidden = {
      'password',
      'passwordHash',
      'password_hash',
      'salt',
      'verifier',
    };
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!forbidden.contains(entry.key))
            entry.key.toString(): _scrubCredentialFields(entry.value),
      };
    }
    if (value is List) return value.map(_scrubCredentialFields).toList();
    return value;
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.isEmpty) {
      throw StateError('Required table "$table" is missing.');
    }
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) await db.execute('ALTER TABLE $table ADD COLUMN $definition');
  }

  static Future<void> _verifySchema(DatabaseExecutor db) async {
    final requiredColumns = <String, Set<String>>{
      'users': {
        'id',
        'firebase_uid',
        'username',
        'name',
        'email',
        'role',
        'account_status',
        'is_active',
        'legacy_owner_key',
        'migration_state',
      },
      'orders': {
        'id',
        'order_id',
        'user_id',
        'is_deleted',
        'payment_method',
        'is_reseller',
        'total_amount_centavos',
        'srp_total_centavos',
        'deduction_per_item_centavos',
        'discounted_total_centavos',
        'customer_pay_amount_centavos',
        'order_type',
        'stock_deducted',
        'stock_released_on_delete',
        'command_id',
        'schema_version',
        'revision',
        'base_revision',
        'updated_at',
        'writer_device_id',
        'tombstone_revision',
        'purge_state',
        'number_state',
        'provisional_order_id',
      },
      'order_items': {
        'id',
        'order_id',
        'product_id',
        'unit_price_centavos',
        'srp_price_centavos',
        'schema_version',
      },
      'products': {
        'id',
        'user_id',
        'price_centavos',
        'image_path',
        'schema_version',
        'revision',
        'base_revision',
        'updated_at',
        'writer_device_id',
        'tombstone_revision',
        'purge_state',
      },
      'debts': {
        'id',
        'order_id',
        'user_id',
        'is_deleted',
        'principal_original_centavos',
        'principal_outstanding_centavos',
        'interest_outstanding_centavos',
        'interest_rate_basis_points',
        'interest_type',
        'interest_start_timestamp',
        'last_accrual_timestamp',
        'due_date',
        'status',
        'schema_version',
        'revision',
        'base_revision',
        'updated_at',
        'writer_device_id',
        'tombstone_revision',
        'purge_state',
      },
      'payments': {
        'id',
        'debt_id',
        'amount_centavos',
        'interest_applied_centavos',
        'principal_applied_centavos',
        'paid_at',
        'payment_method',
        'reference',
        'note',
        'schema_version',
      },
      'sync_queue': {
        'id',
        'operation',
        'user_id',
        'doc_id',
        'data',
        'created_at',
        'attempt_count',
        'next_attempt_at',
        'last_attempt_at',
        'last_error',
        'status',
        'idempotency_key',
        'updated_at',
        'operation_id',
        'aggregate_key',
        'expected_revision',
        'resulting_revision',
        'device_id',
        'error_class',
        'conflict_id',
      },
      'order_sequences': {'user_id', 'last_value'},
      'resellers': {
        'id',
        'user_id',
        'is_deleted',
        'deleted_at',
        'deduction_per_item_centavos',
        'schema_version',
        'revision',
        'base_revision',
        'updated_at',
        'writer_device_id',
        'tombstone_revision',
        'purge_state',
      },
      'custom_orders': {
        'id',
        'user_id',
        'is_deleted',
        'deleted_at',
        'agreed_price_centavos',
        'deposit_paid_centavos',
        'schema_version',
        'revision',
        'base_revision',
        'updated_at',
        'writer_device_id',
        'tombstone_revision',
        'purge_state',
      },
      'custom_order_payments': {
        'id',
        'custom_order_id',
        'amount_centavos',
        'paid_at',
        'note',
        'schema_version',
      },
      'business_events': {
        'id',
        'user_id',
        'subject_type',
        'subject_id',
        'event_type',
        'amount_centavos',
        'occurred_at',
        'recorded_at',
        'payment_method',
        'reference',
        'related_event_id',
        'reason',
        'command_id',
        'provenance',
        'source_type',
        'source_id',
        'schema_version',
      },
      'activity_logs': {
        'id',
        'message',
        'type',
        'timestamp',
        'user_id',
        'schema_version',
      },
      'device_auth_grants': {
        'uid',
        'state',
        'generation',
        'enrolled_at',
        'last_verified_at',
        'access_generation',
        'profile_digest',
        'revoked_at',
        'revocation_reason',
      },
      'auth_runtime_state': {
        'singleton_id',
        'last_active_uid',
        'pending_firebase_signout_uid',
        'operation_generation',
      },
      'device_identity': {'singleton_id', 'device_id', 'created_at'},
      'sync_conflicts': {
        'id',
        'user_id',
        'collection',
        'doc_id',
        'aggregate_key',
        'local_revision',
        'remote_revision',
        'local_data',
        'remote_data',
        'reason',
        'status',
        'created_at',
        'resolved_at',
      },
      'sync_cursors': {'user_id', 'collection', 'cursor_value', 'updated_at'},
      'dead_letters': {
        'id',
        'queue_row_id',
        'user_id',
        'operation',
        'aggregate_key',
        'payload',
        'error_class',
        'last_error',
        'attempt_count',
        'created_at',
        'resolved_at',
      },
    };

    for (final entry in requiredColumns.entries) {
      final rows = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final actual = rows.map((row) => row['name'] as String).toSet();
      final missing = entry.value.difference(actual);
      if (missing.isNotEmpty) {
        throw StateError(
          'Database schema verification failed for ${entry.key}; '
          'missing columns: $missing',
        );
      }
    }

    final requiredTypes = <String, Map<String, String>>{
      'activity_logs': {'id': 'TEXT', 'schema_version': 'INTEGER'},
      'products': {'price_centavos': 'INTEGER', 'schema_version': 'INTEGER'},
      'orders': {
        'total_amount_centavos': 'INTEGER',
        'customer_pay_amount_centavos': 'INTEGER',
        'schema_version': 'INTEGER',
      },
      'debts': {
        'principal_original_centavos': 'INTEGER',
        'interest_outstanding_centavos': 'INTEGER',
        'schema_version': 'INTEGER',
      },
      'payments': {'amount_centavos': 'INTEGER', 'schema_version': 'INTEGER'},
      'custom_order_payments': {
        'amount_centavos': 'INTEGER',
        'schema_version': 'INTEGER',
      },
      'business_events': {
        'amount_centavos': 'INTEGER',
        'schema_version': 'INTEGER',
      },
    };
    for (final entry in requiredTypes.entries) {
      final rows = await db.rawQuery('PRAGMA table_info(${entry.key})');
      final actual = {
        for (final row in rows)
          row['name'] as String: (row['type'] as String).toUpperCase(),
      };
      for (final expected in entry.value.entries) {
        if (actual[expected.key] != expected.value) {
          throw StateError(
            'Database type verification failed for ${entry.key}.'
            '${expected.key}; expected ${expected.value}, '
            'found ${actual[expected.key]}.',
          );
        }
      }
    }

    final queueColumns = await db.rawQuery('PRAGMA table_info(sync_queue)');
    for (final column in const ['idempotency_key', 'updated_at', 'status']) {
      final row = queueColumns.firstWhere((entry) => entry['name'] == column);
      if (row['notnull'] != 1) {
        throw StateError('sync_queue.$column must be NOT NULL.');
      }
    }

    final orderIndexes = await db.rawQuery('PRAGMA index_list(orders)');
    final hasUniqueOrderId = orderIndexes.any(
      (row) => row['name'] == 'idx_orders_user_order_id' && row['unique'] == 1,
    );
    if (!hasUniqueOrderId) {
      throw StateError('Unique per-user order ID index is missing.');
    }
    final hasUniqueOrderCommand = orderIndexes.any(
      (row) =>
          row['name'] == 'idx_orders_user_command_id' &&
          row['unique'] == 1 &&
          row['partial'] == 1,
    );
    if (!hasUniqueOrderCommand) {
      throw StateError('Unique per-user order command index is missing.');
    }
    final orderCommandIndexColumns = await db.rawQuery(
      'PRAGMA index_info(idx_orders_user_command_id)',
    );
    final orderCommandColumnNames = orderCommandIndexColumns
        .map((row) => row['name'])
        .toList(growable: false);
    if (orderCommandColumnNames.length != 2 ||
        orderCommandColumnNames[0] != 'user_id' ||
        orderCommandColumnNames[1] != 'command_id') {
      throw StateError(
        'Order command uniqueness must be scoped to user_id and command_id.',
      );
    }

    final debtIndexes = await db.rawQuery('PRAGMA index_list(debts)');
    final hasUniqueDebtOrder = debtIndexes.any(
      (row) => row['name'] == 'idx_debts_user_order_id' && row['unique'] == 1,
    );
    if (!hasUniqueDebtOrder) {
      throw StateError('Unique per-user debt/order index is missing.');
    }
    final queueIndexes = await db.rawQuery('PRAGMA index_list(sync_queue)');
    final hasUniqueIdempotency = queueIndexes.any(
      (row) =>
          row['name'] == 'idx_sync_queue_idempotency' && row['unique'] == 1,
    );
    if (!hasUniqueIdempotency) {
      throw StateError('Unique outbox idempotency index is missing.');
    }

    final requiredIndexes = <String, Set<String>>{
      'products': {'idx_products_user'},
      'orders': {
        'idx_orders_user',
        'idx_orders_user_order_id',
        'idx_orders_user_command_id',
      },
      'order_items': {'idx_order_items_order'},
      'debts': {'idx_debts_user', 'idx_debts_user_order_id'},
      'payments': {'idx_payments_debt'},
      'activity_logs': {'idx_logs_user'},
      'resellers': {'idx_resellers_user'},
      'custom_orders': {'idx_custom_orders_user'},
      'custom_order_payments': {'idx_custom_order_payments_order'},
      'business_events': {
        'idx_business_events_user_time',
        'idx_business_events_subject',
        'idx_business_events_user_command',
        'idx_business_events_source',
      },
      'sync_queue': {
        'idx_sync_queue_due',
        'idx_sync_queue_status',
        'idx_sync_queue_idempotency',
      },
    };
    for (final entry in requiredIndexes.entries) {
      final indexes = await db.rawQuery('PRAGMA index_list(${entry.key})');
      final names = indexes.map((row) => row['name'] as String).toSet();
      final missing = entry.value.difference(names);
      if (missing.isNotEmpty) {
        throw StateError(
          'Database schema verification failed for ${entry.key}; '
          'missing indexes: $missing',
        );
      }
    }

    final expectedForeignKeys = <String, Map<String, String>>{
      'order_items': {'table': 'orders', 'from': 'order_id', 'to': 'id'},
      'payments': {'table': 'debts', 'from': 'debt_id', 'to': 'id'},
      'custom_order_payments': {
        'table': 'custom_orders',
        'from': 'custom_order_id',
        'to': 'id',
      },
    };
    for (final entry in expectedForeignKeys.entries) {
      final foreignKeys = await db.rawQuery(
        'PRAGMA foreign_key_list(${entry.key})',
      );
      final expected = entry.value;
      final found = foreignKeys.any(
        (row) =>
            row['table'] == expected['table'] &&
            row['from'] == expected['from'] &&
            row['to'] == expected['to'] &&
            (row['on_delete'] as String).toUpperCase() == 'CASCADE',
      );
      if (!found) {
        throw StateError(
          'Required foreign key is missing from ${entry.key}: $expected',
        );
      }
    }
    final foreignKeyViolations = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyViolations.isNotEmpty) {
      throw StateError(
        'Database foreign-key verification failed: $foreignKeyViolations',
      );
    }
  }
}
