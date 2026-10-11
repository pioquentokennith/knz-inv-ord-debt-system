import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/dto/debt_dto.dart';
import 'package:knz_scent_admin/dto/custom_order_dto.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/repositories/local_order_repository.dart';
import 'package:knz_scent_admin/repositories/local_debt_repository.dart';
import 'package:knz_scent_admin/repositories/local_custom_order_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Counter {
  int queries = 0;
}

class _Executor extends Fake implements DatabaseExecutor {
  _Executor(this.delegate, this.counter);
  final DatabaseExecutor delegate;
  final _Counter counter;
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    counter.queries++;
    return delegate.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }
}

class _Transaction extends _Executor implements Transaction {
  _Transaction(super.delegate, super.counter);
}

class _Database extends _Executor implements Database {
  _Database(Database super.delegate, super.counter);
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => (delegate as Database).transaction(
    (txn) => action(_Transaction(txn, counter)),
    exclusive: exclusive,
  );
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late _Database counted;
  final counter = _Counter();
  const count = 405; // Exercise both sides of the 400-ID parameter boundary.
  final start = DateTime.utc(2026);
  setUpAll(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchemaForTesting(db);
    counted = _Database(db, counter);
    final batch = db.batch();
    for (var i = 0; i < count + 2; i++) {
      final owner = i == count + 1 ? 'other' : 'u';
      final deleted = i == count ? 1 : 0;
      final date = start.add(Duration(seconds: i));
      final order = OrderDto.fromDomain(
        Order(
          id: 'o$i',
          orderId: 'KNZ-$i',
          customerName: 'Customer $i',
          totalAmount: const Money.fromCentavos(300),
          status: OrderStatus.pending,
          orderDate: date,
          items: [
            for (final j in [2, 1])
              OrderItem(
                id: 'o$i-item$j',
                productId: 'p',
                productName: 'Rose',
                unitPrice: const Money.fromCentavos(100),
                quantity: j,
              ),
          ],
        ),
        userId: owner,
      );
      batch.insert('orders', {...order.toLocal(), 'is_deleted': deleted});
      for (final item in order.items) {
        batch.insert('order_items', item.toLocal());
      }
      final debt = DebtDto.fromDomain(
        CustomerDebt(
          id: 'd$i',
          customerName: 'Customer $i',
          orderId: 'KNZ-$i',
          principalOriginal: const Money.fromCentavos(1000),
          principalOutstanding: const Money.fromCentavos(800),
          createdAt: date,
          payments: [
            for (final j in [2, 1])
              PaymentRecord(
                id: 'd$i-pay$j',
                amount: const Money.fromCentavos(100),
                principalApplied: const Money.fromCentavos(100),
                paidAt: date,
              ),
          ],
        ),
        userId: owner,
      );
      batch.insert('debts', {...debt.toLocal(), 'is_deleted': deleted});
      for (final payment in debt.payments) {
        batch.insert('payments', payment.toLocal());
      }
      final custom = CustomOrderDto.fromDomain(
        CustomOrder(
          id: 'c$i',
          customerName: 'Customer $i',
          fragranceSpecs: 'Rose',
          agreedPrice: const Money.fromCentavos(1000),
          depositPaid: const Money.fromCentavos(200),
          userId: owner,
          createdAt: date,
          deliveryDate: DateTime.utc(2027),
          payments: [
            for (final j in [2, 1])
              CustomOrderPayment(
                id: 'c$i-pay$j',
                customOrderId: 'c$i',
                amount: const Money.fromCentavos(100),
                paidAt: date,
              ),
          ],
        ),
      );
      batch.insert('custom_orders', {
        ...custom.toLocal(),
        'is_deleted': deleted,
      });
      for (final payment in custom.payments) {
        batch.insert('custom_order_payments', payment.toLocal());
      }
    }
    await batch.commit(noResult: true);
  });
  tearDownAll(() => db.close());
  setUp(() => counter.queries = 0);

  // Reference implementations reproduce the pre-optimization SELECT patterns.
  Future<List<Order>> oldOrders({
    String owner = 'u',
    bool deleted = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await counted.query(
      'orders',
      where:
          'user_id = ? AND is_deleted = ?'
          '${from == null ? '' : ' AND order_date >= ?'}${to == null ? '' : ' AND order_date <= ?'}',
      whereArgs: [
        owner,
        deleted ? 1 : 0,
        if (from != null) from.toIso8601String(),
        if (to != null) to.toIso8601String(),
      ],
      orderBy: 'order_date DESC',
    );
    return [
      for (final row in rows)
        OrderDto.fromLocal(
          Map<String, dynamic>.from(row),
          (await counted.query(
            'order_items',
            where: 'order_id = ?',
            whereArgs: [row['id']],
            orderBy: 'id ASC',
          )).map(Map<String, dynamic>.from).toList(),
        ).toDomain(),
    ];
  }

  Future<List<CustomerDebt>> debtRows(
    DatabaseExecutor executor, {
    String owner = 'u',
    bool deleted = false,
  }) async {
    final ids = await executor.query(
      'debts',
      columns: ['id'],
      where: 'user_id = ? AND is_deleted = ?',
      whereArgs: [owner, deleted ? 1 : 0],
      orderBy: 'created_at DESC',
    );
    final result = <CustomerDebt>[];
    for (final id in ids) {
      final row = (await executor.query(
        'debts',
        where: 'id = ? AND is_deleted = ?',
        whereArgs: [id['id'], deleted ? 1 : 0],
        limit: 1,
      )).single;
      final payments = await executor.query(
        'payments',
        where: 'debt_id = ?',
        whereArgs: [id['id']],
        orderBy: 'paid_at ASC, id ASC',
      );
      result.add(
        DebtDto.fromLocal(
          Map<String, dynamic>.from(row),
          payments.map(Map<String, dynamic>.from).toList(),
        ).toDomain(),
      );
    }
    return result;
  }

  Future<List<CustomOrder>> oldCustoms({bool deleted = false}) async {
    final rows = await counted.query(
      'custom_orders',
      where: 'user_id = ? AND is_deleted = ?',
      whereArgs: ['u', deleted ? 1 : 0],
      orderBy: 'created_at DESC',
    );
    return [
      for (final row in rows)
        CustomOrderDto.fromLocal(
          Map<String, dynamic>.from(row),
          (await counted.query(
            'custom_order_payments',
            where: 'custom_order_id = ?',
            whereArgs: [row['id']],
            orderBy: 'paid_at ASC, id ASC',
          )).map(Map<String, dynamic>.from).toList(),
        ).toDomain(),
    ];
  }

  test('405 orders match legacy results using 3 reads instead of 406', () async {
    final watch = Stopwatch()..start();
    final before = await oldOrders();
    final beforeUs = watch.elapsedMicroseconds;
    expect(counter.queries, 406);
    counter.queries = 0;
    watch.reset();
    final after = await LocalOrderRepository(
      databaseProvider: () async => counted,
    ).getAll('u');
    final afterUs = watch.elapsedMicroseconds;
    watch.stop();
    expect(counter.queries, 3);
    expect(
      after.map((o) => OrderDto.fromDomain(o, userId: 'u').toCloud()).toList(),
      before.map((o) => OrderDto.fromDomain(o, userId: 'u').toCloud()).toList(),
    );
    expect(after, hasLength(count));
    expect(after.first.items.map((item) => item.id), [
      'o404-item1',
      'o404-item2',
    ]);
    // Test-only timing: descriptive, never a flaky wall-clock assertion.
    // ignore: avoid_print
    print(
      'orders/$count: before=${beforeUs}us/406 reads after=${afterUs}us/3 reads',
    );
  });
  test(
    '405 no-interest debts match legacy results using 3 reads instead of 1622',
    () async {
      final watch = Stopwatch()..start();
      await counted.transaction((txn) async {
        await debtRows(txn);
      });
      final before = await debtRows(counted);
      final beforeUs = watch.elapsedMicroseconds;
      expect(counter.queries, 1622);
      counter.queries = 0;
      watch.reset();
      final after = await LocalDebtRepository(
        databaseProvider: () async => counted,
        now: () => start,
      ).getAll('u');
      final afterUs = watch.elapsedMicroseconds;
      watch.stop();
      expect(counter.queries, 3);
      expect(
        after.map((d) => DebtDto.fromDomain(d, userId: 'u').toCloud()).toList(),
        before
            .map((d) => DebtDto.fromDomain(d, userId: 'u').toCloud())
            .toList(),
      );
      expect(after.first.payments.map((p) => p.id), ['d404-pay1', 'd404-pay2']);
      // ignore: avoid_print
      print(
        'debts/$count: before=${beforeUs}us/1622 reads after=${afterUs}us/3 reads',
      );
    },
  );
  test(
    '405 custom orders match legacy results using 3 reads instead of 406',
    () async {
      final watch = Stopwatch()..start();
      final before = await oldCustoms();
      final beforeUs = watch.elapsedMicroseconds;
      expect(counter.queries, 406);
      counter.queries = 0;
      watch.reset();
      final after = await LocalCustomOrderRepository(
        databaseProvider: () async => counted,
      ).getAll('u');
      final afterUs = watch.elapsedMicroseconds;
      watch.stop();
      expect(counter.queries, 3);
      expect(
        after.map((o) => CustomOrderDto.fromDomain(o).toCloud()).toList(),
        before.map((o) => CustomOrderDto.fromDomain(o).toCloud()).toList(),
      );
      // ignore: avoid_print
      print(
        'customs/$count: before=${beforeUs}us/406 reads after=${afterUs}us/3 reads',
      );
    },
  );
  test(
    'date filters, archive partitions, other owners and empty results are preserved',
    () async {
      final orders = LocalOrderRepository(
        databaseProvider: () async => counted,
      );
      final from = start.add(const Duration(seconds: 10));
      final to = start.add(const Duration(seconds: 15));
      final expected = await oldOrders(from: from, to: to);
      final actual = await orders.getAll('u', fromDate: from, toDate: to);
      expect(actual.map((o) => o.id), expected.map((o) => o.id));
      expect((await orders.getDeleted('u')).single.id, 'o405');
      expect((await orders.getAll('other')).single.id, 'o406');
      final debts = LocalDebtRepository(
        databaseProvider: () async => counted,
        now: () => start,
      );
      expect((await debts.getDeleted('u')).single.id, 'd405');
      expect((await debts.getAll('other')).single.id, 'd406');
      final customs = LocalCustomOrderRepository(
        databaseProvider: () async => counted,
      );
      expect((await customs.getDeleted('u')).single.id, 'c405');
      expect((await customs.getAll('other')).single.id, 'c406');
      counter.queries = 0;
      expect(await orders.getAll('empty'), isEmpty);
      expect(await debts.getAll('empty'), isEmpty);
      expect(await customs.getAll('empty'), isEmpty);
      expect(counter.queries, 3); // No child queries for empty parent sets.
    },
  );
  test('existing child indexes serve the batched lookups', () async {
    for (final (table, parent, index) in [
      ('order_items', 'order_id', 'idx_order_items_order'),
      ('payments', 'debt_id', 'idx_payments_debt'),
      (
        'custom_order_payments',
        'custom_order_id',
        'idx_custom_order_payments_order',
      ),
    ]) {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM $table WHERE $parent IN (?, ?) ORDER BY id ASC',
        ['a', 'b'],
      );
      expect(
        plan.any((row) => (row['detail'] as String).contains(index)),
        isTrue,
        reason: '$plan',
      );
    }
  });
}
