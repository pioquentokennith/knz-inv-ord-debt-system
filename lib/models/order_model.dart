// ─────────────────────────────────────────────────────────────────────────────
// order_model.dart — Order and OrderItem entities
// Purpose : Represents a customer purchase and its individual line items.
//           OrderStatus uses map-based dispatch instead of switch statements
//           for a cleaner, extensible polymorphic design.
// OOP Pillars:
//   • Inheritance  — OrderItem and Order both extend BaseModel
//   • Encapsulation— private fields; public access via getters only
//   • Polymorphism — toMap() overrides BaseModel; OrderStatus extension uses
//                    map-based dispatch instead of switch blocks
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'base_model.dart';

// All possible lifecycle states for an order
enum OrderStatus {
  pending,    // Newly created, not yet processed
  processing, // Being prepared / packed
  shipped,    // Dispatched to the customer
  delivered,  // Received by the customer (counts as collected revenue)
  cancelled,  // Voided — excluded from revenue calculations
  utang,      // Customer owes payment (debt recorded separately)
}

// Extension adds display name, color, and parse helper to OrderStatus
extension OrderStatusExtension on OrderStatus {
  // ── Map-based dispatch — replaces repetitive switch blocks (Polymorphism) ──
  // Centralizing these in a map makes adding a new status a one-line change
  static const _displayNames = {
    OrderStatus.pending:    'Pending',
    OrderStatus.processing: 'Processing',
    OrderStatus.shipped:    'Shipped',
    OrderStatus.delivered:  'Delivered',
    OrderStatus.cancelled:  'Cancelled',
    OrderStatus.utang:      'Utang',
  };

  // Semantic UI colors for status badges — one place to change all badge colors
  static const _colors = {
    OrderStatus.pending:    Color(0xFFFFA726), // Orange — waiting
    OrderStatus.processing: Color(0xFF29B6F6), // Blue — in progress
    OrderStatus.shipped:    Color(0xFFAB47BC), // Purple — on the way
    OrderStatus.delivered:  Color(0xFF43A047), // Green — completed
    OrderStatus.cancelled:  Color(0xFFE53935), // Red — voided
    OrderStatus.utang:      Color(0xFFD4AF37), // Gold — credit/debt
  };

  /// User-friendly display name for this status (no switch needed)
  String get displayName => _displayNames[this] ?? name;

  /// Color used in status badges across the UI
  Color get color => _colors[this] ?? const Color(0xFF888888);

  // Parses a stored status string back to the enum; defaults to pending on unknown
  static OrderStatus fromString(String value) {
    return OrderStatus.values.firstWhere(
      (e) => e.displayName.toLowerCase() == value.toLowerCase(),
      orElse: () => OrderStatus.pending,
    );
  }
}

/// A single line item inside an order (one row per product per order).
class OrderItem extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _productId;
  final String _productName; // Denormalized — preserves the name even if product is later edited
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

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get productId   => _productId;
  String get productName => _productName;
  double get unitPrice   => _unitPrice;
  int    get quantity    => _quantity;
  // Computed subtotal — derived from price and quantity, never stored separately
  double get subtotal    => _unitPrice * _quantity;

  // Returns a new OrderItem with an updated quantity (used when editing order items)
  OrderItem copyWith({int? quantity}) => OrderItem(
    id:          id,
    productId:   _productId,
    productName: _productName,
    unitPrice:   _unitPrice,
    quantity:    quantity ?? _quantity,
  );

  // Serializes to a map for SQLite order_items table or Firestore array element
  @override
  Map<String, dynamic> toMap() => {
    'id':          id,
    'productId':   _productId,
    'productName': _productName,
    'unitPrice':   _unitPrice,
    'quantity':    _quantity,
  };

  // Deserializes a map back into an OrderItem (used when reading from DB or Firestore)
  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    id:          map['id']           as String? ?? '',
    productId:   map['productId']    as String? ?? '',
    productName: map['productName']  as String? ?? '',
    unitPrice:   (map['unitPrice']   as num?)?.toDouble() ?? 0,
    quantity:    map['quantity']     as int?    ?? 1,
  );
}

/// Order entity — the parent record that groups OrderItems under one customer purchase.
class Order extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String          _orderId;       // Human-readable ID e.g. "KNZ-042"
  final String          _customerName;
  final List<OrderItem> _items;
  final double          _totalAmount;
  final DateTime        _orderDate;
  final String?         _notes;

  /// [status] is intentionally mutable — orders change state over their lifecycle
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

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String          get orderId      => _orderId;
  String          get customerName => _customerName;
  // Unmodifiable view prevents external code from mutating the items list
  List<OrderItem> get items        => List.unmodifiable(_items);
  double          get totalAmount  => _totalAmount;
  DateTime        get orderDate    => _orderDate;
  String?         get notes        => _notes;

  // ── Computed properties ───────────────────────────────────────────────────

  // Returns a display-friendly product summary (e.g. "Rose Oud +2 more")
  String get productName {
    if (_items.isEmpty) return '';
    if (_items.length == 1) return _items.first.productName;
    return '${_items.first.productName} +${_items.length - 1} more';
  }

  // Total number of units ordered across all line items
  int get quantity => _items.fold(0, (sum, i) => sum + i.quantity);

  // Returns a new Order with only the specified fields changed
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

  // Serializes the order to a map (items as a nested list of maps)
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

  // Deserializes a map back into an Order, handling both new (items list) and
  // legacy (single productName) formats for backward compatibility
  factory Order.fromMap(Map<String, dynamic> map) {
    final List<OrderItem> items;
    if (map['items'] != null) {
      // New format — items stored as an array
      items = (map['items'] as List)
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList();
    } else if (map['productName'] != null) {
      // Legacy format — single product stored as flat fields
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
      items = []; // No item data available
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
