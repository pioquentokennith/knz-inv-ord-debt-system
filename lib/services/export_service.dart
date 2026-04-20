// ─────────────────────────────────────────────────────────────────────────────
// export_service.dart — CSV and PDF export for orders, inventory, and utang
//
// FIX: Peso sign (₱) rendering fix —
//   • PDF  : loads NotoSans from Google Fonts (supports ₱ natively)
//   • CSV  : uses "PHP" label in column headers + UTF-8 BOM for Excel
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
import '../core/app_constants.dart';

class ExportService {
  ExportService._();

  static final _pdfCurrency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  static final _dateFormat  = DateFormat('yyyy-MM-dd');
  static final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

  // ── Font cache ─────────────────────────────────────────────────────────────
  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Load NotoSans from Google Fonts — has full Unicode coverage (₱ included).
  /// Falls back to Helvetica if offline (peso will render as box, rest is fine).
  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    try {
      _regular = await PdfGoogleFonts.notoSansRegular();
      _bold    = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      _regular = pw.Font.helvetica();
      _bold    = pw.Font.helveticaBold();
    }
  }

  static pw.ThemeData _theme() => pw.ThemeData.withFont(
        base: _regular ?? pw.Font.helvetica(),
        bold: _bold    ?? pw.Font.helveticaBold(),
      );

  // ════════════════════════════════════════════════════════════════════════════
  // CSV
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> exportOrdersCsv(List<Order> orders) async {
    final rows = <List<dynamic>>[
      ['Order ID', 'Customer', 'Date', 'Status', 'Items',
       'Total Amount (PHP)', 'Notes'],
    ];
    for (final o in orders) {
      rows.add([
        o.orderId,
        o.customerName,
        _dateFormat.format(o.orderDate),
        o.status.displayName,
        o.items.map((i) => '${i.productName} x${i.quantity}').join(' | '),
        o.totalAmount.toStringAsFixed(2),
        o.notes ?? '',
      ]);
    }
    await _csvShare(rows,
        'knz_orders_${_dateFormat.format(DateTime.now())}.csv',
        '${AppStrings.appName} — Orders Export');
  }

  static Future<void> exportInventoryCsv(List<Product> products) async {
    final rows = <List<dynamic>>[
      ['Name', 'Category', 'Price (PHP)', 'Stock Qty',
       'Min Stock Level', 'Status', 'Description', 'Created At'],
    ];
    for (final p in products) {
      rows.add([
        p.name,
        p.category.displayName,
        p.price.toStringAsFixed(2),
        p.stockQty,
        p.minStockLevel,
        p.isLowStock ? 'Low Stock' : 'OK',
        p.description,
        _dateFormat.format(p.createdAt),
      ]);
    }
    await _csvShare(rows,
        'knz_inventory_${_dateFormat.format(DateTime.now())}.csv',
        '${AppStrings.appName} — Inventory Export');
  }

  static Future<void> exportDebtsCsv(List<CustomerDebt> debts) async {
    final rows = <List<dynamic>>[
      ['Customer', 'Order ID', 'Total (PHP)', 'Paid (PHP)',
       'Balance (PHP)', 'Status', 'Days Old', 'Created At'],
    ];
    for (final d in debts) {
      rows.add([
        d.customerName,
        d.orderId,
        d.totalAmount.toStringAsFixed(2),
        d.amountPaid.toStringAsFixed(2),
        d.remainingBalance.toStringAsFixed(2),
        d.isPaid ? 'Paid' : (d.isOverdue ? 'Overdue' : 'Unpaid'),
        d.daysOld,
        _dateFormat.format(d.createdAt),
      ]);
    }
    await _csvShare(rows,
        'knz_utang_${_dateFormat.format(DateTime.now())}.csv',
        '${AppStrings.appName} — Utang Export');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF — export (share)
  // ════════════════════════════════════════════════════════════════════════════

  static Future<void> exportOrdersPdf(List<Order> orders,
      {required String businessName, String? subtitle}) async {
    await _ensureFonts();
    final bytes = await _buildOrdersPdf(orders,
            businessName: businessName, subtitle: subtitle)
        .save();
    await _pdfShare(bytes,
        'knz_orders_${_dateFormat.format(DateTime.now())}.pdf',
        '${AppStrings.appName} — Orders Report');
  }

  static Future<void> exportInventoryPdf(List<Product> products,
      {required String businessName}) async {
    await _ensureFonts();
    final bytes =
        await _buildInventoryPdf(products, businessName: businessName).save();
    await _pdfShare(bytes,
        'knz_inventory_${_dateFormat.format(DateTime.now())}.pdf',
        '${AppStrings.appName} — Inventory Report');
  }

  static Future<void> exportDebtsPdf(List<CustomerDebt> debts,
      {required String businessName}) async {
    await _ensureFonts();
    final bytes =
        await _buildDebtsPdf(debts, businessName: businessName).save();
    await _pdfShare(bytes,
        'knz_utang_${_dateFormat.format(DateTime.now())}.pdf',
        '${AppStrings.appName} — Utang Report');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF — print
  // ════════════════════════════════════════════════════════════════════════════

  /// FIX: Removed unused [context] parameter — Printing.layoutPdf doesn't need it.
  static Future<void> printOrdersPdf(List<Order> orders,
      {required String businessName}) async {
    await _ensureFonts();
    final pdf = _buildOrdersPdf(orders, businessName: businessName);
    await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(), name: '${AppStrings.appName} Orders Report');
  }

  static Future<void> printInventoryPdf(List<Product> products,
      {required String businessName}) async {
    await _ensureFonts();
    final pdf = _buildInventoryPdf(products, businessName: businessName);
    await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(), name: '${AppStrings.appName} Inventory Report');
  }

  static Future<void> printDebtsPdf(List<CustomerDebt> debts,
      {required String businessName}) async {
    await _ensureFonts();
    final pdf = _buildDebtsPdf(debts, businessName: businessName);
    await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(), name: '${AppStrings.appName} Utang Report');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF BUILDERS
  // ════════════════════════════════════════════════════════════════════════════

  static pw.Document _buildOrdersPdf(List<Order> orders,
      {required String businessName, String? subtitle}) {
    final pdf = pw.Document();
    final now = _dateTimeFmt.format(DateTime.now());
    final revenue = orders
        .where((o) => o.status == OrderStatus.delivered)
        .fold(0.0, (s, o) => s + o.totalAmount);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      header: (ctx) => _header(businessName, 'Orders Report',
          subtitle ?? 'Generated: $now', ctx.pageNumber, ctx.pagesCount),
      footer: (ctx) => _footer(businessName),
      build: (ctx) => [
        pw.Row(children: [
          _box('Total Orders', '${orders.length}'),
          pw.SizedBox(width: 12),
          _box('Delivered Revenue', _pdfCurrency.format(revenue)),
          pw.SizedBox(width: 12),
          _box('Pending',
              '${orders.where((o) => o.status == OrderStatus.pending).length}'),
        ]),
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
            _headerRow(['Order ID', 'Customer', 'Date', 'Status', 'Items', 'Total']),
            ...orders.asMap().entries.map((e) {
              final o = e.value;
              final even = e.key % 2 == 0;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white),
                children: [
                  _cell(o.orderId, bold: true),
                  _cell(o.customerName),
                  _cell(_dateFormat.format(o.orderDate)),
                  _cell(o.status.displayName, color: _statusColor(o.status)),
                  _cell(o.items
                      .map((i) => '${i.productName} x${i.quantity}')
                      .join(', ')),
                  _cell(_pdfCurrency.format(o.totalAmount), bold: true),
                ],
              );
            }),
          ],
        ),
      ],
    ));
    return pdf;
  }

  static pw.Document _buildInventoryPdf(List<Product> products,
      {required String businessName}) {
    final pdf = pw.Document();
    final now = _dateTimeFmt.format(DateTime.now());
    final lowStock  = products.where((p) => p.isLowStock).length;
    final totalVal  = products.fold(0.0, (s, p) => s + p.price * p.stockQty);

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      header: (ctx) => _header(businessName, 'Inventory Report',
          'Generated: $now', ctx.pageNumber, ctx.pagesCount),
      footer: (ctx) => _footer(businessName),
      build: (ctx) => [
        pw.Row(children: [
          _box('Total Products', '${products.length}'),
          pw.SizedBox(width: 12),
          _box('Low Stock Items', '$lowStock'),
          pw.SizedBox(width: 12),
          _box('Est. Stock Value', _pdfCurrency.format(totalVal)),
        ]),
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
            _headerRow(['Name', 'Category', 'Price (PHP)', 'Stock', 'Min', 'Status']),
            ...products.asMap().entries.map((e) {
              final p    = e.value;
              final even = e.key % 2 == 0;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white),
                children: [
                  _cell(p.name, bold: true),
                  _cell(p.category.displayName),
                  _cell(_pdfCurrency.format(p.price)),
                  _cell('${p.stockQty}',
                      color: p.isLowStock ? PdfColors.red700 : PdfColors.black),
                  _cell('${p.minStockLevel}'),
                  _cell(p.isLowStock ? 'Low Stock' : 'OK',
                      color: p.isLowStock
                          ? PdfColors.red700
                          : PdfColors.green700),
                ],
              );
            }),
          ],
        ),
      ],
    ));
    return pdf;
  }

  static pw.Document _buildDebtsPdf(List<CustomerDebt> debts,
      {required String businessName}) {
    final pdf = pw.Document();
    final now        = _dateTimeFmt.format(DateTime.now());
    final totalUnpaid = debts
        .where((d) => !d.isPaid)
        .fold(0.0, (s, d) => s + d.remainingBalance);
    final overdueCount = debts.where((d) => d.isOverdue).length;
    final unpaidCount  = debts.where((d) => !d.isPaid).length;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: _theme(),
      header: (ctx) => _header(businessName, 'Utang / Debt Report',
          'Generated: $now', ctx.pageNumber, ctx.pagesCount),
      footer: (ctx) => _footer(businessName),
      build: (ctx) => [
        pw.Row(children: [
          _box('Total Unpaid', _pdfCurrency.format(totalUnpaid)),
          pw.SizedBox(width: 12),
          _box('Unpaid Orders', '$unpaidCount'),
          pw.SizedBox(width: 12),
          _box('Overdue (7d+)', '$overdueCount'),
        ]),
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
          },
          children: [
            _headerRow(['Customer', 'Order ID', 'Total (PHP)',
                        'Paid (PHP)', 'Balance (PHP)', 'Status']),
            ...debts.asMap().entries.map((e) {
              final d    = e.value;
              final even = e.key % 2 == 0;
              final statusLabel = d.isPaid
                  ? 'Paid'
                  : d.isOverdue ? 'Overdue' : 'Unpaid';
              final statusColor = d.isPaid
                  ? PdfColors.green700
                  : d.isOverdue ? PdfColors.red700 : PdfColors.orange700;
              return pw.TableRow(
                decoration: pw.BoxDecoration(
                    color: even ? PdfColors.grey50 : PdfColors.white),
                children: [
                  _cell(d.customerName, bold: true),
                  _cell(d.orderId),
                  _cell(_pdfCurrency.format(d.totalAmount)),
                  _cell(_pdfCurrency.format(d.amountPaid)),
                  _cell(_pdfCurrency.format(d.remainingBalance),
                      bold: true,
                      color: d.isPaid ? PdfColors.green700 : PdfColors.red700),
                  _cell(statusLabel, color: statusColor),
                ],
              );
            }),
          ],
        ),
      ],
    ));
    return pdf;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PDF WIDGET HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  static pw.Widget _header(String biz, String title, String sub,
          int pageNum, int pageCount) =>
      pw.Column(children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(biz,
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800)),
            pw.Text(title,
                style: const pw.TextStyle(
                    fontSize: 13, color: PdfColors.grey600)),
            pw.Text(sub,
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey500)),
          ]),
          pw.Text('Page $pageNum / $pageCount',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey500)),
        ]),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.SizedBox(height: 8),
      ]);

  static pw.Widget _footer(String biz) => pw.Column(children: [
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Text('$biz — Confidential Business Record',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey400),
            textAlign: pw.TextAlign.center),
      ]);

  static pw.Widget _box(String label, String value) => pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label,
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey600)),
            pw.SizedBox(height: 2),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey800)),
          ]),
        ),
      );

  static pw.TableRow _headerRow(List<String> cols) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey800),
        children: cols
            .map((t) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 6, horizontal: 6),
                  child: pw.Text(t,
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white)),
                ))
            .toList(),
      );

  static pw.Widget _cell(String text,
          {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: color ?? PdfColors.grey800)),
      );

  static PdfColor _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered: return PdfColors.green700;
      case OrderStatus.cancelled: return PdfColors.red700;
      case OrderStatus.pending:   return PdfColors.orange700;
      case OrderStatus.utang:     return PdfColors.amber700;
      default:                    return PdfColors.grey700;
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FILE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  /// Write CSV with UTF-8 BOM so Excel opens ₱/special chars correctly.
  static Future<void> _csvShare(
      List<List<dynamic>> rows, String filename, String subject) async {
    final csv = const ListToCsvConverter().convert(rows);
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    // BOM (\uFEFF) tells Excel this is UTF-8 — prevents garbled characters
    await file.writeAsString('\uFEFF$csv', encoding: utf8);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: subject,
    );
  }

  static Future<void> _pdfShare(
      List<int> bytes, String filename, String subject) async {
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: subject,
    );
  }
}
