import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/screens/forgot_password_screen.dart';

void main() {
  testWidgets('successful reset request shows the generic confirmation', (
    tester,
  ) async {
    String? requestedEmail;
    await tester.pumpWidget(
      MaterialApp(
        home: ForgotPasswordScreen(
          sendPasswordReset: (email) async => requestedEmail = email,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '  Staff@Example.com  ');
    await tester.tap(find.text('SEND RESET INSTRUCTIONS'));
    await tester.pump();

    expect(requestedEmail, 'staff@example.com');
    expect(find.text('Check your email'), findsOneWidget);
    expect(
      find.text(
        'If an eligible account matches that address, password-reset instructions have been sent.',
      ),
      findsOneWidget,
    );
  });
}
