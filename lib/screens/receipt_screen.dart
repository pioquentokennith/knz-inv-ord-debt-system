// ─────────────────────────────────────────────────────────────────────────────
// receipt_screen.dart
// Purpose : Full-screen receipt viewer and Bluetooth thermal printer for orders.
// Function: OrderReceiptPrinter is a static utility class (Abstraction / Single
//           Responsibility) that builds ESC/POS byte sequences for 58mm printers.
//           ReceiptScreen shows an on-screen preview using the shared receipt
//           widget hierarchy (ReceiptCard, ReceiptHeader, ReceiptInfoRow, etc.)
//           and embeds _OrderPrintPanel which manages the full Bluetooth lifecycle
//           (scan → connect → print → disconnect) using the sealed BtPrintState.
// Usage   : ReceiptScreen.show(context, order, userName: AppState().currentUser?.displayName ?? '');
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_constants.dart';
import '../core/app_state.dart';
import '../core/money.dart';
import '../models/business_event_model.dart';
import '../models/order_model.dart';
import '../models/payment_method_model.dart';
import '../services/accounting_service.dart';
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

  static final _dateFmt = DateFormat('MM/dd/yyyy  hh:mm a');

  // Builds the full ESC/POS byte sequence for a 58mm thermal printer.
  //
  // Design principles applied:
  //   • No double-width/double-height on labels — only on the TOTAL value
  //     so the most important number is large without making labels muddy.
  //   • Bold used sparingly: header name, item names, section labels only.
  //     Price/amount columns are normal weight for crisp thin strokes.
  //   • Consistent column widths across every row section (8/4 split).
  //   • Empty line before every major divider for visual breathing room.
  //   • Aligned label colons with fixed-width prefixes for easy scanning.
  static Future<List<int>> buildBytes(
    Order order, {
    String userName = '',
    Iterable<BusinessEvent> businessEvents = const [],
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    List<int> b = [];

    // ── Header ───────────────────────────────────────────────────────────────
    b += gen.emptyLines(1);
    // Store name: bold, normal size — readable without being blocky
    b += gen.text(
      'KNZ  SCENT',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    b += gen.text(
      'Luxury  Fragrance  House',
      styles: const PosStyles(align: PosAlign.center),
    );
    b += gen.emptyLines(1);
    b += gen.text(
      '- ORDER RECEIPT -',
      styles: const PosStyles(align: PosAlign.center),
    );
    b += gen.hr(ch: '-');

    // ── Order info ───────────────────────────────────────────────────────────
    b += gen.text('ID   : ${order.orderId}');
    b += gen.text('NAME : ${order.customerName}');
    b += gen.text('DATE : ${_dateFmt.format(order.orderDate)}');
    b += gen.text('STAT : ${order.status.displayName.toUpperCase()}');
    // ── Account (who processed this order) ───────────────────────────────────
    if (userName.isNotEmpty) {
      b += gen.text('ACCT : $userName');
    }
    b += gen.hr(ch: '-');

    // ── Items header ─────────────────────────────────────────────────────────
    b += gen.row([
      PosColumn(text: 'ITEM', width: 8, styles: const PosStyles()),
      PosColumn(
        text: 'AMOUNT',
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    b += gen.hr(ch: '-');

    // ── Item rows ────────────────────────────────────────────────────────────
    for (final item in order.items) {
      // Product name on its own line — bold for scanability
      b += gen.text(item.productName, styles: const PosStyles(bold: true));
      // Qty × unit price on left, subtotal on right — normal weight for clarity
      b += gen.row([
        PosColumn(
          text: '  ${item.quantity} x ${_printerMoney(item.unitPrice)}',
          width: 7,
          styles: const PosStyles(),
        ),
        PosColumn(
          text: _printerMoney(item.subtotal),
          width: 5,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    // ── Total ────────────────────────────────────────────────────────────────
    b += gen.emptyLines(1);
    b += gen.hr(ch: '=');

    final orderEvents = businessEvents
        .where(
          (event) =>
              event.subject == BusinessEventSubject.order &&
              event.subjectId == order.id,
        )
        .toList(growable: false);
    if (orderEvents.isNotEmpty) {
      final collected = BusinessEventLedger.netCash(orderEvents);
      final balance = (order.customerPayAmount - collected).max(Money.zero);
      b += gen.text('COLLECTED : ${_printerMoney(collected)}');
      b += gen.text('BALANCE   : ${_printerMoney(balance)}');
      b += gen.hr(ch: '-');
    }
    // Label: normal size, normal weight — stands out from items but not blocky
    b += gen.row([
      PosColumn(text: 'TOTAL', width: 5, styles: const PosStyles()),
      // Amount: double-size only on the value — the one number that matters
      PosColumn(
        text: _printerMoney(order.customerPayAmount),
        width: 7,
        styles: const PosStyles(
          bold: true,
          align: PosAlign.right,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    ]);
    b += gen.hr(ch: '=');

    // ── Notes (optional) ─────────────────────────────────────────────────────
    if (order.notes != null && order.notes!.isNotEmpty) {
      b += gen.emptyLines(1);
      b += gen.text('NOTE :');
      b += gen.text(order.notes!);
    }

    // ── Footer ───────────────────────────────────────────────────────────────
    b += gen.emptyLines(1);
    b += gen.hr(ch: '-');
    b += gen.text(
      'Thank you for your purchase!',
      styles: const PosStyles(align: PosAlign.center),
    );
    b += gen.text(
      AppStrings.appName,
      styles: const PosStyles(align: PosAlign.center),
    );
    b += gen.hr(ch: '-');
    b += gen.emptyLines(1);
    b += gen.cut();
    return b;
  }

  static String _printerMoney(Money value) => 'P${value.toStringAsFixed(2)}';
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
  final String userName;
  final List<BusinessEvent>? businessEvents;

  const ReceiptScreen({
    super.key,
    required this.order,
    this.userName = '',
    this.businessEvents,
  });

  // Static factory navigation method — callers never construct ReceiptScreen directly.
  // Pushes a MaterialPageRoute so the back button always returns to the calling screen.
  static void show(BuildContext context, Order order, {String userName = ''}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(order: order, userName: userName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = businessEvents ?? AppState().eventsForOrder(order.id);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        foregroundColor: AppColors.gold,
        title: const Text(
          'Receipt',
          style: TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _OrderReceiptPreview(
                order: order,
                userName: userName,
                businessEvents: events,
              ),
            ),
            _OrderPrintPanel(
              order: order,
              userName: userName,
              businessEvents: events,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// In-app receipt preview
// Private — only ReceiptScreen can create this.
// ─────────────────────────────────────────────────────────────────────────────
class _OrderReceiptPreview extends StatelessWidget {
  final Order order;
  final String userName;
  final List<BusinessEvent> businessEvents;

  const _OrderReceiptPreview({
    required this.order,
    this.userName = '',
    this.businessEvents = const [],
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM dd, yyyy  hh:mm a');
    final breakdown = AccountingService.instance.orderBreakdown(order);
    final total = breakdown.customerPayTotal;
    final collected = BusinessEventLedger.netCash(businessEvents);
    final balance = (total - collected).max(Money.zero);
    final refunds = businessEvents
        .where((event) => event.type == BusinessEventType.refund)
        .fold(Money.zero, (sum, event) => sum + event.amount!);

    final statusColor = switch (order.status) {
      OrderStatus.delivered => AppColors.success,
      OrderStatus.shipped => Colors.purple,
      OrderStatus.processing => AppColors.info,
      OrderStatus.pending => AppColors.warning,
      OrderStatus.cancelled => AppColors.error,
      OrderStatus.utang => AppColors.warning,
    };

    return ReceiptCard(
      children: [
        // ── Header ────────────────────────────────────────────────────
        ReceiptHeader(badgeLabel: 'ORDER RECEIPT', badgeColor: AppColors.gold),
        const ReceiptDivider(),

        // ── Order Info ────────────────────────────────────────────────
        ReceiptSection(
          child: Column(
            children: [
              ReceiptInfoRow(
                label: 'Order ID',
                value: order.orderId,
                valueStyle: const TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ReceiptInfoRow(label: 'Customer', value: order.customerName),
              const SizedBox(height: 8),
              ReceiptInfoRow(
                label: 'Date',
                value: dateFmt.format(order.orderDate),
              ),
              // ── Payment method row ─────────────────────────────────────
              if (order.paymentMethod != null) ...[
                const SizedBox(height: 8),
                ReceiptInfoRow(
                  label: 'Payment',
                  value:
                      order.paymentMethod!.displayName +
                      (order.paymentReference != null
                          ? '  ···${order.paymentReference}'
                          : ''),
                ),
              ],
              // ── Reseller discount row ──────────────────────────────────
              if (order.isReseller) ...[
                const SizedBox(height: 8),
                ReceiptInfoRow(
                  label: 'Discount',
                  value:
                      '−₱${order.deductionPerItem.toStringAsFixed(0)}/item Reseller',
                  valueStyle: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              // ── Account row (only shown when userName is provided) ─────
              if (userName.isNotEmpty) ...[
                const SizedBox(height: 8),
                ReceiptInfoRow(
                  label: 'Account',
                  value: userName,
                  valueStyle: const TextStyle(
                    color: AppColors.whiteTertiary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (businessEvents.isNotEmpty) ...[
          const ReceiptDivider(),
          ReceiptSection(
            child: Column(
              children: [
                ReceiptInfoRow(
                  label: 'Net collected',
                  value: collected.format(),
                ),
                if (refunds.isPositive)
                  ReceiptInfoRow(
                    label: 'Refunds recorded',
                    value: refunds.format(),
                  ),
                ReceiptInfoRow(label: 'Balance', value: balance.format()),
              ],
            ),
          ),
        ],
        const ReceiptDivider(),

        // ── Items ─────────────────────────────────────────────────────
        ReceiptSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(
                    child: Text(
                      'ITEM',
                      style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 10,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'AMOUNT',
                    style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 10,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(height: 1, color: AppColors.divider),
              const SizedBox(height: 8),
              ...order.items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item.quantity} x ${item.unitPrice.format()}',
                              style: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item.subtotal.format(),
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const ReceiptDivider(),

        // ── Total ─────────────────────────────────────────────────────
        ReceiptSection(
          child: order.isReseller
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SRP TOTAL',
                          style: TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 12,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          breakdown.srpTotal.format(),
                          style: const TextStyle(
                            color: AppColors.whiteTertiary,
                            fontSize: 14,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'NET (−₱${order.deductionPerItem.toStringAsFixed(0)}/item)',
                            maxLines: 2,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          breakdown.customerPayTotal.format(),
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      total.format(),
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
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
              const Text(
                'Status',
                style: TextStyle(color: AppColors.whiteTertiary, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  order.status.displayName.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Notes (optional) ──────────────────────────────────────────
        if (order.notes != null && order.notes!.isNotEmpty) ...[
          const ReceiptDivider(),
          ReceiptSection(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notes',
                  style: TextStyle(
                    color: AppColors.whiteTertiary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  order.notes!,
                  style: const TextStyle(
                    color: AppColors.whiteSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
        const ReceiptDivider(),

        // ── Footer ────────────────────────────────────────────────────
        ReceiptFooter(
          line1: '✦  Thank you for your purchase!  ✦',
          line2: '${AppStrings.appName} — ${AppStrings.luxuryFragranceHouse}',
        ),
      ],
    );
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
  final String userName;
  final List<BusinessEvent> businessEvents;

  const _OrderPrintPanel({
    required this.order,
    this.userName = '',
    this.businessEvents = const [],
  });

  @override
  State<_OrderPrintPanel> createState() => _OrderPrintPanelState();
}

class _OrderPrintPanelState extends State<_OrderPrintPanel> {
  // Single sealed state object replaces the old (enum + String + List) trio.
  BtPrintState _state = const BtIdle();
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
      _set(
        const BtError(
          'Bluetooth permission denied.\nPlease allow in Settings.',
        ),
      );
      return;
    }
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _set(const BtError('Please turn on Bluetooth first.'));
      return;
    }

    _set(const BtScanning());
    List<ScanResult> found = [];

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((r) {
      found = r.where((x) => x.device.platformName.isNotEmpty).toList();
      if (mounted) _set(const BtScanning()); // keep spinner while scanning
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 8));
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    if (mounted) {
      _set(
        found.isEmpty
            ? const BtError('No printers found. Make sure printer is on.')
            : BtScanned(found),
      );
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
      final bytes = await OrderReceiptPrinter.buildBytes(
        widget.order,
        userName: widget.userName,
        businessEvents: widget.businessEvents,
      );
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
    state: _state,
    statusMessage: _state.defaultMessage,
    onSelect: _connectTo,
    onScan: _startScan,
    onPrint: _print,
    onDisconnect: _disconnect,
  );
}
