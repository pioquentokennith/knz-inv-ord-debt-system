// ─────────────────────────────────────────────────────────────────────────────
// agreement_pdf_service.dart — Generates a printable Custom Perfume Agreement PDF
// Purpose : Builds a formatted, branded PDF using the same pdf/printing/share_plus
//           stack as ExportService so no new dependencies are needed.
// OOP: Abstraction — callers only call generateAndShare(order, ownerName).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/custom_order_model.dart';

class AgreementPdfService {
  AgreementPdfService._();
  static final instance = AgreementPdfService._();

  // Font cache — same lazy-load approach as ExportService
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    try {
      _regular = await PdfGoogleFonts.notoSansRegular();
      _bold = await PdfGoogleFonts.notoSansBold();
    } catch (_) {
      _regular = pw.Font.helvetica();
      _bold = pw.Font.helveticaBold();
    }
  }

  static pw.ThemeData _theme() => pw.ThemeData.withFont(
    base: _regular ?? pw.Font.helvetica(),
    bold: _bold ?? pw.Font.helveticaBold(),
  );

  // ── Public entry point ────────────────────────────────────────────────────

  /// Generates the PDF and opens the system share sheet.
  Future<void> generateAndShare(
    CustomOrder order, {
    String ownerName = 'KNZ Scent',
  }) async {
    await _ensureFonts();
    final bytes = await _build(order, ownerName);
    await _share(bytes, 'KNZ_Agreement_${order.id.substring(0, 6)}.pdf');
  }

  // ── PDF builder ───────────────────────────────────────────────────────────

  Future<List<int>> _build(CustomOrder order, String ownerName) async {
    final pdf = pw.Document(theme: _theme());
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFmt = DateFormat('MMMM dd, yyyy');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── 1. Header ────────────────────────────────────────────────────
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'KNZ SCENT',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('D4AF37'),
                      ),
                    ),
                    pw.Text(
                      'Custom Perfume Agreement',
                      style: const pw.TextStyle(
                        fontSize: 13,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Date: ${dateFmt.format(order.createdAt)}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.Text(
                      'Ref: ${order.id.substring(0, 8).toUpperCase()}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Divider(color: PdfColor.fromHex('D4AF37'), thickness: 1.5),
            pw.SizedBox(height: 12),

            // ── 2. Customer details ──────────────────────────────────────────
            _sectionHeader('CUSTOMER DETAILS'),
            pw.SizedBox(height: 6),
            _infoRow('Customer Name', order.customerName),
            if (order.contact != null) _infoRow('Contact', order.contact!),
            pw.SizedBox(height: 14),

            // ── 3. Fragrance specifications ──────────────────────────────────
            _sectionHeader('FRAGRANCE SPECIFICATIONS'),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                order.fragranceSpecs,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey800,
                ),
              ),
            ),
            pw.SizedBox(height: 14),

            // ── 4. Pricing breakdown ─────────────────────────────────────────
            _sectionHeader('PRICING'),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _tableRow(['Description', 'Amount'], isHeader: true),
                _tableRow(['Agreed Price', currency.format(order.agreedPrice)]),
                _tableRow(['Deposit Paid', currency.format(order.depositPaid)]),
                _tableRow([
                  'Balance Due',
                  currency.format(order.balanceDue),
                ], bold: true),
              ],
            ),
            pw.SizedBox(height: 14),

            // ── 5. Delivery date ─────────────────────────────────────────────
            _sectionHeader('DELIVERY'),
            pw.SizedBox(height: 6),
            _infoRow(
              'Target Delivery Date',
              dateFmt.format(order.deliveryDate),
            ),
            pw.SizedBox(height: 14),

            // ── 6. Terms & conditions ────────────────────────────────────────
            if (order.terms != null && order.terms!.isNotEmpty) ...[
              _sectionHeader('TERMS AND CONDITIONS'),
              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(6),
                  ),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text(
                  order.terms!,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(height: 14),
            ],

            // ── 7. Signature lines ───────────────────────────────────────────
            pw.Spacer(),
            pw.Divider(color: PdfColors.grey400),
            pw.SizedBox(height: 16),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _signatureBlock('Owner / KNZ Scent', ownerName),
                _signatureBlock('Customer', order.customerName),
                _signatureBlock('Date', dateFmt.format(DateTime.now())),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                'This agreement is binding upon both parties. KNZ Scent · knzscent.com',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  // ── Private PDF helpers ───────────────────────────────────────────────────

  static pw.Widget _sectionHeader(String title) => pw.Text(
    title,
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey600,
      letterSpacing: 1.5,
    ),
  );

  static pw.Widget _infoRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
        ),
        pw.Text(
          ': ',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey400),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
        ),
      ],
    ),
  );

  static pw.TableRow _tableRow(
    List<String> cells, {
    bool isHeader = false,
    bool bold = false,
  }) {
    final bg = isHeader ? PdfColors.grey800 : PdfColors.white;
    final fg = isHeader
        ? PdfColors.white
        : (bold ? PdfColors.grey900 : PdfColors.grey700);
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: cells
          .map(
            (t) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 8,
              ),
              child: pw.Text(
                t,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: (isHeader || bold)
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: fg,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  static pw.Widget _signatureBlock(String role, String name) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(width: 120, height: 0.5, color: PdfColors.grey600),
      pw.SizedBox(height: 4),
      pw.Text(
        name,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
      ),
      pw.Text(
        role,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
      ),
    ],
  );

  // ── File I/O ──────────────────────────────────────────────────────────────

  Future<void> _share(List<int> bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    try {
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf'),
      ], subject: 'KNZ Scent — Custom Perfume Agreement');
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup; do not mask the share result.
      }
    }
  }
}
