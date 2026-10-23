import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/core/app_state.dart';
import 'package:knz_scent_admin/database/database_helper.dart';
import 'package:knz_scent_admin/dto/business_event_dto.dart';
import 'package:knz_scent_admin/dto/custom_order_dto.dart';
import 'package:knz_scent_admin/dto/debt_dto.dart';
import 'package:knz_scent_admin/dto/order_dto.dart';
import 'package:knz_scent_admin/dto/product_dto.dart';
import 'package:knz_scent_admin/dto/reseller_dto.dart';
import 'package:knz_scent_admin/core/money.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/reseller_model.dart';
import 'package:knz_scent_admin/models/user_model.dart';
import 'package:knz_scent_admin/services/auth_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fixtures/accounting_fixture.dart';

class _Auth extends Fake implements IAuthService {
  _Auth(this.role);
  final String role;
  @override
  Future<AuthResult> restoreTrustedDevice() async => AuthResult(
    status: 'offline',
    user: AppUser(
      id: 'owner-1',
      username: 'owner',
      name: 'Owner',
      email: 'owner@example.com',
      role: role,
      accountStatus: 'approved',
      isActive: true,
      createdAt: DateTime.utc(2026),
    ),
  );
  @override
  Future<void> logout() async {}
}

/// Real local loading and screen state, with synthetic data and no cloud access.
class FeatureFixture {
  final data = AccountingFixture();
  final state = AppState();
  late Directory directory;
  late Database db;
  List<int>? sharedBytes;
  Completer<void> shared = Completer<void>();
  static const _paths = MethodChannel('plugins.flutter.io/path_provider');
  static const _share = MethodChannel('dev.fluttercommunity.plus/share');

  Future<void> open() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('knz-features-');
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(directory.path);
    db = await DatabaseHelper.instance.database;
    final batch = db.batch();
    batch.insert(
      'products',
      ProductDto.fromDomain(
        Product(
          id: 'fixture-product',
          name: 'Fixture Rose',
          description: 'Synthetic inventory',
          category: ProductCategory.eauDeParfum,
          price: const Money.fromCentavos(20000),
          stockQty: 10,
          minStockLevel: 2,
        ),
        userId: 'owner-1',
      ).toLocal(),
    );
    batch.insert(
      'resellers',
      ResellerDto.fromDomain(
        Reseller(
          id: 'fixture-reseller',
          name: 'Fixture Reseller',
          deductionPerItem: const Money.fromCentavos(3050),
          userId: 'owner-1',
          createdAt: DateTime.utc(2026),
        ),
      ).toLocal(),
    );
    for (final original in data.orders) {
      // Order creation and delivery deliberately fall in different months.
      final order = original.id == 'reseller'
          ? original.copyWith(orderDate: DateTime.utc(2026, 4, 30))
          : original;
      final dto = OrderDto.fromDomain(order, userId: 'owner-1');
      batch.insert('orders', dto.toLocal());
      for (final item in dto.items) {
        batch.insert('order_items', item.toLocal());
      }
    }
    for (final debt in data.debts) {
      final dto = DebtDto.fromDomain(debt, userId: 'owner-1');
      batch.insert('debts', dto.toLocal());
      for (final payment in dto.payments) {
        batch.insert('payments', payment.toLocal());
      }
    }
    for (final order in data.customOrders) {
      final dto = CustomOrderDto.fromDomain(order);
      batch.insert('custom_orders', dto.toLocal());
      for (final payment in dto.payments) {
        batch.insert('custom_order_payments', payment.toLocal());
      }
    }
    for (final event in data.businessEvents) {
      batch.insert(
        'business_events',
        BusinessEventDto.fromDomain(event).toLocal(),
      );
    }
    await batch.commit(noResult: true);
    await signInAs('Administrator');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(_share, (call) async {
      final paths = (call.arguments as Map)['paths'] as List;
      sharedBytes = await File(paths.single as String).readAsBytes();
      if (!shared.isCompleted) shared.complete();
      return 'test';
    });
  }

  Future<void> signInAs(String role) async {
    state.configure(
      authService: _Auth(role),
      stopSynchronization: () async {},
      cancelNotifications: () async {},
      syncBusinessAlerts: (_, _) async {},
    );
    await state.restoreTrustedDevice();
  }

  Future<void> close() async {
    await state.logout();
    await db.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_paths, null);
    messenger.setMockMethodCallHandler(_share, null);
    await directory.delete(recursive: true);
  }

  /// Decode content streams emitted by the PDF package (Helvetica fallback).
  /// Assertions inspect the generated document, not a duplicate calculation.
  String pdfContent() {
    final bytes = sharedBytes!;
    final raw = latin1.decode(bytes);
    final streams = <String>[];
    for (final match in RegExp(r'stream\r?\n').allMatches(raw)) {
      final end = raw.indexOf('endstream', match.end);
      if (end < 0) continue;
      final startObject = raw.lastIndexOf(' obj', match.start);
      final header = raw.substring(
        startObject < 0 ? 0 : startObject,
        match.start,
      );
      if (!header.contains('/FlateDecode')) continue;
      try {
        streams.add(latin1.decode(zlib.decode(bytes.sublist(match.end, end))));
      } on FormatException {
        /* Embedded non-content stream. */
      }
    }
    return streams.join('\n');
  }
}
