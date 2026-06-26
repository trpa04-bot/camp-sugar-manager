import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';

class ReservationImportParser {
  static Future<ReservationImportResult> parseText(
    String text, {
    ReservationSource? sourceHint,
    String? localeHint,
  }) async {
    final normalized = text.trim();

    if (normalized.isEmpty) {
      return ReservationImportResult(
        rawImportedText: text,
        confidence: 0.0,
        needsReview: true,
        warnings: ['Tekst je prazan'],
      );
    }

    // Detect source if not provided
    final detectedSource = sourceHint ?? _detectSource(normalized);

    // Parse based on source
    late ReservationImportResult result;

    switch (detectedSource) {
      case ReservationSource.booking:
        result = _parseBooking(normalized);
        break;
      case ReservationSource.airbnb:
        result = _parseAirbnb(normalized);
        break;
      case ReservationSource.campspace:
        result = _parseCampspace(normalized);
        break;
      case ReservationSource.whatsapp:
        result = _parseWhatsapp(normalized);
        break;
      case ReservationSource.email:
        result = _parseEmail(normalized);
        break;
      default:
        result = _parseGeneric(normalized);
    }

    return result.copyWith(rawImportedText: text, source: detectedSource);
  }

  static ReservationSource _detectSource(String text) {
    final lower = text.toLowerCase();

    final hasCampspaceStructure =
        lower.contains('guest:') &&
        lower.contains('arrival') &&
        lower.contains('departure') &&
        RegExp(r'\b\d+\s*pitches?\b', caseSensitive: false).hasMatch(lower);

    if (lower.contains('booking')) {
      return ReservationSource.booking;
    }
    if (lower.contains('airbnb') || lower.contains('confirmation code')) {
      return ReservationSource.airbnb;
    }
    if (lower.contains('campspace') || hasCampspaceStructure) {
      return ReservationSource.campspace;
    }
    if (lower.startsWith('bok,') ||
        lower.startsWith('hello,') ||
        (lower.contains('dolazim') && !lower.contains('airbnb'))) {
      return ReservationSource.whatsapp;
    }
    if (lower.contains('poštovani') || lower.contains('dear')) {
      return ReservationSource.email;
    }

    return ReservationSource.other;
  }

  // ============================================================================
  // BOOKING PARSER
  // ============================================================================
  static ReservationImportResult _parseBooking(String text) {
    final confidences = <String, double>{};
    final warnings = <String>[];

    // Extract name
    String? name = _extractNameFromText(text, 'booking');
    confidences['primaryGuestFullName'] = name != null ? 0.9 : 0.2;

    // Extract dates
    final dates = _extractDates(text);
    final checkInDate = dates.isNotEmpty ? dates[0] : null;
    final checkOutDate = dates.length > 1 ? dates[1] : null;
    confidences['checkInDate'] = checkInDate != null ? 0.9 : 0.0;
    confidences['checkOutDate'] = checkOutDate != null ? 0.9 : 0.0;

    // Extract guest count
    final guestInfo = _extractGuestCount(text);
    confidences['guestCount'] = guestInfo['guestCount'] != null ? 0.85 : 0.0;
    confidences['adults'] = guestInfo['adults'] != null ? 0.8 : 0.0;

    // Extract booking/reservation number
    String? bookingNum = _extractBookingNumber(text);
    confidences['sourceReservationId'] = bookingNum != null ? 0.95 : 0.0;

    // Extract price
    final price = _extractPrice(text);
    confidences['totalPrice'] = price != null ? 0.85 : 0.0;

    final avg = confidences.values.isEmpty
        ? 0.5
        : confidences.values.reduce((a, b) => a + b) /
              confidences.values.length;

    return ReservationImportResult(
      primaryGuestFullName: name,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: guestInfo['adults'] as int?,
      children: guestInfo['children'] as int?,
      guestCount: guestInfo['guestCount'] as int?,
      sourceReservationId: bookingNum,
      totalPrice: price,
      confidence: avg,
      needsReview: avg < 0.8,
      fieldConfidences: confidences,
      warnings: warnings,
    );
  }

  // ============================================================================
  // AIRBNB PARSER
  // ============================================================================
  static ReservationImportResult _parseAirbnb(String text) {
    final confidences = <String, double>{};

    String? name = _extractNameFromText(text, 'airbnb');
    confidences['primaryGuestFullName'] = name != null ? 0.85 : 0.2;

    final dates = _extractDates(text);
    final checkInDate = dates.isNotEmpty ? dates[0] : null;
    final checkOutDate = dates.length > 1 ? dates[1] : null;
    confidences['checkInDate'] = checkInDate != null ? 0.85 : 0.0;
    confidences['checkOutDate'] = checkOutDate != null ? 0.85 : 0.0;

    final guestInfo = _extractGuestCount(text);
    confidences['guestCount'] = guestInfo['guestCount'] != null ? 0.8 : 0.0;
    final inferredAdults =
        guestInfo['adults'] as int? ??
        ((guestInfo['children'] as int?) == null &&
                (guestInfo['infants'] as int?) == null
            ? guestInfo['guestCount'] as int?
            : null);
    confidences['adults'] = inferredAdults != null ? 0.75 : 0.0;

    String? confirmationCode = _extractConfirmationCode(text);
    confidences['sourceReservationId'] = confirmationCode != null ? 0.95 : 0.0;

    final avg = confidences.values.isEmpty
        ? 0.5
        : confidences.values.reduce((a, b) => a + b) /
              confidences.values.length;

    return ReservationImportResult(
      primaryGuestFullName: name,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: inferredAdults,
      children: guestInfo['children'] as int?,
      infants: guestInfo['infants'] as int?,
      guestCount: guestInfo['guestCount'] as int?,
      sourceReservationId: confirmationCode,
      confidence: avg,
      needsReview: avg < 0.8,
      fieldConfidences: confidences,
    );
  }

  // ============================================================================
  // CAMPSPACE PARSER
  // ============================================================================
  static ReservationImportResult _parseCampspace(String text) {
    final confidences = <String, double>{};

    String? name = _extractNameFromText(text, 'campspace');
    confidences['primaryGuestFullName'] = name != null ? 0.9 : 0.2;

    final dates = _extractDates(text);
    final checkInDate = dates.isNotEmpty ? dates[0] : null;
    final checkOutDate = dates.length > 1 ? dates[1] : null;
    confidences['checkInDate'] = checkInDate != null ? 0.9 : 0.0;
    confidences['checkOutDate'] = checkOutDate != null ? 0.9 : 0.0;

    final guestInfo = _extractGuestCount(text);
    confidences['adults'] = guestInfo['adults'] != null ? 0.85 : 0.0;
    confidences['children'] = guestInfo['children'] != null ? 0.85 : 0.0;
    confidences['guestCount'] = guestInfo['guestCount'] != null ? 0.85 : 0.0;

    final pitchCount = _extractPitchCount(text);
    confidences['pitchCount'] = pitchCount > 1 ? 0.9 : 0.5;

    final avg = confidences.values.isEmpty
        ? 0.5
        : confidences.values.reduce((a, b) => a + b) /
              confidences.values.length;

    return ReservationImportResult(
      primaryGuestFullName: name,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: guestInfo['adults'] as int?,
      children: guestInfo['children'] as int?,
      guestCount: guestInfo['guestCount'] as int?,
      pitchCount: pitchCount,
      confidence: avg,
      needsReview: avg < 0.8,
      fieldConfidences: confidences,
    );
  }

  // ============================================================================
  // WHATSAPP PARSER
  // ============================================================================
  static ReservationImportResult _parseWhatsapp(String text) {
    final confidences = <String, double>{};
    final warnings = <String>[];

    final dates = _extractDates(text);
    final checkInDate = dates.isNotEmpty ? dates[0] : null;
    final checkOutDate = dates.length > 1 ? dates[1] : null;

    if (checkInDate == null) {
      warnings.add('Nije pronađen datum dolaska');
    }

    confidences['checkInDate'] = checkInDate != null ? 0.8 : 0.0;
    confidences['checkOutDate'] = checkOutDate != null ? 0.8 : 0.0;

    final guestInfo = _extractGuestCount(text);
    confidences['adults'] = guestInfo['adults'] != null ? 0.85 : 0.0;
    confidences['children'] = guestInfo['children'] != null ? 0.85 : 0.0;
    confidences['guestCount'] = guestInfo['guestCount'] != null ? 0.85 : 0.0;

    final avg = confidences.values.isEmpty
        ? 0.6
        : confidences.values.reduce((a, b) => a + b) /
              confidences.values.length;

    return ReservationImportResult(
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: guestInfo['adults'] as int?,
      children: guestInfo['children'] as int?,
      guestCount: guestInfo['guestCount'] as int?,
      confidence: avg,
      needsReview: true,
      fieldConfidences: confidences,
      warnings: warnings,
    );
  }

  // ============================================================================
  // EMAIL PARSER
  // ============================================================================
  static ReservationImportResult _parseEmail(String text) {
    final confidences = <String, double>{};

    String? name = _extractNameFromText(text, 'email');
    confidences['primaryGuestFullName'] = name != null ? 0.75 : 0.2;

    final dates = _extractDates(text);
    final checkInDate = dates.isNotEmpty ? dates[0] : null;
    final checkOutDate = dates.length > 1 ? dates[1] : null;
    confidences['checkInDate'] = checkInDate != null ? 0.8 : 0.0;
    confidences['checkOutDate'] = checkOutDate != null ? 0.8 : 0.0;

    final guestInfo = _extractGuestCount(text);
    confidences['guestCount'] = guestInfo['guestCount'] != null ? 0.75 : 0.0;

    final avg = confidences.values.isEmpty
        ? 0.5
        : confidences.values.reduce((a, b) => a + b) /
              confidences.values.length;

    return ReservationImportResult(
      primaryGuestFullName: name,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: guestInfo['adults'] as int?,
      children: guestInfo['children'] as int?,
      guestCount: guestInfo['guestCount'] as int?,
      confidence: avg,
      needsReview: true,
      fieldConfidences: confidences,
    );
  }

  // ============================================================================
  // GENERIC PARSER
  // ============================================================================
  static ReservationImportResult _parseGeneric(String text) {
    final confidences = <String, double>{};
    final warnings = <String>[];

    final name = _extractNameFromText(text, 'generic');
    confidences['primaryGuestFullName'] = name != null ? 0.75 : 0.0;

    final dates = _extractDates(text);
    final checkInDate = dates.isNotEmpty ? dates[0] : null;
    final checkOutDate = dates.length > 1 ? dates[1] : null;

    if (checkInDate == null) {
      warnings.add('Nije pronađen datum dolaska');
    }

    confidences['checkInDate'] = checkInDate != null ? 0.7 : 0.0;
    confidences['checkOutDate'] = checkOutDate != null ? 0.7 : 0.0;

    final guestInfo = _extractGuestCount(text);
    confidences['guestCount'] = guestInfo['guestCount'] != null ? 0.7 : 0.0;

    final pitchCount = _extractPitchCount(text);
    confidences['pitchCount'] = pitchCount > 1 ? 0.8 : 0.5;

    final price = _extractPrice(text);
    confidences['totalPrice'] = price != null ? 0.75 : 0.0;

    final avg = confidences.values.isEmpty
        ? 0.4
        : confidences.values.reduce((a, b) => a + b) /
              confidences.values.length;

    return ReservationImportResult(
      primaryGuestFullName: name,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
      adults: guestInfo['adults'] as int?,
      children: guestInfo['children'] as int?,
      guestCount: guestInfo['guestCount'] as int?,
      pitchCount: pitchCount,
      totalPrice: price,
      confidence: avg,
      needsReview: true,
      fieldConfidences: confidences,
      warnings: warnings,
    );
  }

  // ============================================================================
  // EXTRACTION HELPERS
  // ============================================================================

  static String? _extractNameFromText(String text, String context) {
    final reservationForMatch = RegExp(
      r'rezervacija\s+za\s+([^\n\r,.;]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (reservationForMatch != null) {
      final raw = reservationForMatch.group(1)?.trim() ?? '';
      final withoutDateTail = raw
          .split(
            RegExp(
              r'\b(?:od|do|from|to|arrival|departure|check-in|check-out)\b',
              caseSensitive: false,
            ),
          )
          .first
          .trim();
      final cleaned = _sanitizeNameCandidate(withoutDateTail);
      if (cleaned != null) {
        return cleaned;
      }
    }

    const letterClass = r"A-Za-zÀ-ÖØ-öø-ÿČĆĐŠŽčćđšž";
    final namePatterns = [
      RegExp(
        '(?:rezervacija\\s+za)\\s+([$letterClass][$letterClass\\-\']*(?:[ \\t]+[$letterClass][$letterClass\\-\']*){1,3})',
        caseSensitive: false,
      ),
      RegExp(
        '(?:guest\\s+name|primary\\s+guest|guest|gost|ime\\s+gosta|ime|name)\\s*:\\s*([$letterClass][$letterClass\\-\']*(?:[ \\t]+[$letterClass][$letterClass\\-\']*){1,3})',
        caseSensitive: false,
      ),
    ];

    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) {
        continue;
      }
      final candidate = match.group(1)?.trim();
      final cleaned = _sanitizeNameCandidate(candidate);
      if (cleaned != null) {
        return cleaned;
      }
    }

    // Fallback: find first substantial line
    final lines = text.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();

      // Skip if line is empty or is a label/date/number line
      if (trimmed.isEmpty ||
          trimmed.toLowerCase().contains('check-in') ||
          trimmed.toLowerCase().contains('check-out') ||
          trimmed.toLowerCase().contains('arrival') ||
          trimmed.toLowerCase().contains('departure') ||
          trimmed.toLowerCase().contains('confirmation') ||
          trimmed.toLowerCase().contains('booking') ||
          trimmed.toLowerCase().contains('airbnb') ||
          trimmed.toLowerCase().contains('campspace') ||
          trimmed.toLowerCase().contains('reservation') ||
          trimmed.toLowerCase().contains('total') ||
          trimmed.toLowerCase().contains('guest') ||
          trimmed.startsWith('2') ||
          trimmed.startsWith('3') ||
          RegExp(
            r'^\d+\s+(?:adult|child|guest|pitch|parcela)',
            caseSensitive: false,
          ).hasMatch(trimmed)) {
        continue;
      }

      // Check if line looks like a name
      if (RegExp('^[$letterClass]').hasMatch(trimmed) &&
          trimmed.length > 2 &&
          trimmed.contains(RegExp(r'\s')) &&
          trimmed.length < 50) {
        // Extract just the name part (before comma or colon)
        final namePart = trimmed.split(RegExp(r'[,:]'))[0].trim();
        final cleaned = _sanitizeNameCandidate(namePart);
        if (cleaned != null) {
          return cleaned;
        }
      }
    }

    return null;
  }

  static String? _sanitizeNameCandidate(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[,:;.]$'), '')
        .trim();
    if (normalized.isEmpty || normalized.length > 60) {
      return null;
    }

    final lower = normalized.toLowerCase();
    const banned = [
      'rezervacija za',
      'gost',
      'guest',
      'name',
      'arrival',
      'departure',
      'confirmation',
      'booking',
      'check-in',
      'check-out',
    ];
    if (banned.any(lower.contains)) {
      return null;
    }
    if (!RegExp(
      r"^[A-Za-zÀ-ÖØ-öø-ÿČĆĐŠŽčćđšž][A-Za-zÀ-ÖØ-öø-ÿČĆĐŠŽčćđšž\s\-']+$",
    ).hasMatch(normalized)) {
      return null;
    }

    return normalized;
  }

  static Map<String, dynamic> _extractGuestCount(String text) {
    var adults = 0;
    var children = 0;
    var infants = 0;
    int? totalGuests;

    // Word number mappings
    const wordNumbers = {
      'jedno': 1,
      'jedan': 1,
      'dva': 2,
      'dvoje': 2,
      'tri': 3,
      'troje': 3,
      'četiri': 4,
      'četvoro': 4,
      'pet': 5,
      'šest': 6,
      'sedam': 7,
      'osam': 8,
      'devet': 9,
      'deset': 10,
    };

    // Adults patterns
    final adultPatterns = [
      RegExp(
        r'(\d+)\s*(?:adult|adults|odrasl|odrasli|Erwachsene|adulti)',
        caseSensitive: false,
      ),
      RegExp(r'(\d+)\s*(?:osob[ae]|person|persons)', caseSensitive: false),
    ];

    for (final pattern in adultPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        adults = int.tryParse(match.group(1)!) ?? adults;
        break;
      }
    }

    // Children patterns - numeric
    final childPatterns = [
      RegExp(
        r'(\d+)\s*(?:child|children|djec[ae]|dijete|bambini|kids?|Kind)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in childPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        children = int.tryParse(match.group(1)!) ?? children;
        break;
      }
    }

    // Children patterns - word numbers (e.g., "dvoje djece")
    if (children == 0) {
      final wordPattern = RegExp(
        r'(jedno|jedan|dva|dvoje|tri|troje|četiri|četvoro|pet|šest|sedam|osam|devet|deset)\s*(?:child|children|djec[ae]|dijete|bambini|kids?|Kind)',
        caseSensitive: false,
      );
      final match = wordPattern.firstMatch(text);
      if (match != null) {
        final word = match.group(1)!.toLowerCase();
        children = wordNumbers[word] ?? children;
      }
    }

    // Infants patterns
    final infantPatterns = [
      RegExp(r'(\d+)\s*(?:infant|infants)', caseSensitive: false),
    ];

    for (final pattern in infantPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        infants = int.tryParse(match.group(1)!) ?? infants;
        break;
      }
    }

    // Total guests if not already calculated
    var calculated = adults + children + infants;
    if (calculated == 0) {
      final guestPattern = RegExp(
        r'(\d+)\s*(?:guest|guests|osob|person)',
        caseSensitive: false,
      );
      final match = guestPattern.firstMatch(text);
      if (match != null) {
        totalGuests = int.tryParse(match.group(1)!);
      }
    } else {
      totalGuests = calculated;
    }

    return {
      'adults': adults > 0 ? adults : null,
      'children': children > 0 ? children : null,
      'infants': infants > 0 ? infants : null,
      'guestCount': totalGuests,
    };
  }

  static int _extractPitchCount(String text) {
    final pattern = RegExp(
      r'(\d+)\s*(?:pitches?|parcele?|camping\s+spot|tent\s+spot)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match != null) {
      final count = int.tryParse(match.group(1)!);
      return count ?? 1;
    }
    return 1;
  }

  static String? _extractBookingNumber(String text) {
    final pattern = RegExp(
      r'(?:booking\s+(?:number|id)|reservation\s+(?:number|id))[\s:]*(\d+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    return match?.group(1);
  }

  static String? _extractConfirmationCode(String text) {
    final pattern = RegExp(
      r'(?:confirmation\s+(?:code|number))[\s:]*([A-Z0-9]+)',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    return match?.group(1);
  }

  static double? _extractPrice(String text) {
    // Try to extract price in various formats
    final patterns = [
      RegExp(r'€\s*([\d.,]+)', caseSensitive: false),
      RegExp(r'\$\s*([\d.,]+)', caseSensitive: false),
      RegExp(
        r'(?:total|price|cost)[\s:]*€?\$?\s*([\d.,]+)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final priceStr = match.group(1)!;
        return _parsePrice(priceStr);
      }
    }

    return null;
  }

  static double? _parsePrice(String priceStr) {
    // Handle formats like "500.00", "1.500,00", "500,00", "1,500.00"
    // Strategy: last dot/comma is decimal separator IF followed by 1-2 digits
    // Otherwise, it's a thousands separator

    final trimmed = priceStr.trim();

    // Find positions of separators
    final lastDot = trimmed.lastIndexOf('.');
    final lastComma = trimmed.lastIndexOf(',');

    // Check what's after each separator
    final afterDot = lastDot >= 0 ? trimmed.length - lastDot - 1 : -1;
    final afterComma = lastComma >= 0 ? trimmed.length - lastComma - 1 : -1;

    String normalized = trimmed;

    // If last separator has 1-2 digits after it, it's decimal separator
    if (afterDot > 0 && afterDot <= 2 && lastDot > lastComma) {
      // Dot is decimal: "500.00" or "1.500.00"
      // Remove thousands separators (commas) and keep dot as decimal
      normalized = trimmed.replaceAll(',', '');
    } else if (afterComma > 0 && afterComma <= 2 && lastComma > lastDot) {
      // Comma is decimal: "500,00" or "1.500,00"
      // Replace . with nothing and , with .
      normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');
    } else if (afterDot > 2 && lastDot > lastComma) {
      // Dot is thousands separator (more than 2 digits after): "1.500"
      normalized = trimmed.replaceAll('.', '');
    } else if (afterComma > 2 && lastComma > lastDot) {
      // Comma is thousands separator
      normalized = trimmed.replaceAll(',', '');
    }

    return double.tryParse(normalized);
  }

  // ============================================================================
  // DATE EXTRACTION
  // ============================================================================

  static List<DateTime> _extractDates(String text) {
    final dates = <DateTime>[];

    // Parse explicit ranges before generic date parsing.
    dates.addAll(_extractDateRanges(text));

    // Try numeric patterns first
    dates.addAll(_extractNumericDates(text));

    // Try named month patterns
    dates.addAll(_extractNamedDates(text));

    // Sort and deduplicate
    dates.sort();

    // Remove duplicates while preserving order
    final seen = <DateTime>{};
    final result = <DateTime>[];
    for (final date in dates) {
      if (!seen.contains(date)) {
        result.add(date);
        seen.add(date);
      }
    }
    return result;
  }

  static List<DateTime> _extractDateRanges(String text) {
    final dates = <DateTime>[];

    const monthToken =
        r'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|januar|februar|märz|mai|juni|juli|oktober|dezember|gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre|siječanj|siječnja|veljača|veljače|ožujak|ožujka|travanj|travnja|svibanj|svibnja|lipanj|lipnja|srpanj|srpnja|kolovoz|kolovoza|rujan|rujna|listopad|listopada|studeni|studenoga|prosinac|prosinca';

    final monthDayRange = RegExp(
      '\\b($monthToken)\\.?\\s+(\\d{1,2}),?\\s*(\\d{4})\\s*(?:-|–|to)\\s*($monthToken)\\.?\\s+(\\d{1,2}),?\\s*(\\d{4})\\b',
      caseSensitive: false,
    );

    final dayMonthRange = RegExp(
      '\\b(\\d{1,2})\\.?\\s+($monthToken)\\.?\\s+(\\d{4})\\s*(?:-|–|to)\\s*(\\d{1,2})\\.?\\s+($monthToken)\\.?\\s+(\\d{4})\\b',
      caseSensitive: false,
    );

    for (final match in monthDayRange.allMatches(text)) {
      final startMonth = _monthFromToken(match.group(1));
      final startDay = int.tryParse(match.group(2) ?? '');
      final startYear = int.tryParse(match.group(3) ?? '');
      final endMonth = _monthFromToken(match.group(4));
      final endDay = int.tryParse(match.group(5) ?? '');
      final endYear = int.tryParse(match.group(6) ?? '');

      final parsed = _buildRangeDates(
        startYear,
        startMonth,
        startDay,
        endYear,
        endMonth,
        endDay,
      );
      if (parsed != null) {
        dates.addAll(parsed);
      }
    }

    for (final match in dayMonthRange.allMatches(text)) {
      final startDay = int.tryParse(match.group(1) ?? '');
      final startMonth = _monthFromToken(match.group(2));
      final startYear = int.tryParse(match.group(3) ?? '');
      final endDay = int.tryParse(match.group(4) ?? '');
      final endMonth = _monthFromToken(match.group(5));
      final endYear = int.tryParse(match.group(6) ?? '');

      final parsed = _buildRangeDates(
        startYear,
        startMonth,
        startDay,
        endYear,
        endMonth,
        endDay,
      );
      if (parsed != null) {
        dates.addAll(parsed);
      }
    }

    return dates;
  }

  static List<DateTime>? _buildRangeDates(
    int? startYear,
    int? startMonth,
    int? startDay,
    int? endYear,
    int? endMonth,
    int? endDay,
  ) {
    if (startYear == null ||
        startMonth == null ||
        startDay == null ||
        endYear == null ||
        endMonth == null ||
        endDay == null) {
      return null;
    }

    if (startYear < 2000 || endYear < 2000) {
      return null;
    }

    try {
      final start = DateTime(startYear, startMonth, startDay);
      final end = DateTime(endYear, endMonth, endDay);
      if (!start.isBefore(end)) {
        return null;
      }
      return [start, end];
    } catch (_) {
      return null;
    }
  }

  static int? _monthFromToken(String? token) {
    if (token == null || token.trim().isEmpty) {
      return null;
    }
    final key = token.toLowerCase().replaceAll('.', '').trim();

    const monthMap = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
      'januar': 1,
      'februar': 2,
      'märz': 3,
      'mai': 5,
      'juni': 6,
      'juli': 7,
      'oktober': 10,
      'dezember': 12,
      'gennaio': 1,
      'febbraio': 2,
      'marzo': 3,
      'aprile': 4,
      'maggio': 5,
      'giugno': 6,
      'luglio': 7,
      'agosto': 8,
      'settembre': 9,
      'ottobre': 10,
      'novembre': 11,
      'dicembre': 12,
      'siječanj': 1,
      'siječnja': 1,
      'veljača': 2,
      'veljače': 2,
      'ožujak': 3,
      'ožujka': 3,
      'travanj': 4,
      'travnja': 4,
      'svibanj': 5,
      'svibnja': 5,
      'lipanj': 6,
      'lipnja': 6,
      'srpanj': 7,
      'srpnja': 7,
      'kolovoz': 8,
      'kolovoza': 8,
      'rujan': 9,
      'rujna': 9,
      'listopad': 10,
      'listopada': 10,
      'studeni': 11,
      'studenoga': 11,
      'prosinac': 12,
      'prosinca': 12,
    };

    return monthMap[key];
  }

  static List<DateTime> _extractNumericDates(String text) {
    final dates = <DateTime>[];
    final now = DateTime.now();

    // Patterns: DD.MM.YYYY, DD/MM/YYYY, DD-MM-YYYY, YYYY-MM-DD, DD.MM, DD/MM
    final patterns = [
      (RegExp(r'\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b'), 'dmy'),
      (RegExp(r'\b(\d{1,2})/(\d{1,2})/(\d{4})\b'), 'dmy'),
      (RegExp(r'\b(\d{1,2})-(\d{1,2})-(\d{4})\b'), 'dmy'),
      (RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'), 'ymd'),
      (RegExp(r'\b(\d{1,2})\.(\d{1,2})\b'), 'dm'),
      (RegExp(r'\b(\d{1,2})/(\d{1,2})\b'), 'dm'),
    ];

    for (final (pattern, format) in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        try {
          int day, month, year;

          if (format == 'ymd') {
            year = int.parse(match.group(1)!);
            month = int.parse(match.group(2)!);
            day = int.parse(match.group(3)!);
          } else if (format == 'dm') {
            day = int.parse(match.group(1)!);
            month = int.parse(match.group(2)!);
            year = _inferYear(month, now, dates);
          } else {
            // dmy
            day = int.parse(match.group(1)!);
            month = int.parse(match.group(2)!);
            year = int.parse(match.group(3)!);
          }

          // Validate
          if (month < 1 || month > 12 || day < 1 || day > 31) {
            continue;
          }

          final date = DateTime(year, month, day);
          if (date.year >= 2000 && date.year <= 2100) {
            dates.add(date);
          }
        } catch (e) {
          // Skip invalid dates
        }
      }
    }

    return dates;
  }

  static List<DateTime> _extractNamedDates(String text) {
    final dates = <DateTime>[];
    final now = DateTime.now();

    const monthTokens = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
      'jan',
      'feb',
      'mar',
      'apr',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
      'januar',
      'februar',
      'märz',
      'mai',
      'juni',
      'juli',
      'oktober',
      'dezember',
      'gennaio',
      'febbraio',
      'marzo',
      'aprile',
      'maggio',
      'giugno',
      'luglio',
      'agosto',
      'settembre',
      'ottobre',
      'novembre',
      'dicembre',
      'siječanj',
      'siječnja',
      'veljača',
      'veljače',
      'ožujak',
      'ožujka',
      'travanj',
      'travnja',
      'svibanj',
      'svibnja',
      'lipanj',
      'lipnja',
      'srpanj',
      'srpnja',
      'kolovoz',
      'kolovoza',
      'rujan',
      'rujna',
      'listopad',
      'listopada',
      'studeni',
      'studenoga',
      'prosinac',
      'prosinca',
    ];
    final monthPattern = monthTokens.join('|');

    // Pattern: "June 19, 2026" or "Aug 10 2026"
    final pattern1 = RegExp(
      '\\b($monthPattern)\\.?[ \\t]+(\\d{1,2})(?:,?[ \\t]+(\\d{4}))?\\b',
      caseSensitive: false,
    );

    // Pattern: "19 Juni 2026", "3. rujna 2026"
    final pattern2 = RegExp(
      '\\b(\\d{1,2})\\.?[ \\t]+($monthPattern)\\.?(?:[ \\t]+(\\d{4}))?\\b',
      caseSensitive: false,
    );

    // Pattern 1: Month Day, Year
    for (final match in pattern1.allMatches(text)) {
      try {
        final monthStr = match.group(1)!.toLowerCase();
        final day = int.parse(match.group(2)!);
        int year;

        if (match.group(3) != null) {
          year = int.parse(match.group(3)!);
        } else {
          year = _inferYear(_monthFromToken(monthStr) ?? 1, now, dates);
        }

        final month = _monthFromToken(monthStr) ?? 0;
        if (month > 0 && day >= 1 && day <= 31) {
          final date = DateTime(year, month, day);
          if (date.year >= 2000 && date.year <= 2100) {
            dates.add(date);
          }
        }
      } catch (e) {
        // Skip
      }
    }

    // Pattern 2: Day Month, Year
    for (final match in pattern2.allMatches(text)) {
      try {
        final day = int.parse(match.group(1)!);
        final monthStr = match.group(2)!.toLowerCase();
        int year;

        if (match.group(3) != null) {
          year = int.parse(match.group(3)!);
        } else {
          year = _inferYear(_monthFromToken(monthStr) ?? 1, now, dates);
        }

        final month = _monthFromToken(monthStr) ?? 0;
        if (month > 0 && day >= 1 && day <= 31) {
          final date = DateTime(year, month, day);
          if (date.year >= 2000 && date.year <= 2100) {
            dates.add(date);
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return dates;
  }

  static int _inferYear(int month, DateTime now, List<DateTime> existingDates) {
    // If we already have a year in existingDates, use that
    if (existingDates.isNotEmpty) {
      return existingDates.first.year;
    }

    // If month is current or upcoming, use this year
    if (month >= now.month) {
      return now.year;
    }

    // If month is in the past, likely next year
    return now.year + 1;
  }
}
