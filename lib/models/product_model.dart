// ─────────────────────────────────────────────────────────────────────────────
// product_model.dart — Product entity
// Demonstrates: Inheritance (extends BaseModel), Encapsulation (private fields
// exposed through getters), Setter with validation for mutable stockQty.
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';

enum ProductCategory {
  eauDeParfum,
  eauDeToilette,
  bodyMist,
  perfumeOil,
  giftSet,
}

extension ProductCategoryExtension on ProductCategory {
  String get displayName {
    switch (this) {
      case ProductCategory.eauDeParfum:   return 'Eau de Parfum';
      case ProductCategory.eauDeToilette: return 'Eau de Toilette';
      case ProductCategory.bodyMist:      return 'Body Mist';
      case ProductCategory.perfumeOil:    return 'Perfume Oil';
      case ProductCategory.giftSet:       return 'Gift Set';
    }
  }

  String get shortName {
    switch (this) {
      case ProductCategory.eauDeParfum:   return 'EAU DE PARFUM';
      case ProductCategory.eauDeToilette: return 'EAU DE TOILETTE';
      case ProductCategory.bodyMist:      return 'BODY MIST';
      case ProductCategory.perfumeOil:    return 'PERFUME OIL';
      case ProductCategory.giftSet:       return 'GIFT SET';
    }
  }

  static ProductCategory fromString(String value) {
    return ProductCategory.values.firstWhere(
      (e) =>
          e.displayName.toLowerCase() == value.toLowerCase() ||
          e.shortName.toLowerCase() == value.toLowerCase(),
      orElse: () => ProductCategory.eauDeParfum,
    );
  }
}

/// Product — inherits identity & serialization contract from [BaseModel].
/// All fields are private; public access is via getters (Encapsulation).
/// [stockQty] exposes a validated setter since stock changes frequently.
class Product extends BaseModel {
  // ── Private fields (Encapsulation) ────────────────────────────────────────
  final String          _name;
  final String          _description;
  final ProductCategory _category;
  final double          _price;
  int                   _stockQty;
  final int             _minStockLevel;
  final String?         _imagePath;
  final DateTime        _createdAt;

  // super.id — Dart super-parameter syntax (fixes use_super_parameters lint)
  Product({
    required super.id,
    required String          name,
    required String          description,
    required ProductCategory category,
    required double          price,
    required int             stockQty,
    required int             minStockLevel,
    String?                  imagePath,
    DateTime?                createdAt,
  })  : _name          = name,
        _description   = description,
        _category      = category,
        _price         = price,
        _stockQty      = stockQty,
        _minStockLevel = minStockLevel,
        _imagePath     = imagePath,
        _createdAt     = createdAt ?? DateTime.now();

  // ── Getters (Encapsulation) ───────────────────────────────────────────────
  String          get name          => _name;
  String          get description   => _description;
  ProductCategory get category      => _category;
  double          get price         => _price;
  int             get stockQty      => _stockQty;
  int             get minStockLevel => _minStockLevel;
  String?         get imagePath     => _imagePath;
  DateTime        get createdAt     => _createdAt;

  // ── Validated setter (Encapsulation) ─────────────────────────────────────
  set stockQty(int value) {
    if (value < 0) throw ArgumentError('Stock quantity cannot be negative.');
    _stockQty = value;
  }

  // ── Computed getters ──────────────────────────────────────────────────────
  bool get isLowStock => _stockQty <= _minStockLevel;

  Product copyWith({
    String?          id,
    String?          name,
    String?          description,
    ProductCategory? category,
    double?          price,
    int?             stockQty,
    int?             minStockLevel,
    String?          imagePath,
    DateTime?        createdAt,
  }) {
    return Product(
      id:            id            ?? this.id,
      name:          name          ?? _name,
      description:   description   ?? _description,
      category:      category      ?? _category,
      price:         price         ?? _price,
      stockQty:      stockQty      ?? _stockQty,
      minStockLevel: minStockLevel ?? _minStockLevel,
      imagePath:     imagePath     ?? _imagePath,
      createdAt:     createdAt     ?? _createdAt,
    );
  }

  @override
  Map<String, dynamic> toMap() => {
    'id':            id,
    'name':          _name,
    'description':   _description,
    'category':      _category.displayName,
    'price':         _price,
    'stockQty':      _stockQty,
    'minStockLevel': _minStockLevel,
    'imagePath':     _imagePath,
    'createdAt':     _createdAt.toIso8601String(),
  };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
    id:            map['id']            as String? ?? '',
    name:          map['name']          as String? ?? '',
    description:   map['description']   as String? ?? '',
    category:      ProductCategoryExtension.fromString(map['category'] as String? ?? ''),
    price:         (map['price']        as num?)?.toDouble() ?? 0,
    stockQty:      map['stockQty']      as int?    ?? 0,
    minStockLevel: map['minStockLevel'] as int?    ?? 5,
    imagePath:     map['imagePath']     as String?,
    createdAt:     map['createdAt'] != null
        ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
