import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_bootstrap.dart';
import 'package:knz_scent_admin/screens/login_screen.dart';

Future<void> _succeeds() async {}

void main() {
  testWidgets('password visibility can be toggled', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = AppBootstrap(
      initializeDatabase: _succeeds,
      initializePreferences: _succeeds,
      configureLocalState: _succeeds,
      restoreTrustedSession: _succeeds,
      initializeFirebase: _succeeds,
      initializeCrashlytics: _succeeds,
      initializeNotifications: _succeeds,
      initializeCloudAuthentication: _succeeds,
      startSynchronization: _succeeds,
    );

    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(bootstrap: bootstrap)),
    );
    await tester.pump(const Duration(milliseconds: 700));

    TextField passwordField = tester
        .widgetList<TextField>(find.byType(TextField))
        .last;
    expect(passwordField.obscureText, isTrue);
    expect(find.byTooltip('Show password'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Show password')), const Size(48, 48));

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    passwordField = tester.widgetList<TextField>(find.byType(TextField)).last;
    expect(passwordField.obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    passwordField = tester.widgetList<TextField>(find.byType(TextField)).last;
    expect(passwordField.obscureText, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
