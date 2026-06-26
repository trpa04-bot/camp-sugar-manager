import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../../document_scan/mrz/mrz_line_finder.dart';
import '../../document_scan/mrz/mrz_parser.dart';
import '../../document_scan/mrz/mrz_result.dart';
import '../../document_scan/mrz/mrz_type.dart';
import '../models/mrz_scan_result.dart';

/// Scans the machine-readable zone (MRZ) of identity documents.
///
/// This service now delegates the hard parts to two well-tested, dependency-free
/// modules:
///  * [MrzLineFinder] — locates and cleans MRZ rows inside noisy OCR text,
///    tolerating surrounding human-readable text, stray spaces and clipping.
///  * [MrzParser] — parses TD1/TD2/TD3 rows with full ICAO 9303 check-digit
///    validation and OCR character-confusion correction (O↔0, I↔1, B↔8, ...).
///
/// Two entry points are provided:
///  * [scanCapturedBytes] — native/mobile path that runs ML Kit on the image
///    bytes (uses a temp file via `dart:io`).
///  * [scanRecognizedText] — web-safe path that parses already-recognized OCR
///    text (e.g. text returned by the Cloud Functions Vision pipeline), so MRZ
///    extraction works in the browser without `dart:io` or the camera plugin.
class MrzScannerService {
  MrzScannerService({
    TextRecognizer? textRecognizer,
    MrzLineFinder lineFinder = const MrzLineFinder(),
    MrzParser parser = const MrzParser(),
  }) : _textRecognizer =
           textRecognizer ?? TextRecognizer(script: TextRecognitionScript.latin),
       _lineFinder = lineFinder,
       _parser = parser;

  final TextRecognizer _textRecognizer;
  final MrzLineFinder _lineFinder;
  final MrzParser _parser;

  /// Native path: crops the lower part of the document, runs ML Kit OCR and
  /// parses the MRZ. Throws [StateError] if no readable MRZ is found.
  Future<MrzScanResult> scanCapturedBytes(Uint8List bytes) async {
    final croppedBytes = _cropMrzBottom(bytes);
    final tempDir = Directory.systemTemp.createTempSync('mrz_scan_');
    final tempFile = File('${tempDir.path}/mrz.jpg');
    await tempFile.writeAsBytes(croppedBytes, flush: true);
    try {
      final recognized = await _textRecognizer.processImage(
        InputImage.fromFilePath(tempFile.path),
      );
      return scanRecognizedText(recognized.text);
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Web-safe path: parses an MRZ out of already-recognized OCR [rawText].
  ///
  /// This contains no platform-specific code, so it runs on web, desktop and
  /// mobile alike. Throws [StateError] when no MRZ can be located.
  MrzScanResult scanRecognizedText(String rawText) {
    final candidate = _lineFinder.find(rawText);
    if (candidate == null) {
      throw StateError(
        'MRZ nije pronađen ili nije dovoljno čitljiv. '
        'Slikajte donji dio dokumenta oštrije i bez odsjaja.',
      );
    }

    final parsed = _parser.parse(candidate.lines);
    if (parsed.type == MrzType.unknown) {
      throw StateError('MRZ nije prepoznat. Pokušajte ponovno.');
    }
    return _mapResult(parsed);
  }

  void dispose() {
    _textRecognizer.close();
  }

  Uint8List _cropMrzBottom(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Slika dokumenta nije ispravna.');
    }
    final top = (decoded.height * 0.55).round().clamp(0, decoded.height - 1);
    final crop = img.copyCrop(
      decoded,
      x: 0,
      y: top,
      width: decoded.width,
      height: decoded.height - top,
    );
    return Uint8List.fromList(img.encodeJpg(crop, quality: 95));
  }

  MrzScanResult _mapResult(MrzResult parsed) {
    final checks = MrzCheckResult(
      documentNumber: parsed.validDocumentNumberChecksum,
      birthDate: parsed.validBirthDateChecksum,
      expiryDate: parsed.validExpiryDateChecksum,
      composite: parsed.validCompositeChecksum,
    );

    final names = _splitGivenNames(parsed.givenNames);

    return MrzScanResult(
      format: _formatLabel(parsed.type),
      rawLines: parsed.rawLines,
      cleanedLines: parsed.rawLines,
      normalizedText: parsed.rawLines.join('\n'),
      documentCode: parsed.documentCode,
      documentType: _mapDocumentType(parsed.documentCode),
      firstName: names.firstName,
      lastName: parsed.surname,
      middleNames: names.middleNames,
      documentNumber: parsed.documentNumber,
      nationality: parsed.nationality,
      nationalityCode: parsed.nationality,
      issuingCountry: parsed.issuingCountry,
      dateOfBirth: _toDisplayDate(parsed.dateOfBirth),
      gender: parsed.sex,
      dateOfExpiry: _toDisplayDate(parsed.expiryDate),
      optionalData: parsed.personalNumber,
      personalNumber: parsed.personalNumber,
      checks: checks,
      errors: parsed.warnings,
      correctedCharacterCount: 0,
      confidence: parsed.confidence,
    );
  }

  String _formatLabel(MrzType type) {
    switch (type) {
      case MrzType.td1:
        return 'TD1';
      case MrzType.td2:
        return 'TD2';
      case MrzType.td3:
        return 'TD3';
      case MrzType.unknown:
        return 'UNKNOWN';
    }
  }

  String? _mapDocumentType(String? code) {
    final clean = (code ?? '').replaceAll('<', '').trim().toUpperCase();
    if (clean.startsWith('P')) return 'passport';
    if (clean.startsWith('I') ||
        clean.startsWith('A') ||
        clean.startsWith('C')) {
      return 'nationalIdCard';
    }
    return null;
  }

  /// Converts an ISO `yyyy-MM-dd` date (as produced by [MrzParser]) into the
  /// app's display format `dd.MM.yyyy`. Returns the input unchanged if it does
  /// not match, so we never lose information.
  String? _toDisplayDate(String? isoDate) {
    if (isoDate == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate);
    if (match == null) return isoDate;
    return '${match.group(3)}.${match.group(2)}.${match.group(1)}';
  }

  _GivenNames _splitGivenNames(String? givenNames) {
    if (givenNames == null || givenNames.trim().isEmpty) {
      return const _GivenNames();
    }
    final tokens = givenNames
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) {
      return const _GivenNames();
    }
    return _GivenNames(
      firstName: tokens.first,
      middleNames: tokens.length > 1 ? tokens.sublist(1).join(' ') : null,
    );
  }
}

class _GivenNames {
  const _GivenNames({this.firstName, this.middleNames});

  final String? firstName;
  final String? middleNames;
}
