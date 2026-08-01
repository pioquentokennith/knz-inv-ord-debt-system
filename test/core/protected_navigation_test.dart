import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/core/protected_navigation.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:knz_scent_admin/services/session_timeout_service.dart';

class _AuthStub implements IAuthService {
  int logoutCalls = 0;
  int loginCalls = 0;

  @override
  Future<AuthResult> login(String email, String password) async {
    loginCalls++;
    return const AuthResult(status: 'signed_out');
  }

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState state;
  late _AuthStub auth;

  setUp(() {
    state = AppState();
    auth = _AuthStub();
    state.configure(
      authService: auth,
      stopSynchronization: () async {},
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );
  });

  tearDown(() {
    SessionTimeoutService.instance
      ..stop()
      ..timeoutDuration = const Duration(minutes: 10);
  });

  testWidgets('logout removes Recycle Bin and its dialog before Android Back', (
    tester,
  ) async {
    await _pumpRoot(tester);
    await _pushProtectedPage(tester, 'Recycle Bin');
    unawaited(
      showDialog<void>(
        context: ProtectedNavigation.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Delete permanently?')),
      ),
    );
    await tester.pumpAndSettle();

    await state.logout();
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsNothing);
    expect(find.text('Delete permanently?'), findsNothing);
    expect(auth.logoutCalls, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsNothing);
  });

  testWidgets('session timeout removes an open protected route', (
    tester,
  ) async {
    await _pumpRoot(tester);
    await _pushProtectedPage(tester, 'Recycle Bin');
    SessionTimeoutService.instance
      ..timeoutDuration = const Duration(milliseconds: 10)
      ..start(onTimeout: () => unawaited(state.logout()));

    await tester.pump(const Duration(milliseconds: 11));
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsNothing);
    expect(auth.logoutCalls, 1);
  });

  for (final dialogName in ['Order Dialog', 'Payment Dialog']) {
    testWidgets('logout dismisses an open $dialogName', (tester) async {
      await _pumpRoot(tester);
      unawaited(
        showDialog<void>(
          context: ProtectedNavigation.navigatorKey.currentContext!,
          builder: (_) => AlertDialog(title: Text(dialogName)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(dialogName), findsOneWidget);

      await state.logout();
      await tester.pumpAndSettle();

      expect(find.text('Login'), findsOneWidget);
      expect(find.text(dialogName), findsNothing);
    });
  }

  testWidgets(
    'protected routes disappear before asynchronous logout cleanup finishes',
    (tester) async {
      final cleanupStarted = Completer<void>();
      final allowCleanup = Completer<void>();
      state.configure(
        authService: auth,
        stopSynchronization: () async {
          cleanupStarted.complete();
          await allowCleanup.future;
        },
        cancelNotifications: () async {},
        syncBusinessAlerts: (_, _) async {},
      );
      await _pumpRoot(tester);
      await _pushProtectedPage(tester, 'Protected customer data');

      final logout = state.logout();
      await cleanupStarted.future;
      await tester.pump();

      expect(state.isLoggedIn, isFalse);
      expect(state.products, isEmpty);
      expect(state.orders, isEmpty);
      expect(state.debts, isEmpty);
      expect(find.text('Protected customer data'), findsNothing);
      expect(find.text('Login'), findsOneWidget);

      allowCleanup.complete();
      await logout;
    },
  );

  test('a new account login waits for previous logout cleanup', () async {
    final cleanupStarted = Completer<void>();
    final allowCleanup = Completer<void>();
    state.configure(
      authService: auth,
      stopSynchronization: () async {
        cleanupStarted.complete();
        await allowCleanup.future;
      },
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );

    final logout = state.logout();
    await cleanupStarted.future;
    final login = state.login('next@example.com', 'password');
    await Future<void>.delayed(Duration.zero);
    expect(auth.loginCalls, 0);

    allowCleanup.complete();
    await logout;
    expect(await login, isFalse);
    expect(auth.loginCalls, 1);
  });
}

Future<void> _pumpRoot(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: ProtectedNavigation.navigatorKey,
      navigatorObservers: [ProtectedNavigation.observer],
      home: const Scaffold(body: Text('Login')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pushProtectedPage(WidgetTester tester, String label) async {
  ProtectedNavigation.navigatorKey.currentState!.push(
    MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(label))),
  );
  await tester.pumpAndSettle();
}
