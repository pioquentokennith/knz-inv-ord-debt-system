import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_bootstrap.dart';
import 'package:knz_scent_admin/screens/register_screen.dart';

Future<void> _succeeds() async {}

void main() {
  testWidgets('registration describes the Firebase verification-link flow', (
    tester,
  ) async {
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
      MaterialApp(home: RegisterScreen(bootstrap: bootstrap)),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('verification link'), findsOneWidget);
    expect(find.textContaining('Administrator must approve'), findsOneWidget);
    expect(find.textContaining('6-digit OTP'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
