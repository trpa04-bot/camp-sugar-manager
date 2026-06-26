/// Utility for extracting guest first/last name from a Google Calendar event
/// title, handling descriptor tokens that indicate booking type/context.
library;

class GuestNameParts {
  const GuestNameParts({
    required this.firstName,
    required this.lastName,
    required this.rawTitleSuffix,
    required this.extractedFromTitle,
  });

  final String? firstName;
  final String? lastName;
  final String? rawTitleSuffix;

  /// True when name was derived from a calendar title (may need review).
  final bool extractedFromTitle;
}

class GoogleCalendarTitleParser {
  static const Set<String> _descriptorTokens = {
    'kamper', 'camper', 'campspace', 'booking', 'airbnb', 'whatsapp', 'motor',
    'motori', 'sator', 'šator', 'šatorom', 'caravan', 'kamp', 'rez',
    'parcela', 'pitch', 'bg', 'sa', 'dole', 'kut', 'gornji', 'donji',
    'lijevi', 'desni', 'gore', 'kampom',
  };

  static String _normalize(String token) {
    const map = {'č': 'c', 'ć': 'c', 'đ': 'd', 'š': 's', 'ž': 'z'};
    var s = token.toLowerCase();
    for (final entry in map.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }
    return s;
  }

  static bool _isDescriptor(String token) {
    return _descriptorTokens.contains(token.toLowerCase()) ||
        _descriptorTokens.contains(_normalize(token));
  }

  /// Accepts hyphenated names like "Anna-Maria" by validating each segment.
  static bool _looksLikeName(String token) {
    if (token.isEmpty) return false;
    for (final seg in token.split('-')) {
      if (seg.isEmpty) return false;
      final first = seg[0];
      if (first != first.toUpperCase() || first == first.toLowerCase()) {
        return false;
      }
      final rest = seg.substring(1);
      for (final c in rest.split('')) {
        if (c != c.toLowerCase() && c != "'") return false;
      }
    }
    return true;
  }

  static GuestNameParts extractNameParts(String? title) {
    if (title == null || title.trim().isEmpty) {
      return const GuestNameParts(
        firstName: null,
        lastName: null,
        rawTitleSuffix: null,
        extractedFromTitle: false,
      );
    }

    final cleaned = title
        .replaceAll(RegExp(r' [-\/|] .*$'), '')
        .replaceAll(RegExp(r'\d+'), '')
        .trim();

    final tokens =
        cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    if (tokens.isEmpty) {
      return GuestNameParts(
        firstName: null,
        lastName: null,
        rawTitleSuffix: cleaned.isEmpty ? null : cleaned,
        extractedFromTitle: false,
      );
    }

    final firstToken = tokens[0];
    if (!_looksLikeName(firstToken)) {
      return GuestNameParts(
        firstName: null,
        lastName: null,
        rawTitleSuffix: tokens.join(' '),
        extractedFromTitle: false,
      );
    }

    final firstName = firstToken;
    String? lastName;
    var suffixStart = 1;

    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (_isDescriptor(token)) continue;
      if (_looksLikeName(token)) {
        lastName = token;
        suffixStart = i + 1;
      }
      break;
    }

    final suffixParts = tokens.skip(suffixStart).toList();
    final rawSuffix = suffixParts.isEmpty ? null : suffixParts.join(' ');

    return GuestNameParts(
      firstName: firstName,
      lastName: lastName,
      rawTitleSuffix: rawSuffix,
      extractedFromTitle: true,
    );
  }
}
