// ─────────────────────────────────────────────────────────────────────────────
// utang_receipt_printer.dart
// FIX 5: Extracted from utang_screen.dart (was lines 1301–1788)
// Contains: UtangReceiptScreen (public), _UtangReceiptPreview,
//           _UtangInfoRow, _UtangBtPrintPanel, _BtState
// Usage: UtangReceiptScreen.show(context, debt);
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../core/app_constants.dart';
import '../models/debt_model.dart';

class UtangReceiptScreen extends StatelessWidget {
  final CustomerDebt debt;

  const UtangReceiptScreen({super.key, required this.debt});

  static void show(BuildContext context, CustomerDebt debt) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => UtangReceiptScreen(debt: debt)),
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
          icon:
              const Icon(Icons.arrow_back_ios, color: AppColors.gold),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.cardBorder),
        ),
      ),
      body: Column(children: [
        Expanded(child: _UtangReceiptPreview(debt: debt)),
        _UtangBtPrintPanel(debt: debt),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Preview
// ─────────────────────────────────────────────────────────────────────────────
class _UtangReceiptPreview extends StatelessWidget {
  final CustomerDebt debt;
  const _UtangReceiptPreview({required this.debt});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFmt  = DateFormat('MMM dd, yyyy  hh:mm a');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 24, horizontal: 20),
                  decoration: const BoxDecoration(
                    gradient: AppColors.sidebarGradient,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(children: [
                    const Icon(Icons.water_drop_outlined,
                        color: AppColors.gold, size: 30),
                    const SizedBox(height: 6),
                    const Text('KNZ Scent',
                        style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.warning
                                .withValues(alpha: 0.5)),
                      ),
                      child: const Text('UTANG STATEMENT',
                          style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
                Container(height: 1, color: AppColors.divider),
                // Customer info
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Column(children: [
                    _UtangInfoRow(
                        label: 'Customer',
                        value: debt.customerName,
                        valueStyle: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 8),
                    _UtangInfoRow(
                        label: 'Order ID', value: debt.orderId),
                    const SizedBox(height: 8),
                    _UtangInfoRow(
                        label: 'Date',
                        value: dateFmt.format(debt.createdAt)),
                  ]),
                ),
                Container(height: 1, color: AppColors.divider),
                // Amounts
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Column(children: [
                    _UtangInfoRow(
                        label: 'Order Total',
                        value: currency.format(debt.totalAmount)),
                    const SizedBox(height: 8),
                    _UtangInfoRow(
                        label: 'Total Paid',
                        value: currency.format(debt.amountPaid),
                        valueStyle: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: debt.isPaid
                            ? AppColors.success.withValues(alpha: 0.08)
                            : AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: debt.isPaid
                                ? AppColors.success
                                    .withValues(alpha: 0.3)
                                : AppColors.error
                                    .withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              debt.isPaid
                                  ? 'FULLY PAID'
                                  : 'BALANCE DUE',
                              style: TextStyle(
                                  color: debt.isPaid
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 1)),
                          Text(
                              currency
                                  .format(debt.remainingBalance),
                              style: TextStyle(
                                  color: debt.isPaid
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18)),
                        ],
                      ),
                    ),
                  ]),
                ),
                if (debt.payments.isNotEmpty) ...[
                  Container(height: 1, color: AppColors.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Payment History',
                              style: TextStyle(
                                  color: AppColors.whiteTertiary,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          ...debt.payments.reversed.map((p) =>
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: Row(children: [
                                  const Icon(
                                      Icons.check_circle_outline,
                                      color: AppColors.success,
                                      size: 14),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            DateFormat('MMM dd, yyyy')
                                                .format(p.paidAt),
                                            style: const TextStyle(
                                                color: AppColors
                                                    .whiteSecondary,
                                                fontSize: 12)),
                                        if (p.note != null &&
                                            p.note!.isNotEmpty)
                                          Text(p.note!,
                                              style: const TextStyle(
                                                  color: AppColors
                                                      .whiteTertiary,
                                                  fontSize: 11)),
                                      ])),
                                  Text(currency.format(p.amount),
                                      style: const TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                ]),
                              )),
                        ]),
                  ),
                ],
                Container(height: 1, color: AppColors.divider),
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 18, horizontal: 24),
                  decoration: const BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(16))),
                  child: const Text(
                    'Pakibayad po ang inyong balanse.\nSalamat sa inyong tiwala! - KNZ Scent',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UtangInfoRow extends StatelessWidget {
  final String     label;
  final String     value;
  final TextStyle? valueStyle;

  const _UtangInfoRow(
      {required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.whiteTertiary, fontSize: 13)),
        Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: valueStyle ??
                    const TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bluetooth Print Panel
// ─────────────────────────────────────────────────────────────────────────────
class _UtangBtPrintPanel extends StatefulWidget {
  final CustomerDebt debt;
  const _UtangBtPrintPanel({required this.debt});

  @override
  State<_UtangBtPrintPanel> createState() => _UtangBtPrintPanelState();
}

class _UtangBtPrintPanelState extends State<_UtangBtPrintPanel> {
  _BtState           _btState     = _BtState.idle;
  List<ScanResult>   _scanResults = [];
  BluetoothDevice?   _connectedDevice;
  String             _statusMessage =
      'Tap "Connect Printer" to find your printer';
  StreamSubscription? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();
    return (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
        (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
  }

  Future<void> _startScan() async {
    final granted = await _requestPermissions();
    if (!granted) {
      _setStatus(_BtState.error,
          'Bluetooth permission denied.\nPlease allow in Settings.');
      return;
    }
    final adapterState =
        await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _setStatus(_BtState.error, 'Please turn on Bluetooth first.');
      return;
    }
    setState(() {
      _btState       = _BtState.scanning;
      _scanResults   = [];
      _statusMessage = 'Scanning for printers...';
    });
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results
              .where((r) => r.device.platformName.isNotEmpty)
              .toList();
        });
      }
    });
    await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 8));
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    if (mounted) {
      setState(() {
        _btState = _scanResults.isEmpty
            ? _BtState.error
            : _BtState.scanned;
        _statusMessage = _scanResults.isEmpty
            ? 'No printers found. Make sure printer is on.'
            : 'Select your printer below:';
      });
    }
  }

  Future<void> _connectTo(BluetoothDevice device) async {
    _setStatus(
        _BtState.connecting, 'Connecting to ${device.platformName}...');
    try {
      await device
          .connect(timeout: const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _btState         = _BtState.connected;
          _statusMessage   = '✓ Connected to ${device.platformName}';
        });
      }
    } catch (_) {
      _setStatus(_BtState.error, 'Connection failed. Try again.');
    }
  }

  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
    if (mounted) {
      setState(() {
        _connectedDevice = null;
        _btState         = _BtState.idle;
        _scanResults     = [];
        _statusMessage   = 'Tap "Connect Printer" to find your printer';
      });
    }
  }

  Future<List<int>> _buildPrintBytes() async {
    final profile = await CapabilityProfile.load();
    final gen     = Generator(PaperSize.mm58, profile);
    final cur     = NumberFormat.currency(symbol: 'P', decimalDigits: 2);
    final dateFmt = DateFormat('MM/dd/yyyy  hh:mm a');
    final debt    = widget.debt;
    List<int> bytes = [];

    // ── Header ─────────────────────────────────────────────────────
    bytes += gen.emptyLines(1);
    bytes += gen.text('KNZ SCENT',
        styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2));
    bytes += gen.text('Luxury Fragrance House',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.feed(1);
    bytes += gen.text('UTANG STATEMENT',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += gen.hr();

    // ── Customer Info ──────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(text: 'Customer :', width: 5),
      PosColumn(
          text: debt.customerName,
          width: 7,
          styles: const PosStyles(bold: true)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Order ID :', width: 5),
      PosColumn(text: debt.orderId, width: 7),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Date     :', width: 5),
      PosColumn(text: dateFmt.format(debt.createdAt), width: 7),
    ]);
    bytes += gen.hr();

    // ── Amounts ────────────────────────────────────────────────────
    bytes += gen.row([
      PosColumn(text: 'Order Total:', width: 6),
      PosColumn(
          text: cur.format(debt.totalAmount),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Total Paid:', width: 6),
      PosColumn(
          text: cur.format(debt.amountPaid),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += gen.hr();

    // ── Balance / Fully Paid ───────────────────────────────────────
    final balanceLabel = debt.isPaid ? 'FULLY PAID:' : 'BALANCE DUE:';
    bytes += gen.row([
      PosColumn(
          text: balanceLabel,
          width: 5,
          styles: const PosStyles(
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
      PosColumn(
          text: cur.format(debt.remainingBalance),
          width: 7,
          styles: const PosStyles(
              bold: true,
              align: PosAlign.right,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
    ]);

    // ── Payment History ────────────────────────────────────────────
    if (debt.payments.isNotEmpty) {
      bytes += gen.hr();
      bytes += gen.text('Payment History:',
          styles: const PosStyles(bold: true));
      bytes += gen.hr(ch: '-');
      for (final p in debt.payments) {
        bytes += gen.row([
          PosColumn(
              text: DateFormat('MM/dd/yy').format(p.paidAt),
              width: 7),
          PosColumn(
              text: cur.format(p.amount),
              width: 5,
              styles: const PosStyles(align: PosAlign.right)),
        ]);
        if (p.note != null && p.note!.isNotEmpty) {
          bytes += gen.text('  ${p.note!}',
              styles: const PosStyles(fontType: PosFontType.fontB));
        }
      }
    }

    // ── Footer ─────────────────────────────────────────────────────
    bytes += gen.feed(1);
    bytes += gen.hr();
    bytes += gen.text('Pakibayad po ang inyong balanse.',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('Salamat! - KNZ Scent',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.hr();
    bytes += gen.emptyLines(3);
    bytes += gen.cut();

    return bytes;
  }

  Future<void> _print() async {
    if (_connectedDevice == null) return;
    _setStatus(_BtState.printing, 'Printing...');
    try {
      final bytes    = await _buildPrintBytes();
      final services =
          await _connectedDevice!.discoverServices();
      BluetoothCharacteristic? printChar;
      for (final svc in services) {
        for (final ch in svc.characteristics) {
          if (ch.properties.write ||
              ch.properties.writeWithoutResponse) {
            printChar = ch;
            break;
          }
        }
        if (printChar != null) break;
      }
      if (printChar == null) {
        _setStatus(_BtState.error, 'Cannot find print channel.');
        return;
      }
      const chunk = 200;
      for (int i = 0; i < bytes.length; i += chunk) {
        final end =
            (i + chunk < bytes.length) ? i + chunk : bytes.length;
        await printChar.write(bytes.sublist(i, end),
            withoutResponse:
                printChar.properties.writeWithoutResponse);
        await Future.delayed(
            const Duration(milliseconds: 20));
      }
      _setStatus(_BtState.connected, '✓ Printed successfully!');
    } catch (_) {
      _setStatus(_BtState.error, 'Print failed. Try again.');
    }
  }

  void _setStatus(_BtState state, String message) {
    if (mounted) {
      setState(() {
        _btState       = state;
        _statusMessage = message;
      });
    }
  }

  bool get _isBusy =>
      _btState == _BtState.scanning ||
      _btState == _BtState.connecting ||
      _btState == _BtState.printing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: AppColors.sidebar,
          border:
              Border(top: BorderSide(color: AppColors.cardBorder))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            color: (_btState == _BtState.connected
                    ? AppColors.success
                    : _btState == _BtState.error
                        ? AppColors.error
                        : AppColors.whiteTertiary)
                .withValues(alpha: 0.08),
            child: Row(children: [
              if (_isBusy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2))
              else
                Icon(
                  _btState == _BtState.connected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_outlined,
                  color: _btState == _BtState.connected
                      ? AppColors.success
                      : _btState == _BtState.error
                          ? AppColors.error
                          : AppColors.whiteTertiary,
                  size: 16,
                ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(_statusMessage,
                      style: TextStyle(
                          color: _btState == _BtState.connected
                              ? AppColors.success
                              : _btState == _BtState.error
                                  ? AppColors.error
                                  : AppColors.whiteTertiary,
                          fontSize: 12))),
            ]),
          ),
          // Device list
          if (_btState == _BtState.scanned &&
              _scanResults.isNotEmpty)
            Container(
              constraints:
                  const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.cardBorder)),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _scanResults.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 1, color: AppColors.divider),
                itemBuilder: (_, i) {
                  final r = _scanResults[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                        Icons.print_outlined,
                        color: AppColors.gold,
                        size: 18),
                    title: Text(r.device.platformName,
                        style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 13)),
                    subtitle: Text(
                        r.device.remoteId.toString(),
                        style: const TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 10)),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.whiteTertiary,
                        size: 18),
                    onTap: () => _connectTo(r.device),
                  );
                },
              ),
            ),
          // Action buttons
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: _btState == _BtState.connected
                ? Row(children: [
                    Expanded(
                        child: GestureDetector(
                      onTap: _isBusy ? null : _disconnect,
                      child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                              color: AppColors.error
                                  .withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                  color: AppColors.error
                                      .withValues(alpha: 0.4))),
                          alignment: Alignment.center,
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                    Icons.bluetooth_disabled,
                                    color: AppColors.error,
                                    size: 18),
                                SizedBox(width: 8),
                                Text('Disconnect',
                                    style: TextStyle(
                                        color: AppColors.error,
                                        fontWeight:
                                            FontWeight.w700,
                                        fontSize: 13))
                              ])),
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 2,
                        child: GestureDetector(
                      onTap: _isBusy ? null : _print,
                      child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                              gradient: _isBusy
                                  ? null
                                  : AppColors.goldGradient,
                              color: _isBusy
                                  ? AppColors.cardBorder
                                  : null,
                              borderRadius:
                                  BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.print_outlined,
                                    color: AppColors.background,
                                    size: 18),
                                SizedBox(width: 8),
                                Text('Print Receipt',
                                    style: TextStyle(
                                        color:
                                            AppColors.background,
                                        fontWeight:
                                            FontWeight.w700,
                                        fontSize: 13))
                              ])),
                    )),
                  ])
                : GestureDetector(
                    onTap: _isBusy ? null : _startScan,
                    child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                            gradient: _isBusy
                                ? null
                                : AppColors.goldGradient,
                            color: _isBusy
                                ? AppColors.cardBorder
                                : null,
                            borderRadius:
                                BorderRadius.circular(10)),
                        alignment: Alignment.center,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bluetooth_searching,
                                  color: _isBusy
                                      ? AppColors.whiteTertiary
                                      : AppColors.background,
                                  size: 18),
                              const SizedBox(width: 8),
                              Text(
                                  _isBusy
                                      ? 'Please wait...'
                                      : 'Connect Printer',
                                  style: TextStyle(
                                      color: _isBusy
                                          ? AppColors.whiteTertiary
                                          : AppColors.background,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ])),
                  ),
          ),
        ],
      ),
    );
  }
}

enum _BtState {
  idle,
  scanning,
  scanned,
  connecting,
  connected,
  printing,
  error,
}
