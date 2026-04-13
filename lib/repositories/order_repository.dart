import '../models/order_model.dart';

abstract class OrderRepository {
  Future<List<Order>> getAll(String userId);
  Future<void> add(Order order, String userId);
  Future<void> updateStatus(String orderId, OrderStatus status);
  Future<void> delete(String orderId);
  Future<int> getNextOrderNumber(String userId);
}
