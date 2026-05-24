// ─────────────────────────────────────────────────────────────────────────────
// order_model.dart — Order and OrderItem entities (v6 fields added)
// Purpose : Represents a customer purchase and its individual line items.
// Changes (v6):
//   • Order — added paymentMethod, paymentReference, isReseller,
//             deductionPerItem, discountedTotal, orderType fields
//   • OrderItem — unchanged
// OOP Pillars:
//   • Inheritance  — OrderItem and Order both extend BaseModel
//   • Encapsulation— private fields; public access via getters only
//   • Polymorphism — toMap() overrides BaseModel; OrderStatus uses map dispatch
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'base_model.dart';
import 'payment_method_model.dart';

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
  final double _unitPrice;   // Actual selling price (after any deduction)
  final double? _srpPrice;   // Original catalog SRP — null for legacy rows (fallback to unitPrice)
  final int    _quantity;

  OrderItem({
    required super.id,
    required String productId,
    required String productName,
    required double unitPrice,
    double?         srpPrice,
    required int    quantity,
  })  : _productId   = productId,
        _productName = productName,
        _unitPrice   = unitPrice,
        _srpPrice    = srpPrice,
        _quantity    = quantity;

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get productId   => _productId;
  String get productName => _productName;
  double get unitPrice   => _unitPrice;
  /// Original catalog SRP. Falls back to unitPrice for legacy rows.
  double get srpPrice    => _srpPrice ?? _unitPrice;
  int    get quantity    => _quantity;
  // Computed subtotal — derived from price and quantity, never stored separately
  double get subtotal    => _unitPrice * _quantity;

  // Returns a new OrderItem with an updated quantity (used when editing order items)
  OrderItem copyWith({int? quantity}) => OrderItem(
    id:          id,
    productId:   _productId,
    productName: _productName,
    unitPrice:   _unitPrice,
    srpPrice:    _srpPrice,
    quantity:    quantity ?? _quantity,
  );

  // Serializes to a map for SQLite order_items table or Firestore array element
  @override
  Map<String, dynamic> toMap() => {
    'id':          id,
    'productId':   _productId,
    'productName': _productName,
    'unitPrice':   _unitPrice,
    'srpPrice':    _srpPrice,
    'quantity':    _quantity,
  };

  // Deserializes a map back into an OrderItem (used when reading from DB or Firestore)
  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    id:          map['id']           as String? ?? '',
    productId:   map['productId']    as String? ?? '',
    productName: map['productName']  as String? ?? '',
    unitPrice:   (map['unitPrice']   as num?)?.toDouble() ?? 0,
    srpPrice:    (map['srpPrice']    as num?)?.toDouble(),
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

  // ── v6 new fields ─────────────────────────────────────────────────────────
  final PaymentMethod?  _paymentMethod;    // How the customer paid
  final String?         _paymentReference; // Masked card/wallet number
  final bool            _isReseller;       // true = reseller discount applied
  final double          _deductionPerItem; // Fixed peso minus per item (₱0 for non-reseller orders)
  final double?         _discountedTotal;  // totalAmount × (1 - pct/100); null if no discount
  final String          _orderType;        // 'regular' | 'customized'

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
    // v6 fields — all optional for backward compat with existing rows
    PaymentMethod?           paymentMethod,
    String?                  paymentReference,
    bool                     isReseller      = false,
    double                   deductionPerItem = 0,
    double?                  discountedTotal,
    String                   orderType       = 'regular',
  })  : _orderId          = orderId,
        _customerName     = customerName,
        _items            = items,
        _totalAmount      = totalAmount,
        _orderDate        = orderDate,
        _notes            = notes,
        _paymentMethod    = paymentMethod,
        _paymentReference = paymentReference,
        _isReseller       = isReseller,
        _deductionPerItem = deductionPerItem,
        _discountedTotal  = discountedTotal,
        _orderType        = orderType;

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String          get orderId          => _orderId;
  String          get customerName     => _customerName;
  // Unmodifiable view prevents external code from mutating the items list
  List<OrderItem> get items            => List.unmodifiable(_items);
  double          get totalAmount      => _totalAmount;
  DateTime        get orderDate        => _orderDate;
  String?         get notes            => _notes;

  // v6 getters
  PaymentMethod?  get paymentMethod    => _paymentMethod;
  String?         get paymentReference => _paymentReference;
  bool            get isReseller       => _isReseller;
  double          get deductionPerItem => _deductionPerItem;
  /// The net amount the customer actually pays after discount.
  /// Falls back to totalAmount if no discount was applied.
  double          get discountedTotal  => _discountedTotal ?? _totalAmount;
  String          get orderType        => _orderType;

  // ── Computed properties ───────────────────────────────────────────────────

  // Returns a display-friendly product summary (e.g. "Rose Oud +2 more")
  String get productName {
    if (_items.isEmpty) return '';
    if (_items.length == 1) return _items.first.productName;
    return '${_items.first.productName} +${_items.length - 1} more';
  }

  // Total number of units ordered across all line items
  int get quantity => _items.fold(0, (sum, i) => sum + i.quantity);

  // The discount amount in currency (SRP - net) — reseller order-level discount.
  // NOTE: discountedTotal falls back to totalAmount when null, so for orders where
  // totalAmount IS the net (saved after discount), discountAmount will be 0.
  // Use totalDiscountAmount (item-level) for accurate discount reporting.
  double get discountAmount => _totalAmount - discountedTotal;

  /// Per-item deduction discount: sum of (srpPrice - unitPrice) × qty across all items.
  /// This is the authoritative discount figure because:
  ///   • order_dialog saves totalAmount = net price (already discounted)
  ///   • discountedTotal is null for those orders → discountAmount = 0
  ///   • But srpPrice and unitPrice are always saved correctly
  ///   • So (srpPrice - unitPrice) × qty correctly recovers the deduction
  ///
  /// LEGACY FALLBACK: For orders restored from Firestore before srp_price was
  /// included in the cloud restore, srpPrice falls back to unitPrice making the
  /// per-item deduction = 0. In that case, fall back to deductionPerItem × total qty.
  double get itemDiscountAmount {
    final itemBased = _items.fold(0.0, (sum, item) {
      final deduction = (item.srpPrice - item.unitPrice).clamp(0.0, item.srpPrice);
      return sum + deduction * item.quantity;
    });
    // For legacy orders: srpPrice == unitPrice so itemBased == 0.
    // We do NOT fall back to deductionPerItem because that would produce wrong
    // Discount figures (the discount info is simply not recoverable for old data).
    return itemBased;
  }

  /// Total discount across all items = per-item (srpPrice - unitPrice) × qty.
  /// This is the only reliable discount figure since totalAmount is saved as net.
  double get totalDiscountAmount => itemDiscountAmount;

  /// SRP total = sum of srpPrice × qty per item (true catalog price before discount).
  /// For legacy rows where srp_price was null (cloud-restored without srp_price),
  /// srpPrice falls back to unitPrice. In that case, reconstruct from deductionPerItem.
  double get srpTotal {
    // Use stored srpPrice directly (= _srpPrice ?? _unitPrice).
    // For legacy orders: srpPrice == unitPrice == 220 (the true SRP, no item discount tracked).
    // For new orders: srpPrice=220, unitPrice=170. Both are correct as-is.
    return _items.fold(0.0, (sum, item) => sum + item.srpPrice * item.quantity);
  }

  /// Net amount = totalAmount, which IS the net (after all discounts applied at order time).
  /// totalAmount is always saved as the final amount the customer pays.
  double get netAfterAllDiscounts => customerPayAmount;

  /// The amount the customer actually pays.
  /// For reseller orders: discountedTotal (saved as net). Falls back to totalAmount.
  /// For regular orders: totalAmount (which is already the net selling price).
  double get customerPayAmount => _discountedTotal ?? _totalAmount;

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
    PaymentMethod?    paymentMethod,
    String?           paymentReference,
    bool?             isReseller,
    double?           deductionPerItem,
    double?           discountedTotal,
    String?           orderType,
  }) {
    return Order(
      id:               id              ?? this.id,
      orderId:          orderId         ?? _orderId,
      customerName:     customerName    ?? _customerName,
      items:            items           ?? _items,
      totalAmount:      totalAmount     ?? _totalAmount,
      status:           status          ?? this.status,
      orderDate:        orderDate       ?? _orderDate,
      notes:            notes           ?? _notes,
      paymentMethod:    paymentMethod   ?? _paymentMethod,
      paymentReference: paymentReference ?? _paymentReference,
      isReseller:       isReseller      ?? _isReseller,
      deductionPerItem:  deductionPerItem ?? _deductionPerItem,
      discountedTotal:  discountedTotal ?? _discountedTotal,
      orderType:        orderType       ?? _orderType,
    );
  }

  // Serializes the order to a map (items as a nested list of maps)
  @override
  Map<String, dynamic> toMap() => {
    'id':                id,
    'orderId':           _orderId,
    'customerName':      _customerName,
    'items':             _items.map((i) => i.toMap()).toList(),
    'totalAmount':       _totalAmount,
    'status':            status.displayName,
    'orderDate':         _orderDate.toIso8601String(),
    'notes':             _notes,
    // v6
    'paymentMethod':     _paymentMethod?.storageKey,
    'paymentReference':  _paymentReference,
    'isReseller':        _isReseller ? 1 : 0,
    'deductionPerItem':  _deductionPerItem,
    'discountedTotal':   _discountedTotal,
    'orderType':         _orderType,
  };

  // Deserializes a map back into an Order
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
      id:               map['id']               as String? ?? '',
      orderId:          map['orderId']           as String? ?? '',
      customerName:     map['customerName']      as String? ?? '',
      items:            items,
      totalAmount:      (map['totalAmount']      as num?)?.toDouble() ?? 0,
      status:           OrderStatusExtension.fromString(map['status'] as String? ?? 'Pending'),
      orderDate:        map['orderDate'] != null
          ? DateTime.tryParse(map['orderDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      notes:            map['notes']             as String?,
      // v6 fields — safe defaults for older DB rows
      paymentMethod:    PaymentMethodExtension.fromString(map['paymentMethod'] as String?),
      paymentReference: map['paymentReference']  as String?,
      isReseller:       (map['isReseller']        as int? ?? 0) == 1,
      deductionPerItem:  (map['deductionPerItem']   as num?)?.toDouble() ?? (map['discountPercent'] as num?)?.toDouble() ?? 0,
      discountedTotal:  (map['discountedTotal']   as num?)?.toDouble(),
      orderType:        map['orderType']          as String? ?? 'regular',
    );
  }
}
