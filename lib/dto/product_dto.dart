import '../core/money.dart';
import '../models/product_model.dart';
import 'dto_reader.dart';

class ProductDto {
  static const currentVersion = 1;

  ProductDto({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.priceCentavos,
    required this.stockQty,
    required this.minStockLevel,
    required this.imagePath,
    required this.createdAt,
    required this.userId,
    required this.isDeleted,
    required this.deletedAt,
  }) {
    if (priceCentavos < 0 || stockQty < 0 || minStockLevel < 0) {
      throw const FormatException('Product numeric fields cannot be negative.');
    }
    final categories = ProductCategory.values
        .map((value) => value.displayName)
        .toSet();
    if (!categories.contains(category)) {
      throw FormatException('Product category is invalid: $category');
    }
  }

  final String id;
  final String name;
  final String description;
  final String category;
  final int priceCentavos;
  final int stockQty;
  final int minStockLevel;
  final String? imagePath;
  final DateTime createdAt;
  final String userId;
  final bool isDeleted;
  final DateTime? deletedAt;

  factory ProductDto.fromDomain(
    Product product, {
    required String userId,
    bool isDeleted = false,
    DateTime? deletedAt,
  }) => ProductDto(
    id: product.id,
    name: product.name,
    description: product.description,
    category: product.category.displayName,
    priceCentavos: product.price.centavos,
    stockQty: product.stockQty,
    minStockLevel: product.minStockLevel,
    imagePath: product.imagePath,
    createdAt: product.createdAt.toUtc(),
    userId: userId,
    isDeleted: isDeleted,
    deletedAt: deletedAt?.toUtc(),
  );

  factory ProductDto.fromLocal(Map<String, dynamic> map) => _fromMap(map);

  factory ProductDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static ProductDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
  }) {
    final r = DtoReader(map, 'Product');
    r.version(currentVersion);
    final rawCategory = r.string(const ['category']);
    final category = rawCategory.toLowerCase() == 'perfume'
        ? ProductCategory.eauDeParfum.displayName
        : rawCategory;
    return ProductDto(
      id: r.string(const ['id']),
      name: r.string(const ['name']),
      description: r.optionalString(const ['description']) ?? '',
      category: category,
      priceCentavos: r.centavos(
        const ['price_centavos', 'priceCentavos'],
        legacyMoneyKeys: const ['price'],
      ),
      stockQty: r.integer(const ['stock_qty', 'stockQty'], defaultValue: 0),
      minStockLevel: r.integer(const [
        'min_stock_level',
        'minStockLevel',
      ], defaultValue: 5),
      imagePath: r.optionalString(const ['image_path', 'imagePath']),
      createdAt: r.date(const ['created_at', 'createdAt']),
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
      isDeleted: r.boolean(const ['is_deleted', 'isDeleted']),
      deletedAt: r.optionalDate(const ['deleted_at', 'deletedAt']),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category,
    'price_centavos': priceCentavos,
    'stock_qty': stockQty,
    'min_stock_level': minStockLevel,
    'image_path': imagePath,
    'created_at': createdAt.toIso8601String(),
    'user_id': userId,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  Product toDomain() => Product(
    id: id,
    name: name,
    description: description,
    category: ProductCategoryExtension.fromString(category),
    price: Money.fromCentavos(priceCentavos),
    stockQty: stockQty,
    minStockLevel: minStockLevel,
    imagePath: imagePath,
    createdAt: createdAt,
  );
}
