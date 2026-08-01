import '../core/money.dart';
import '../models/reseller_model.dart';
import 'dto_reader.dart';

class ResellerDto {
  static const currentVersion = 1;

  ResellerDto({
    required this.id,
    required this.name,
    required this.contact,
    required this.deductionPerItemCentavos,
    required this.userId,
    required this.createdAt,
    required this.isDeleted,
    required this.deletedAt,
  }) {
    if (deductionPerItemCentavos < 0) {
      throw const FormatException('Reseller deduction cannot be negative.');
    }
  }

  final String id;
  final String name;
  final String? contact;
  final int deductionPerItemCentavos;
  final String userId;
  final DateTime createdAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  factory ResellerDto.fromDomain(
    Reseller reseller, {
    bool isDeleted = false,
    DateTime? deletedAt,
  }) => ResellerDto(
    id: reseller.id,
    name: reseller.name,
    contact: reseller.contact,
    deductionPerItemCentavos: reseller.deductionPerItem.centavos,
    userId: reseller.userId,
    createdAt: reseller.createdAt.toUtc(),
    isDeleted: isDeleted,
    deletedAt: deletedAt?.toUtc(),
  );

  factory ResellerDto.fromLocal(Map<String, dynamic> map) => _fromMap(map);

  factory ResellerDto.fromCloud(
    Map<String, dynamic> map, {
    required String userId,
  }) => _fromMap(map, ownerOverride: userId);

  static ResellerDto _fromMap(
    Map<String, dynamic> map, {
    String? ownerOverride,
  }) {
    final r = DtoReader(map, 'Reseller');
    r.version(currentVersion);
    return ResellerDto(
      id: r.string(const ['id']),
      name: r.string(const ['name']),
      contact: r.optionalString(const ['contact']),
      deductionPerItemCentavos: r.centavos(
        const ['deduction_per_item_centavos', 'deductionPerItemCentavos'],
        legacyMoneyKeys: const ['discount_percent'],
        defaultValue: 0,
      ),
      userId: ownerOverride ?? r.string(const ['user_id', 'userId']),
      createdAt: r.date(const ['created_at', 'createdAt']),
      isDeleted: r.boolean(const ['is_deleted', 'isDeleted']),
      deletedAt: r.optionalDate(const ['deleted_at', 'deletedAt']),
    );
  }

  Map<String, dynamic> toLocal() => {
    'id': id,
    'name': name,
    'contact': contact,
    'deduction_per_item_centavos': deductionPerItemCentavos,
    'user_id': userId,
    'created_at': createdAt.toIso8601String(),
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
    'schema_version': currentVersion,
  };

  Map<String, dynamic> toCloud() => toLocal();

  Reseller toDomain() => Reseller(
    id: id,
    name: name,
    contact: contact,
    deductionPerItem: Money.fromCentavos(deductionPerItemCentavos),
    userId: userId,
    createdAt: createdAt,
  );
}
