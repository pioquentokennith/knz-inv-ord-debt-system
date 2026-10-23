import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/payment_method_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/models/custom_order_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/repositories/local_product_repository.dart';
import 'package:knz_scent_admin/repositories/local_order_repository.dart';
import 'package:knz_scent_admin/repositories/local_debt_repository.dart';
import 'package:knz_scent_admin/repositories/local_reseller_repository.dart';
import 'package:knz_scent_admin/repositories/local_custom_order_repository.dart';
import 'package:knz_scent_admin/repositories/local_business_event_repository.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/accounting_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TrustedAuth extends Fake implements IAuthService {
  @override
  Future<AuthResult> restoreTrustedDevice() async => AuthResult(
    status: 'offline',
    user: AppUser(
      id: 'u',
      username: 'owner',
      name: 'Owner',
      email: 'u@example.com',
      role: 'Administrator',
      accountStatus: 'approved',
      isActive: true,
      createdAt: DateTime.utc(2026),
    ),
  );
  @override
  Future<void> logout() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late Database database;
  final state = AppState();
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('offline-state-');
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(directory.path);
    database = await DatabaseHelper.instance.database;
    state.configure(
      authService: _TrustedAuth(),
      stopSynchronization: () async {},
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );
  });
  tearDownAll(() async {
    await state.logout();
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'trusted offline session loads local data, refreshes stock and invalidates only financial cache',
    () async {
      await state.restoreTrustedDevice();
      expect(state.isLoggedIn, isTrue);
      final emptyReport = state.accountingReport;
      expect(identical(emptyReport, state.accountingReport), isTrue);
      await state.addProduct(
        Product(
          id: 'p',
          name: 'Rose',
          description: '',
          category: ProductCategory.eauDeParfum,
          price: const Money.fromCentavos(10000),
          stockQty: 5,
          minStockLevel: 1,
        ),
      );
      expect(identical(emptyReport, state.accountingReport), isTrue);
      final product = state.products.single;
      await state.addOrder(
        Order(
          id: 'o',
          orderId: 'PENDING',
          customerName: 'Customer',
          items: [
            OrderItem(
              id: 'i',
              productId: product.id,
              productName: 'Rose',
              unitPrice: const Money.fromCentavos(10000),
              quantity: 2,
            ),
          ],
          totalAmount: const Money.fromCentavos(20000),
          status: OrderStatus.pending,
          orderDate: DateTime.utc(2026),
          commandId: 'create-o',
        ),
      );
      expect(state.products.single.stockQty, 3);
      final orderReport = state.accountingReport;
      expect(identical(emptyReport, orderReport), isFalse);
      await state.updateOrderStatus('o', OrderStatus.cancelled);
      expect(state.products.single.stockQty, 5);
      await state.updateOrderStatus('o', OrderStatus.pending);
      expect(state.products.single.stockQty, 3);
      final beforePayment = state.accountingReport;
      final period = AccountingPeriod(
        from: DateTime.utc(2020),
        to: DateTime.utc(2030),
      );
      final beforePeriod = state.accountingReportForPeriod(period);
      final beforeSales = state.salesRecords;
      await state.recordOrderPayment(
        orderId: 'o',
        amount: const Money.fromCentavos(1000),
        method: PaymentMethod.cashOnDelivery,
      );
      final afterPayment = state.accountingReport;
      expect(identical(beforePayment, afterPayment), isFalse);
      expect(afterPayment.cashReceived.centavos, 1000);
      final afterPeriod = state.accountingReportForPeriod(period);
      expect(identical(beforePeriod, afterPeriod), isFalse);
      expect(afterPeriod.cashReceived.centavos, 1000);
      final afterSales = state.salesRecords;
      expect(identical(beforeSales, afterSales), isFalse);
      expect(identical(afterSales, state.salesRecords), isTrue);
      expect(identical(afterPayment, state.accountingReport), isTrue);
      await state.retryFailedSync();
      expect(identical(afterPayment, state.accountingReport), isTrue);
      expect(state.isLoggedIn, isTrue);
      expect(await database.query('sync_queue'), isNotEmpty);
      // Stand in for an inbound product-only commit. It must not reload any
      // financial list or recreate either accounting projection.
      final order = state.orders.single;
      final revision = state.financialRevision;
      final productId = state.products.single.id;
      await database.update(
        'products',
        {'name': 'Remote Rose'},
        where: 'id = ?',
        whereArgs: [productId],
      );
      await state.refreshData(collections: {'products'});
      expect(state.products.single.name, 'Remote Rose');
      expect(identical(order, state.orders.single), isTrue);
      expect(state.financialRevision, revision);
      expect(identical(afterPayment, state.accountingReport), isTrue);
      expect(
        identical(afterPeriod, state.accountingReportForPeriod(period)),
        isTrue,
      );
      expect(identical(afterSales, state.salesRecords), isTrue);
      expect(
        identical(
          state.accountingReportForPeriod(const AccountingPeriod()),
          afterPayment,
        ),
        isTrue,
      );
      // A targeted order refresh must invalidate all financial projections,
      // including period caches, even though no cloud access is available.
      await database.update(
        'orders',
        {'customer_name': 'Remote customer'},
        where: 'id = ?',
        whereArgs: ['o'],
      );
      await state.refreshData(collections: {'orders'});
      expect(state.orders.single.customerName, 'Remote customer');
      expect(
        identical(afterPeriod, state.accountingReportForPeriod(period)),
        isFalse,
      );
      expect(identical(afterSales, state.salesRecords), isFalse);
      final retained = state.accountingReportForPeriod(period);
      for (var year = 2000; year < 2010; year++) {
        state.accountingReportForPeriod(
          AccountingPeriod(
            from: DateTime.utc(year),
            to: DateTime.utc(year + 1),
          ),
        );
      }
      expect(
        identical(retained, state.accountingReportForPeriod(period)),
        isFalse,
        reason:
            'Period cache must stay bounded instead of retaining every selected range.',
      );
    },
  );

  test(
    'all empty and populated repository reads work with online flag but no Firebase',
    () async {
      final queue = SyncQueue.forTesting(
        databaseProvider: () async => database,
        currentUid: () => 'u',
      );
      addTearDown(queue.stopMonitoring);
      final products = LocalProductRepository(
        databaseProvider: () async => database,
        queue: queue,
      );
      final orders = LocalOrderRepository(
        databaseProvider: () async => database,
        queue: queue,
      );
      final debts = LocalDebtRepository(
        databaseProvider: () async => database,
        queue: queue,
      );
      final resellers = LocalResellerRepository(
        databaseProvider: () async => database,
        queue: queue,
      );
      final customs = LocalCustomOrderRepository(
        databaseProvider: () async => database,
        queue: queue,
      );
      final events = LocalBusinessEventRepository(
        databaseProvider: () async => database,
        queue: queue,
      );
      // Old getAll fallbacks would access uninitialized Firebase for this empty UID.
      expect(await products.getAll('empty'), isEmpty);
      expect(await orders.getAll('empty'), isEmpty);
      expect(await debts.getAll('empty'), isEmpty);
      expect(await resellers.getAll('empty'), isEmpty);
      expect(await customs.getAll('empty'), isEmpty);
      expect(await events.getAll('empty'), isEmpty);
      await debts.add(
        CustomerDebt(
          id: 'd',
          customerName: 'Customer',
          orderId: 'standalone',
          principalOriginal: const Money.fromCentavos(10000),
          principalOutstanding: const Money.fromCentavos(10000),
          createdAt: DateTime.utc(2026),
        ),
        'u',
      );
      await resellers.save(
        Reseller(
          id: 'r',
          name: 'Reseller',
          deductionPerItem: Money.zero,
          userId: 'u',
          createdAt: DateTime.utc(2026),
        ),
      );
      await customs.save(
        CustomOrder(
          id: 'c',
          customerName: 'Customer',
          fragranceSpecs: 'Rose',
          agreedPrice: const Money.fromCentavos(10000),
          deliveryDate: DateTime.utc(2027),
          userId: 'u',
          createdAt: DateTime.utc(2026),
        ),
      );
      expect(await products.getAll('u'), hasLength(1));
      expect(await orders.getAll('u'), hasLength(1));
      expect(await debts.getAll('u'), hasLength(1));
      expect(await resellers.getAll('u'), hasLength(1));
      expect(await customs.getAll('u'), hasLength(1));
      expect(await events.getAll('u'), hasLength(1));
      final count = (await database.query('sync_queue')).length;
      await debts.getAll('u');
      await debts.getAll('u');
      expect(await database.query('sync_queue'), hasLength(count));
    },
  );

  test(
    'outbound finalization refreshes both displayed IDs without inbound changes',
    () async {
      await state.refreshData(collections: {'orders', 'debts'});
      final oldOrder = state.orders.single;
      final oldDebt = state.debts.single;
      final product = state.products.single;
      final oldSales = state.salesRecords;
      expect(oldOrder.orderId, startsWith('TMP-'));
      await database.transaction((txn) async {
        await txn.update(
          'orders',
          {'order_id': 'KNZ-000004', 'number_state': 'finalized'},
          where: 'id = ? AND user_id = ?',
          whereArgs: [oldOrder.id, 'u'],
        );
        await txn.update(
          'debts',
          {'order_id': 'KNZ-000004'},
          where: 'id = ? AND user_id = ?',
          whereArgs: [oldDebt.id, 'u'],
        );
      });
      await state.refreshSyncedData('other-user', {'orders', 'debts'});
      expect(state.orders.single.orderId, oldOrder.orderId);
      expect(state.debts.single.orderId, oldDebt.orderId);
      await state.refreshSyncedData('u', {'orders', 'debts'});
      expect(state.orders.single.orderId, 'KNZ-000004');
      expect(state.debts.single.orderId, 'KNZ-000004');
      expect(identical(state.salesRecords, oldSales), isFalse);
      expect(identical(state.products.single, product), isTrue);
      expect(state.isLoggedIn, isTrue);
    },
  );
}
