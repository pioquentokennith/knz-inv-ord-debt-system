// ─────────────────────────────────────────────────────────────────────────────
// product_model.dart — Product entity
// Purpose : Represents a single fragrance product in the catalog.
//           Enforces business rules (no negative stock/price) through a
//           validated setter and computed properties.
// Demonstrates: Inheritance (extends BaseModel), Encapsulation (private fields
// exposed through getters), validated setter for mutable stockQty.
// ─────────────────────────────────────────────────────────────────────────────

import 'base_model.dart';
import '../core/money.dart';

// Enum listing all fragrance product categories supported by the app
enum ProductCategory {
  eauDeParfum,
  eauDeToilette,
  bodyMist,
  perfumeOil,
  giftSet,
}

// Extension adds display/parse helpers to the ProductCategory enum
extension ProductCategoryExtension on ProductCategory {
  // Full display name shown in UI dropdowns and PDF reports
  String get displayName {
    switch (this) {
      case ProductCategory.eauDeParfum:
        return 'Eau de Parfum';
      case ProductCategory.eauDeToilette:
        return 'Eau de Toilette';
      case ProductCategory.bodyMist:
        return 'Body Mist';
      case ProductCategory.perfumeOil:
        return 'Perfume Oil';
      case ProductCategory.giftSet:
        return 'Gift Set';
    }
  }

  // Short uppercase version used in product badge labels
  String get shortName {
    switch (this) {
      case ProductCategory.eauDeParfum:
        return 'EAU DE PARFUM';
      case ProductCategory.eauDeToilette:
        return 'EAU DE TOILETTE';
      case ProductCategory.bodyMist:
        return 'BODY MIST';
      case ProductCategory.perfumeOil:
        return 'PERFUME OIL';
      case ProductCategory.giftSet:
        return 'GIFT SET';
    }
  }

  // Parses a category from a stored string (case-insensitive); defaults to eauDeParfum
  static ProductCategory fromString(String value) {
    return ProductCategory.values.firstWhere(
      (e) =>
          e.displayName.toLowerCase() == value.toLowerCase() ||
          e.shortName.toLowerCase() == value.toLowerCase(),
      orElse: () =>
          ProductCategory.eauDeParfum, // Safe fallback for unknown strings
    );
  }
}

/// Product — inherits identity and serialization contract from [BaseModel].
/// All fields are private; public access is via getters (Encapsulation).
/// [stockQty] exposes a validated setter since stock changes frequently.
class Product extends BaseModel {
  // ── Private fields (Encapsulation — external code cannot mutate these directly) ──
  final String _name;
  final String _description;
  final ProductCategory _category;
  final Money _price;
  int _stockQty; // Mutable — stock changes after each order
  final int
  _minStockLevel; // Immutable threshold that triggers low-stock alerts
  final String? _imagePath;
  final DateTime _createdAt;

  // super.id uses Dart super-parameter syntax to pass id up to BaseModel
  Product({
    required super.id,
    required String name,
    required String description,
    required ProductCategory category,
    required Money price,
    required int stockQty,
    required int minStockLevel,
    String? imagePath,
    DateTime? createdAt,
  }) : _name = name,
       _description = description,
       _category = category,
       _price = price,
       _stockQty = stockQty,
       _minStockLevel = minStockLevel,
       _imagePath = imagePath,
       _createdAt = createdAt ?? DateTime.now() {
    // Default to now if not provided
    if (this.id.trim().isEmpty) {
      throw ArgumentError.value(this.id, 'id', 'Product id cannot be blank.');
    }
    if (_name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'Product name cannot be blank.');
    }
    if (_price.isNegative) {
      throw ArgumentError.value(
        price,
        'price',
        'Product price must be non-negative.',
      );
    }
    if (_stockQty < 0) {
      throw ArgumentError.value(
        stockQty,
        'stockQty',
        'Stock quantity cannot be negative.',
      );
    }
    if (_minStockLevel < 0) {
      throw ArgumentError.value(
        minStockLevel,
        'minStockLevel',
        'Minimum stock level cannot be negative.',
      );
    }
  }

  // ── Public read-only getters (Encapsulation) ──────────────────────────────
  String get name => _name;
  String get description => _description;
  ProductCategory get category => _category;
  Money get price => _price;
  int get stockQty => _stockQty;
  int get minStockLevel => _minStockLevel;
  String? get imagePath => _imagePath;
  DateTime get createdAt => _createdAt;

  // ── Validated setter — prevents negative stock from being set externally ──
  set stockQty(int value) {
    if (value < 0) throw ArgumentError('Stock quantity cannot be negative.');
    _stockQty = value;
  }

  // ── Computed property — true when stock is at or below the minimum level ──
  // Used by the dashboard to surface low-stock alerts
  bool get isLowStock => _stockQty <= _minStockLevel;

  // Returns a new Product with only the specified fields changed (immutable-style update)
  Product copyWith({
    String? id,
    String? name,
    String? description,
    ProductCategory? category,
    Money? price,
    int? stockQty,
    int? minStockLevel,
    String? imagePath,
    DateTime? createdAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? _name,
      description: description ?? _description,
      category: category ?? _category,
      price: price ?? _price,
      stockQty: stockQty ?? _stockQty,
      minStockLevel: minStockLevel ?? _minStockLevel,
      imagePath: imagePath ?? _imagePath,
      createdAt: createdAt ?? _createdAt,
    );
  }

  // Serializes the product to a map used for SQLite inserts and Firestore writes
  @override
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': _name,
    'description': _description,
    'category':
        _category.displayName, // Store display name string, not enum index
    'price_centavos': _price.centavos,
    'stockQty': _stockQty,
    'minStockLevel': _minStockLevel,
    'imagePath': _imagePath,
    'createdAt': _createdAt.toIso8601String(),
  };

  // Deserializes a map (from SQLite or Firestore) back into a Product instance
  factory Product.fromMap(Map<String, dynamic> map) => Product(
    id: map['id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    description: map['description'] as String? ?? '',
    category: ProductCategoryExtension.fromString(
      map['category'] as String? ?? '',
    ),
    price: Money.fromCentavos(map['priceCentavos'] as int? ?? 0),
    stockQty: map['stockQty'] as int? ?? 0,
    minStockLevel: map['minStockLevel'] as int? ?? 5,
    imagePath: map['imagePath'] as String?,
    createdAt: map['createdAt'] != null
        ? DateTime.tryParse(map['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}
