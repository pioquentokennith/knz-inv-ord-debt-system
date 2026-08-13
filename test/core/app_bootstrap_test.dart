import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_bootstrap.dart';
import 'package:knz_scent_admin/core/startup_gate.dart';

Future<void> _succeeds() async {}

AppBootstrap _bootstrap({
  Future<void> Function()? database,
  Future<void> Function()? preferences,
  Future<void> Function()? localState,
  Future<void> Function()? firebase,
  Future<void> Function()? crashlytics,
  Future<void> Function()? notifications,
  Future<void> Function()? cloudAuthentication,
  Future<void> Function()? synchronization,
}) {
  return AppBootstrap(
    initializeDatabase: database ?? _succeeds,
    initializePreferences: preferences ?? _succeeds,
    configureLocalState: localState ?? _succeeds,
    restoreTrustedSession: _succeeds,
    initializeFirebase: firebase ?? _succeeds,
    initializeCrashlytics: crashlytics ?? _succeeds,
    initializeNotifications: notifications ?? _succeeds,
    initializeCloudAuthentication: cloudAuthentication ?? _succeeds,
    startSynchronization: synchronization ?? _succeeds,
    requiredTimeout: const Duration(milliseconds: 100),
    optionalTimeout: const Duration(milliseconds: 100),
  );
}

Widget _app(AppBootstrap bootstrap) => MaterialApp(
  home: StartupGate(
    bootstrap: bootstrap,
    homeBuilder: (_) => const Scaffold(body: Text('Local setup flow')),
  ),
);

void main() {
  test('Firebase initialization is shared and reports success', () async {
    final firebase = Completer<void>();
    var calls = 0;
    final bootstrap = _bootstrap(
      firebase: () {
        calls++;
        return firebase.future;
      },
    );

    final first = bootstrap.ensureFirebaseInitialized();
    final second = bootstrap.ensureFirebaseInitialized();
    expect(calls, 1);

    firebase.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(bootstrap.isAvailable(StartupCapability.firebase), isTrue);
  });

  test('optional service failures do not disable authentication', () async {
    var cloudAuthenticationCalled = false;
    final bootstrap = _bootstrap(
      crashlytics: () async => throw StateError('crashlytics unavailable'),
      notifications: () async => throw StateError('notifications unavailable'),
      cloudAuthentication: () async => cloudAuthenticationCalled = true,
      synchronization: () async => throw StateError('sync unavailable'),
    );

    await bootstrap.initializeOptional();

    expect(cloudAuthenticationCalled, isTrue);
    expect(bootstrap.isAvailable(StartupCapability.firebase), isTrue);
    expect(
      bootstrap.isAvailable(StartupCapability.cloudAuthentication),
      isTrue,
    );
    expect(bootstrap.isAvailable(StartupCapability.emailVerification), isTrue);
    expect(
      bootstrap.unavailableCapabilities.value,
      containsAll({
        StartupCapability.crashlytics,
        StartupCapability.notifications,
        StartupCapability.synchronization,
      }),
    );
    expect(
      bootstrap.unavailableCapabilities.value,
      isNot(contains(StartupCapability.firebase)),
    );
  });

  testWidgets('opens local state before showing the usable flow', (
    tester,
  ) async {
    final calls = <String>[];
    final bootstrap = _bootstrap(
      database: () async => calls.add('database'),
      preferences: () async => calls.add('preferences'),
      localState: () async => calls.add('state'),
    );

    await tester.pumpWidget(_app(bootstrap));
    await tester.pump();

    expect(calls.take(3), ['database', 'preferences', 'state']);
    expect(find.text('Local setup flow'), findsOneWidget);
  });

  testWidgets('does not wait for optional cloud startup', (tester) async {
    final firebase = Completer<void>();
    final notifications = Completer<void>();
    final bootstrap = _bootstrap(
      firebase: () => firebase.future,
      notifications: () => notifications.future,
    );

    await tester.pumpWidget(_app(bootstrap));
    await tester.pump();

    expect(find.text('Local setup flow'), findsOneWidget);

    firebase.complete();
    notifications.complete();
    await tester.pump();
  });

  testWidgets('surfaces Firebase and notification failures as local mode', (
    tester,
  ) async {
    final bootstrap = _bootstrap(
      firebase: () async => throw StateError('offline'),
      notifications: () async => throw StateError('unavailable'),
    );

    await tester.pumpWidget(_app(bootstrap));
    await tester.pump();
    await tester.pump();

    expect(find.text('Local setup flow'), findsOneWidget);
    expect(find.textContaining('Local mode is available'), findsOneWidget);
    expect(
      bootstrap.unavailableCapabilities.value,
      containsAll({
        StartupCapability.firebase,
        StartupCapability.notifications,
        StartupCapability.emailVerification,
        StartupCapability.synchronization,
      }),
    );
  });

  testWidgets('shows required local failures and allows a retry', (
    tester,
  ) async {
    var attempts = 0;
    final bootstrap = _bootstrap(
      database: () async {
        attempts++;
        if (attempts == 1) throw StateError('database unavailable');
      },
    );

    await tester.pumpWidget(_app(bootstrap));
    await tester.pump();
    expect(
      find.textContaining('Local data could not be opened'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Local setup flow'), findsOneWidget);
    expect(attempts, 2);
  });
}
