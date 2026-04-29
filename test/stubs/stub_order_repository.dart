// stub_order_repository.dart — In-memory stub for OrderRepository
import 'package:knz_scent_admin/models/order_model.dart';
import 'package:knz_scent_admin/repositories/order_repository.dart';

class StubOrderRepository implements OrderRepository {
  final Map<String, Order> store   = {};
  final Map<String, Order> deleted = {};
  int counter = 0;

  @override Future<List<Order>> getAll(String userId, {DateTime? fromDate, DateTime? toDate}) async {
    var result = store.values.toList();
    if (fromDate != null) result = result.where((o) => !o.orderDate.isBefore(fromDate)).toList();
    if (toDate   != null) result = result.where((o) => !o.orderDate.isAfter(toDate)).toList();
    return result;
  }
  @override Future<void> add(Order order, String userId) async { counter++; store[order.id] = order; }
  @override Future<void> updateStatus(String orderId, OrderStatus status) async {
    final o = store[orderId];
    if (o != null) store[orderId] = o.copyWith(status: status);
  }
  @override Future<void> delete(String orderId) async {
    final o = store.remove(orderId);
    if (o != null) deleted[orderId] = o;
  }
  @override Future<int> getNextOrderNumber(String userId) async => counter + 1;
  @override Future<List<Order>> getDeleted(String userId) async => deleted.values.toList();
  @override Future<void> restore(String orderId) async {
    final o = deleted.remove(orderId);
    if (o != null) store[orderId] = o;
  }
  @override Future<void> hardDelete(String orderId) async {
    store.remove(orderId);
    deleted.remove(orderId);
  }

  void seed(Order order) => store[order.id] = order;
  void clear() { store.clear(); deleted.clear(); counter = 0; }
  int get count        => store.length;
  int get deletedCount => deleted.length;
}
