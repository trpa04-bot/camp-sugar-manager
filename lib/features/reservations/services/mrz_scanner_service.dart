import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../models/mrz_scan_result.dart';

class MrzScannerService {
  MrzScannerService({TextRecognizer? textRecognizer})
    : _textRecognizer =
          textRecognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _textRecognizer;

  Future<MrzScanResult> scanCapturedBytes(Uint8List bytes) async {
    final croppedBytes = _cropMrzBottom(bytes);
    final tempDir = Directory.systemTemp.createTempSync('mrz_scan_');
    final tempFile = File('${tempDir.path}/mrz.jpg');
    await tempFile.writeAsBytes(croppedBytes, flush: true);
    try {
      final recognized = await _textRecognizer.processImage(
        InputImage.fromFilePath(tempFile.path),
      );
      final lines = recognized.text
          .split(RegExp(r'\r?\n'))
          .map(_normalizeMrzLine)
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final parsed = _parseMrz(lines);
      if (parsed == null) {
        throw StateError('MRZ nije pronađen ili nije dovoljno čitljiv.');
      }
      return parsed;
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
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

  MrzScanResult? _parseMrz(List<String> lines) {
    final normalized = lines
        .map(_normalizeMrzLine)
        .where((line) => line.length >= 25)
        .toList(growable: false);

    for (var i = 0; i < normalized.length - 1; i++) {
      final first = _pad(normalized[i], 44);
      final second = _pad(normalized[i + 1], 44);
      if (first.startsWith('P<') && first.contains('<<')) {
        final result = _parseTd3(first, second);
        if (result != null) return result;
      }
    }

    for (var i = 0; i < normalized.length - 1; i++) {
      final first = _pad(normalized[i], 36);
      final second = _pad(normalized[i + 1], 36);
      if (RegExp(r'^[ACI]<').hasMatch(first) && first.contains('<<')) {
        final result = _parseTd2(first, second);
        if (result != null) return result;
      }
    }

    for (var i = 0; i < normalized.length - 2; i++) {
      final first = _pad(normalized[i], 30);
      final second = _pad(normalized[i + 1], 30);
      final third = _pad(normalized[i + 2], 30);
      if (RegExp(r'^[ACI]').hasMatch(first) && third.contains('<<')) {
        final result = _parseTd1(first, second, third);
        if (result != null) return result;
      }
    }
    return null;
  }

  MrzScanResult? _parseTd3(String line1, String line2) {
    if (line1.length != 44 || line2.length != 44) return null;
    final docNumber = _field(line2.substring(0, 9));
    final nationality = _field(line2.substring(10, 13));
    final birth = _date(line2.substring(13, 19));
    final expiry = _date(line2.substring(21, 27));
    final names = _names(line1.substring(5));
    final checks = MrzCheckResult(
      documentNumber: _check(line2.substring(0, 9), line2.substring(9, 10)),
      birthDate: _check(line2.substring(13, 19), line2.substring(19, 20)),
      expiryDate: _check(line2.substring(21, 27), line2.substring(27, 28)),
      composite: _check(
        line2.substring(0, 10) +
            line2.substring(13, 20) +
            line2.substring(21, 43),
        line2.substring(43, 44),
      ),
    );
    return _buildResult(
      format: 'TD3',
      rawLines: [line1, line2],
      documentCode: _field(line1.substring(0, 2)),
      documentType: _mapDocumentType(line1.substring(0, 2)),
      firstName: names.firstName,
      lastName: names.lastName,
      middleNames: names.middleNames,
      documentNumber: docNumber,
      nationality: nationality,
      issuingCountry: _field(line1.substring(2, 5)),
      dateOfBirth: birth,
      gender: _gender(line2.substring(20, 21)),
      dateOfExpiry: expiry,
      optionalData: _field(line2.substring(28, 42)),
      personalNumber: _field(line2.substring(28, 42)),
      checks: checks,
    );
  }

  MrzScanResult? _parseTd2(String line1, String line2) {
    if (line1.length != 36 || line2.length != 36) return null;
    final docNumber = _field(line2.substring(0, 9));
    final nationality = _field(line2.substring(10, 13));
    final birth = _date(line2.substring(13, 19));
    final expiry = _date(line2.substring(21, 27));
    final names = _names(line1.substring(5));
    final checks = MrzCheckResult(
      documentNumber: _check(line2.substring(0, 9), line2.substring(9, 10)),
      birthDate: _check(line2.substring(13, 19), line2.substring(19, 20)),
      expiryDate: _check(line2.substring(21, 27), line2.substring(27, 28)),
      composite: _check(
        line2.substring(0, 10) +
            line2.substring(13, 20) +
            line2.substring(21, 35),
        line2.substring(35, 36),
      ),
    );
    return _buildResult(
      format: 'TD2',
      rawLines: [line1, line2],
      documentCode: _field(line1.substring(0, 2)),
      documentType: _mapDocumentType(line1.substring(0, 2)),
      firstName: names.firstName,
      lastName: names.lastName,
      middleNames: names.middleNames,
      documentNumber: docNumber,
      nationality: nationality,
      issuingCountry: _field(line1.substring(2, 5)),
      dateOfBirth: birth,
      gender: _gender(line2.substring(20, 21)),
      dateOfExpiry: expiry,
      optionalData: _field(line2.substring(28, 35)),
      personalNumber: _field(line2.substring(28, 35)),
      checks: checks,
    );
  }

  MrzScanResult? _parseTd1(String line1, String line2, String line3) {
    if (line1.length != 30 || line2.length != 30 || line3.length != 30) {
      return null;
    }
    final docNumber = _field(line1.substring(5, 14));
    final nationality = _field(line2.substring(15, 18));
    final birth = _date(line2.substring(0, 6));
    final expiry = _date(line2.substring(8, 14));
    final names = _names(line3);
    final checks = MrzCheckResult(
      documentNumber: _check(line1.substring(5, 14), line1.substring(14, 15)),
      birthDate: _check(line2.substring(0, 6), line2.substring(6, 7)),
      expiryDate: _check(line2.substring(8, 14), line2.substring(14, 15)),
      composite: _check(
        line1.substring(5, 30) +
            line2.substring(0, 7) +
            line2.substring(8, 15) +
            line2.substring(18, 29),
        line2.substring(29, 30),
      ),
    );
    return _buildResult(
      format: 'TD1',
      rawLines: [line1, line2, line3],
      documentCode: _field(line1.substring(0, 2)),
      documentType: _mapDocumentType(line1.substring(0, 2)),
      firstName: names.firstName,
      lastName: names.lastName,
      middleNames: names.middleNames,
      documentNumber: docNumber,
      nationality: nationality,
      issuingCountry: _field(line1.substring(2, 5)),
      dateOfBirth: birth,
      gender: _gender(line2.substring(7, 8)),
      dateOfExpiry: expiry,
      optionalData: _field(line1.substring(15, 30)),
      personalNumber: _field(line2.substring(18, 29)),
      checks: checks,
    );
  }

  MrzScanResult _buildResult({
    required String format,
    required List<String> rawLines,
    required String? documentCode,
    required String? documentType,
    required String? firstName,
    required String? lastName,
    required String? middleNames,
    required String? documentNumber,
    required String? nationality,
    required String? issuingCountry,
    required String? dateOfBirth,
    required String? gender,
    required String? dateOfExpiry,
    required String? optionalData,
    required String? personalNumber,
    required MrzCheckResult checks,
  }) {
    final correctedCharacterCount = 0;
    return MrzScanResult(
      format: format,
      rawLines: rawLines,
      cleanedLines: rawLines,
      normalizedText: rawLines.join('\n'),
      documentCode: documentCode,
      documentType: documentType,
      firstName: firstName,
      lastName: lastName,
      middleNames: middleNames,
      documentNumber: documentNumber,
      nationality: nationality,
      nationalityCode: nationality,
      issuingCountry: issuingCountry,
      dateOfBirth: dateOfBirth,
      gender: gender,
      dateOfExpiry: dateOfExpiry,
      optionalData: optionalData,
      personalNumber: personalNumber,
      checks: checks,
      errors: _errors(checks),
      correctedCharacterCount: correctedCharacterCount,
      confidence: _confidence(checks),
    );
  }

  bool _check(String value, String digit) => _checksum(value) == digit;

  String _checksum(String value) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < value.length; i++) {
      sum += _charValue(value[i]) * weights[i % 3];
    }
    return (sum % 10).toString();
  }

  int _charValue(String char) {
    final code = char.codeUnitAt(0);
    if (code >= 48 && code <= 57) return code - 48;
    if (char == '<') return 0;
    return code - 55;
  }

  String _normalizeMrzLine(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^A-Z0-9<]'), '');
  }

  String _pad(String value, int length) {
    if (value.length >= length) return value.substring(0, length);
    return value.padRight(length, '<');
  }

  String? _field(String value) {
    final cleaned = value
        .replaceAll('<', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned.toUpperCase();
  }

  String? _gender(String value) {
    final cleaned = value.trim().toUpperCase();
    if (cleaned == 'M' || cleaned == 'F' || cleaned == 'X') return cleaned;
    return null;
  }

  String? _date(String value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return null;
    final yy = int.parse(value.substring(0, 2));
    final mm = int.parse(value.substring(2, 4));
    final dd = int.parse(value.substring(4, 6));
    final now = DateTime.now();
    final c2000 = DateTime(2000 + yy, mm, dd);
    final c1900 = DateTime(1900 + yy, mm, dd);
    final chosen = c2000.isBefore(now.add(const Duration(days: 1)))
        ? c2000
        : c1900;
    return '${chosen.day.toString().padLeft(2, '0')}.${chosen.month.toString().padLeft(2, '0')}.${chosen.year}';
  }

  String? _mapDocumentType(String code) {
    final clean = code.replaceAll('<', '').trim().toUpperCase();
    if (clean == 'P') return 'passport';
    if (clean == 'I' || clean == 'A' || clean == 'C') return 'nationalIdCard';
    return null;
  }

  MrzNameParts _names(String value) {
    final parts = value.split('<<');
    final lastName = _field(parts.isNotEmpty ? parts.first : '');
    final givenNames = parts.length > 1
        ? _field(parts.sublist(1).join(' '))
        : null;
    if (givenNames == null) {
      return MrzNameParts(lastName: lastName);
    }
    final tokens = givenNames.split(' ');
    return MrzNameParts(
      lastName: lastName,
      firstName: tokens.first,
      middleNames: tokens.length > 1 ? tokens.sublist(1).join(' ') : null,
    );
  }

  List<String> _errors(MrzCheckResult checks) {
    final errors = <String>[];
    if (!checks.documentNumber) errors.add('documentNumberCheckFailed');
    if (!checks.birthDate) errors.add('birthDateCheckFailed');
    if (!checks.expiryDate) errors.add('expiryDateCheckFailed');
    if (!checks.composite) errors.add('compositeCheckFailed');
    return errors;
  }

  double _confidence(MrzCheckResult checks) {
    final passCount = [
      checks.documentNumber,
      checks.birthDate,
      checks.expiryDate,
      checks.composite,
    ].where((value) => value).length;
    return (0.55 + passCount * 0.1).clamp(0.0, 0.99).toDouble();
  }
}

class MrzNameParts {
  const MrzNameParts({this.firstName, this.middleNames, this.lastName});

  final String? firstName;
  final String? middleNames;
  final String? lastName;
}
