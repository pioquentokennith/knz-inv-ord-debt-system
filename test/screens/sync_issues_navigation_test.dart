import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/screens/main_shell.dart';
import 'package:knz_scent_admin/screens/sales_screen.dart';
import 'package:knz_scent_admin/screens/sync_issues_screen.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Auth extends Fake implements IAuthService {
  @override
  Future<AuthResult> restoreTrustedDevice() async => AuthResult(
    status: 'offline',
    user: AppUser(
      id: 'navigation-user',
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

class _RouteStack extends NavigatorObserver {
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
  sqfliteFfiInit();
  late Directory directory;
  late Database database;
  final state = AppState();
  setUpAll(() async {
    // Ahem's square glyphs overflow the fixed-width drawer branding. Use the
    // SDK's bundled Roboto at normal text scale for this navigation regression.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final font = await File(
      '${artifacts.path}/material_fonts/roboto-regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      'NavigationTestRoboto',
    )..addFont(Future.value(font.buffer.asByteData()))).load();
    directory = await Directory.systemTemp.createTemp('sync-navigation-');
    // In-process SQLite lets widget pumps settle real repository futures without
    // adding test-only dependencies to either screen.
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(directory.path);
    database = await DatabaseHelper.instance.database;
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
    await database.close();
    await directory.delete(recursive: true);
  });

  for (final width in [400.0, 1100.0]) {
    for (final systemBack in [false, true]) {
      testWidgets(
        'Sync Issues preserves shell at width $width using ${systemBack ? 'Android route pop' : 'back arrow'}',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final navigator = GlobalKey<NavigatorState>();
          final stack = _RouteStack();
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: ThemeData(fontFamily: 'NavigationTestRoboto'),
              navigatorObservers: [stack],
              home: const Scaffold(body: Text('Entry route')),
            ),
          );
          navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const MainShell()),
          );
          await tester.pumpAndSettle();
          final shell = tester.state<MainShellState>(find.byType(MainShell));
          shell.navigateTo(NavItem.sales);
          await tester.pumpAndSettle();
          final shellRoute = stack.routes.last;
          expect(find.byType(SalesScreen), findsOneWidget);
          expect(stack.routes, hasLength(2));

          Future<void> showSyncEntry() async {
            if (width < 768) {
              expect(
                find.widgetWithText(ListTile, 'Sync Issues'),
                findsNothing,
                reason:
                    'The overlay must be closed when returning to the shell.',
              );
              await tester.tap(find.byIcon(Icons.menu));
              await tester.pumpAndSettle();
            }
            final entry = find.widgetWithText(ListTile, 'Sync Issues');
            await tester.ensureVisible(entry);
            await tester.pumpAndSettle();
            expect(entry.hitTestable(), findsOneWidget);
          }

          // Repeat entry/exit to detect leftover overlays or accumulated routes.
          for (var visit = 0; visit < 2; visit++) {
            await showSyncEntry();
            await tester.tap(find.widgetWithText(ListTile, 'Sync Issues'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(SyncIssuesScreen), findsOneWidget);
            expect(find.byType(BackButton), findsOneWidget);
            expect(find.text('No sync issues require review.'), findsOneWidget);
            expect(
              stack.routes,
              hasLength(3),
              reason: 'Opening Sync Issues must not pop the shell.',
            );
            expect(stack.routes[1], same(shellRoute));
            expect(find.byType(MainShell, skipOffstage: false), findsOneWidget);

            if (systemBack) {
              await tester.binding.handlePopRoute();
            } else {
              await tester.tap(find.byType(BackButton));
            }
            await tester.pumpAndSettle();
            expect(
              find.byType(SyncIssuesScreen, skipOffstage: false),
              findsNothing,
            );
            expect(
              tester.state<MainShellState>(find.byType(MainShell)),
              same(shell),
            );
            expect(find.byType(SalesScreen), findsOneWidget);
            expect(stack.routes, hasLength(2));
            expect(stack.routes.last, same(shellRoute));
            expect(find.text('Entry route'), findsNothing);
          }
          await showSyncEntry(); // The drawer/sidebar remains usable after Back.
          expect(state.isLoggedIn, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
