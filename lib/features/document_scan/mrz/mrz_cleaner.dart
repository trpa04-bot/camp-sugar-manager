class MrzCleaner {
  static const Map<String, String> _digitExpected = {
    'O': '0',
    'I': '1',
    'B': '8',
    'S': '5',
    'Z': '2',
    'G': '6',
  };

  static const Map<String, String> _letterExpected = {
    '0': 'O',
    '1': 'I',
    '8': 'B',
    '5': 'S',
    '2': 'Z',
    '6': 'G',
  };

  static String cleanForDigits(String value) {
    return _cleanByMask(value, 'D' * value.length);
  }

  static String cleanForLetters(String value) {
    return _cleanByMask(value, 'A' * value.length);
  }

  static String cleanByMask(String value, String mask) {
    return _cleanByMask(value, mask);
  }

  static String _cleanByMask(String value, String mask) {
    final length = value.length < mask.length ? value.length : mask.length;
    final buffer = StringBuffer();

    for (var i = 0; i < length; i++) {
      final char = value[i];
      final mode = mask[i];
      if (mode == 'D') {
        buffer.write(_digitExpected[char] ?? char);
      } else if (mode == 'A') {
        buffer.write(_letterExpected[char] ?? char);
      } else {
        buffer.write(char);
      }
    }

    if (value.length > length) {
      buffer.write(value.substring(length));
    }

    return buffer.toString();
  }
}
