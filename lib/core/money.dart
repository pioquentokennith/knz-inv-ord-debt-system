/// Immutable Philippine peso amount stored as integer centavos.
class Money implements Comparable<Money> {
  const Money.fromCentavos(this.centavos);

  static const zero = Money.fromCentavos(0);

  final int centavos;

  // Generous business limits, below native integer overflow even when totals
  // are added. Unit prices/discounts and quantities have tighter domain limits.
  static const int maxCentavos = 999999999999;
  static const int maxUnitCentavos = 100000000;
  static const int maxQuantity = 1000000;
  // Storage/report arithmetic uses the interoperable exact-integer range.
  // Input policy limits must not reject historical records during decoding.
  static const int maxStoredCentavos = 9007199254740991;

  void validate({String field = 'Amount', int max = maxStoredCentavos}) {
    if (centavos < -max || centavos > max) {
      throw ArgumentError('$field exceeds the supported amount limit.');
    }
  }

  static void validateQuantity(
    int value, {
    bool allowZero = true,
    int max = maxStoredCentavos,
  }) {
    if (value < (allowZero ? 0 : 1) || value > max) {
      throw ArgumentError('Quantity must be ${allowZero ? 0 : 1}–$max.');
    }
  }

  static Money _checked(int value) {
    final money = Money.fromCentavos(value);
    money.validate();
    return money;
  }

  factory Money.parse(String input, {int max = maxCentavos}) {
    final value = input.trim().replaceAll(',', '');
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid money amount: $input');
    }
    final negative = match.group(1) == '-';
    final pesos = BigInt.parse(match.group(2)!);
    final fraction = match.group(3) ?? '';
    final firstTwo = '${fraction}00'.substring(0, 2);
    var result = pesos * BigInt.from(100) + BigInt.parse(firstTwo);
    if (fraction.length > 2 && int.parse(fraction[2]) >= 5) {
      result += BigInt.one;
    }
    if (result > BigInt.from(max)) {
      throw const FormatException('Amount exceeds the supported amount limit.');
    }
    return Money.fromCentavos((negative ? -result : result).toInt());
  }

  static Money? tryParse(String input) {
    try {
      return Money.parse(input);
    } on FormatException {
      return null;
    }
  }

  /// Converts legacy SQLite REAL values through their decimal representation,
  /// avoiding any new binary floating-point money arithmetic.
  factory Money.fromLegacyNumber(num value) =>
      Money.parse(value.toString(), max: maxStoredCentavos);

  Money operator +(Money other) {
    validate();
    other.validate();
    return _checked(centavos + other.centavos);
  }

  Money operator -(Money other) {
    validate();
    other.validate();
    return _checked(centavos - other.centavos);
  }

  Money operator -() {
    validate();
    return _checked(-centavos);
  }

  Money operator *(int multiplier) {
    validate();
    final result = BigInt.from(centavos) * BigInt.from(multiplier);
    if (result.abs() > BigInt.from(maxStoredCentavos)) {
      throw ArgumentError('Total exceeds the supported amount limit.');
    }
    return Money.fromCentavos(result.toInt());
  }

  Money min(Money other) => centavos <= other.centavos ? this : other;

  Money max(Money other) => centavos >= other.centavos ? this : other;

  Money get abs => Money.fromCentavos(centavos.abs());

  bool get isZero => centavos == 0;
  bool get isNegative => centavos < 0;
  bool get isPositive => centavos > 0;
  bool get isFinite => true;

  bool operator <(Object other) => centavos < _comparisonCentavos(other);
  bool operator <=(Object other) => centavos <= _comparisonCentavos(other);
  bool operator >(Object other) => centavos > _comparisonCentavos(other);
  bool operator >=(Object other) => centavos >= _comparisonCentavos(other);

  /// Divides using deterministic half-up rounding.
  Money divide(int divisor) {
    if (divisor <= 0) throw ArgumentError.value(divisor, 'divisor');
    return Money.fromCentavos(roundRatioHalfUp(centavos, divisor));
  }

  String format({bool symbol = true}) {
    final absolute = centavos.abs();
    final pesos = absolute ~/ 100;
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    final sign = centavos < 0 ? '-' : '';
    return '${symbol ? '₱' : ''}$sign$pesos.$fraction';
  }

  /// Compatibility formatter for existing peso UI while values migrate to this
  /// type. Only two decimal places are valid for centavo-backed currency.
  String toStringAsFixed(int fractionDigits) {
    if (fractionDigits != 2 && fractionDigits != 0) {
      throw ArgumentError.value(fractionDigits, 'fractionDigits');
    }
    if (fractionDigits == 0) {
      return roundRatioHalfUp(centavos, 100).toString();
    }
    return format(symbol: false);
  }

  /// Terminal conversion for chart/layout libraries. Business calculations and
  /// report inputs must remain in centavos before this boundary.
  double toChartValue() => centavos / 100.0;

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  @override
  bool operator ==(Object other) =>
      other is Money && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  String toString() => format();

  int _comparisonCentavos(Object other) {
    if (other is Money) return other.centavos;
    if (other is num && other == 0) return 0;
    throw ArgumentError(
      'Money can only be compared with Money or numeric zero.',
    );
  }
}

int roundRatioHalfUp(int numerator, int denominator) {
  return roundProductRatioHalfUp(numerator, 1, denominator);
}

int roundProductRatioHalfUp(int value, int multiplier, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator');
  }
  final numerator = BigInt.from(value) * BigInt.from(multiplier);
  final divisor = BigInt.from(denominator);
  var result = numerator.abs() ~/ divisor;
  if ((numerator.abs() % divisor) * BigInt.two >= divisor) result += BigInt.one;
  if (result > BigInt.from(Money.maxStoredCentavos)) {
    throw ArgumentError('Ratio exceeds the supported exact-integer range.');
  }
  return (numerator.isNegative ? -result : result).toInt();
}
