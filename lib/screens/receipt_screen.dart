import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_constants.dart';
import '../models/order_model.dart';
import '../widgets/receipt_shared_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OrderReceiptPrinter — Abstraction: separates ESC/POS byte-building logic
// from the UI layer.  _OrderPrintPanelState no longer owns this concern.
//
// OOP:
//   • Single Responsibility — only knows how to turn an Order into bytes.
//   • Abstraction          — callers just call buildBytes(); they don't know
//                            about Generator, PaperSize, or PosStyles.
//   • Encapsulation        — all formatting constants are private.
// ─────────────────────────────────────────────────────────────────────────────
class OrderReceiptPrinter {
  const OrderReceiptPrinter._();

  static final _cur     = NumberFormat.currency(symbol: 'P', decimalDigits: 2);
  static final _dateFmt = DateFormat('MM/dd/yyyy  hh:mm a');

  /// Builds the ESC/POS byte sequence for [order].
  /// Returns an empty list on failure.
  static Future<List<int>> buildBytes(Order order) async {
    final profile = await CapabilityProfile.load();
    final gen     = Generator(PaperSize.mm58, profile);
    List<int> b   = [];

    b += gen.emptyLines(1);
    b += gen.text('KNZ SCENT',
        styles: const PosStyles(
            align: PosAlign.center, bold: true,
            height: PosTextSize.size2, width: PosTextSize.size2));
    b += gen.text('Luxury Fragrance House',
        styles: const PosStyles(align: PosAlign.center));
    b += gen.feed(1);
    b += gen.text('ORDER RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += gen.hr();

    b += gen.text('Order ID : ${order.orderId}',
        styles: const PosStyles(bold: true));
    b += gen.text('Customer : ${order.customerName}');
    b += gen.text('Date     : ${_dateFmt.format(order.orderDate)}');
    b += gen.text('Status   : ${order.status.displayName.toUpperCase()}',
        styles: const PosStyles(bold: true));
    b += gen.hr();

    b += gen.text('Item', styles: const PosStyles(bold: true));
    b += gen.hr(ch: '-');
    for (final item in order.items) {
      b += gen.text(item.productName, styles: const PosStyles(bold: true));
      b += gen.text(
          '  ${item.quantity} x ${_cur.format(item.unitPrice)} = ${_cur.format(item.subtotal)}',
          styles: const PosStyles(fontType: PosFontType.fontB));
    }

    b += gen.hr();
    b += gen.text('TOTAL: ${_cur.format(order.totalAmount)}',
        styles: const PosStyles(
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2));

    if (order.notes != null && order.notes!.isNotEmpty) {
      b += gen.hr(ch: '-');
      b += gen.text('Note:', styles: const PosStyles(bold: true));
      b += gen.text(order.notes!,
          styles: const PosStyles(fontType: PosFontType.fontB));
    }

    b += gen.feed(1);
    b += gen.hr();
    b += gen.text('Thank you for your purchase!',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    b += gen.text(AppStrings.appName,
        styles: const PosStyles(align: PosAlign.center));
    b += gen.hr();
    b += gen.emptyLines(3);
    b += gen.cut();
    return b;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReceiptScreen — in-app receipt preview + Bluetooth thermal print
// Compatible with: Senda SDXP-210 / PT-210 58mm Bluetooth Thermal Printer
//
// OOP:
//   • Encapsulation — StatelessWidget; no mutable state exposed publicly.
//   • Abstraction   — static show() hides navigation mechanics from callers.
// ─────────────────────────────────────────────────────────────────────────────
class ReceiptScreen extends StatelessWidget {
  final Order order;

  const ReceiptScreen({super.key, required this.order});

  /// Factory navigation method — callers never instantiate ReceiptScreen
  /// directly, keeping the navigation contract stable.
  static void show(BuildContext context, Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        foregroundColor: AppColors.gold,
        title: const Text('Receipt',
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
        Expanded(child: _OrderReceiptPreview(order: order)),
        _OrderPrintPanel(order: order),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// In-app receipt preview
// Private — only ReceiptScreen can create this.
// ─────────────────────────────────────────────────────────────────────────────
class _OrderReceiptPreview extends StatelessWidget {
  final Order order;

  const _OrderReceiptPreview({required this.order});

  @override
  Widget build(BuildContext context) {
    final cur     = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFmt = DateFormat('MMM dd, yyyy  hh:mm a');
    final total   = order.items.fold(0.0, (s, i) => s + i.subtotal);

    final statusColor = switch (order.status) {
      OrderStatus.delivered  => AppColors.success,
      OrderStatus.shipped    => Colors.purple,
      OrderStatus.processing => AppColors.info,
      OrderStatus.pending    => AppColors.warning,
      OrderStatus.cancelled  => AppColors.error,
      OrderStatus.utang      => AppColors.warning,
    };

    return ReceiptCard(children: [
      // ── Header ────────────────────────────────────────────────────
      ReceiptHeader(badgeLabel: 'ORDER RECEIPT', badgeColor: AppColors.gold),
      const ReceiptDivider(),

      // ── Order Info ────────────────────────────────────────────────
      ReceiptSection(
        child: Column(children: [
          ReceiptInfoRow(
            label: 'Order ID',
            value: order.orderId,
            valueStyle: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
          const SizedBox(height: 8),
          ReceiptInfoRow(label: 'Customer', value: order.customerName),
          const SizedBox(height: 8),
          ReceiptInfoRow(label: 'Date', value: dateFmt.format(order.orderDate)),
        ]),
      ),
      const ReceiptDivider(),

      // ── Items ─────────────────────────────────────────────────────
      ReceiptSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Expanded(
                child: Text('ITEM',
                    style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 10,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700)),
              ),
              Text('AMOUNT',
                  style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 10,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Container(height: 1, color: AppColors.divider),
            const SizedBox(height: 8),
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            Text(
                              '${item.quantity} x ${cur.format(item.unitPrice)}',
                              style: const TextStyle(
                                  color: AppColors.whiteTertiary,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(cur.format(item.subtotal),
                          style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
          ],
        ),
      ),
      const ReceiptDivider(),

      // ── Total ─────────────────────────────────────────────────────
      ReceiptSection(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL',
                style: TextStyle(
                    color: AppColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2)),
            Text(cur.format(total),
                style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      const ReceiptDivider(),

      // ── Status ────────────────────────────────────────────────────
      ReceiptSection(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Status',
                style:
                    TextStyle(color: AppColors.whiteTertiary, fontSize: 13)),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: statusColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                order.status.displayName.toUpperCase(),
                style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5),
              ),
            ),
          ],
        ),
      ),

      // ── Notes (optional) ──────────────────────────────────────────
      if (order.notes != null && order.notes!.isNotEmpty) ...[
        const ReceiptDivider(),
        ReceiptSection(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Notes',
                  style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 11,
                      letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(order.notes!,
                  style: const TextStyle(
                      color: AppColors.whiteSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
      const ReceiptDivider(),

      // ── Footer ────────────────────────────────────────────────────
      ReceiptFooter(
        line1: '✦  Thank you for your purchase!  ✦',
        line2:
            '${AppStrings.appName} — ${AppStrings.luxuryFragranceHouse}',
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bluetooth Print Panel
//
// OOP:
//   • Encapsulation — BT state lives in _OrderPrintPanelState; nothing leaks.
//   • Abstraction   — byte-building delegated to OrderReceiptPrinter.
//   • Sealed state  — _state is typed BtPrintState (sealed hierarchy);
//                     no raw Strings or parallel booleans needed.
// ─────────────────────────────────────────────────────────────────────────────
class _OrderPrintPanel extends StatefulWidget {
  final Order order;

  const _OrderPrintPanel({required this.order});

  @override
  State<_OrderPrintPanel> createState() => _OrderPrintPanelState();
}

class _OrderPrintPanelState extends State<_OrderPrintPanel> {
  // Single sealed state object replaces the old (enum + String + List) trio.
  BtPrintState    _state  = const BtIdle();
  StreamSubscription? _scanSub;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _scanSub?.cancel();
    // Disconnect only if we hold a live device.
    if (_state case BtConnected(:final device)) {
      device.disconnect();
    }
    super.dispose();
  }

  // ── BT Permissions ───────────────────────────────────────────────────────

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

  // ── BT Actions ───────────────────────────────────────────────────────────

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
      if (mounted) _set(BtScanning()); // keep spinner while scanning
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
      // Delegated to OrderReceiptPrinter — no formatting logic here.
      final bytes    = await OrderReceiptPrinter.buildBytes(widget.order);
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
        _set(const BtError('Cannot find print channel on this device.'));
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

      // Return to connected state so user can print again.
      _set(BtConnected(current.device));
    } catch (_) {
      if (mounted) _set(const BtError('Print failed. Try again.'));
    }
  }

  // ── State helper ─────────────────────────────────────────────────────────

  void _set(BtPrintState next) {
    if (mounted) setState(() => _state = next);
  }

  // ── Build ────────────────────────────────────────────────────────────────

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
