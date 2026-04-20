// ─────────────────────────────────────────────────────────────────────────────
// activity_log_test.dart — Unit tests for StubActivityLogRepository
//
// WHY: activity_log was never directly tested — only used as a stub in
//      AppState tests. These tests verify the in-memory stub used in all
//      other tests behaves correctly (add, getAll, 50-log cap).
//
// Coverage:
//   ✔ add() stores log and getAll() returns it
//   ✔ add() multiple logs — all returned
//   ✔ add() enforces 50-log cap (oldest dropped)
//   ✔ getAll() returns empty list for fresh repo
//   ✔ ActivityLog.timeAgo computed getter — just now, minutes, hours, days
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'stubs/stub_activity_log_repository.dart';

ActivityLog _log({
  String id      = 'log-1',
  String message = 'Test action',
  String type    = 'order',
  DateTime? timestamp,
}) =>
    ActivityLog(
      id:        id,
      message:   message,
      type:      type,
      timestamp: timestamp ?? DateTime.now(),
    );

void main() {
  late StubActivityLogRepository repo;

  setUp(() => repo = StubActivityLogRepository());

  group('StubActivityLogRepository — add() / getAll()', () {
    test('getAll() returns empty list on fresh repo', () async {
      final logs = await repo.getAll('u1');
      expect(logs, isEmpty);
    });

    test('add() stores a log that getAll() returns', () async {
      await repo.add(_log(id: 'l1', message: 'Order created'), 'u1');

      final logs = await repo.getAll('u1');
      expect(logs.length, 1);
      expect(logs.first.message, 'Order created');
    });

    test('add() multiple logs — all returned in insertion order (newest first)', () async {
      await repo.add(_log(id: 'l1', message: 'First'), 'u1');
      await repo.add(_log(id: 'l2', message: 'Second'), 'u1');
      await repo.add(_log(id: 'l3', message: 'Third'), 'u1');

      final logs = await repo.getAll('u1');
      expect(logs.length, 3);
      // Stub inserts at front — newest first
      expect(logs.first.message, 'Third');
    });

    test('add() caps at 50 logs — oldest entry is dropped', () async {
      // Add 51 logs
      for (var i = 1; i <= 51; i++) {
        await repo.add(_log(id: 'l$i', message: 'Log $i'), 'u1');
      }

      final logs = await repo.getAll('u1');
      expect(logs.length, 50, reason: 'Cap must be enforced at 50');
      // Log 1 (oldest) must have been evicted
      expect(
        logs.any((l) => l.message == 'Log 1'),
        isFalse,
        reason: 'Oldest log must be dropped when cap is exceeded',
      );
      // Log 51 (newest) must still be there
      expect(logs.first.message, 'Log 51');
    });
  });

  group('ActivityLog — timeAgo computed getter', () {
    test('"just now" for timestamps less than 60 seconds ago', () {
      final log = _log(timestamp: DateTime.now().subtract(const Duration(seconds: 30)));
      expect(log.timeAgo, 'just now');
    });

    test('"Xm ago" for timestamps between 1–59 minutes ago', () {
      final log = _log(timestamp: DateTime.now().subtract(const Duration(minutes: 5)));
      expect(log.timeAgo, '5m ago');
    });

    test('"Xh ago" for timestamps between 1–23 hours ago', () {
      final log = _log(timestamp: DateTime.now().subtract(const Duration(hours: 3)));
      expect(log.timeAgo, '3h ago');
    });

    test('"Xd ago" for timestamps 1+ days ago', () {
      final log = _log(timestamp: DateTime.now().subtract(const Duration(days: 2)));
      expect(log.timeAgo, '2d ago');
    });

    test('boundary: exactly 60 seconds = "1m ago" not "just now"', () {
      final log = _log(timestamp: DateTime.now().subtract(const Duration(seconds: 60)));
      expect(log.timeAgo, '1m ago');
    });
  });
}
