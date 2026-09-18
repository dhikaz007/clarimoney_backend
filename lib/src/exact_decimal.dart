class ExactDecimal implements Comparable<ExactDecimal> {
  const ExactDecimal._(this.unscaled, this.scale);

  factory ExactDecimal.parse(Object value) {
    final text = value.toString().trim();
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(text);
    if (match == null) throw const FormatException('Invalid decimal');
    final fraction = match.group(3) ?? '';
    final sign = match.group(1) == '-' ? -1 : 1;
    return ExactDecimal._(
      BigInt.parse('${match.group(2)}$fraction') * BigInt.from(sign),
      fraction.length,
    );
  }

  final BigInt unscaled;
  final int scale;

  ExactDecimal operator +(ExactDecimal other) {
    final targetScale = scale > other.scale ? scale : other.scale;
    return ExactDecimal._(
      unscaled * _ten(targetScale - scale) +
          other.unscaled * _ten(targetScale - other.scale),
      targetScale,
    );
  }

  ExactDecimal operator -(ExactDecimal other) => this + other.negate();
  ExactDecimal negate() => ExactDecimal._(-unscaled, scale);
  ExactDecimal multiplyInteger(int value) =>
      ExactDecimal._(unscaled * BigInt.from(value), scale);

  ExactDecimal divide(ExactDecimal other, {int precision = 24}) {
    if (other.unscaled == BigInt.zero) throw IntegerDivisionByZeroException();
    return ExactDecimal._(
      (unscaled * _ten(precision + other.scale)) ~/
          (other.unscaled * _ten(scale)),
      precision,
    ).trim();
  }

  ExactDecimal trim() {
    var value = unscaled;
    var outputScale = scale;
    while (outputScale > 0 && value % BigInt.from(10) == BigInt.zero) {
      value ~/= BigInt.from(10);
      outputScale--;
    }
    return ExactDecimal._(value, outputScale);
  }

  bool get isZero => unscaled == BigInt.zero;

  @override
  int compareTo(ExactDecimal other) {
    final targetScale = scale > other.scale ? scale : other.scale;
    return (unscaled * _ten(targetScale - scale)).compareTo(
      other.unscaled * _ten(targetScale - other.scale),
    );
  }

  Object get jsonValue {
    final value = trim();
    final digits = value.unscaled.abs().toString().padLeft(
      value.scale + 1,
      '0',
    );
    final split = digits.length - value.scale;
    final text = value.scale == 0
        ? digits
        : '${digits.substring(0, split)}.${digits.substring(split)}';
    final signed = value.unscaled.isNegative ? '-$text' : text;
    if (!signed.contains('.')) {
      final integer = BigInt.parse(signed);
      if (integer >= BigInt.from(-9007199254740991) &&
          integer <= BigInt.from(9007199254740991)) {
        return integer.toInt();
      }
    }
    final significantDigits = signed
        .replaceAll(RegExp(r'[-.]'), '')
        .replaceFirst(RegExp(r'^0+'), '')
        .length;
    if (significantDigits <= 15) return double.parse(signed);
    return signed;
  }

  @override
  String toString() => jsonValue.toString();
}

BigInt _ten(int exponent) => BigInt.from(10).pow(exponent);

Object? exactJsonDecimal(Object? value) =>
    value == null ? null : ExactDecimal.parse(value).jsonValue;
