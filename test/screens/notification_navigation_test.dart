import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/screens/main_shell.dart';
import 'package:knz_scent_admin/screens/inventory_screen.dart';
import 'package:knz_scent_admin/screens/utang_screen.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import '../support/notification_fakes.dart';

class _Auth extends Fake implements IAuthService {
  @override
  Future<AuthResult> restoreTrustedDevice() async => AuthResult(
    status: 'offline',
    user: AppUser(
      id: 'notification-user',
      username: 'admin',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'Administrator',
      accountStatus: 'approved',
      isActive: true,
      createdAt: DateTime.utc(2026),
    ),
  );
  @override
  Future<void> logout() async {}
}

class _Routes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  sqfliteFfiInit();
  late Directory directory;
  late Database database;
  final app = AppState();
  setUpAll(() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
      final font = await File(
        '${artifacts.path}/material_fonts/roboto-regular.ttf',
      ).readAsBytes();
      await (FontLoader(
        'NotificationTestRoboto',
      )..addFont(Future.value(font.buffer.asByteData()))).load();
    }
    directory = await Directory.systemTemp.createTemp(
      'notification-navigation-',
    );
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(directory.path);
    database = await DatabaseHelper.instance.database;
    app.configure(
      authService: _Auth(),
      stopSynchronization: () async {},
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );
    await app.restoreTrustedDevice();
  });
  tearDownAll(() async {
    await app.logout();
    await database.close();
    await directory.delete(recursive: true);
  });

  for (final target in NotificationDestination.values) {
    for (final cold in [false, true]) {
      testWidgets(
        '${target.name} notification ${cold ? 'launch' : 'active tap'} reuses shell and preserves drawer/back',
        (tester) async {
          tester.view.physicalSize = const Size(500, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final platform = FakeAlertPlatform();
          final store = MemoryAlertStore();
          NotificationService create() =>
              NotificationService(
                platform: platform,
                store: store,
                now: () => DateTime.utc(2026, 1, 3, 2),
              )..configure(
                activeUser: () => app.currentUser?.id,
                snapshot: () => app.isLoggedIn
                    ? NotificationSnapshot(
                        app.currentUser!.id,
                        [
                          Product(
                            id: 'p',
                            name: 'Private',
                            description: '',
                            category: ProductCategory.eauDeParfum,
                            price: const Money.fromCentavos(100),
                            stockQty: 1,
                            minStockLevel: 5,
                          ),
                        ],
                        [
                          CustomerDebt(
                            id: 'd',
                            customerName: 'Private',
                            orderId: 'o',
                            principalOriginal: const Money.fromCentavos(100),
                            principalOutstanding: const Money.fromCentavos(100),
                            createdAt: DateTime.utc(2026),
                            dueDate: DateTime.utc(2026, 1, 3),
                          ),
                        ],
                      )
                    : null,
              );
          var service = create();
          await service.init();
          await service.idle;
          final payload = platform.shows
              .firstWhere(
                (e) => e.stock == (target == NotificationDestination.inventory),
              )
              .payload;
          if (cold) {
            service.dispose();
            platform.launchPayload = payload;
            service = create();
            await service.init();
            await service.idle;
          }
          final key = GlobalKey<NavigatorState>();
          final routes = _Routes();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: key,
              navigatorObservers: [routes],
              theme: ThemeData(fontFamily: 'NotificationTestRoboto'),
              home: MainShell(notifications: service),
            ),
          );
          await tester.pumpAndSettle();
          final shell = tester.state<MainShellState>(find.byType(MainShell));
          if (!cold) {
            key.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Details route')),
              ),
            );
            await tester.pumpAndSettle();
            expect(routes.routes, hasLength(2));
            platform.tap!(payload);
            await tester.pumpAndSettle();
          }
          expect(routes.routes, hasLength(1));
          expect(
            tester.state<MainShellState>(find.byType(MainShell)),
            same(shell),
          );
          expect(
            find.byType(
              target == NotificationDestination.inventory
                  ? InventoryScreen
                  : UtangScreen,
            ),
            findsOneWidget,
          );
          expect(find.text('Details route'), findsNothing);
          await tester.tap(find.byIcon(Icons.menu));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(ListTile, 'Sync Issues'), findsOneWidget);
          // Existing secondary routes still pop back to this same shell.
          key.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Second details')),
            ),
          );
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(routes.routes, hasLength(1));
          expect(find.byType(MainShell), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await service.idle;
          service.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
