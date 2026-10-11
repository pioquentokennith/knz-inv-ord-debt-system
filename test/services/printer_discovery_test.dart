import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/services/printer_discovery.dart';
import 'package:knz_scent_admin/widgets/receipt_shared_widgets.dart';

class _Device extends Fake implements BluetoothDevice {
  @override
  String get platformName => 'Senda';
  @override
  DeviceIdentifier get remoteId => const DeviceIdentifier('printer-1');
}

class _Result extends Fake implements ScanResult {
  @override
  BluetoothDevice get device => _Device();
}

void main() {
  late StreamController<List<ScanResult>> results;
  late StreamController<bool> scanning;
  late StreamController<BluetoothAdapterState> adapter;
  late List<BtPrintState> states;
  late PrinterDiscovery service;
  var permitted = true;
  var enabled = true;
  var stopped = 0;
  Future<void> Function()? onStart;
  setUp(() {
    permitted = true;
    enabled = true;
    stopped = 0;
    onStart = null;
    states = [];
    results = StreamController.broadcast(sync: true);
    scanning = StreamController.broadcast(sync: true);
    adapter = StreamController.broadcast(sync: true);
    service = PrinterDiscovery(
      states.add,
      requestPermission: () async => permitted,
      adapterStates: () async* {
        yield enabled ? BluetoothAdapterState.on : BluetoothAdapterState.off;
        yield* adapter.stream;
      },
      scanResults: () => results.stream,
      scanningStates: () => scanning.stream,
      startScan: () async {
        scanning.add(true);
        await onStart?.call();
      },
      stopScan: () async {
        stopped++;
      },
    );
  });
  tearDown(() async {
    await service.dispose();
    await results.close();
    await scanning.close();
    await adapter.close();
  });
  test(
    'printers appear during scan, deduplicate, and selection cancels callbacks',
    () async {
      await service.start();
      results.add([_Result(), _Result()]);
      expect((states.last as BtScanning).results, hasLength(1));
      expect(stopped, 0);
      await service
          .stop(); // Same action used before connecting a selected device.
      final count = states.length;
      results.add([_Result()]);
      scanning.add(false);
      expect(states, hasLength(count));
      expect(results.hasListener, isFalse);
      expect(scanning.hasListener, isFalse);
    },
  );
  test('empty completed scan and disabled Bluetooth produce errors', () async {
    await service.start();
    scanning.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<BtError>());
    enabled = false;
    await service.start();
    expect((states.last as BtError).message, contains('turn on'));
  });
  test('permission failure and plugin exception are surfaced', () async {
    permitted = false;
    await service.start();
    expect((states.last as BtError).message, contains('permission'));
    permitted = true;
    onStart = () async => throw StateError('plugin failure');
    await service.start();
    expect((states.last as BtError).message, contains('failed'));
  });
  test(
    'disposing during platform startup waits then stops without publishing',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      onStart = () async {
        started.complete();
        await release.future;
      };
      final start = service.start();
      await started.future;
      final count = states.length;
      final dispose = service.dispose();
      release.complete();
      await Future.wait([start, dispose]);
      results.add([_Result()]);
      expect(states, hasLength(count));
      expect(stopped, 1);
    },
  );
}
