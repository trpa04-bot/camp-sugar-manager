class MrzValidator {
  static const List<int> _weights = [7, 3, 1];

  static int charValue(String char) {
    if (char == '<') {
      return 0;
    }
    final unit = char.codeUnitAt(0);
    if (unit >= 48 && unit <= 57) {
      return unit - 48;
    }
    if (unit >= 65 && unit <= 90) {
      return unit - 55;
    }
    return 0;
  }

  static String computeCheckDigit(String value) {
    var sum = 0;
    for (var i = 0; i < value.length; i++) {
      sum += charValue(value[i]) * _weights[i % _weights.length];
    }
    return (sum % 10).toString();
  }

  static bool validateCheckDigit(String value, String checkDigit) {
    if (checkDigit.isEmpty) {
      return false;
    }
    return computeCheckDigit(value) == checkDigit;
  }
}
