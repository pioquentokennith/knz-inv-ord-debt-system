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
import '../core/money.dart';
import 'base_model.dart';
import 'payment_method_model.dart';

// All possible lifecycle states for an order
enum OrderStatus {
  pending, // Newly created, not yet processed
  processing, // Being prepared / packed
  shipped, // Dispatched to the customer
  delivered, // Received by the customer (counts as collected revenue)
  cancelled, // Voided — excluded from revenue calculations
  utang, // Customer owes payment (debt recorded separately)
}

// Extension adds display name, color, and parse helper to OrderStatus
extension OrderStatusExtension on OrderStatus {
  // ── Map-based dispatch — replaces repetitive switch blocks (Polymorphism) ──
  static const _displayNames = {
    OrderStatus.pending: 'Pending',
    OrderStatus.processing: 'Processing',
    OrderStatus.shipped: 'Shipped',
    OrderStatus.delivered: 'Delivered',
    OrderStatus.cancelled: 'Cancelled',
    OrderStatus.utang: 'Utang',
  };

  // Semantic UI colors for status badges — one place to change all badge colors
  static const _colors = {
    OrderStatus.pending: Color(0xFFFFA726), // Orange — waiting
    OrderStatus.processing: Color(0xFF29B6F6), // Blue — in progress
    OrderStatus.shipped: Color(0xFFAB47BC), // Purple — on the way
    OrderStatus.delivered: Color(0xFF43A047), // Green — completed
    OrderStatus.cancelled: Color(0xFFE53935), // Red — voided
    OrderStatus.utang: Color(0xFFD4AF37), // Gold — credit/debt
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
  final String
  _productName; // Denormalized — preserves the name even if product is later edited
  final Money _unitPrice; // Actual selling price (after any deduction)
  final Money?
  _srpPrice; // Original catalog SRP — null for legacy rows (fallback to unitPrice)
  final int _quantity;

  OrderItem({
    required super.id,
    required String productId,
    required String productName,
    required Money unitPrice,
    Money? srpPrice,
    required int quantity,
  }) : _productId = productId,
       _productName = productName,
       _unitPrice = unitPrice,
       _srpPrice = srpPrice,
       _quantity = quantity {
    final storedSrp = _srpPrice;
    // Empty item/product IDs remain accepted for the documented legacy flat
    // order format. New writes assign an item id and validate productId in the
    // repository transaction.
    if (_productName.trim().isEmpty) {
      throw ArgumentError.value(
        productName,
        'productName',
        'Product name cannot be blank.',
      );
    }
    if (_unitPrice.isNegative) {
      throw ArgumentError.value(
        unitPrice,
        'unitPrice',
        'Unit price must be non-negative.',
      );
    }
    if (storedSrp != null && storedSrp.isNegative) {
      throw ArgumentError.value(
        srpPrice,
        'srpPrice',
        'SRP must be non-negative.',
      );
    }
    if (_quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Order item quantity must be positive.',
      );
    }
  }

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get productId => _productId;
  String get productName => _productName;
  Money get unitPrice => _unitPrice;

  /// Original catalog SRP. Falls back to unitPrice for legacy rows.
  Money get srpPrice => _srpPrice ?? _unitPrice;
  int get quantity => _quantity;
  // Computed subtotal — derived from price and quantity, never stored separately
  Money get subtotal => _unitPrice * _quantity;

  // Serializes to a map for SQLite order_items table or Firestore array element
  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'productId': _productId,
    'productName': _productName,
    'unitPriceCentavos': _unitPrice.centavos,
    'srpPriceCentavos': _srpPrice?.centavos,
    'quantity': _quantity,
  };

  // Deserializes a map back into an OrderItem (used when reading from DB or Firestore)
  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
    id: map['id'] as String? ?? '',
    productId: map['productId'] as String? ?? '',
    productName: map['productName'] as String? ?? '',
    unitPrice: Money.fromCentavos(map['unitPriceCentavos'] as int? ?? 0),
    srpPrice: map['srpPriceCentavos'] == null
        ? null
        : Money.fromCentavos(map['srpPriceCentavos'] as int),
    quantity: map['quantity'] as int? ?? 1,
  );
}

/// Order entity — the parent record that groups OrderItems under one customer purchase.
class Order extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _orderId; // Human-readable ID e.g. "KNZ-042"
  final String _customerName;
  final List<OrderItem> _items;
  final Money _totalAmount;
  final Money? _storedSrpTotal;
  final DateTime _orderDate;
  final String? _notes;
  final String? _commandId;

  // ── v6 new fields ─────────────────────────────────────────────────────────
  final PaymentMethod? _paymentMethod; // How the customer paid
  final String? _paymentReference; // Masked card/wallet number
  final bool _isReseller; // true = reseller discount applied
  final Money
  _deductionPerItem; // Fixed peso minus per item (₱0 for non-reseller orders)
  final Money?
  _discountedTotal; // totalAmount × (1 - pct/100); null if no discount
  final String _orderType; // 'regular' | 'customized'

  /// [status] is intentionally mutable — orders change state over their lifecycle
  OrderStatus status;

  Order({
    required super.id,
    required String orderId,
    required String customerName,
    required List<OrderItem> items,
    required Money totalAmount,
    Money? srpTotal,
    required this.status,
    required DateTime orderDate,
    String? notes,
    // v6 fields — all optional for backward compat with existing rows
    PaymentMethod? paymentMethod,
    String? paymentReference,
    bool isReseller = false,
    Money deductionPerItem = Money.zero,
    Money? discountedTotal,
    String orderType = 'regular',
    String? commandId,
  }) : _orderId = orderId,
       _customerName = customerName,
       _items = List<OrderItem>.unmodifiable(items),
       _totalAmount = totalAmount,
       _storedSrpTotal = srpTotal,
       _orderDate = orderDate,
       _notes = notes,
       _commandId = commandId,
       _paymentMethod = paymentMethod,
       _paymentReference = paymentReference,
       _isReseller = isReseller,
       _deductionPerItem = deductionPerItem,
       _discountedTotal = discountedTotal,
       _orderType = orderType {
    final storedDiscountedTotal = _discountedTotal;
    if (this.id.trim().isEmpty) {
      throw ArgumentError.value(this.id, 'id', 'Order id cannot be blank.');
    }
    if (_orderId.trim().isEmpty) {
      throw ArgumentError.value(
        orderId,
        'orderId',
        'Human-readable order id cannot be blank.',
      );
    }
    if (_customerName.trim().isEmpty) {
      throw ArgumentError.value(
        customerName,
        'customerName',
        'Customer name cannot be blank.',
      );
    }
    if (_totalAmount.isNegative) {
      throw ArgumentError.value(
        totalAmount,
        'totalAmount',
        'Order total must be non-negative.',
      );
    }
    if (_deductionPerItem.isNegative) {
      throw ArgumentError.value(
        deductionPerItem,
        'deductionPerItem',
        'Deduction must be non-negative.',
      );
    }
    if (storedDiscountedTotal != null && storedDiscountedTotal.isNegative) {
      throw ArgumentError.value(
        discountedTotal,
        'discountedTotal',
        'Discounted total must be non-negative.',
      );
    }
    if (_orderType.trim().isEmpty) {
      throw ArgumentError.value(
        orderType,
        'orderType',
        'Order type cannot be blank.',
      );
    }
    if (_commandId != null && _commandId.trim().isEmpty) {
      throw ArgumentError.value(
        commandId,
        'commandId',
        'Order command id cannot be blank.',
      );
    }
  }

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get orderId => _orderId;
  String get customerName => _customerName;
  // Unmodifiable view prevents external code from mutating the items list
  List<OrderItem> get items => List.unmodifiable(_items);
  Money get totalAmount => _totalAmount;
  DateTime get orderDate => _orderDate;
  String? get notes => _notes;
  String? get commandId => _commandId;

  // v6 getters
  PaymentMethod? get paymentMethod => _paymentMethod;
  String? get paymentReference => _paymentReference;
  bool get isReseller => _isReseller;
  Money get deductionPerItem => _deductionPerItem;

  Money? get storedDiscountedTotal => _discountedTotal;
  String get orderType => _orderType;

  // ── Computed properties ───────────────────────────────────────────────────

  // Returns a display-friendly product summary (e.g. "Rose Oud +2 more")
  String get productName {
    if (_items.isEmpty) return '';
    if (_items.length == 1) return _items.first.productName;
    return '${_items.first.productName} +${_items.length - 1} more';
  }

  // Total number of units ordered across all line items
  int get quantity => _items.fold(0, (sum, i) => sum + i.quantity);

  /// Canonical gross total represented by the persisted line items.
  Money get lineSrpTotal => _items.fold(
    Money.zero,
    (sum, item) => sum + item.srpPrice * item.quantity,
  );

  /// Canonical amount payable represented by the persisted line items.
  Money get lineCustomerPayTotal =>
      _items.fold(Money.zero, (sum, item) => sum + item.subtotal);

  /// Per-item deduction discount: sum of (srpPrice - unitPrice) × qty across all items.
  /// This is the authoritative discount figure because:
  ///   • order_dialog saves totalAmount = net price (already discounted)
  ///   • srpPrice and unitPrice are saved separately
  ///   • (srpPrice - unitPrice) × qty recovers the deduction
  ///
  /// LEGACY FALLBACK: For orders restored from Firestore before srp_price was
  /// included in the cloud restore, srpPrice falls back to unitPrice making the
  /// per-item deduction = 0. In that case, fall back to deductionPerItem × total qty.
  Money get itemDiscountAmount {
    final itemBased = _items.fold(Money.zero, (sum, item) {
      final deduction = (item.srpPrice - item.unitPrice)
          .max(Money.zero)
          .min(item.srpPrice);
      return sum + deduction * item.quantity;
    });
    // For legacy orders: srpPrice == unitPrice so itemBased == 0.
    // We do NOT fall back to deductionPerItem because that would produce wrong
    // Discount figures (the discount info is simply not recoverable for old data).
    return itemBased;
  }

  /// Total discount across all items = per-item (srpPrice - unitPrice) × qty.
  /// This is the only reliable discount figure since totalAmount is saved as net.
  Money get totalDiscountAmount => itemDiscountAmount;

  /// SRP total = sum of srpPrice × qty per item (true catalog price before discount).
  /// For legacy rows where srp_price was null (cloud-restored without srp_price),
  /// srpPrice falls back to unitPrice. In that case, reconstruct from deductionPerItem.
  Money get srpTotal {
    // Use stored srpPrice directly (= _srpPrice ?? _unitPrice).
    // For legacy orders: srpPrice == unitPrice == 220 (the true SRP, no item discount tracked).
    // For new orders: srpPrice=220, unitPrice=170. Both are correct as-is.
    return _storedSrpTotal ?? lineSrpTotal;
  }

  /// The amount the customer actually pays.
  /// For reseller orders: discountedTotal (saved as net). Falls back to totalAmount.
  /// For regular orders: totalAmount (which is already the net selling price).
  Money get customerPayAmount => _discountedTotal ?? _totalAmount;

  // Returns a new Order with only the specified fields changed
  Order copyWith({
    String? id,
    String? orderId,
    String? customerName,
    List<OrderItem>? items,
    Money? totalAmount,
    Money? srpTotal,
    OrderStatus? status,
    DateTime? orderDate,
    String? notes,
    PaymentMethod? paymentMethod,
    String? paymentReference,
    bool? isReseller,
    Money? deductionPerItem,
    Money? discountedTotal,
    String? orderType,
    String? commandId,
  }) {
    return Order(
      id: id ?? this.id,
      orderId: orderId ?? _orderId,
      customerName: customerName ?? _customerName,
      items: items ?? _items,
      totalAmount: totalAmount ?? _totalAmount,
      srpTotal: srpTotal ?? _storedSrpTotal,
      status: status ?? this.status,
      orderDate: orderDate ?? _orderDate,
      notes: notes ?? _notes,
      paymentMethod: paymentMethod ?? _paymentMethod,
      paymentReference: paymentReference ?? _paymentReference,
      isReseller: isReseller ?? _isReseller,
      deductionPerItem: deductionPerItem ?? _deductionPerItem,
      discountedTotal: discountedTotal ?? _discountedTotal,
      orderType: orderType ?? _orderType,
      commandId: commandId ?? _commandId,
    );
  }

  // Serializes the order to a map (items as a nested list of maps)
  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'orderId': _orderId,
    'customerName': _customerName,
    'items': _items.map((i) => i.toMap()).toList(),
    'totalAmountCentavos': _totalAmount.centavos,
    'srpTotalCentavos': srpTotal.centavos,
    'status': status.displayName,
    'orderDate': _orderDate.toIso8601String(),
    'notes': _notes,
    // v6
    'paymentMethod': _paymentMethod?.storageKey,
    'paymentReference': _paymentReference,
    'isReseller': _isReseller ? 1 : 0,
    'deductionPerItemCentavos': _deductionPerItem.centavos,
    'discountedTotalCentavos': _discountedTotal?.centavos,
    'orderType': _orderType,
    'commandId': _commandId,
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
      final total = Money.fromCentavos(map['totalAmountCentavos'] as int? ?? 0);
      final qty = map['quantity'] as int? ?? 1;
      items = [
        OrderItem(
          id: '',
          productId: '',
          productName: map['productName'] as String? ?? '',
          unitPrice: qty > 0 ? total.divide(qty) : total,
          quantity: qty,
        ),
      ];
    } else {
      items = []; // No item data available
    }

    return Order(
      id: map['id'] as String? ?? '',
      orderId: map['orderId'] as String? ?? '',
      customerName: map['customerName'] as String? ?? '',
      items: items,
      totalAmount: Money.fromCentavos(map['totalAmountCentavos'] as int? ?? 0),
      srpTotal: map['srpTotalCentavos'] == null
          ? null
          : Money.fromCentavos(map['srpTotalCentavos'] as int),
      status: OrderStatusExtension.fromString(
        map['status'] as String? ?? 'Pending',
      ),
      orderDate: map['orderDate'] != null
          ? DateTime.tryParse(map['orderDate'] as String) ?? DateTime.now()
          : DateTime.now(),
      notes: map['notes'] as String?,
      // v6 fields — safe defaults for older DB rows
      paymentMethod: PaymentMethodExtension.fromString(
        map['paymentMethod'] as String?,
      ),
      paymentReference: map['paymentReference'] as String?,
      isReseller: (map['isReseller'] as int? ?? 0) == 1,
      deductionPerItem: Money.fromCentavos(
        map['deductionPerItemCentavos'] as int? ?? 0,
      ),
      discountedTotal: map['discountedTotalCentavos'] == null
          ? null
          : Money.fromCentavos(map['discountedTotalCentavos'] as int),
      orderType: map['orderType'] as String? ?? 'regular',
      commandId: map['commandId'] as String?,
    );
  }
}
