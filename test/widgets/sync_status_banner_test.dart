import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/repositories/sync_queue.dart';
import 'package:knz_scent_admin/widgets/sync_status_banner.dart';

void main() {
  testWidgets('shows durable sync failure and exposes retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusBanner(
            status: const SyncStatus(
              pendingCount: 3,
              failedCount: 1,
              lastError: 'Firestore is unavailable',
            ),
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(
      find.text('1 cloud change(s) failed to sync. Local data is safe.'),
      findsOneWidget,
    );
    expect(find.text('RETRY'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    expect(retried, isTrue);
  });

  testWidgets('shows durable conflicts as requiring review', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SyncStatusBanner(
            status: SyncStatus(
              pendingCount: 1,
              failedCount: 0,
              conflictCount: 1,
              deadLetterCount: 2,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('1 sync conflict'), findsOneWidget);
    expect(find.textContaining('2 invalid operation'), findsOneWidget);
    expect(find.text('RETRY'), findsNothing);
  });
}
