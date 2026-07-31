import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

int _occurrences(String source, String value) =>
    RegExp(RegExp.escape(value)).allMatches(source).length;

void main() {
  group('custom-order and reseller recycle-bin contract', () {
    test('repository mutations are owner-scoped and state-aware', () {
      final customOrders = _read(
        'lib/repositories/local_custom_order_repository.dart',
      );
      final resellers = _read(
        'lib/repositories/local_reseller_repository.dart',
      );

      for (final repository in [customOrders, resellers]) {
        expect(repository, contains("where: 'user_id = ? AND is_deleted = 1'"));
        expect(
          repository,
          contains("where: 'id = ? AND user_id = ? AND is_deleted = 0'"),
        );
        expect(
          _occurrences(
            repository,
            "where: 'id = ? AND user_id = ? AND is_deleted = 1'",
          ),
          greaterThanOrEqualTo(2),
          reason: 'deleted-row reads and writes must remain owner-scoped',
        );
        expect(repository, contains('if (changed != 1)'));
      }
    });

    test('AppState and the screen expose both complete lifecycles', () {
      final appState = _read('lib/core/app_state.dart');
      final screen = _read('lib/screens/recycle_bin_screen.dart');

      for (final entity in ['CustomOrder', 'Reseller']) {
        expect(appState, contains('getDeleted${entity}s()'));
        expect(appState, contains('restore$entity(String'));
        expect(appState, contains('hardDelete$entity(String'));
        expect(screen, contains('_restore$entity('));
        expect(screen, contains('_hardDelete$entity('));
      }

      expect(screen, contains('TabController(length: 5'));
      expect(screen, contains('_appState.getDeletedCustomOrders()'));
      expect(screen, contains('_appState.getDeletedResellers()'));
      expect(screen, contains('_customOrdersBin()'));
      expect(screen, contains('_resellersBin()'));
    });
  });
}
