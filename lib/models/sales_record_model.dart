// ─────────────────────────────────────────────────────────────────────────────
// sales_record_model.dart — Flattened sales record for the Sales Table screen
// Purpose : A read-only view model that joins order_items + orders into one
//           flat row suitable for display in the sales ledger table.
//           Not persisted to its own table — always derived from existing data.
// OOP Pillars:
//   • Encapsulation — private fields, read-only getters
//   • Abstraction   — callers work with SalesRecord; SQL join is hidden in repo
// ─────────────────────────────────────────────────────────────────────────────

import '../core/money.dart';

class SalesRecord {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String _itemId; // order_items.id  (unique per row)
  final String _orderId; // human-readable e.g. "KNZ-042"
  final String _itemName; // product_name (denormalized)
  final Money _srp; // srp_price — original catalog price
  final Money _discountedPrice; // unit_price — actual selling price
  final int _quantity;
  final String _customerName;
  final DateTime _datePurchased;
  final Money _totalSales; // discountedPrice × quantity
  final bool _isReseller;
  final int _discountBasisPoints;

  const SalesRecord({
    required String itemId,
    required String orderId,
    required String itemName,
    required Money srp,
    required Money discountedPrice,
    required int quantity,
    required String customerName,
    required DateTime datePurchased,
    required Money totalSales,
    required bool isReseller,
    required int discountBasisPoints,
  }) : _itemId = itemId,
       _orderId = orderId,
       _itemName = itemName,
       _srp = srp,
       _discountedPrice = discountedPrice,
       _quantity = quantity,
       _customerName = customerName,
       _datePurchased = datePurchased,
       _totalSales = totalSales,
       _isReseller = isReseller,
       _discountBasisPoints = discountBasisPoints;

  // ── Public read-only getters ──────────────────────────────────────────────
  String get itemId => _itemId;
  String get orderId => _orderId;
  String get itemName => _itemName;
  Money get srp => _srp;
  Money get discountedPrice => _discountedPrice;
  int get quantity => _quantity;
  String get customerName => _customerName;
  DateTime get datePurchased => _datePurchased;
  Money get totalSales => _totalSales;
  bool get isReseller => _isReseller;
  int get discountBasisPoints => _discountBasisPoints;
  double get discountPercent => _discountBasisPoints / 100;

  /// Convenience: the raw discount amount for this line (SRP - discounted) × qty
  Money get discountAmount => (_srp - _discountedPrice) * _quantity;

  /// Builds a SalesRecord from a flat SQL JOIN row.
  /// Expects columns from the join of orders + order_items.
  factory SalesRecord.fromJoinMap(Map<String, dynamic> map) {
    final discountedPrice = Money.fromCentavos(
      map['unit_price_centavos'] as int? ?? 0,
    );
    // `discount_percent` is a legacy column name that now stores a fixed peso
    // deduction. Applying it as a percentage double-discounted reseller rows.
    // The line item's SRP/net pair is the authoritative representation.
    final srp = map['srp_price_centavos'] == null
        ? discountedPrice
        : Money.fromCentavos(map['srp_price_centavos'] as int);
    final discountBasisPoints = srp.isPositive && discountedPrice < srp
        ? roundRatioHalfUp(
            (srp - discountedPrice).centavos * 10000,
            srp.centavos,
          )
        : 0;
    final qty = map['quantity'] as int? ?? 1;

    return SalesRecord(
      itemId: map['item_id'] as String? ?? '',
      orderId: map['order_id_hr'] as String? ?? '', // human-readable
      itemName: map['product_name'] as String? ?? '',
      srp: srp,
      discountedPrice: discountedPrice,
      quantity: qty,
      customerName: map['customer_name'] as String? ?? '',
      datePurchased: map['order_date'] != null
          ? DateTime.tryParse(map['order_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      totalSales: discountedPrice * qty,
      isReseller: (map['is_reseller'] as int? ?? 0) == 1,
      discountBasisPoints: discountBasisPoints,
    );
  }
}
