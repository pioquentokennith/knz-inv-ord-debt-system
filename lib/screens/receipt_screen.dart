import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_constants.dart';
import '../models/order_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReceiptScreen — in-app receipt preview + Bluetooth thermal print
// Compatible with: Senda SDXP-210 / PT-210 58mm Bluetooth Thermal Printer
// ─────────────────────────────────────────────────────────────────────────────
class ReceiptScreen extends StatelessWidget {
  final Order order;

  const ReceiptScreen({super.key, required this.order});

  /// Push this screen from anywhere in the app
  static void show(BuildContext context, Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptScreen(order: order)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(child: _ReceiptPreview(order: order)),
          _PrintPanel(order: order),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.sidebar,
      foregroundColor: AppColors.gold,
      title: const Text(
        'Receipt',
        style: TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ReceiptPreview — styled receipt card shown inside the app
// ─────────────────────────────────────────────────────────────────────────────
class _ReceiptPreview extends StatelessWidget {
  final Order order;

  const _ReceiptPreview({required this.order});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final dateFmt = DateFormat('MMM dd, yyyy  hh:mm a');

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
                _PreviewHeader(),
                _ReceiptDivider(),
                _PreviewOrderInfo(order: order, dateFmt: dateFmt),
                _ReceiptDivider(),
                _PreviewItemsTable(order: order, currency: currency),
                _ReceiptDivider(),
                _PreviewTotals(order: order, currency: currency),
                _ReceiptDivider(),
                _PreviewStatus(order: order),
                if (order.notes != null && order.notes!.isNotEmpty) ...[
                  _ReceiptDivider(),
                  _PreviewNotes(notes: order.notes!),
                ],
                _ReceiptDivider(),
                _PreviewFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 24),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: const Column(
        children: [
          Icon(Icons.water_drop_outlined, color: AppColors.gold, size: 32),
          SizedBox(height: 8),
          Text('KNZ Scent',
              style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4)),
          SizedBox(height: 4),
          Text('S C E N T',
              style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 11,
                  letterSpacing: 8,
                  fontWeight: FontWeight.w300)),
          SizedBox(height: 10),
          _OfficialReceiptBadge(),
        ],
      ),
    );
  }
}

class _OfficialReceiptBadge extends StatelessWidget {
  const _OfficialReceiptBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text('OFFICIAL RECEIPT',
          style: TextStyle(
              color: AppColors.gold,
              fontSize: 10,
              letterSpacing: 3,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _PreviewOrderInfo extends StatelessWidget {
  final Order order;
  final DateFormat dateFmt;

  const _PreviewOrderInfo({required this.order, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          _InfoRow(
            label: 'Order ID',
            value: order.orderId,
            valueStyle: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                fontSize: 15),
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'Customer', value: order.customerName),
          const SizedBox(height: 8),
          _InfoRow(label: 'Date', value: dateFmt.format(order.orderDate)),
        ],
      ),
    );
  }
}

class _PreviewItemsTable extends StatelessWidget {
  final Order order;
  final NumberFormat currency;

  const _PreviewItemsTable({required this.order, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text('ITEM',
                    style: TextStyle(
                        color: AppColors.whiteTertiary,
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600)),
              ),
              Text('AMOUNT',
                  style: TextStyle(
                      color: AppColors.whiteTertiary,
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
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
                          Text(
                            item.productName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis, // FIX: Inayos ang text overflow
                            style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.quantity} x ${currency.format(item.unitPrice)}',
                            style: const TextStyle(
                                color: AppColors.whiteTertiary,
                                fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      currency.format(item.subtotal),
                      style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _PreviewTotals extends StatelessWidget {
  final Order order;
  final NumberFormat currency;

  const _PreviewTotals({required this.order, required this.currency});

  double get _computedTotal =>
      order.items.fold(0.0, (sum, item) => sum + item.subtotal);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('TOTAL',
              style: TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5)),
          Text(currency.format(_computedTotal),
              style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  final Order order;

  const _PreviewStatus({required this.order});

  Color get _color {
    switch (order.status) {
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.shipped:
        return Colors.purple;
      case OrderStatus.processing:
        return AppColors.info;
      case OrderStatus.pending:
        return AppColors.warning;
      case OrderStatus.cancelled:
        return AppColors.error;
      case OrderStatus.utang:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Status',
              style: TextStyle(
                  color: AppColors.whiteTertiary, fontSize: 13)),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _color.withValues(alpha: 0.4)),
            ),
            child: Text(
              order.status.displayName.toUpperCase(),
              style: TextStyle(
                  color: _color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewNotes extends StatelessWidget {
  final String notes;

  const _PreviewNotes({required this.notes});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notes',
              style: TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 11,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text(notes,
              style: const TextStyle(
                  color: AppColors.whiteSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _PreviewFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: const Column(
        children: [
          Text('✦  Thank you for your purchase!  ✦',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1)),
          SizedBox(height: 4),
          Text('KNZ Scent — Luxury Fragrance House',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.whiteTertiary,
                  fontSize: 11,
                  letterSpacing: 1)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PrintPanel — Bluetooth scan + connect + print to 58mm thermal printer
// ─────────────────────────────────────────────────────────────────────────────
class _PrintPanel extends StatefulWidget {
  final Order order;

  const _PrintPanel({required this.order});

  @override
  State<_PrintPanel> createState() => _PrintPanelState();
}

class _PrintPanelState extends State<_PrintPanel> {
  _PrintState _state = _PrintState.idle;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  String _statusMessage = 'Tap "Connect Printer" to find your printer';
  StreamSubscription? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }

  // ── Permissions (FIXED) ────────────────────────────────────────────────
  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();

    // Kailangang maging true ang Scan at Connect para sa Android 12+
    return (statuses[Permission.bluetoothScan]?.isGranted ?? false) &&
           (statuses[Permission.bluetoothConnect]?.isGranted ?? false);
  }

  // ── Scan ───────────────────────────────────────────────────────────────
  Future<void> _startScan() async {
    final granted = await _requestPermissions();
    if (!granted) {
      _setStatus(_PrintState.error,
          'Bluetooth permission denied.\nPlease allow in Settings.');
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _setStatus(_PrintState.error, 'Please turn on Bluetooth first.');
      return;
    }

    setState(() {
      _state = _PrintState.scanning;
      _scanResults = [];
      _statusMessage = 'Scanning for printers...';
    });

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults =
              results.where((r) => r.device.platformName.isNotEmpty).toList();
        });
      }
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    await Future.delayed(const Duration(seconds: 8));
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();

    if (mounted) {
      setState(() {
        _state = _scanResults.isEmpty
            ? _PrintState.error
            : _PrintState.scanned;
        _statusMessage = _scanResults.isEmpty
            ? 'No printers found. Make sure printer is on.'
            : 'Select your printer below:';
      });
    }
  }

  // ── Connect ────────────────────────────────────────────────────────────
  Future<void> _connectTo(BluetoothDevice device) async {
    _setStatus(
        _PrintState.connecting, 'Connecting to ${device.platformName}...');
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _state = _PrintState.connected;
          _statusMessage = '✓ Connected to ${device.platformName}';
        });
      }
    } catch (_) {
      _setStatus(_PrintState.error, 'Connection failed. Try again.');
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────
  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
    if (mounted) {
      setState(() {
        _connectedDevice = null;
        _state = _PrintState.idle;
        _scanResults = [];
        _statusMessage = 'Tap "Connect Printer" to find your printer';
      });
    }
  }

  // ── Build ESC/POS bytes for 58mm paper ────────────────────────────────
  Future<List<int>> _buildReceiptBytes() async {
    final profile = await CapabilityProfile.load();
    final gen    = Generator(PaperSize.mm58, profile);
    final cur    = NumberFormat.currency(symbol: 'P', decimalDigits: 2);
    final dateFmt = DateFormat('MM/dd/yyyy hh:mm a');

    List<int> bytes = [];

    bytes += gen.text('================================',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('KNZ SCENT',
        styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2));
    bytes += gen.text('Luxury Fragrance House',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('================================',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('OFFICIAL RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += gen.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.emptyLines(1);

    bytes += gen.row([
      PosColumn(text: 'Order ID  :', width: 5),
      PosColumn(
          text: widget.order.orderId,
          width: 7,
          styles: const PosStyles(bold: true)),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Customer  :', width: 5),
      PosColumn(text: widget.order.customerName, width: 7),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Date      :', width: 5),
      PosColumn(text: dateFmt.format(widget.order.orderDate), width: 7),
    ]);
    bytes += gen.row([
      PosColumn(text: 'Status    :', width: 5),
      PosColumn(
          text: widget.order.status.displayName.toUpperCase(),
          width: 7,
          styles: const PosStyles(bold: true)),
    ]);

    bytes += gen.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));

    bytes += gen.row([
      PosColumn(
          text: 'Item',
          width: 6,
          styles: const PosStyles(bold: true, underline: true)),
      PosColumn(
          text: 'Qty',
          width: 2,
          styles: const PosStyles(
              bold: true, underline: true, align: PosAlign.center)),
      PosColumn(
          text: 'Amount',
          width: 4,
          styles: const PosStyles(
              bold: true, underline: true, align: PosAlign.right)),
    ]);

    for (final item in widget.order.items) {
      final name = item.productName.length > 18
          ? '${item.productName.substring(0, 16)}..'
          : item.productName;

      bytes += gen.row([
        PosColumn(text: name, width: 6),
        PosColumn(
            text: '${item.quantity}',
            width: 2,
            styles: const PosStyles(align: PosAlign.center)),
        PosColumn(
            text: cur.format(item.subtotal),
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += gen.row([
        PosColumn(
            text: '  @ ${cur.format(item.unitPrice)} each',
            width: 12,
            styles: const PosStyles(fontType: PosFontType.fontB)),
      ]);
    }

    bytes += gen.text('--------------------------------',
        styles: const PosStyles(align: PosAlign.center));

    bytes += gen.row([
      PosColumn(
          text: 'TOTAL:',
          width: 5,
          styles: const PosStyles(
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
      PosColumn(
          text: cur.format(widget.order.totalAmount),
          width: 7,
          styles: const PosStyles(
              bold: true,
              align: PosAlign.right,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
    ]);

    if (widget.order.notes != null && widget.order.notes!.isNotEmpty) {
      bytes += gen.text('--------------------------------',
          styles: const PosStyles(align: PosAlign.center));
      bytes += gen.text('Note:', styles: const PosStyles(bold: true));
      bytes += gen.text(widget.order.notes!,
          styles: const PosStyles(fontType: PosFontType.fontB));
    }

    bytes += gen.emptyLines(1);
    bytes += gen.text('================================',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('Thank you for your purchase!',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += gen.text('KNZ Scent',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.text('================================',
        styles: const PosStyles(align: PosAlign.center));
    bytes += gen.emptyLines(3);
    bytes += gen.cut();

    return bytes;
  }

  // ── Print ──────────────────────────────────────────────────────────────
  Future<void> _print() async {
    if (_connectedDevice == null) return;
    _setStatus(_PrintState.printing, 'Printing receipt...');

    try {
      final bytes = await _buildReceiptBytes();
      final services = await _connectedDevice!.discoverServices();

      BluetoothCharacteristic? printChar;
      for (final svc in services) {
        for (final ch in svc.characteristics) {
          if (ch.properties.write || ch.properties.writeWithoutResponse) {
            printChar = ch;
            break;
          }
        }
        if (printChar != null) break;
      }

      if (printChar == null) {
        _setStatus(
            _PrintState.error, 'Cannot find print channel on this device.');
        return;
      }

      const chunk = 200;
      for (int i = 0; i < bytes.length; i += chunk) {
        final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
        await printChar.write(
          bytes.sublist(i, end),
          withoutResponse: printChar.properties.writeWithoutResponse,
        );
        await Future.delayed(const Duration(milliseconds: 20));
      }

      _setStatus(_PrintState.connected, '✓ Receipt printed successfully!');
    } catch (e) {
      _setStatus(_PrintState.error, 'Print failed. Try again.');
    }
  }

  void _setStatus(_PrintState state, String message) {
    if (mounted) setState(() { _state = state; _statusMessage = message; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBar(state: _state, message: _statusMessage),
          if (_state == _PrintState.scanned && _scanResults.isNotEmpty)
            _DeviceList(results: _scanResults, onSelect: _connectTo),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: _ActionButtons(
              state: _state,
              onScan: _startScan,
              onPrint: _print,
              onDisconnect: _disconnect,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final _PrintState state;
  final String message;

  const _StatusBar({required this.state, required this.message});

  Color get _color {
    switch (state) {
      case _PrintState.connected:
        return AppColors.success;
      case _PrintState.error:
        return AppColors.error;
      case _PrintState.printing:
        return AppColors.info;
      default:
        return AppColors.whiteTertiary;
    }
  }

  IconData get _icon {
    switch (state) {
      case _PrintState.connected:
        return Icons.bluetooth_connected;
      case _PrintState.error:
        return Icons.error_outline;
      default:
        return Icons.bluetooth_outlined;
    }
  }

  bool get _isBusy =>
      state == _PrintState.scanning ||
      state == _PrintState.connecting ||
      state == _PrintState.printing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _color.withValues(alpha: 0.08),
      child: Row(
        children: [
          if (_isBusy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _color),
            )
          else
            Icon(_icon, color: _color, size: 16),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(color: _color, fontSize: 12))),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final List<ScanResult> results;
  final void Function(BluetoothDevice) onSelect;

  const _DeviceList({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (_, i) {
          final r = results[i];
          final name = r.device.platformName.toLowerCase();
          final isPrinter =
              name.contains('printer') ||
              name.contains('sdxp') ||
              name.contains('pt-') ||
              name.contains('mtp') ||
              name.contains('thermal');
          return ListTile(
            dense: true,
            leading: Icon(
              isPrinter ? Icons.print_outlined : Icons.bluetooth,
              color: isPrinter ? AppColors.gold : AppColors.whiteTertiary,
              size: 18,
            ),
            title: Text(r.device.platformName,
                style: TextStyle(
                    color: isPrinter ? AppColors.gold : AppColors.white,
                    fontSize: 13,
                    fontWeight:
                        isPrinter ? FontWeight.w600 : FontWeight.normal)),
            subtitle: Text(r.device.remoteId.toString(),
                style: const TextStyle(
                    color: AppColors.whiteTertiary, fontSize: 10)),
            trailing: const Icon(Icons.chevron_right,
                color: AppColors.whiteTertiary, size: 18),
            onTap: () => onSelect(r.device),
          );
        },
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final _PrintState state;
  final VoidCallback onScan;
  final VoidCallback onPrint;
  final VoidCallback onDisconnect;

  const _ActionButtons({
    required this.state,
    required this.onScan,
    required this.onPrint,
    required this.onDisconnect,
  });

  bool get _isBusy =>
      state == _PrintState.scanning ||
      state == _PrintState.connecting ||
      state == _PrintState.printing;

  @override
  Widget build(BuildContext context) {
    if (state == _PrintState.connected) {
      return Row(children: [
        Expanded(
          child: _OutlineButton(
            label: 'Disconnect',
            icon: Icons.bluetooth_disabled,
            color: AppColors.error,
            onTap: _isBusy ? null : onDisconnect,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _GoldButton(
            label: 'Print Receipt',
            icon: Icons.print_outlined,
            onTap: _isBusy ? null : onPrint,
          ),
        ),
      ]);
    }

    return _GoldButton(
      label: _isBusy ? 'Please wait...' : 'Connect Printer',
      icon: Icons.bluetooth_searching,
      onTap: _isBusy ? null : onScan,
    );
  }
}

class _ReceiptDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.divider);
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _InfoRow({required this.label, required this.value, this.valueStyle});

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
                      fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _GoldButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: active ? AppColors.goldGradient : null,
          color: active ? null : AppColors.cardBorder,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: active ? AppColors.background : AppColors.whiteTertiary,
                size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: active
                        ? AppColors.background
                        : AppColors.whiteTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _OutlineButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

enum _PrintState {
  idle,
  scanning,
  scanned,
  connecting,
  connected,
  printing,
  error,
}