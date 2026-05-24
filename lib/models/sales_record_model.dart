// ─────────────────────────────────────────────────────────────────────────────
// sales_record_model.dart — Flattened sales record for the Sales Table screen
// Purpose : A read-only view model that joins order_items + orders into one
//           flat row suitable for display in the sales ledger table.
//           Not persisted to its own table — always derived from existing data.
// OOP Pillars:
//   • Encapsulation — private fields, read-only getters
//   • Abstraction   — callers work with SalesRecord; SQL join is hidden in repo
// ─────────────────────────────────────────────────────────────────────────────

class SalesRecord {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String   _itemId;           // order_items.id  (unique per row)
  final String   _orderId;          // human-readable e.g. "KNZ-042"
  final String   _itemName;         // product_name (denormalized)
  final double   _srp;              // unit_price — original price before discount
  final double   _discountedPrice;  // srp × (1 - discountPercent/100)
  final int      _quantity;
  final String   _customerName;
  final DateTime _datePurchased;
  final double   _totalSales;       // discountedPrice × quantity
  final bool     _isReseller;
  final double   _discountPercent;

  const SalesRecord({
    required String   itemId,
    required String   orderId,
    required String   itemName,
    required double   srp,
    required double   discountedPrice,
    required int      quantity,
    required String   customerName,
    required DateTime datePurchased,
    required double   totalSales,
    required bool     isReseller,
    required double   discountPercent,
  })  : _itemId          = itemId,
        _orderId         = orderId,
        _itemName        = itemName,
        _srp             = srp,
        _discountedPrice = discountedPrice,
        _quantity        = quantity,
        _customerName    = customerName,
        _datePurchased   = datePurchased,
        _totalSales      = totalSales,
        _isReseller      = isReseller,
        _discountPercent = discountPercent;

  // ── Public read-only getters ──────────────────────────────────────────────
  String   get itemId          => _itemId;
  String   get orderId         => _orderId;
  String   get itemName        => _itemName;
  double   get srp             => _srp;
  double   get discountedPrice => _discountedPrice;
  int      get quantity        => _quantity;
  String   get customerName    => _customerName;
  DateTime get datePurchased   => _datePurchased;
  double   get totalSales      => _totalSales;
  bool     get isReseller      => _isReseller;
  double   get discountPercent => _discountPercent;

  /// Convenience: the raw discount amount for this line (SRP - discounted) × qty
  double get discountAmount => (_srp - _discountedPrice) * _quantity;

  /// Builds a SalesRecord from a flat SQL JOIN row.
  /// Expects columns from the join of orders + order_items.
  factory SalesRecord.fromJoinMap(Map<String, dynamic> map) {
    final srp             = (map['unit_price']       as num?)?.toDouble() ?? 0;
    final discountPercent = (map['discount_percent'] as num?)?.toDouble() ?? 0;
    final discountedPrice = srp * (1 - discountPercent / 100);
    final qty             = map['quantity']           as int?    ?? 1;

    return SalesRecord(
      itemId:          map['item_id']       as String? ?? '',
      orderId:         map['order_id_hr']   as String? ?? '', // human-readable
      itemName:        map['product_name']  as String? ?? '',
      srp:             srp,
      discountedPrice: discountedPrice,
      quantity:        qty,
      customerName:    map['customer_name'] as String? ?? '',
      datePurchased:   map['order_date'] != null
          ? DateTime.tryParse(map['order_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      totalSales:      discountedPrice * qty,
      isReseller:      (map['is_reseller']    as int? ?? 0) == 1,
      discountPercent: discountPercent,
    );
  }
}
