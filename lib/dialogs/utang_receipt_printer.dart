// ─────────────────────────────────────────────────────────────────────────────
// utang_receipt_printer.dart
// Purpose : Full-screen receipt viewer and Bluetooth thermal printer for utang
//           (debt) statements.
// Function: UtangReceiptPrinter builds ESC/POS byte sequences from a CustomerDebt
//           object for 58mm thermal printers. UtangReceiptScreen shows an on-screen
//           preview using shared receipt widgets (ReceiptCard, ReceiptHeader, etc.)
//           and embeds a Bluetooth print panel (_UtangPrintPanel) that manages the
//           full BT scan → connect → print → disconnect lifecycle using the sealed
//           BtPrintState hierarchy defined in receipt_shared_widgets.dart.
// Usage   : UtangReceiptScreen.show(context, debt, userName: AppState().currentUser?.displayName ?? '');
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../models/debt_model.dart';
import '../widgets/receipt_shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UtangReceiptPrinter — Abstraction: ESC/POS byte-building for utang receipts.
//
// OOP:
//   • Single Responsibility — only knows how to turn a CustomerDebt into bytes.
//   • Abstraction          — callers call buildBytes(); internals are hidden.
//   • Encapsulation        — formatting helpers are private static members.
// ─────────────────────────────────────────────────────────────────────────────
class UtangReceiptPrinter {
  const UtangReceiptPrinter._();

  static final _cur     = NumberFormat.currency(symbol: 'P', decimalDigits: 2);
  static final _dateFmt = DateFormat('MM/dd/yyyy  hh:mm a');
  static final _shortDt = DateFormat('MM/dd/yy');

  /// Builds the ESC/POS byte sequence for [debt].
  ///
  /// Design principles applied:
  ///   • No double-width/double-height on labels — only on the BALANCE value.
  ///   • Bold used sparingly: store name, customer name, section labels only.
  ///   • Consistent label prefix width (5 chars) so colons align vertically.
  ///   • Empty line before major dividers for visual breathing room.
  ///   • Payment history rows: date left, amount right — same 5/7 split.
  static Future<List<int>> buildBytes(CustomerDebt debt, {String userName = ''}) async {
    final profile = await CapabilityProfile.load();
    final gen     = Generator(PaperSize.mm58, profile);
    List<int> b   = [];

    // ── Header ───────────────────────────────────────────────────────────────
    b += gen.emptyLines(1);
    // Store name: bold, normal size — readable without being blocky
    b += gen.text('KNZ  SCENT',
        styles: const PosStyles(
            align: PosAlign.center,
            bold: true));
    b += gen.text('Luxury  Fragrance  House',
        styles: const PosStyles(align: PosAlign.center));
    b += gen.emptyLines(1);
    b += gen.text('- UTANG STATEMENT -',
        styles: const PosStyles(align: PosAlign.center));
    b += gen.hr(ch: '-');

    // ── Customer info ────────────────────────────────────────────────────────
    // Bold on customer name only — most important info stands out
    b += gen.text('NAME : ${debt.customerName}',
        styles: const PosStyles(bold: true));
    b += gen.text('ID   : ${debt.orderId}');
    b += gen.text('DATE : ${_dateFmt.format(debt.createdAt)}');
    // ── Account (who recorded this utang) ────────────────────────────────────
    if (userName.isNotEmpty) {
      b += gen.text('ACCT : $userName');
    }
    b += gen.hr(ch: '-');

    // ── Amounts ──────────────────────────────────────────────────────────────
    // Normal weight on both columns — thin strokes print crisper on thermal
    b += gen.row([
      PosColumn(text: 'Order Total', width: 5,
          styles: const PosStyles()),
      PosColumn(text: _cur.format(debt.totalAmount), width: 7,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    b += gen.row([
      PosColumn(text: 'Total Paid', width: 5,
          styles: const PosStyles()),
      PosColumn(text: _cur.format(debt.amountPaid), width: 7,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    // ── Balance ───────────────────────────────────────────────────────────────
    b += gen.emptyLines(1);
    b += gen.hr(ch: '=');
    final balanceLabel = debt.isPaid ? 'PAID' : 'BALANCE';
    // Label: normal size so it doesn't compete with the amount
    b += gen.row([
      PosColumn(text: balanceLabel,
          width: 5,
          styles: const PosStyles()),
      // Amount: double-size on value only — the critical number
      PosColumn(text: _cur.format(debt.remainingBalance),
          width: 7,
          styles: const PosStyles(
              bold: true,
              align: PosAlign.right,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
    ]);
    b += gen.hr(ch: '=');

    // ── Payment History (optional) ────────────────────────────────────────────
    if (debt.payments.isNotEmpty) {
      b += gen.emptyLines(1);
      b += gen.hr(ch: '-');
      b += gen.text('PAYMENT HISTORY');
      b += gen.hr(ch: '-');
      for (final p in debt.payments) {
        b += gen.row([
          PosColumn(text: _shortDt.format(p.paidAt), width: 5,
              styles: const PosStyles()),
          PosColumn(text: _cur.format(p.amount), width: 7,
              styles: const PosStyles(align: PosAlign.right)),
        ]);
        if (p.note != null && p.note!.isNotEmpty) {
          b += gen.text('  ${p.note!}');
        }
      }
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    b += gen.emptyLines(1);
    b += gen.hr(ch: '-');
    b += gen.text('Pakibayad po ang inyong balanse.',
        styles: const PosStyles(align: PosAlign.center));
    b += gen.text('Salamat!  -  ${AppStrings.appName}',
        styles: const PosStyles(align: PosAlign.center));
    b += gen.hr(ch: '-');
    b += gen.emptyLines(1);
    b += gen.cut();
    return b;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UtangReceiptScreen
// ─────────────────────────────────────────────────────────────────────────────
class UtangReceiptScreen extends StatelessWidget {
  final CustomerDebt debt;
  final String       userName;

  const UtangReceiptScreen({super.key, required this.debt, this.userName = ''});

  static void show(BuildContext context, CustomerDebt debt, {String userName = ''}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UtangReceiptScreen(debt: debt, userName: userName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        title: const Text('Utang Receipt',
            style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.gold),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: Column(children: [
        Expanded(child: _UtangReceiptPreview(debt: debt, userName: userName)),
        _UtangPrintPanel(debt: debt, userName: userName),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// In-app preview
// ─────────────────────────────────────────────────────────────────────────────
class _UtangReceiptPreview extends StatelessWidget {
  final CustomerDebt debt;
  final String       userName;

  const _UtangReceiptPreview({required this.debt, this.userName = ''});

  @override
  Widget build(BuildContext context) {
    final cur      = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFmt  = DateFormat('MMM dd, yyyy  hh:mm a');
    final balanceColor = debt.isPaid ? AppColors.success : AppColors.error;

    return ReceiptCard(children: [
      // ── Header ────────────────────────────────────────────────────
      ReceiptHeader(
        badgeLabel: 'UTANG STATEMENT',
        badgeColor: AppColors.warning,
      ),
      const ReceiptDivider(),

      // ── Customer Info ─────────────────────────────────────────────
      ReceiptSection(
        child: Column(children: [
          ReceiptInfoRow(
            label: 'Customer',
            value: debt.customerName,
            valueStyle: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
          const SizedBox(height: 8),
          ReceiptInfoRow(label: 'Order ID', value: debt.orderId),
          const SizedBox(height: 8),
          ReceiptInfoRow(
              label: 'Date', value: dateFmt.format(debt.createdAt)),
          // ── Account row (only shown when userName is provided) ─────
          if (userName.isNotEmpty) ...[
            const SizedBox(height: 8),
            ReceiptInfoRow(
              label: 'Account',
              value: userName,
              valueStyle: const TextStyle(
                  color: AppColors.whiteTertiary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13),
            ),
          ],
        ]),
      ),
      const ReceiptDivider(),

      // ── Amounts ───────────────────────────────────────────────────
      ReceiptSection(
        child: Column(children: [
          ReceiptInfoRow(
              label: 'Order Total',
              value: cur.format(debt.totalAmount)),
          const SizedBox(height: 8),
          ReceiptInfoRow(
            label: 'Total Paid',
            value: cur.format(debt.amountPaid),
            valueStyle: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: balanceColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: balanceColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  debt.isPaid ? 'FULLY PAID' : 'BALANCE DUE',
                  style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1.2),
                ),
                Text(
                  cur.format(debt.remainingBalance),
                  style: TextStyle(
                      color: balanceColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 17),
                ),
              ],
            ),
          ),
        ]),
      ),

      // ── Payment History ───────────────────────────────────────────
      if (debt.payments.isNotEmpty) ...[
        const ReceiptDivider(),
        ReceiptSection(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PAYMENT HISTORY',
                  style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 9,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...debt.payments.reversed.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                DateFormat('MMM dd, yyyy')
                                    .format(p.paidAt),
                                style: const TextStyle(
                                    color: AppColors.whiteSecondary,
                                    fontSize: 12)),
                            if (p.note != null && p.note!.isNotEmpty)
                              Text(p.note!,
                                  style: const TextStyle(
                                      color: AppColors.whiteTertiary,
                                      fontSize: 11)),
                          ],
                        ),
                      ),
                      Text(cur.format(p.amount),
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ]),
                  )),
            ],
          ),
        ),
      ],
      const ReceiptDivider(),

      // ── Footer ────────────────────────────────────────────────────
      ReceiptFooter(
        line1: 'Pakibayad po ang inyong balanse.',
        line2: 'Salamat sa inyong tiwala! — ${AppStrings.appName}',
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bluetooth Print Panel
// Mirrors _OrderPrintPanelState — same sealed-state pattern.
// ─────────────────────────────────────────────────────────────────────────────
class _UtangPrintPanel extends StatefulWidget {
  final CustomerDebt debt;
  final String       userName;

  const _UtangPrintPanel({required this.debt, this.userName = ''});

  @override
  State<_UtangPrintPanel> createState() => _UtangPrintPanelState();
}

class _UtangPrintPanelState extends State<_UtangPrintPanel> {
  BtPrintState        _state  = const BtIdle();
  StreamSubscription? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    if (_state case BtConnected(:final device)) {
      device.disconnect();
    }
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    final s = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();
    return (s[Permission.bluetoothScan]?.isGranted ?? false) &&
        (s[Permission.bluetoothConnect]?.isGranted ?? false);
  }

  Future<void> _startScan() async {
    if (!await _requestPermissions()) {
      _set(const BtError(
          'Bluetooth permission denied.\nPlease allow in Settings.'));
      return;
    }
    if (await FlutterBluePlus.adapterState.first !=
        BluetoothAdapterState.on) {
      _set(const BtError('Please turn on Bluetooth first.'));
      return;
    }

    _set(const BtScanning());
    List<ScanResult> found = [];

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      found = r.where((x) => x.device.platformName.isNotEmpty).toList();
      if (mounted) _set(const BtScanning());
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 8));
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    if (mounted) {
      _set(found.isEmpty
          ? const BtError('No printers found. Make sure printer is on.')
          : BtScanned(found));
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    _set(BtConnecting(device.platformName));
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      if (mounted) _set(BtConnected(device));
    } catch (_) {
      if (mounted) _set(const BtError('Connection failed. Try again.'));
    }
  }

  Future<void> _disconnect() async {
    if (_state case BtConnected(:final device)) {
      await device.disconnect();
    }
    if (mounted) _set(const BtIdle());
  }

  Future<void> _print() async {
    final current = _state;
    if (current is! BtConnected) return;

    _set(const BtPrinting());
    try {
      final bytes    = await UtangReceiptPrinter.buildBytes(widget.debt, userName: widget.userName);
      final services = await current.device.discoverServices();

      BluetoothCharacteristic? ch;
      for (final svc in services) {
        for (final c in svc.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            ch = c;
            break;
          }
        }
        if (ch != null) break;
      }

      if (ch == null) {
        _set(const BtError('Cannot find print channel.'));
        return;
      }

      const chunk = 200;
      for (int i = 0; i < bytes.length; i += chunk) {
        await ch.write(
          bytes.sublist(i, (i + chunk).clamp(0, bytes.length)),
          withoutResponse: ch.properties.writeWithoutResponse,
        );
        await Future.delayed(const Duration(milliseconds: 20));
      }

      _set(BtConnected(current.device));
    } catch (_) {
      if (mounted) _set(const BtError('Print failed. Try again.'));
    }
  }

  void _set(BtPrintState next) {
    if (mounted) setState(() => _state = next);
  }

  @override
  Widget build(BuildContext context) => BtPrintPanelShell(
        state:         _state,
        statusMessage: _state.defaultMessage,
        onSelect:      _connectTo,
        onScan:        _startScan,
        onPrint:       _print,
        onDisconnect:  _disconnect,
      );
}