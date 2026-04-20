// stub_services.dart — Stub service implementations wrapping in-memory repos
import 'package:uuid/uuid.dart';
import 'package:knz_scent_admin/models/product_model.dart';
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/models/debt_model.dart';
import 'package:knz_scent_admin/services/product_service.dart';
import 'package:knz_scent_admin/services/order_service.dart';
import 'package:knz_scent_admin/services/debt_service.dart';
import 'stub_product_repository.dart';
import 'stub_order_repository.dart';
import 'stub_debt_repository.dart';

// ── Product ───────────────────────────────────────────────────────────────────

class StubProductService implements IProductService {
  final StubProductRepository repo;
  final _uuid = const Uuid();
  StubProductService(this.repo);

  @override Future<List<Product>> getAll(String userId) => repo.getAll(userId);

  @override
  Future<String?> addProduct({
    required String userId, required String name, required String description,
    required ProductCategory category, required double price,
    required int stockQty, required int minStockLevel, String? imagePath,
  }) async {
    if (name.trim().isEmpty)  return 'Product name is required';
    if (price < 0)            return 'Price cannot be negative';
    if (stockQty < 0)         return 'Stock cannot be negative';
    if (minStockLevel < 0)    return 'Min stock level cannot be negative';
    await repo.add(Product(
      id: _uuid.v4(), name: name.trim(), description: description.trim(),
      category: category, price: price, stockQty: stockQty,
      minStockLevel: minStockLevel, imagePath: imagePath,
    ), userId);
    return null;
  }

  @override Future<void> updateProduct(Product product) => repo.update(product);
  @override Future<String?> updateStock(String productId, int newQty) async {
    if (newQty < 0) return 'Stock cannot be negative';
    await repo.updateStock(productId, newQty);
    return null;
  }
  @override Future<void> deleteProduct(String productId) => repo.delete(productId);
  @override Future<List<Product>> getDeleted(String userId) => repo.getDeleted(userId);
  @override Future<void> restoreProduct(String productId) => repo.restore(productId);
  @override Future<void> hardDeleteProduct(String productId) => repo.hardDelete(productId);
}

// ── Order ─────────────────────────────────────────────────────────────────────

class StubOrderService implements IOrderService {
  final StubOrderRepository   orderRepo;
  final StubProductRepository productRepo;
  StubOrderService(this.orderRepo, this.productRepo);

  @override Future<List<Order>> getAll(String userId) => orderRepo.getAll(userId);
  @override Future<String> generateOrderId(String userId) async {
    final num = await orderRepo.getNextOrderNumber(userId);
    return 'KNZ-${num.toString().padLeft(3, '0')}';
  }
  @override Future<void> createOrder(Order order, String userId, List<Product> products) async {
    if (userId.isEmpty) throw StateError('No active user — cannot create order');
    await orderRepo.add(order, userId);
    for (final item in order.items) {
      try {
        final product = products.firstWhere(
          (p) => p.id == item.productId ||
                 p.name.toLowerCase() == item.productName.toLowerCase(),
        );
        final newQty = (product.stockQty - item.quantity).clamp(0, 999999);
        await productRepo.updateStock(product.id, newQty);
      } catch (_) {}
    }
  }
  @override Future<void> updateStatus(String orderId, OrderStatus status) =>
      orderRepo.updateStatus(orderId, status);
  @override Future<void> deleteOrder(String orderId) => orderRepo.delete(orderId);
  @override Future<List<Order>> getDeleted(String userId) => orderRepo.getDeleted(userId);
  @override Future<void> restoreOrder(String orderId) => orderRepo.restore(orderId);
  @override Future<void> hardDeleteOrder(String orderId) => orderRepo.hardDelete(orderId);
}

// ── Debt ──────────────────────────────────────────────────────────────────────

class StubDebtService implements IDebtService {
  final StubDebtRepository repo;
  StubDebtService(this.repo);

  @override Future<List<CustomerDebt>> getAll(String userId) => repo.getAll(userId);
  @override Future<void> addDebt(CustomerDebt debt, String userId) => repo.add(debt, userId);
  @override Future<String?> addPayment(
      String debtId, PaymentRecord payment, double remainingBalance) async {
    if (payment.amount <= 0) return 'Payment amount must be greater than zero';
    if (payment.amount > remainingBalance) {
      return 'Amount exceeds remaining balance of ₱${remainingBalance.toStringAsFixed(2)}';
    }
    await repo.addPayment(debtId, payment);
    return null;
  }
  @override Future<void> deleteDebt(String debtId) => repo.delete(debtId);
  @override Future<List<CustomerDebt>> getDeleted(String userId) => repo.getDeleted(userId);
  @override Future<void> restoreDebt(String debtId) => repo.restore(debtId);
  @override Future<void> hardDeleteDebt(String debtId) => repo.hardDelete(debtId);
}
