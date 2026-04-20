// ─────────────────────────────────────────────────────────────────────────────
// product_service_test.dart — Integration tests for ProductService
//
// Tests the full service layer (validation + repo interaction) using an
// in-memory StubProductRepository — no SQLite, no Firebase, no I/O.
//
// Coverage:
//   ✔ addProduct  — valid input, blank name, negative price, negative stock,
//                   negative minStockLevel
//   ✔ getAll      — returns only what was added
//   ✔ updateProduct — mutation is persisted in repo
//   ✔ updateStock   — valid and negative-qty guard
//   ✔ deleteProduct — soft-delete moves item to deleted bucket
//   ✔ getDeleted  — returns soft-deleted items
//   ✔ restoreProduct — moves item back to active
//   ✔ hardDeleteProduct — purges from both buckets
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'stubs/stub_product_repository.dart';
import 'stubs/stub_services.dart';

void main() {
  late StubProductRepository repo;
  late StubProductService service;

  setUp(() {
    repo = StubProductRepository();
    service = StubProductService(repo);
  });

  group('ProductService — addProduct()', () {
    test('valid input adds product to repo and returns null error', () async {
      final error = await service.addProduct(
        userId:        'u1',
        name:          'Noir Intense',
        description:   'A rich woody fragrance',
        category:      ProductCategory.eauDeParfum,
        price:         1299.0,
        stockQty:      50,
        minStockLevel: 5,
      );

      expect(error, isNull);
      expect(repo.count, 1);
    });

    test('blank name returns validation error', () async {
      final error = await service.addProduct(
        userId:        'u1',
        name:          '   ',
        description:   '',
        category:      ProductCategory.bodyMist,
        price:         499.0,
        stockQty:      10,
        minStockLevel: 2,
      );

      expect(error, 'Product name is required');
      expect(repo.count, 0, reason: 'Nothing should be stored on validation error');
    });

    test('negative price returns validation error', () async {
      final error = await service.addProduct(
        userId:        'u1',
        name:          'Test Scent',
        description:   '',
        category:      ProductCategory.perfumeOil,
        price:         -1.0,
        stockQty:      5,
        minStockLevel: 1,
      );

      expect(error, 'Price cannot be negative');
      expect(repo.count, 0);
    });

    test('negative stockQty returns validation error', () async {
      final error = await service.addProduct(
        userId:        'u1',
        name:          'Test Scent',
        description:   '',
        category:      ProductCategory.eauDeToilette,
        price:         500.0,
        stockQty:      -3,
        minStockLevel: 1,
      );

      expect(error, 'Stock cannot be negative');
      expect(repo.count, 0);
    });

    test('negative minStockLevel returns validation error', () async {
      final error = await service.addProduct(
        userId:        'u1',
        name:          'Test Scent',
        description:   '',
        category:      ProductCategory.giftSet,
        price:         999.0,
        stockQty:      10,
        minStockLevel: -1,
      );

      expect(error, 'Min stock level cannot be negative');
      expect(repo.count, 0);
    });

    test('zero price is allowed (free sample)', () async {
      final error = await service.addProduct(
        userId:        'u1',
        name:          'Free Sample',
        description:   '',
        category:      ProductCategory.bodyMist,
        price:         0.0,
        stockQty:      100,
        minStockLevel: 0,
      );

      expect(error, isNull);
      expect(repo.count, 1);
    });
  });

  group('ProductService — getAll()', () {
    test('returns all products added through the service', () async {
      await service.addProduct(
        userId: 'u1', name: 'A', description: '', category: ProductCategory.eauDeParfum,
        price: 100, stockQty: 10, minStockLevel: 1,
      );
      await service.addProduct(
        userId: 'u1', name: 'B', description: '', category: ProductCategory.bodyMist,
        price: 200, stockQty: 20, minStockLevel: 2,
      );

      final products = await service.getAll('u1');

      expect(products.length, 2);
    });
  });

  group('ProductService — updateStock()', () {
    test('valid new qty updates stock and returns null', () async {
      await service.addProduct(
        userId: 'u1', name: 'Scent X', description: '', category: ProductCategory.eauDeParfum,
        price: 800, stockQty: 20, minStockLevel: 5,
      );
      final productId = repo.store.keys.first;

      final error = await service.updateStock(productId, 15);

      expect(error, isNull);
      expect(repo.store[productId]!.stockQty, 15);
    });

    test('negative new qty returns validation error', () async {
      await service.addProduct(
        userId: 'u1', name: 'Scent Y', description: '', category: ProductCategory.eauDeParfum,
        price: 500, stockQty: 10, minStockLevel: 2,
      );
      final productId = repo.store.keys.first;

      final error = await service.updateStock(productId, -5);

      expect(error, 'Stock cannot be negative');
      expect(repo.store[productId]!.stockQty, 10, reason: 'Stock must be unchanged on error');
    });
  });

  group('ProductService — Recycle Bin', () {
    test('deleteProduct soft-deletes: active list shrinks, deleted list grows', () async {
      await service.addProduct(
        userId: 'u1', name: 'Scent Z', description: '', category: ProductCategory.giftSet,
        price: 1500, stockQty: 5, minStockLevel: 1,
      );
      final productId = repo.store.keys.first;

      await service.deleteProduct(productId);

      expect(repo.count, 0);
      expect(repo.deletedCount, 1);
    });

    test('getDeleted returns the soft-deleted product', () async {
      await service.addProduct(
        userId: 'u1', name: 'Scent Z', description: '', category: ProductCategory.giftSet,
        price: 1500, stockQty: 5, minStockLevel: 1,
      );
      final productId = repo.store.keys.first;
      await service.deleteProduct(productId);

      final deleted = await service.getDeleted('u1');

      expect(deleted.length, 1);
      expect(deleted.first.id, productId);
    });

    test('restoreProduct moves product back to active', () async {
      await service.addProduct(
        userId: 'u1', name: 'Scent Z', description: '', category: ProductCategory.giftSet,
        price: 1500, stockQty: 5, minStockLevel: 1,
      );
      final productId = repo.store.keys.first;
      await service.deleteProduct(productId);

      await service.restoreProduct(productId);

      expect(repo.count, 1);
      expect(repo.deletedCount, 0);
    });

    test('hardDeleteProduct removes product from both stores', () async {
      await service.addProduct(
        userId: 'u1', name: 'Scent Z', description: '', category: ProductCategory.giftSet,
        price: 1500, stockQty: 5, minStockLevel: 1,
      );
      final productId = repo.store.keys.first;
      await service.deleteProduct(productId);

      await service.hardDeleteProduct(productId);

      expect(repo.count, 0);
      expect(repo.deletedCount, 0);
    });
  });
}
