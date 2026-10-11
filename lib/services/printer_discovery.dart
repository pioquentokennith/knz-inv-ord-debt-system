import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/receipt_shared_widgets.dart';

/// Shared progressive discovery for the existing BLE/ESC-POS receipt panels.
class PrinterDiscovery {
  PrinterDiscovery(
    this.onState, {
    Future<bool> Function()? requestPermission,
    Stream<BluetoothAdapterState> Function()? adapterStates,
    Stream<List<ScanResult>> Function()? scanResults,
    Stream<bool> Function()? scanningStates,
    Future<void> Function()? startScan,
    Future<void> Function()? stopScan,
  }) : _requestPermission = requestPermission ?? _permissions,
       _adapterStates = adapterStates ?? (() => FlutterBluePlus.adapterState),
       _scanResults = scanResults ?? (() => FlutterBluePlus.onScanResults),
       _scanningStates = scanningStates ?? (() => FlutterBluePlus.isScanning),
       _startScan =
           startScan ??
           (() =>
               FlutterBluePlus.startScan(timeout: const Duration(seconds: 8))),
       _stopScan = stopScan ?? FlutterBluePlus.stopScan;

  final Future<bool> Function() _requestPermission;
  final Stream<BluetoothAdapterState> Function() _adapterStates;
  final Stream<List<ScanResult>> Function() _scanResults;
  final Stream<bool> Function() _scanningStates;
  final Future<void> Function() _startScan;
  final Future<void> Function() _stopScan;
  Future<void>? _stopping;
  Future<void>? _scanStart;

  static Future<bool> _permissions() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();
    return (permissions[Permission.bluetoothScan]?.isGranted ?? false) &&
        (permissions[Permission.bluetoothConnect]?.isGranted ?? false);
  }

  final void Function(BtPrintState) onState;
  StreamSubscription<List<ScanResult>>? _results;
  StreamSubscription<bool>? _scanning;
  StreamSubscription<BluetoothAdapterState>? _adapter;
  final Map<String, ScanResult> _found = {};
  int _generation = 0;
  bool _disposed = false;
  bool _active = false;

  Future<void> start() async {
    if (_disposed || _active) return;
    final generation = ++_generation;
    _active = true;
    _found.clear();
    bool current() => !_disposed && generation == _generation;
    onState(const BtScanning());
    try {
      await _stopping;
      if (!current()) return;
      final permitted = await _requestPermission();
      if (!current()) return;
      if (!permitted) {
        await _fail('Bluetooth permission denied. Please allow in Settings.');
        return;
      }
      final adapter = await _adapterStates().first.timeout(
        const Duration(seconds: 5),
      );
      if (!current()) return;
      if (adapter != BluetoothAdapterState.on) {
        await _fail('Please turn on Bluetooth first.');
        return;
      }
      _adapter = _adapterStates().listen(
        (state) {
          if (current() && state != BluetoothAdapterState.on) {
            unawaited(_fail('Bluetooth was turned off.'));
          }
        },
        onError: (Object _) {
          if (current()) unawaited(_fail('Could not access Bluetooth.'));
        },
      );
      _results = _scanResults().listen(
        (results) {
          if (!current()) return;
          for (final result in results) {
            if (result.device.platformName.isNotEmpty) {
              _found[result.device.remoteId.str] = result;
            }
          }
          onState(BtScanning(List.unmodifiable(_found.values)));
        },
        onError: (Object _) {
          if (current()) {
            unawaited(_fail('Printer discovery failed. Try again.'));
          }
        },
      );
      var started = false;
      _scanning = _scanningStates().listen((scanning) {
        if (!current()) return;
        if (scanning) started = true;
        if (started && !scanning) unawaited(_finish());
      });
      final scanStart = _startScan();
      _scanStart = scanStart;
      await scanStart;
      if (identical(_scanStart, scanStart)) _scanStart = null;
    } catch (_) {
      if (current()) await _fail('Printer discovery failed. Try again.');
    }
  }

  Future<void> _finish() async {
    final results = List<ScanResult>.unmodifiable(_found.values);
    final generation = _generation + 1;
    await stop();
    if (!_disposed && generation == _generation) {
      onState(
        results.isEmpty
            ? const BtError('No printers found. Make sure printer is on.')
            : BtScanned(results),
      );
    }
  }

  Future<void> _fail(String message) async {
    final generation = _generation + 1;
    await stop();
    if (!_disposed && generation == _generation) onState(BtError(message));
  }

  Future<void> stop() async {
    _generation++;
    if (!_active && _stopping != null) {
      await _stopping;
      return;
    }
    final wasActive = _active;
    _active = false;
    final results = _results?.cancel();
    final scanning = _scanning?.cancel();
    final adapter = _adapter?.cancel();
    _results = null;
    _scanning = null;
    _adapter = null;
    final starting = _scanStart;
    _scanStart = null;
    final cleanup = () async {
      await Future.wait([
        if (results != null) results,
        if (scanning != null) scanning,
        if (adapter != null) adapter,
      ]);
      if (starting != null) {
        // start() reports this failure. Finish the platform start before stopping,
        // otherwise a late completion can restart discovery after selection.
        try {
          await starting;
        } catch (_) {
          /* Reported by start(). */
        }
      }
      if (wasActive) {
        try {
          await _stopScan();
        } catch (_) {
          // The adapter may already be off. Subscriptions are still released.
        }
      }
    }();
    _stopping = cleanup;
    await cleanup;
    if (identical(_stopping, cleanup)) _stopping = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }
}
