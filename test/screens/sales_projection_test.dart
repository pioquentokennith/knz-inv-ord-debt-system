import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/models/business_event_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/screens/sales_screen.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Auth extends Fake implements IAuthService {
  @override
  Future<AuthResult> restoreTrustedDevice() async => AuthResult(
    status: 'offline',
    user: AppUser(
      id: 'u',
      username: 'u',
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
  late Database db;
  final state = AppState();
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('sales-projection-');
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(directory.path);
    db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    for (var i = 0; i < 51; i++) {
      final date = DateTime.utc(2026, 1, 1).add(Duration(minutes: i));
      final order = OrderDto.fromDomain(
        Order(
          id: 'o$i',
          orderId: 'KNZ-$i',
          customerName: 'Customer $i',
          orderDate: date,
          status: OrderStatus.delivered,
          totalAmount: const Money.fromCentavos(100),
          srpTotal: const Money.fromCentavos(120),
          isReseller: i.isEven,
          items: [
            OrderItem(
              id: 'i$i',
              productId: 'p',
              productName: 'Rose ${i.toString().padLeft(2, '0')}',
              quantity: 1,
              unitPrice: const Money.fromCentavos(100),
              srpPrice: const Money.fromCentavos(120),
            ),
          ],
        ),
        userId: 'u',
      );
      batch.insert('orders', order.toLocal());
      batch.insert('order_items', order.items.single.toLocal());
      batch.insert(
        'business_events',
        BusinessEventDto.fromDomain(
          BusinessEvent(
            id: 'e$i',
            userId: 'u',
            subject: BusinessEventSubject.order,
            subjectId: 'o$i',
            type: BusinessEventType.delivery,
            occurredAt: date,
            recordedAt: date,
            commandId: 'delivery-$i',
          ),
        ).toLocal(),
      );
    }
    await batch.commit(noResult: true);
    state.configure(
      authService: _Auth(),
      stopSynchronization: () async {},
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );
    await state.restoreTrustedDevice();
  });
  tearDownAll(() async {
    await state.logout();
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'cached Sales preserves page totals, sort, filters and financial invalidation',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SalesScreen())),
      );
      await tester.pumpAndSettle();
      DataTable table() => tester.widget<DataTable>(find.byType(DataTable));
      String firstId() => (table().rows.first.cells.first.child as Text).data!;
      expect(table().rows, hasLength(50));
      expect(firstId(), 'KNZ-50');
      expect(find.text('Total: ₱51.00'), findsOneWidget);
      expect(find.text('Discount: ₱10.20'), findsOneWidget);
      final cached = state.salesRecords;
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(table().rows, hasLength(1));
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Total: ₱51.00'), findsOneWidget);
      await tester.runAsync(
        () => state.refreshData(collections: {'activity_logs'}),
      );
      await tester.pumpAndSettle();
      expect(identical(cached, state.salesRecords), isTrue);
      expect(table().rows, hasLength(1));
      await tester.enterText(find.byType(TextField), 'Rose 00');
      await tester.pumpAndSettle();
      expect(firstId(), 'KNZ-0');
      expect(find.text('Total: ₱1.00'), findsOneWidget);
      expect(find.text('Discount: ₱0.20'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('All Orders'));
      await tester.pumpAndSettle();
      expect(table().rows, hasLength(26));
      expect(find.text('Total: ₱26.00'), findsOneWidget);
      await tester.tap(find.text('Resellers Only'));
      await tester.pumpAndSettle();
      expect(table().rows, hasLength(25));
      await tester.tap(find.text('Regular Only'));
      await tester.tap(find.text('Item Name'));
      await tester.pumpAndSettle();
      expect(firstId(), 'KNZ-0');
      await tester.runAsync(() async {
        await db.update(
          'order_items',
          {'product_name': 'AAA'},
          where: 'id = ?',
          whereArgs: ['i50'],
        );
        await state.refreshData(collections: {'orders'});
      });
      await tester.pumpAndSettle();
      expect(firstId(), 'KNZ-50');
      expect(identical(cached, state.salesRecords), isFalse);
      expect(find.text('Total: ₱51.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
