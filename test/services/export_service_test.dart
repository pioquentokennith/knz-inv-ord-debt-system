import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/services/accounting_service.dart';
import 'package:knz_scent_admin/services/export_service.dart';

import '../fixtures/accounting_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CSV summary uses the fixed accounting report without recomputing totals',
    () {
      final fixture = AccountingFixture();
      final report = AccountingService.instance.summarize(
        orders: fixture.orders,
        debts: fixture.debts,
        customOrders: fixture.customOrders,
        businessEvents: fixture.businessEvents,
        period: AccountingPeriod(
          from: fixture.periodFrom,
          to: fixture.periodTo,
        ),
      );

      final rows = ExportService.buildAnalyticsCsvRows(
        report: report,
        orders: fixture.orders,
        debts: fixture.debts,
        generatedAt: 'fixture',
      );
      final values = {
        for (final row in rows.where((row) => row.length == 2))
          row.first.toString(): row.last.toString(),
      };

      expect(values['Gross Sales (PHP)'], '700.00');
      expect(values['Discounts (PHP)'], '70.00');
      expect(values['Net Sales (PHP)'], '630.00');
      expect(values['Debt Collections (PHP)'], '100.00');
      expect(values['Custom Order Receipts (PHP)'], '120.00');
      expect(values['Total Cash Received (PHP)'], '550.00');
      expect(values['Receivables Interest (PHP)'], '30.00');
    },
  );

  test('CSV sanitization neutralizes formulas and preserves numeric cells', () {
    expect(ExportService.sanitizeCsvCell('=SUM(A1:A2)'), "'=SUM(A1:A2)");
    expect(ExportService.sanitizeCsvCell('  +cmd'), "'  +cmd");
    expect(ExportService.sanitizeCsvCell('-10'), "'-10");
    expect(ExportService.sanitizeCsvCell('@name'), "'@name");
    expect(ExportService.sanitizeCsvCell('Safe Customer'), 'Safe Customer');
    expect(ExportService.sanitizeCsvCell(1250), 1250);

    final csv = ExportService.encodeCsvRows([
      ['Customer', 'Amount'],
      ['=HYPERLINK("bad")', 1250],
    ]);
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains('1250'));
  });

  test(
    'PDF builder consumes the same fixture and creates a valid document',
    () async {
      final fixture = AccountingFixture();
      final bytes = await ExportService.buildAnalyticsPdfBytes(
        orders: fixture.orders,
        debts: fixture.debts,
        customOrders: fixture.customOrders,
        businessEvents: fixture.businessEvents,
        businessName: 'Fixture Business',
        paymentFrom: fixture.periodFrom,
        paymentTo: fixture.periodTo,
      );

      expect(bytes.length, greaterThan(1000));
      expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    },
  );
}
