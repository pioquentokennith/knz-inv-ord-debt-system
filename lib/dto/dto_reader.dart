import '../core/money.dart';

class DtoReader {
  DtoReader(this.data, this.entity);

  final Map<String, dynamic> data;
  final String entity;

  int version(int current) {
    final value = data['schema_version'] ?? data['schemaVersion'] ?? 0;
    final parsed = integerValue(value, 'schema_version');
    if (parsed < 0 || parsed > current) {
      throw FormatException(
        '$entity has unsupported schema version $parsed; current is $current.',
      );
    }
    return parsed;
  }

  String string(List<String> keys, {String? defaultValue}) {
    final value = _value(keys);
    if (value == null && defaultValue != null) return defaultValue;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        '$entity.${keys.first} must be a non-empty string.',
      );
    }
    return value;
  }

  String? optionalString(List<String> keys) {
    final value = _value(keys);
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$entity.${keys.first} must be a string or null.');
    }
    return value;
  }

  int integer(List<String> keys, {int? defaultValue}) {
    final value = _value(keys);
    if (value == null && defaultValue != null) return defaultValue;
    return integerValue(value, keys.first);
  }

  int? optionalInteger(List<String> keys) {
    final value = _value(keys);
    return value == null ? null : integerValue(value, keys.first);
  }

  int centavos(
    List<String> centavoKeys, {
    List<String> legacyMoneyKeys = const [],
    int? defaultValue,
  }) {
    final exact = _value(centavoKeys);
    if (exact != null) return integerValue(exact, centavoKeys.first);
    final legacy = _value(legacyMoneyKeys);
    if (legacy is num && legacy.isFinite) {
      return Money.fromLegacyNumber(legacy).centavos;
    }
    if (defaultValue != null) return defaultValue;
    throw FormatException('$entity.${centavoKeys.first} is required.');
  }

  bool boolean(List<String> keys, {bool defaultValue = false}) {
    final value = _value(keys);
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num && (value == 0 || value == 1)) return value == 1;
    throw FormatException('$entity.${keys.first} must be boolean or 0/1.');
  }

  DateTime date(List<String> keys, {DateTime? defaultValue}) {
    final value = _value(keys);
    if (value == null && defaultValue != null) return defaultValue.toUtc();
    if (value is! String) {
      throw FormatException('$entity.${keys.first} must be an ISO timestamp.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$entity.${keys.first} is not a valid timestamp.');
    }
    return parsed.toUtc();
  }

  DateTime? optionalDate(List<String> keys) {
    final value = _value(keys);
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$entity.${keys.first} must be an ISO timestamp.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$entity.${keys.first} is not a valid timestamp.');
    }
    return parsed.toUtc();
  }

  List<Map<String, dynamic>> maps(List<String> keys) {
    final value = _value(keys);
    if (value == null) return const [];
    if (value is! List) {
      throw FormatException('$entity.${keys.first} must be a list.');
    }
    return value
        .map((item) {
          if (item is! Map) {
            throw FormatException(
              '$entity.${keys.first} contains a non-map value.',
            );
          }
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }

  int integerValue(Object? value, String field) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncate()) {
      return value.toInt();
    }
    throw FormatException('$entity.$field must be an integer.');
  }

  Object? _value(List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key)) return data[key];
    }
    return null;
  }
}
