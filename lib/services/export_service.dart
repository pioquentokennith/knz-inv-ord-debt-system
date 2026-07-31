// ─────────────────────────────────────────────────────────────────────────────
// export_service.dart — CSV and PDF export for orders, inventory, and utang
// Purpose : Generates shareable/printable reports from in-memory data lists.
//           Abstracts all file I/O, font loading, and platform share-sheet logic
//           so screens only call a single static method per report type.
//
// FIX: Currency rendering —
//   • PDF : uses the ASCII "PHP" prefix so offline Helvetica remains readable
//   • CSV : uses "PHP" label in column headers + UTF-8 BOM for Excel
//   • Values in CSV: plain numbers (no symbol) so Excel can sum them
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/debt_model.dart';
import '../models/custom_order_model.dart';
import '../core/app_constants.dart';
import '../core/money.dart';
import 'accounting_service.dart';

// All methods are static — ExportService is a namespace, not an instance
class ExportService {
  ExportService._(); // Private constructor prevents instantiation

  // ── Shared formatters ─────────────────────────────────────────────────────
  static const _pdfCurrency = _CentavoCurrencyFormatter();
  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

  // ── Font cache — loaded once and reused for all PDF builds ────────────────
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Loads NotoSans from Google Fonts — has full Unicode coverage including ₱.
  /// Falls back to Helvetica if offline (peso will render as a box, rest is fine).
  static Future<void> _ensureFonts() async {
    if (_regular != null) return; // Already loaded — skip network request
    try {
      _regular = await PdfGoogleFonts.notoSansRegular();
      _bold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      // Offline fallback — built-in Helvetica does not support ₱ but is always available
      _regular = pw.Font.helvetica();
      _bold = pw.Font.helveticaBold();
    }
  }

  // Builds a ThemeData using the loaded fonts for consistent PDF typography
  static pw.ThemeData _theme() => pw.ThemeData.withFont(
    base: _regular ?? pw.Font.helvetica(),
    bold: _bold ?? pw.Font.helveticaBold(),
  );

  // ════════════════════════════════════════════════════════════════════════════
  // CSV EXPORTS — lightweight tabular data for spreadsheet use
  // ════════════════════════════════════════════════════════════════════════════

  // Exports all orders to a CSV file and opens the system share sheet
  static Future<void> exportOrdersCsv(List<Order> orders) async {
    final rows = <List<dynamic>>[
      // Header row — PHP label instead of ₱ so Excel parses it correctly
      [
        'Order ID',
        'Customer',
        'Date',
        'Status',
        'Items',
        'Total Amount (PHP)',
        'Notes',
      ],
    ];
    for (final o in orders.where(
      (order) => order.status != OrderStatus.cancelled,
    )) {
      rows.add([
        o.orderId,
        o.customerName,
        _dateFormat.format(o.orderDate),
        o.status.displayName,
        // Join multiple items into a single readable cell
        o.items.map((i) => '${i.productName} x${i.quantity}').join(' | '),
        o.customerPayAmount.toStringAsFixed(
          2,
        ), // FIX: was totalAmount (SRP for resellers)
        o.notes ?? '',
      ]);
    }
    await _csvShare(
      rows,
      'knz_orders_${_dateFormat.format(DateTime.now())}.csv',
      '${AppStrings.appName} — Orders Export',
    );
  }

  // Exports all inventory products to a CSV file and opens the share sheet
  static Future<void> exportInventoryCsv(List<Product> products) async {
    final rows = <List<dynamic>>[
      [
        'Name',
        'Category',
        'Price (PHP)',
        'Stock Qty',
        'Min Stock Level',
        'Status',
        'Description',
        'Created At',
      ],
    ];
    for (final p in products) {
      rows.add([
        p.name,
        p.category.displayName,
        p.price.toStringAsFixed(2),
        p.stockQty,
        p.minStockLevel,
        p.isLowStock ? 'Low Stock' : 'OK', // Human-readable status flag
        p.description,
        _dateFormat.format(p.createdAt),
      ]);
    }
    await _csvShare(
      rows,
      'knz_inventory_${_dateFormat.format(DateTime.now())}.csv',
      '${AppStrings.appName} — Inventory Export',
    );
  }

  // Exports all debt records to a CSV file and opens the share sheet
  static Future<void> exportDebtsCsv(List<CustomerDebt> debts) async {
    final rows = <List<dynamic>>[
      [
        'Customer',
        'Order ID',
        'Principal (PHP)',
        'Paid (PHP)',
        'Principal Due (PHP)',
        'Interest Due (PHP)',
        'Total Due (PHP)',
        'Status',
        'Days Old',
        'Created At',
      ],
    ];
    for (final d in debts) {
      rows.add([
        d.customerName,
        d.orderId,
        d.totalAmount.toStringAsFixed(2),
        d.amountPaid.toStringAsFixed(2),
        d.remainingBalance.toStringAsFixed(2),
        d.accruedInterest.toStringAsFixed(2),
        d.totalWithInterest.toStringAsFixed(2),
        d.isPaid ? 'Paid' : (d.isOverdue ? 'Overdue' : 'Unpaid'),
        d.daysOld,
        _dateFormat.format(d.createdAt),
      ]);
    }
    await _csvShare(
      rows,
      'knz_utang_${_dateFormat.format(DateTime.now())}.csv',
      '${AppStrings.appName} — Utang Export',
    );
  }

  // Exports a full analytics summary to CSV — all key metrics in one file
  // Sections: Summary KPIs, Orders by Status, Utang Records, Top Products
  static Future<void> exportAnalyticsCsv({
    required List<Order> orders,
    required List<CustomerDebt> debts,
    List<CustomOrder> customOrders = const [],
    DateTime? paymentFrom,
    DateTime? paymentTo,
  }) async {
    final now = _dateFormat.format(DateTime.now());
    final report = AccountingService.instance.summarize(
      orders: orders,
      debts: debts,
      customOrders: customOrders,
      period: AccountingPeriod(from: paymentFrom, to: paymentTo),
    );
    final rows = buildAnalyticsCsvRows(
      report: report,
      orders: orders,
      debts: debts,
      generatedAt: now,
    );

    await _csvShare(
      rows,
      'knz_analytics_${_dateFormat.format(DateTime.now())}.csv',
      '${AppStrings.appName} — Analytics Report',
    );
  }

  static List<List<dynamic>> buildAnalyticsCsvRows({
    required AccountingReport report,
    required List<Order> orders,
    required List<CustomerDebt> debts,
    String generatedAt = '',
  }) {
    final rows = <List<dynamic>>[
      ['=== REVENUE & COLLECTIONS SUMMARY ===', 'Generated: $generatedAt'],
      ['Metric', 'Value'],
      ['Gross Sales (PHP)', report.grossSales.toStringAsFixed(2)],
      ['Discounts (PHP)', report.discounts.toStringAsFixed(2)],
      ['Net Sales (PHP)', report.netSales.toStringAsFixed(2)],
      ['Debt Collections (PHP)', report.debtCollections.toStringAsFixed(2)],
      [
        'Custom Order Receipts (PHP)',
        report.customOrderReceipts.toStringAsFixed(2),
      ],
      ['Total Cash Received (PHP)', report.cashReceived.toStringAsFixed(2)],
      [
        'Receivables Principal (PHP)',
        report.receivablesPrincipal.toStringAsFixed(2),
      ],
      [
        'Receivables Interest (PHP)',
        report.receivablesInterest.toStringAsFixed(2),
      ],
      ['Recognized Sales', report.recognizedOrders.length],
      ['Items Sold', report.itemsSold],
      [],
      ['=== ORDERS BY STATUS ==='],
      ['Status', 'Count', '% of Total'],
    ];
    for (final status in OrderStatus.values) {
      final count = orders.where((order) => order.status == status).length;
      final percentage = orders.isEmpty ? 0 : count / orders.length * 100;
      rows.add([
        status.displayName,
        count,
        '${percentage.toStringAsFixed(1)}%',
      ]);
    }
    rows.addAll([
      [],
      ['=== UTANG RECORDS ==='],
      [
        'Customer',
        'Order ID',
        'Principal (PHP)',
        'Collected (PHP)',
        'Principal Due (PHP)',
        'Interest Due (PHP)',
        'Total Due (PHP)',
        'Status',
        'Days Old',
        'Created At',
      ],
    ]);
    for (final debt in debts) {
      rows.add([
        debt.customerName,
        debt.orderId,
        debt.totalAmount.toStringAsFixed(2),
        report.debtCollectionsFor(debt.id).toStringAsFixed(2),
        debt.remainingBalance.toStringAsFixed(2),
        debt.accruedInterest.toStringAsFixed(2),
        debt.totalWithInterest.toStringAsFixed(2),
        debt.isPaid ? 'Paid' : (debt.isOverdue ? 'Overdue' : 'Unpaid'),
        debt.daysOld,
        _dateFormat.format(debt.createdAt),
      ]);
    }
    final sales = <String, int>{};
    for (final order in report.recognizedOrders) {
      for (final item in order.items) {
        sales[item.productName] =
            (sales[item.productName] ?? 0) + item.quantity;
      }
    }
    final sorted = sales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    rows.addAll([
      [],
      ['=== TOP PRODUCTS BY SALES ==='],
      ['Rank', 'Product Name', 'Total Units Sold'],
    ]);
    for (var index = 0; index < sorted.length; index++) {
      rows.add([index + 1, sorted[index].key, sorted[index].value]);
    }
    return rows;
  }

  static dynamic sanitizeCsvCell(dynamic value) {
    if (value is! String) return value;
    if (RegExp(r'^\s*[=+\-@]').hasMatch(value) ||
        value.startsWith('\t') ||
        value.startsWith('\r')) {
      return "'$value";
    }
    return value;
  }

  static String encodeCsvRows(List<List<dynamic>> rows) =>
      const ListToCsvConverter().convert(
        rows
            .map(
              (row) =>
                  row.map<dynamic>(sanitizeCsvCell).toList(growable: false),
            )
            .toList(growable: false),
      );

  // ════════════════════════════════════════════════════════════════════════════
  // PDF EXPORTS — formatted reports for sharing as files
  // ════════════════════════════════════════════════════════════════════════════

  // Builds an orders PDF and opens the system share sheet
  static Future<void> exportOrdersPdf(
    List<Order> orders, {
    required String businessName,
    String? subtitle,
    String? userName,
  }) async {
    await _ensureFonts();
    final bytes = await _buildOrdersPdf(
      orders,
      businessName: businessName,
      subtitle: subtitle,
      userName: userName,
    ).save();
    await _pdfShare(
      bytes,
      'knz_orders_${_dateFormat.format(DateTime.now())}.pdf',
      '${AppStrings.appName} — Orders Report',
    );
  }

  // Builds an inventory PDF and opens the system share sheet
  static Future<void> exportInventoryPdf(
    List<Product> products, {
    required String businessName,
    String? userName,
  }) async {
    await _ensureFonts();
    final bytes = await _buildInventoryPdf(
      products,
      businessName: businessName,
      userName: userName,
    ).save();
    await _pdfShare(
      bytes,
      'knz_inventory_${_dateFormat.format(DateTime.now())}.pdf',
      '${AppStrings.appName} — Inventory Report',
    );
  }

  // Builds a debts PDF and opens the system share sheet
  static Future<void> exportDebtsPdf(
    List<CustomerDebt> debts, {
    required String businessName,
    String? userName,
  }) async {
    await _ensureFonts();
    final bytes = await _buildDebtsPdf(
      debts,
      businessName: businessName,
      userName: userName,
    ).save();
    await _pdfShare(
      bytes,
      'knz_utang_${_dateFormat.format(DateTime.now())}.pdf',
      '${AppStrings.appName} — Utang Report',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF PRINTING — sends the report directly to a physical printer
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> printOrdersPdf(
    List<Order> orders, {
    required String businessName,
    String? userName,
  }) async {
    await _ensureFonts();
    final pdf = _buildOrdersPdf(
      orders,
      businessName: businessName,
      userName: userName,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: '${AppStrings.appName} Orders Report',
    );
  }

  static Future<void> printInventoryPdf(
    List<Product> products, {
    required String businessName,
    String? userName,
  }) async {
    await _ensureFonts();
    final pdf = _buildInventoryPdf(
      products,
      businessName: businessName,
      userName: userName,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: '${AppStrings.appName} Inventory Report',
    );
  }

  static Future<void> printDebtsPdf(
    List<CustomerDebt> debts, {
    required String businessName,
    String? userName,
  }) async {
    await _ensureFonts();
    final pdf = _buildDebtsPdf(
      debts,
      businessName: businessName,
      userName: userName,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: '${AppStrings.appName} Utang Report',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF DOCUMENT BUILDERS — construct the pw.Document object
  // ════════════════════════════════════════════════════════════════════════════

  static pw.Document _buildOrdersPdf(
    List<Order> orders, {
    required String businessName,
    String? subtitle,
    String? userName,
  }) {
    final pdf = pw.Document();
    final now = _dateTimeFmt.format(DateTime.now());
    final exportedOrders = orders
        .where((order) => order.status != OrderStatus.cancelled)
        .toList();
    final revenue = AccountingService.instance.netSales(exportedOrders);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: _theme(),
        header: (ctx) => _header(
          businessName,
          'Orders Report',
          subtitle ?? 'Generated: $now',
          ctx.pageNumber,
          ctx.pagesCount,
          userName: userName,
        ),
        footer: (ctx) => _footer(businessName),
        build: (ctx) => [
          pw.Row(
            children: [
              _box('Total Orders', '${exportedOrders.length}'),
              pw.SizedBox(width: 12),
              _box('Recognized Revenue', _pdfCurrency.format(revenue)),
              pw.SizedBox(width: 12),
              _box(
                'Pending',
                '${exportedOrders.where((o) => o.status == OrderStatus.pending).length}',
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(70),
              1: const pw.FixedColumnWidth(100),
              2: const pw.FixedColumnWidth(75),
              3: const pw.FixedColumnWidth(65),
              4: const pw.FlexColumnWidth(),
              5: const pw.FixedColumnWidth(80),
            },
            children: [
              _headerRow([
                'Order ID',
                'Customer',
                'Date',
                'Status',
                'Items',
                'Total',
              ]),
              ...(List<Order>.from(exportedOrders)..sort((a, b) {
                    const priority = {
                      OrderStatus.delivered: 0,
                      OrderStatus.utang: 1,
                      OrderStatus.cancelled: 2,
                      OrderStatus.pending: 3,
                      OrderStatus.shipped: 4,
                      OrderStatus.processing: 5,
                    };
                    final pa = priority[a.status] ?? 6;
                    final pb = priority[b.status] ?? 6;
                    return pa.compareTo(pb);
                  }))
                  .asMap()
                  .entries
                  .map((e) {
                    final o = e.value;
                    final even = e.key % 2 == 0;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: even ? PdfColors.grey50 : PdfColors.white,
                      ),
                      children: [
                        _cell(o.orderId, bold: true),
                        _cell(o.customerName),
                        _cell(_dateFormat.format(o.orderDate)),
                        _cell(
                          o.status.displayName,
                          color: _statusColor(o.status),
                        ),
                        _cell(
                          o.items
                              .map((i) => '${i.productName} x${i.quantity}')
                              .join(', '),
                        ),
                        _cell(
                          _pdfCurrency.format(o.customerPayAmount),
                          bold: true,
                        ), // FIX: was totalAmount
                      ],
                    );
                  }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('RECOGNIZED TOTAL', bold: true),
                  _cell(''),
                  _cell(''),
                  _cell(''),
                  _cell(''),
                  _cell(
                    _pdfCurrency.format(
                      AccountingService.instance.netSales(exportedOrders),
                    ),
                    bold: true,
                    color: PdfColors.grey800,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return pdf;
  }

  static pw.Document _buildInventoryPdf(
    List<Product> products, {
    required String businessName,
    String? userName,
  }) {
    final pdf = pw.Document();
    final now = _dateTimeFmt.format(DateTime.now());
    final lowStock = products.where((p) => p.isLowStock).length;
    final totalVal = products.fold(
      Money.zero,
      (s, p) => s + p.price * p.stockQty,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: _theme(),
        header: (ctx) => _header(
          businessName,
          'Inventory Report',
          'Generated: $now',
          ctx.pageNumber,
          ctx.pagesCount,
          userName: userName,
        ),
        footer: (ctx) => _footer(businessName),
        build: (ctx) => [
          pw.Row(
            children: [
              _box('Total Products', '${products.length}'),
              pw.SizedBox(width: 12),
              _box('Low Stock Items', '$lowStock'),
              pw.SizedBox(width: 12),
              _box('Est. Stock Value', _pdfCurrency.format(totalVal)),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FixedColumnWidth(90),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(55),
              4: const pw.FixedColumnWidth(55),
              5: const pw.FixedColumnWidth(65),
            },
            children: [
              _headerRow([
                'Name',
                'Category',
                'Price (PHP)',
                'Stock',
                'Min',
                'Status',
              ]),
              ...products.asMap().entries.map((e) {
                final p = e.value;
                final even = e.key % 2 == 0;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white,
                  ),
                  children: [
                    _cell(p.name, bold: true),
                    _cell(p.category.displayName),
                    _cell(_pdfCurrency.format(p.price)),
                    _cell(
                      '${p.stockQty}',
                      color: p.isLowStock ? PdfColors.red700 : PdfColors.black,
                    ),
                    _cell('${p.minStockLevel}'),
                    _cell(
                      p.isLowStock ? 'Low Stock' : 'OK',
                      color: p.isLowStock
                          ? PdfColors.red700
                          : PdfColors.green700,
                    ),
                  ],
                );
              }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('TOTAL', bold: true),
                  _cell(''),
                  _cell(''),
                  _cell(
                    '${products.fold(0, (s, p) => s + p.stockQty)}',
                    bold: true,
                  ),
                  _cell(''),
                  _cell(''),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return pdf;
  }

  static pw.Document _buildDebtsPdf(
    List<CustomerDebt> debts, {
    required String businessName,
    String? userName,
  }) {
    final pdf = pw.Document();
    final now = _dateTimeFmt.format(DateTime.now());
    final debtReport = AccountingService.instance.summarize(
      orders: const [],
      debts: debts,
    );
    final totalUnpaid = debtReport.receivables;
    final overdueCount = debts.where((d) => d.isOverdue).length;
    final unpaidCount = debts.where((d) => !d.isPaid).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: _theme(),
        header: (ctx) => _header(
          businessName,
          'Utang / Debt Report',
          'Generated: $now',
          ctx.pageNumber,
          ctx.pagesCount,
          userName: userName,
        ),
        footer: (ctx) => _footer(businessName),
        build: (ctx) => [
          pw.Row(
            children: [
              _box('Total Unpaid', _pdfCurrency.format(totalUnpaid)),
              pw.SizedBox(width: 12),
              _box('Unpaid Orders', '$unpaidCount'),
              pw.SizedBox(width: 12),
              _box('Overdue (7d+)', '$overdueCount'),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FixedColumnWidth(75),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(80),
              4: const pw.FixedColumnWidth(80),
              5: const pw.FixedColumnWidth(60),
              6: const pw.FixedColumnWidth(60),
            },
            children: [
              _headerRow([
                'Customer',
                'Order ID',
                'Principal Due',
                'Paid (PHP)',
                'Interest Due',
                'Total Due (PHP)',
                'Status',
              ]),
              ...debts.asMap().entries.map((e) {
                final d = e.value;
                final even = e.key % 2 == 0;
                final statusLabel = d.isPaid
                    ? 'Paid'
                    : d.isOverdue
                    ? 'Overdue'
                    : 'Unpaid';
                final statusColor = d.isPaid
                    ? PdfColors.green700
                    : d.isOverdue
                    ? PdfColors.red700
                    : PdfColors.orange700;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white,
                  ),
                  children: [
                    _cell(d.customerName, bold: true),
                    _cell(d.orderId),
                    _cell(_pdfCurrency.format(d.principalOutstanding)),
                    _cell(
                      _pdfCurrency.format(debtReport.debtCollectionsFor(d.id)),
                    ),
                    _cell(_pdfCurrency.format(d.interestOutstanding)),
                    _cell(
                      _pdfCurrency.format(d.totalWithInterest),
                      bold: true,
                      color: d.isPaid ? PdfColors.green700 : PdfColors.red700,
                    ),
                    _cell(statusLabel, color: statusColor),
                  ],
                );
              }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('TOTAL', bold: true),
                  _cell(''),
                  _cell(
                    _pdfCurrency.format(debtReport.receivablesPrincipal),
                    bold: true,
                  ),
                  _cell(
                    _pdfCurrency.format(debtReport.debtCollections),
                    bold: true,
                    color: PdfColors.green700,
                  ),
                  _cell(
                    _pdfCurrency.format(debtReport.receivablesInterest),
                    bold: true,
                  ),
                  _cell(
                    _pdfCurrency.format(debtReport.receivables),
                    bold: true,
                    color: PdfColors.red700,
                  ),
                  _cell(''),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return pdf;
  }

  // Builds an analytics PDF and opens the system share sheet
  static Future<void> exportAnalyticsPdf({
    required List<Order> orders,
    required List<CustomerDebt> debts,
    List<CustomOrder> customOrders = const [],
    required String businessName,
    String? userName,
    DateTime? paymentFrom,
    DateTime? paymentTo,
    String reportTitle = 'Analytics Report',
  }) async {
    await _ensureFonts();
    final bytes = await _buildAnalyticsPdf(
      orders: orders,
      debts: debts,
      customOrders: customOrders,
      businessName: businessName,
      userName: userName,
      paymentFrom: paymentFrom,
      paymentTo: paymentTo,
      reportTitle: reportTitle,
    ).save();
    await _pdfShare(
      bytes,
      'knz_analytics_${_dateFormat.format(DateTime.now())}.pdf',
      '${AppStrings.appName} — $reportTitle',
    );
  }

  static Future<List<int>> buildAnalyticsPdfBytes({
    required List<Order> orders,
    required List<CustomerDebt> debts,
    List<CustomOrder> customOrders = const [],
    required String businessName,
    String? userName,
    DateTime? paymentFrom,
    DateTime? paymentTo,
    String reportTitle = 'Revenue & Collections Summary',
  }) async {
    await _ensureFonts();
    return _buildAnalyticsPdf(
      orders: orders,
      debts: debts,
      customOrders: customOrders,
      businessName: businessName,
      userName: userName,
      paymentFrom: paymentFrom,
      paymentTo: paymentTo,
      reportTitle: reportTitle,
    ).save();
  }

  // Prints the analytics report via the system print dialog
  static Future<void> printAnalyticsPdf({
    required List<Order> orders,
    required List<CustomerDebt> debts,
    List<CustomOrder> customOrders = const [],
    required String businessName,
    String? userName,
    DateTime? paymentFrom,
    DateTime? paymentTo,
    String reportTitle = 'Analytics Report',
  }) async {
    await _ensureFonts();
    final pdf = _buildAnalyticsPdf(
      orders: orders,
      debts: debts,
      customOrders: customOrders,
      businessName: businessName,
      userName: userName,
      paymentFrom: paymentFrom,
      paymentTo: paymentTo,
      reportTitle: reportTitle,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: '${AppStrings.appName} $reportTitle',
    );
  }

  // Builds the multi-page analytics PDF document:
  //   Page 1 — Summary KPIs (with Total Revenue) + Orders by Status
  //   Page 2 — Utang / Debt Records
  //   Page 3 — Top Products by Sales
  static pw.Document _buildAnalyticsPdf({
    required List<Order> orders,
    required List<CustomerDebt> debts,
    List<CustomOrder> customOrders = const [],
    required String businessName,
    String? userName,
    DateTime? paymentFrom,
    DateTime? paymentTo,
    String reportTitle = 'Analytics Report',
  }) {
    final pdf = pw.Document();
    final now = _dateTimeFmt.format(DateTime.now());

    // ── Derived values ────────────────────────────────────────────────────────
    final report = AccountingService.instance.summarize(
      orders: orders,
      debts: debts,
      customOrders: customOrders,
      period: AccountingPeriod(from: paymentFrom, to: paymentTo),
    );
    final totalOrders = orders.length;
    final deliveredCount = report.recognizedOrders.length;
    final itemsSold = report.itemsSold;
    final totalDebt = report.receivables;
    final unpaidCount = debts.where((d) => !d.isPaid).length;
    final paidCount = debts.where((d) => d.isPaid).length;
    final overdueCount = debts.where((d) => d.isOverdue).length;

    // ── Top products ──────────────────────────────────────────────────────────
    final salesMap = <String, int>{};
    for (final o in report.recognizedOrders) {
      for (final item in o.items) {
        salesMap[item.productName] =
            (salesMap[item.productName] ?? 0) + item.quantity;
      }
    }
    final topProducts = salesMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: _theme(),
        header: (ctx) => _header(
          businessName,
          reportTitle,
          'Generated: $now',
          ctx.pageNumber,
          ctx.pagesCount,
          userName: userName,
        ),
        footer: (ctx) => _footer(businessName),
        build: (ctx) => [
          // ── Section 1: Summary KPIs ─────────────────────────────────────────
          pw.Text(
            'Summary',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 10),

          // ── TOTAL REVENUE box — spans full width ──────────────────────────
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 14,
            ),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TOTAL CASH RECEIVED',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Paid sales, debt collections, and custom-order receipts',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey500,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  _pdfCurrency.format(report.cashReceived),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          pw.Row(
            children: [
              _box('Gross Sales', _pdfCurrency.format(report.grossSales)),
              pw.SizedBox(width: 10),
              _box('Discounts', _pdfCurrency.format(report.discounts)),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ),
          pw.SizedBox(height: 8),

          // ── Breakdown: Delivered Revenue + Utang Collected side by side ────
          pw.Row(
            children: [
              _box('Recognized Revenue', _pdfCurrency.format(report.netSales)),
              pw.SizedBox(width: 10),
              _box(
                'Debt Collections',
                _pdfCurrency.format(report.debtCollections),
              ),
              pw.SizedBox(width: 10),
              _box(
                'Custom Receipts',
                _pdfCurrency.format(report.customOrderReceipts),
              ),
            ],
          ),
          pw.SizedBox(height: 10),

          // ── Other KPI boxes ────────────────────────────────────────────────
          pw.Row(
            children: [
              _box('Total Orders', '$totalOrders'),
              pw.SizedBox(width: 10),
              _box('Recognized Sales', '$deliveredCount'),
              pw.SizedBox(width: 10),
              _box('Items Sold', '$itemsSold'),
              pw.SizedBox(width: 10),
              _box('Total Utang', _pdfCurrency.format(totalDebt)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              _box('Unpaid', '$unpaidCount'),
              pw.SizedBox(width: 10),
              _box('Paid', '$paidCount'),
              pw.SizedBox(width: 10),
              _box('Overdue', '$overdueCount'),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Section 2: Orders by Status ─────────────────────────────────────
          pw.Text(
            'Orders by Status',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FixedColumnWidth(70),
              2: const pw.FixedColumnWidth(80),
            },
            children: [
              _headerRow(['Status', 'Count', '% of Total']),
              ...OrderStatus.values.asMap().entries.map((e) {
                final s = e.value;
                final count = orders.where((o) => o.status == s).length;
                final pct = totalOrders > 0
                    ? '${(count / totalOrders * 100).toStringAsFixed(1)}%'
                    : '0.0%';
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: e.key % 2 == 0 ? PdfColors.grey50 : PdfColors.white,
                  ),
                  children: [
                    _cell(s.displayName),
                    _cell('$count', bold: true),
                    _cell(pct),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Section 3: Utang Records ─────────────────────────────────────────
          pw.Text(
            'Utang / Debt Records',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FixedColumnWidth(70),
              2: const pw.FixedColumnWidth(72),
              3: const pw.FixedColumnWidth(72),
              4: const pw.FixedColumnWidth(72),
              5: const pw.FixedColumnWidth(68),
              6: const pw.FixedColumnWidth(55),
            },
            children: [
              _headerRow([
                'Customer',
                'Order ID',
                'Principal Due',
                'Collected (PHP)',
                'Interest Due',
                'Total Due (PHP)',
                'Status',
              ]),
              ...debts.asMap().entries.map((e) {
                final d = e.value;
                final even = e.key % 2 == 0;
                final statusLabel = d.isPaid
                    ? 'Paid'
                    : d.isOverdue
                    ? 'Overdue'
                    : 'Unpaid';
                final statusColor = d.isPaid
                    ? PdfColors.green700
                    : d.isOverdue
                    ? PdfColors.red700
                    : PdfColors.orange700;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white,
                  ),
                  children: [
                    _cell(d.customerName, bold: true),
                    _cell(d.orderId),
                    _cell(_pdfCurrency.format(d.principalOutstanding)),
                    _cell(_pdfCurrency.format(report.debtCollectionsFor(d.id))),
                    _cell(_pdfCurrency.format(d.interestOutstanding)),
                    _cell(
                      _pdfCurrency.format(d.totalWithInterest),
                      bold: true,
                      color: d.isPaid ? PdfColors.green700 : PdfColors.red700,
                    ),
                    _cell(statusLabel, color: statusColor),
                  ],
                );
              }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('TOTAL', bold: true),
                  _cell(''),
                  _cell(
                    _pdfCurrency.format(report.receivablesPrincipal),
                    bold: true,
                  ),
                  _cell(
                    _pdfCurrency.format(report.debtCollections),
                    bold: true,
                    color: PdfColors.green700,
                  ),
                  _cell(
                    _pdfCurrency.format(
                      debts.fold(
                        Money.zero,
                        (s, d) => s + d.interestOutstanding,
                      ),
                    ),
                    bold: true,
                  ),
                  _cell(
                    _pdfCurrency.format(report.receivables),
                    bold: true,
                    color: PdfColors.red700,
                  ),
                  _cell(''),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Section 4: Top Products ──────────────────────────────────────────
          pw.Text(
            'Top Products by Sales',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(35),
              1: const pw.FlexColumnWidth(),
              2: const pw.FixedColumnWidth(100),
            },
            children: [
              _headerRow(['Rank', 'Product Name', 'Total Units Sold']),
              ...topProducts.asMap().entries.map((e) {
                final even = e.key % 2 == 0;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white,
                  ),
                  children: [
                    _cell('${e.key + 1}', bold: true),
                    _cell(e.value.key),
                    _cell('${e.value.value}', bold: true),
                  ],
                );
              }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell(''),
                  _cell('TOTAL', bold: true),
                  _cell(
                    '${topProducts.fold(0, (s, e) => s + e.value)}',
                    bold: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return pdf;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF WIDGET HELPERS — reusable layout components for PDF pages
  // ════════════════════════════════════════════════════════════════════════════

  static pw.Widget _header(
    String biz,
    String title,
    String sub,
    int pageNum,
    int pageCount, {
    String? userName,
  }) => pw.Column(
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                biz,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
              pw.Text(
                title,
                style: const pw.TextStyle(
                  fontSize: 13,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                sub,
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey500,
                ),
              ),
              if (userName != null && userName.isNotEmpty)
                pw.Text(
                  'Generated by: $userName',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey500,
                  ),
                ),
            ],
          ),
          pw.Text(
            'Page $pageNum / $pageCount',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
      pw.Divider(color: PdfColors.grey400, thickness: 0.5),
      pw.SizedBox(height: 8),
    ],
  );

  static pw.Widget _footer(String biz) => pw.Column(
    children: [
      pw.Divider(color: PdfColors.grey300, thickness: 0.5),
      pw.SizedBox(height: 4),
      pw.Text(
        '$biz - Confidential Business Record',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400),
        textAlign: pw.TextAlign.center,
      ),
    ],
  );

  // Standard grey summary box
  static pw.Widget _box(String label, String value) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    ),
  );

  static pw.TableRow _headerRow(List<String> cols) => pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColors.grey800),
    children: cols
        .map(
          (t) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: pw.Text(
              t,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        )
        .toList(),
  );

  static pw.Widget _cell(String text, {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? PdfColors.grey800,
          ),
        ),
      );

  static PdfColor _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return PdfColors.green700;
      case OrderStatus.cancelled:
        return PdfColors.red700;
      case OrderStatus.pending:
        return PdfColors.orange700;
      case OrderStatus.utang:
        return PdfColors.amber700;
      default:
        return PdfColors.grey700;
    }
  }

  // ── Custom Orders CSV export (Feature 5 / Feature 6) ─────────────────────

  /// Dedicated reseller report with SRP, discount, and net amounts per order.
  static Future<void> exportResellerDetailedPdf(
    List<Order> orders, {
    required String businessName,
  }) async {
    await _ensureFonts();
    final report = AccountingService.instance.summarize(
      orders: orders,
      debts: const [],
    );
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: _theme(),
        header: (ctx) => _header(
          businessName,
          'Reseller Sales Detail',
          'Generated: ${_dateTimeFmt.format(DateTime.now())}',
          ctx.pageNumber,
          ctx.pagesCount,
        ),
        footer: (ctx) => _footer(businessName),
        build: (_) => [
          pw.Row(
            children: [
              _box('Gross SRP', _pdfCurrency.format(report.grossSales)),
              pw.SizedBox(width: 10),
              _box('Discounts', _pdfCurrency.format(report.discounts)),
              pw.SizedBox(width: 10),
              _box('Net Revenue', _pdfCurrency.format(report.netSales)),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(62),
              1: pw.FlexColumnWidth(1.7),
              2: pw.FlexColumnWidth(2.3),
              3: pw.FixedColumnWidth(67),
              4: pw.FixedColumnWidth(67),
              5: pw.FixedColumnWidth(67),
              6: pw.FixedColumnWidth(58),
            },
            children: [
              _headerRow([
                'Order',
                'Reseller',
                'Items',
                'Gross',
                'Discount',
                'Net',
                'Per Item',
              ]),
              ...orders.asMap().entries.map((entry) {
                final order = entry.value;
                final breakdown = AccountingService.instance.orderBreakdown(
                  order,
                );
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: entry.key.isEven
                        ? PdfColors.grey50
                        : PdfColors.white,
                  ),
                  children: [
                    _cell(order.orderId, bold: true),
                    _cell(order.customerName),
                    _cell(
                      order.items
                          .map(
                            (item) => '${item.productName} x${item.quantity}',
                          )
                          .join(', '),
                    ),
                    _cell(_pdfCurrency.format(breakdown.srpTotal)),
                    _cell(_pdfCurrency.format(breakdown.discount)),
                    _cell(
                      _pdfCurrency.format(breakdown.customerPayTotal),
                      bold: true,
                    ),
                    _cell(_pdfCurrency.format(order.deductionPerItem)),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    await _pdfShare(
      await pdf.save(),
      'knz_reseller_detail_${_dateFormat.format(DateTime.now())}.pdf',
      '${AppStrings.appName} — Reseller Sales Detail',
    );
  }

  /// Dedicated custom-order agreement/status report.
  static Future<void> exportCustomOrdersPdf(
    List<CustomOrder> orders, {
    required String businessName,
  }) async {
    await _ensureFonts();
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: _theme(),
        header: (ctx) => _header(
          businessName,
          'Custom Order Status',
          'Generated: ${_dateTimeFmt.format(DateTime.now())}',
          ctx.pageNumber,
          ctx.pagesCount,
        ),
        footer: (ctx) => _footer(businessName),
        build: (_) => [
          pw.Row(
            children: [
              _box('Custom Orders', '${orders.length}'),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.SizedBox()),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.5),
              1: pw.FlexColumnWidth(2.2),
              2: pw.FixedColumnWidth(65),
              3: pw.FixedColumnWidth(65),
              4: pw.FixedColumnWidth(65),
              5: pw.FixedColumnWidth(65),
              6: pw.FixedColumnWidth(60),
              7: pw.FlexColumnWidth(1.4),
            },
            children: [
              _headerRow([
                'Customer',
                'Specifications',
                'Price',
                'Deposit',
                'Balance',
                'Delivery',
                'Status',
                'Payments',
              ]),
              ...orders.asMap().entries.map((entry) {
                final order = entry.value;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: entry.key.isEven
                        ? PdfColors.grey50
                        : PdfColors.white,
                  ),
                  children: [
                    _cell(order.customerName, bold: true),
                    _cell(order.fragranceSpecs),
                    _cell(_pdfCurrency.format(order.agreedPrice)),
                    _cell(_pdfCurrency.format(order.depositPaid)),
                    _cell(_pdfCurrency.format(order.balanceDue), bold: true),
                    _cell(_dateFormat.format(order.deliveryDate)),
                    _cell(order.status.displayName),
                    _cell(
                      order.payments
                          .map(
                            (payment) =>
                                '${_dateFormat.format(payment.paidAt)} ${_pdfCurrency.format(payment.amount)}',
                          )
                          .join(', '),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
    await _pdfShare(
      await pdf.save(),
      'knz_custom_orders_${_dateFormat.format(DateTime.now())}.pdf',
      '${AppStrings.appName} — Custom Orders',
    );
  }

  static Future<void> exportCustomOrdersCsv(List<CustomOrder> orders) async {
    final rows = <List<dynamic>>[
      [
        'Customer',
        'Contact',
        'Fragrance Specs',
        'Agreed Price (PHP)',
        'Deposit Paid (PHP)',
        'Balance Due (PHP)',
        'Delivery Date',
        'Status',
        'Terms',
        'Payment History',
      ],
    ];
    for (final o in orders) {
      rows.add([
        o.customerName,
        o.contact ?? '',
        o.fragranceSpecs,
        o.agreedPrice.toStringAsFixed(2),
        o.depositPaid.toStringAsFixed(2),
        o.balanceDue.toStringAsFixed(2),
        _dateFormat.format(o.deliveryDate),
        o.status.displayName,
        o.terms ?? '',
        o.payments
            .map(
              (payment) =>
                  '${_dateTimeFmt.format(payment.paidAt)} ${payment.amount.toStringAsFixed(2)}',
            )
            .join(' | '),
      ]);
    }
    await _csvShare(
      rows,
      'KNZ_CustomOrders_${_dateFormat.format(DateTime.now())}.csv',
      'KNZ Scent — Custom Orders',
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FILE I/O HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> _csvShare(
    List<List<dynamic>> rows,
    String filename,
    String subject,
  ) async {
    final csv = encodeCsvRows(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString('\uFEFF$csv', encoding: utf8);
    try {
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: subject);
    } finally {
      await _deleteTemporaryFile(file);
    }
  }

  static Future<void> _pdfShare(
    List<int> bytes,
    String filename,
    String subject,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    try {
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], subject: subject);
    } finally {
      await _deleteTemporaryFile(file);
    }
  }

  static Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup is best-effort and must not turn a successful export into an
      // error. The operating system can still purge its temporary directory.
    }
  }
}

class _CentavoCurrencyFormatter {
  const _CentavoCurrencyFormatter();

  String format(Money value) => 'PHP ${value.toStringAsFixed(2)}';
}
