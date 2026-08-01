// ─────────────────────────────────────────────────────────────────────────────
// receipt_shared_widgets.dart
// Purpose : Shared base classes and UI components used by both ReceiptScreen
//           (order receipts) and UtangReceiptScreen (utang statements).
// Function: Defines the abstract ReceiptWidget<T> base class that enforces a
//           typed-data contract via generics. Provides concrete widgets:
//           ReceiptDivider, ReceiptInfoRow, ReceiptHeader, ReceiptCard,
//           ReceiptFooter, and ReceiptSection — all extending ReceiptWidget<T>.
//           Also defines the sealed BtPrintState hierarchy (BtIdle, BtScanning,
//           BtScanned, BtConnecting, BtConnected, BtPrinting, BtError) and
//           Bluetooth UI components: BtStatusBar, BtDeviceList, BtGoldButton,
//           BtOutlineButton, BtActionButtons, BtPrintPanelShell.
//
// OOP Pillars applied:
//   Abstraction   — abstract class ReceiptWidget enforces a typed-data contract
//                   via the generic [data] getter.
//   Encapsulation — all fields are final + constructor-injected; BtPrintState is
//                   sealed so only declared subtypes can exist.
//   Inheritance   — ReceiptDivider / ReceiptInfoRow / ReceiptHeader / ReceiptCard /
//                   ReceiptFooter / ReceiptSection all extend ReceiptWidget.
//   Polymorphism  — BtStatusBar and BtActionButtons branch on the sealed BtPrintState
//                   subtype with exhaustive pattern matching.
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/app_constants.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// ABSTRACTION — Abstract base class for all receipt widgets
// ═══════════════════════════════════════════════════════════════════════════════

/// Abstract contract for every receipt-related widget.
///
/// Subclasses declare their [data] type via the generic [T], which documents
/// what the widget needs and prevents silent null surprises.
/// [buildReceipt] replaces the normal [build] override — the base class
/// provides the [build] wiring so widgets never skip the contract.
abstract class ReceiptWidget<T> extends StatelessWidget {
  const ReceiptWidget({super.key});

  /// The strongly-typed data this widget renders.
  T get data;

  /// Implement this instead of [build].
  Widget buildReceipt(BuildContext context);

  @override
  @nonVirtual
  Widget build(BuildContext context) => buildReceipt(context);
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEALED CLASS — BtPrintState  (Dart 3+)
//
// Why sealed over enum?
//   • BtConnected carries the live BluetoothDevice — no null-checks in callers.
//   • BtError carries its message — no separate _statusMessage String needed.
//   • The compiler enforces exhaustive switch — new states can't be silently
//     missed by existing switch blocks.
// ═══════════════════════════════════════════════════════════════════════════════

sealed class BtPrintState {
  const BtPrintState();
}

/// Initial / reset state — no device, no activity.
final class BtIdle extends BtPrintState {
  const BtIdle();
}

/// Actively scanning for nearby BT devices.
final class BtScanning extends BtPrintState {
  const BtScanning();
}

/// Scan finished; [results] contains discovered devices.
final class BtScanned extends BtPrintState {
  final List<ScanResult> results;
  const BtScanned(this.results);
}

/// Attempting to connect to [deviceName].
final class BtConnecting extends BtPrintState {
  final String deviceName;
  const BtConnecting(this.deviceName);
}

/// Successfully connected; [device] is ready to print.
final class BtConnected extends BtPrintState {
  final BluetoothDevice device;
  const BtConnected(this.device);
}

/// Sending bytes to the connected printer.
final class BtPrinting extends BtPrintState {
  const BtPrinting();
}

/// Something went wrong; [message] describes the problem.
final class BtError extends BtPrintState {
  final String message;
  const BtError(this.message);
}

// ─── Convenience helpers on the sealed type ────────────────────────────────

extension BtPrintStateX on BtPrintState {
  bool get isBusy =>
      this is BtScanning || this is BtConnecting || this is BtPrinting;

  bool get isConnected => this is BtConnected;

  /// Default human-readable status text for each state.
  String get defaultMessage => switch (this) {
    BtIdle() => 'Tap "Connect Printer" to find your printer',
    BtScanning() => 'Scanning for printers...',
    BtScanned() => 'Select your printer below:',
    BtConnecting(deviceName: final n) => 'Connecting to $n...',
    BtConnected(device: final d) => '✓ Connected to ${d.platformName}',
    BtPrinting() => 'Printing receipt...',
    BtError(message: final m) => m,
  };
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECEIPT UI WIDGETS
// All extend ReceiptWidget<T> — Inheritance + Abstraction in action.
// ═══════════════════════════════════════════════════════════════════════════════

// ── Divider ───────────────────────────────────────────────────────────────────

/// A thin horizontal rule between receipt sections.
/// data is void — no external data needed.
class ReceiptDivider extends ReceiptWidget<void> {
  const ReceiptDivider({super.key});

  @override
  void get data {}

  @override
  Widget buildReceipt(BuildContext context) =>
      Container(height: 1, color: AppColors.divider);
}

// ── Info Row ──────────────────────────────────────────────────────────────────

/// A single label–value row.
class ReceiptInfoRow extends ReceiptWidget<({String label, String value})> {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const ReceiptInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  @override
  ({String label, String value}) get data => (label: label, value: value);

  @override
  Widget buildReceipt(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.whiteTertiary, fontSize: 13),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style:
                valueStyle ??
                const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}

// ── Receipt Header ────────────────────────────────────────────────────────────

/// Brand header shown at the top of every receipt card.
class ReceiptHeader
    extends ReceiptWidget<({String badgeLabel, Color badgeColor})> {
  final String badgeLabel;
  final Color badgeColor;

  const ReceiptHeader({
    super.key,
    required this.badgeLabel,
    required this.badgeColor,
  });

  @override
  ({String badgeLabel, Color badgeColor}) get data =>
      (badgeLabel: badgeLabel, badgeColor: badgeColor);

  @override
  Widget buildReceipt(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 24),
      decoration: const BoxDecoration(
        gradient: AppColors.sidebarGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.water_drop_outlined,
            color: AppColors.gold,
            size: 28,
          ),
          const SizedBox(height: 8),
          const Text(
            AppStrings.appName,
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'S C E N T',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 9,
              letterSpacing: 7,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.10),
              border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeLabel,
              style: TextStyle(
                color: badgeColor,
                fontSize: 10,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Receipt Card wrapper ──────────────────────────────────────────────────────

/// Scrollable card container that wraps all receipt sections.
class ReceiptCard extends ReceiptWidget<List<Widget>> {
  final List<Widget> children;

  const ReceiptCard({super.key, required this.children});

  @override
  List<Widget> get data => children;

  @override
  Widget buildReceipt(BuildContext context) {
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
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Receipt Footer ────────────────────────────────────────────────────────────

/// Two-line footer at the bottom of every receipt card.
class ReceiptFooter extends ReceiptWidget<({String line1, String line2})> {
  final String line1;
  final String line2;

  const ReceiptFooter({super.key, required this.line1, required this.line2});

  @override
  ({String line1, String line2}) get data => (line1: line1, line2: line2);

  @override
  Widget buildReceipt(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(
            line1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            line2,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.whiteTertiary,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Block (padded area) ───────────────────────────────────────────────

/// A padded content block between dividers.
class ReceiptSection extends ReceiptWidget<Widget> {
  final Widget child;
  final EdgeInsets padding;

  const ReceiptSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  });

  @override
  Widget get data => child;

  @override
  Widget buildReceipt(BuildContext context) =>
      Padding(padding: padding, child: child);
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLUETOOTH PRINT PANEL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ── Status Bar ────────────────────────────────────────────────────────────────

/// Top status strip in the print panel.
/// Polymorphism: _color / _icon / _isBusy all dispatch on the sealed BtPrintState
/// subtype — the compiler enforces exhaustiveness so new states can't be missed.
class BtStatusBar extends StatelessWidget {
  final BtPrintState state;
  final String message;

  const BtStatusBar({super.key, required this.state, required this.message});

  Color get _color => switch (state) {
    BtConnected() => AppColors.success,
    BtError() => AppColors.error,
    BtPrinting() => AppColors.info,
    _ => AppColors.whiteTertiary,
  };

  IconData get _icon => switch (state) {
    BtConnected() => Icons.bluetooth_connected,
    BtError() => Icons.error_outline,
    _ => Icons.bluetooth_outlined,
  };

  bool get _isBusy => state.isBusy;

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
            child: Text(message, style: TextStyle(color: _color, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Device List ───────────────────────────────────────────────────────────────

class BtDeviceList extends StatelessWidget {
  final List<ScanResult> results;
  final void Function(BluetoothDevice) onSelect;

  const BtDeviceList({
    super.key,
    required this.results,
    required this.onSelect,
  });

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
            title: Text(
              r.device.platformName,
              style: TextStyle(
                color: isPrinter ? AppColors.gold : AppColors.white,
                fontSize: 13,
                fontWeight: isPrinter ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              r.device.remoteId.toString(),
              style: const TextStyle(
                color: AppColors.whiteTertiary,
                fontSize: 10,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: AppColors.whiteTertiary,
              size: 18,
            ),
            onTap: () => onSelect(r.device),
          );
        },
      ),
    );
  }
}

// ── Gold Button ───────────────────────────────────────────────────────────────

class BtGoldButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const BtGoldButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
  });

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
            Icon(
              icon,
              color: active ? AppColors.background : AppColors.whiteTertiary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.background : AppColors.whiteTertiary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Outline Button ────────────────────────────────────────────────────────────

class BtOutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const BtOutlineButton({
    super.key,
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
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action Buttons Row ────────────────────────────────────────────────────────

/// Renders the correct button set for the current [state].
/// Polymorphism: branches cleanly on sealed BtPrintState.
class BtActionButtons extends StatelessWidget {
  final BtPrintState state;
  final VoidCallback onScan;
  final VoidCallback onPrint;
  final VoidCallback onDisconnect;

  const BtActionButtons({
    super.key,
    required this.state,
    required this.onScan,
    required this.onPrint,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final busy = state.isBusy;

    if (state.isConnected) {
      return Row(
        children: [
          Expanded(
            child: BtOutlineButton(
              label: 'Disconnect',
              icon: Icons.bluetooth_disabled,
              color: AppColors.error,
              onTap: busy ? null : onDisconnect,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: BtGoldButton(
              label: 'Print Receipt',
              icon: Icons.print_outlined,
              onTap: busy ? null : onPrint,
            ),
          ),
        ],
      );
    }

    return BtGoldButton(
      label: busy ? 'Please wait...' : 'Connect Printer',
      icon: Icons.bluetooth_searching,
      onTap: busy ? null : onScan,
    );
  }
}

// ── Print Panel Container ─────────────────────────────────────────────────────

/// Composes BtStatusBar + BtDeviceList (conditional) + BtActionButtons.
/// Abstraction: callers inject callbacks; this shell owns zero BT logic.
/// Note: [scanResults] is removed — the shell reads them from the sealed state.
class BtPrintPanelShell extends StatelessWidget {
  final BtPrintState state;
  final String statusMessage;
  final void Function(BluetoothDevice) onSelect;
  final VoidCallback onScan;
  final VoidCallback onPrint;
  final VoidCallback onDisconnect;

  const BtPrintPanelShell({
    super.key,
    required this.state,
    required this.statusMessage,
    required this.onSelect,
    required this.onScan,
    required this.onPrint,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    // Results live inside BtScanned — no separate list needed.
    final scanResults = switch (state) {
      BtScanned(:final results) => results,
      _ => <ScanResult>[],
    };

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BtStatusBar(state: state, message: statusMessage),
          if (scanResults.isNotEmpty)
            BtDeviceList(results: scanResults, onSelect: onSelect),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: BtActionButtons(
              state: state,
              onScan: onScan,
              onPrint: onPrint,
              onDisconnect: onDisconnect,
            ),
          ),
        ],
      ),
    );
  }
}
