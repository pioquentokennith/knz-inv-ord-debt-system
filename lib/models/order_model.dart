// ─────────────────────────────────────────────────────────────────────────────
// order_model.dart — Order & OrderItem entities
// OOP Pillars:
//   • Inheritance  — OrderItem and Order both extend BaseModel
//   • Encapsulation— private fields; public access via getters only
//   • Polymorphism — toMap() overrides BaseModel; OrderStatus extension replaces
//                    switch-statement with map-based dispatch (Polymorphism)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'base_model.dart';

enum OrderStatus {
  pending,
  processing,
  shipped,
  delivered,
  cancelled,
  utang,
}

extension OrderStatusExtension on OrderStatus {
  // ── Polymorphic map dispatch — replaces repetitive switch blocks ──────────
  static const _displayNames = {
    OrderStatus.pending:    'Pending',
    OrderStatus.processing: 'Processing',
    OrderStatus.shipped:    'Shipped',
    OrderStatus.delivered:  'Delivered',
    OrderStatus.cancelled:  'Cancelled',
    OrderStatus.utang:      'Utang',
  };

  static const _colors = {
    OrderStatus.pending:    Color(0xFFFFA726),
    OrderStatus.processing: Color(0xFF29B6F6),
    OrderStatus.shipped:    Color(0xFFAB47BC),
    OrderStatus.delivered:  Color(0xFF43A047),
    OrderStatus.cancelled:  Color(0xFFE53935),
    OrderStatus.utang:      Color(0xFFD4AF37),
  };

  /// Display-friendly name — no switch needed (map-based Polymorphism).
  String get displayName => _displayNames[this] ?? name;

  /// Semantic color for UI badges — centralised, no scattered switch blocks.
  Color get color => _colors[this] ?? const Color(0xFF888888);

  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (e) => e.displayName.toLowerCase() == value.toLowerCase(),
      orElse: () => OrderStatus.pending,
    );
  }
}

/// A single line item inside an order (Inheritance from BaseModel).
class OrderItem extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _productId;
  final String _productName;
  final double _unitPrice;
  final int    _quantity;

  OrderItem({
    required super.id,
    required String productId,
    required String productName,
    required double unitPrice,
    required int    quantity,
  })  : _productId   = productId,
        _productName = productName,
        _unitPrice   = unitPrice,
        _quantity    = quantity;

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  String get productId   => _productId;
  String get productName => _productName;
  double get unitPrice   => _unitPrice;
  int    get quantity    => _quantity;
  double get subtotal    => _unitPrice * _quantity;

  OrderItem copyWith({int? quantity}) => OrderItem(
    id:          id,
    productId:   _productId,
    productName: _productName,
    unitPrice:   _unitPrice,
    quantity:    quantity ?? _quantity,
  );

  /// Polymorphism: overrides BaseModel.toMap()
  @override
  Map<String, dynamic> toMap() => {
    'id':          id,
    'productId':   _productId,
    'productName': _productName,
    'unitPrice':   _unitPrice,
    'quantity':    _quantity,
  };

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    id:          map['id']           as String? ?? '',
    productId:   map['productId']    as String? ?? '',
    productName: map['productName']  as String? ?? '',
    unitPrice:   (map['unitPrice']   as num?)?.toDouble() ?? 0,
    quantity:    map['quantity']     as int?    ?? 1,
  );
}

/// Order entity — inherits from BaseModel (Inheritance).
class Order extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String          _orderId;
  final String          _customerName;
  final List<OrderItem> _items;
  final double          _totalAmount;
  final DateTime        _orderDate;
  final String?         _notes;

  /// [status] is intentionally mutable — orders change status over their lifecycle.
  OrderStatus status;

  Order({
    required super.id,
    required String          orderId,
    required String          customerName,
    required List<OrderItem> items,
    required double          totalAmount,
    required this.status,
    required DateTime        orderDate,
    String?                  notes,
  })  : _orderId      = orderId,
        _customerName = customerName,
        _items        = items,
        _totalAmount  = totalAmount,
        _orderDate    = orderDate,
        _notes        = notes;

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  String          get orderId      => _orderId;
  String          get customerName => _customerName;
  List<OrderItem> get items        => List.unmodifiable(_items);
  double          get totalAmount  => _totalAmount;
  DateTime        get orderDate    => _orderDate;
  String?         get notes        => _notes;

  // ── Computed getters ──────────────────────────────────────────────────────
  String get productName {
    if (_items.isEmpty) return '';
    if (_items.length == 1) return _items.first.productName;
    return '${_items.first.productName} +${_items.length - 1} more';
  }

  int get quantity => _items.fold(0, (sum, i) => sum + i.quantity);

  Order copyWith({
    String?           id,
    String?           orderId,
    String?           customerName,
    List<OrderItem>?  items,
    double?           totalAmount,
    OrderStatus?      status,
    DateTime?         orderDate,
    String?           notes,
  }) {
    return Order(
      id:           id           ?? this.id,
      orderId:      orderId      ?? _orderId,
      customerName: customerName ?? _customerName,
      items:        items        ?? _items,
      totalAmount:  totalAmount  ?? _totalAmount,
      status:       status       ?? this.status,
      orderDate:    orderDate    ?? _orderDate,
      notes:        notes        ?? _notes,
    );
  }

  /// Polymorphism: overrides BaseModel.toMap()
  @override
  Map<String, dynamic> toMap() => {
    'id':           id,
    'orderId':      _orderId,
    'customerName': _customerName,
    'items':        _items.map((i) => i.toMap()).toList(),
    'totalAmount':  _totalAmount,
    'status':       status.displayName,
    'orderDate':    _orderDate.toIso8601String(),
    'notes':        _notes,
  };

  factory Order.fromMap(Map<String, dynamic> map) {
    final List<OrderItem> items;
    if (map['items'] != null) {
      items = (map['items'] as List)
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList();
    } else if (map['productName'] != null) {
      final total = (map['totalAmount'] as num?)?.toDouble() ?? 0;
      final qty   = map['quantity'] as int? ?? 1;
      items = [
        OrderItem(
          id:           '',
          productId:    '',
          productName:  map['productName'] as String? ?? '',
          unitPrice:    qty > 0 ? total / qty : total,
          quantity:     qty,
        )
      ];
    } else {
      items = [];
    }

    return Order(
      id:           map['id']           as String? ?? '',
      orderId:      map['orderId']      as String? ?? '',
      customerName: map['customerName'] as String? ?? '',
      items:        items,
      totalAmount:  (map['totalAmount'] as num?)?.toDouble() ?? 0,
      status:       OrderStatusExtension.fromString(map['status'] as String? ?? 'Pending'),
      orderDate:    map['orderDate'] != null
          ? DateTime.tryParse(map['orderDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      notes:        map['notes'] as String?,
    );
  }
}
