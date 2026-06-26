import 'mrz_type.dart';

/// Result of locating the machine-readable zone (MRZ) inside arbitrary OCR text.
class MrzLineCandidate {
  const MrzLineCandidate({required this.type, required this.lines});

  final MrzType type;
  final List<String> lines;
}

/// Locates and normalizes MRZ rows from raw OCR text.
///
/// Real-world OCR output rarely produces clean, perfectly sized MRZ rows: lines
/// may contain stray spaces, surrounding human-readable text, lowercase
/// characters, or be split/merged. [MrzLineFinder] scans every line, keeps only
/// MRZ-like candidates, normalizes them to the exact fixed width required by the
/// document type (TD1=30, TD2=36, TD3=44), and returns the best contiguous block
/// of rows ready for [MrzParser].
class MrzLineFinder {
  const MrzLineFinder();

  /// Returns the most likely MRZ block found in [rawText], or `null` if none.
  MrzLineCandidate? find(String rawText) {
    final normalized = rawText
        .split(RegExp(r'\r?\n'))
        .map(_normalizeLine)
        .where((line) => _looksLikeMrz(line))
        .toList(growable: false);

    if (normalized.isEmpty) {
      return null;
    }

    return _findTd3(normalized) ??
        _findTd2(normalized) ??
        _findTd1(normalized);
  }

  /// Cleans a single OCR line: uppercases, removes whitespace and any character
  /// that cannot appear in an MRZ (only A-Z, 0-9 and the filler `<` are valid).
  String _normalizeLine(String value) {
    return value
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^A-Z0-9<]'), '');
  }

  /// Heuristic to keep only MRZ-like rows and drop ordinary text lines.
  ///
  /// MRZ rows come in two shapes: the name row is filler-heavy (`<<` between
  /// surname and given names), while data rows are dense alphanumeric strings
  /// with few fillers. We accept a long line if it either contains a filler or
  /// is a long, almost-pure uppercase alphanumeric string (a data row).
  bool _looksLikeMrz(String line) {
    if (line.length < 25) {
      return false;
    }
    // Reject lines that contain characters MRZ never uses (already stripped in
    // normalization, so any remaining line is A-Z/0-9/< only). Keep long ones.
    final hasFiller = line.contains('<');
    final isMostlyDigits =
        RegExp(r'\d').allMatches(line).length >= 6; // data rows carry dates
    return hasFiller || isMostlyDigits;
  }

  MrzLineCandidate? _findTd3(List<String> lines) {
    for (var i = 0; i < lines.length - 1; i++) {
      final first = _fit(lines[i], MrzType.td3.rowLength);
      final second = _fit(lines[i + 1], MrzType.td3.rowLength);
      if (first.startsWith('P') && first.contains('<<')) {
        return MrzLineCandidate(type: MrzType.td3, lines: [first, second]);
      }
    }
    return null;
  }

  MrzLineCandidate? _findTd2(List<String> lines) {
    for (var i = 0; i < lines.length - 1; i++) {
      final first = _fit(lines[i], MrzType.td2.rowLength);
      final second = _fit(lines[i + 1], MrzType.td2.rowLength);
      if (RegExp(r'^[ACIV]').hasMatch(first) && first.contains('<<')) {
        return MrzLineCandidate(type: MrzType.td2, lines: [first, second]);
      }
    }
    return null;
  }

  MrzLineCandidate? _findTd1(List<String> lines) {
    for (var i = 0; i < lines.length - 2; i++) {
      final first = _fit(lines[i], MrzType.td1.rowLength);
      final second = _fit(lines[i + 1], MrzType.td1.rowLength);
      final third = _fit(lines[i + 2], MrzType.td1.rowLength);
      if (RegExp(r'^[ACI]').hasMatch(first) && third.contains('<<')) {
        return MrzLineCandidate(
          type: MrzType.td1,
          lines: [first, second, third],
        );
      }
    }
    return null;
  }

  /// Forces a row to exactly [length] characters: trims overflow (extra OCR
  /// noise) and right-pads short rows with the MRZ filler `<`.
  String _fit(String value, int length) {
    if (value.length == length) {
      return value;
    }
    if (value.length > length) {
      return value.substring(0, length);
    }
    return value.padRight(length, '<');
  }
}
