import 'mrz_cleaner.dart';
import 'mrz_result.dart';
import 'mrz_type.dart';
import 'mrz_validator.dart';

class MrzParser {
  const MrzParser();

  MrzResult parse(List<String> lines) {
    final cleaned = lines
        .map((line) => line.toUpperCase().replaceAll(RegExp(r'\s+'), ''))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    if (cleaned.isEmpty) {
      return MrzResult.empty(rawLines: lines, warnings: ['missing_mrz_row']);
    }

    final type = _detectType(cleaned);
    if (type == MrzType.unknown) {
      final warnings = <String>[];
      if (cleaned.length < 2) {
        warnings.add('missing_mrz_row');
      }
      warnings.add('invalid_row_length');
      return MrzResult.empty(rawLines: cleaned, warnings: warnings);
    }

    if (cleaned.length < type.rowCount) {
      return MrzResult.empty(rawLines: cleaned, warnings: ['missing_mrz_row']);
    }

    final activeLines = cleaned.take(type.rowCount).toList(growable: false);
    if (activeLines.any((line) => line.length != type.rowLength)) {
      return MrzResult.empty(
        rawLines: activeLines,
        warnings: ['invalid_row_length'],
      );
    }

    switch (type) {
      case MrzType.td1:
        return _parseTd1(activeLines);
      case MrzType.td2:
        return _parseTd2(activeLines);
      case MrzType.td3:
        return _parseTd3(activeLines);
      case MrzType.unknown:
        return MrzResult.empty(
          rawLines: activeLines,
          warnings: ['unsupported'],
        );
    }
  }

  MrzType _detectType(List<String> lines) {
    if (lines.length >= 3 &&
        lines[0].length == 30 &&
        lines[1].length == 30 &&
        lines[2].length == 30) {
      return MrzType.td1;
    }
    if (lines.length >= 2 && lines[0].length == 36 && lines[1].length == 36) {
      return MrzType.td2;
    }
    if (lines.length >= 2 && lines[0].length == 44 && lines[1].length == 44) {
      return MrzType.td3;
    }
    return MrzType.unknown;
  }

  MrzResult _parseTd3(List<String> lines) {
    final line1 = lines[0];
    final line2 = lines[1];

    final documentCode = _normalizeField(line1.substring(0, 2));
    final issuingCountry = _normalizeField(
      MrzCleaner.cleanForLetters(line1.substring(2, 5)),
    );

    final rawDocumentNumber = line2.substring(0, 9);
    final documentNumber = _normalizeField(rawDocumentNumber);
    final documentCheck = MrzCleaner.cleanForDigits(line2.substring(9, 10));

    final nationality = _normalizeField(
      MrzCleaner.cleanForLetters(line2.substring(10, 13)),
    );

    final birthRaw = MrzCleaner.cleanByMask(line2.substring(13, 19), 'DDDDDD');
    final birthCheck = MrzCleaner.cleanForDigits(line2.substring(19, 20));

    final sex = _normalizeField(
      MrzCleaner.cleanForLetters(line2.substring(20, 21)),
    );

    final expiryRaw = MrzCleaner.cleanByMask(line2.substring(21, 27), 'DDDDDD');
    final expiryCheck = MrzCleaner.cleanForDigits(line2.substring(27, 28));

    final personalRaw = line2.substring(28, 42);
    final personalNumber = _normalizeField(personalRaw);
    final personalCheck = MrzCleaner.cleanForDigits(line2.substring(42, 43));

    final compositeCheck = MrzCleaner.cleanForDigits(line2.substring(43, 44));

    final validDocument = MrzValidator.validateCheckDigit(
      rawDocumentNumber,
      documentCheck,
    );
    final validBirth = MrzValidator.validateCheckDigit(birthRaw, birthCheck);
    final validExpiry = MrzValidator.validateCheckDigit(expiryRaw, expiryCheck);
    final validComposite = MrzValidator.validateCheckDigit(
      line2.substring(0, 10) +
          line2.substring(13, 20) +
          line2.substring(21, 43),
      compositeCheck,
    );

    final warnings = <String>[];
    if (!validDocument) {
      warnings.add('invalid_document_checksum');
    }
    if (!validBirth) {
      warnings.add('invalid_birth_checksum');
    }
    if (!validExpiry) {
      warnings.add('invalid_expiry_checksum');
    }
    if (!validComposite) {
      warnings.add('invalid_composite_checksum');
    }

    if (personalCheck != '<' &&
        !MrzValidator.validateCheckDigit(personalRaw, personalCheck)) {
      warnings.add('invalid_personal_number_checksum');
    }

    final names = _parseNames(line1.substring(5));

    return MrzResult(
      type: MrzType.td3,
      documentCode: documentCode,
      issuingCountry: issuingCountry,
      documentNumber: documentNumber,
      surname: names.surname,
      givenNames: names.givenNames,
      nationality: nationality,
      dateOfBirth: _parseDate(birthRaw, birth: true),
      sex: sex,
      expiryDate: _parseDate(expiryRaw, birth: false),
      personalNumber: personalNumber,
      rawLines: lines,
      validDocumentNumberChecksum: validDocument,
      validBirthDateChecksum: validBirth,
      validExpiryDateChecksum: validExpiry,
      validCompositeChecksum: validComposite,
      confidence: _calculateConfidence(
        validChecks: [validDocument, validBirth, validExpiry, validComposite],
        warnings: warnings,
      ),
      warnings: warnings,
    );
  }

  MrzResult _parseTd2(List<String> lines) {
    final line1 = lines[0];
    final line2 = lines[1];

    final documentCode = _normalizeField(line1.substring(0, 2));
    final issuingCountry = _normalizeField(
      MrzCleaner.cleanForLetters(line1.substring(2, 5)),
    );

    final rawDocumentNumber = line2.substring(0, 9);
    final documentCheck = MrzCleaner.cleanForDigits(line2.substring(9, 10));
    final nationality = _normalizeField(
      MrzCleaner.cleanForLetters(line2.substring(10, 13)),
    );

    final birthRaw = MrzCleaner.cleanByMask(line2.substring(13, 19), 'DDDDDD');
    final birthCheck = MrzCleaner.cleanForDigits(line2.substring(19, 20));

    final sex = _normalizeField(
      MrzCleaner.cleanForLetters(line2.substring(20, 21)),
    );

    final expiryRaw = MrzCleaner.cleanByMask(line2.substring(21, 27), 'DDDDDD');
    final expiryCheck = MrzCleaner.cleanForDigits(line2.substring(27, 28));

    final personalNumber = _normalizeField(line2.substring(28, 35));
    final compositeCheck = MrzCleaner.cleanForDigits(line2.substring(35, 36));

    final validDocument = MrzValidator.validateCheckDigit(
      rawDocumentNumber,
      documentCheck,
    );
    final validBirth = MrzValidator.validateCheckDigit(birthRaw, birthCheck);
    final validExpiry = MrzValidator.validateCheckDigit(expiryRaw, expiryCheck);
    final validComposite = MrzValidator.validateCheckDigit(
      line2.substring(0, 10) +
          line2.substring(13, 20) +
          line2.substring(21, 35),
      compositeCheck,
    );

    final warnings = <String>[];
    if (!validDocument) {
      warnings.add('invalid_document_checksum');
    }
    if (!validBirth) {
      warnings.add('invalid_birth_checksum');
    }
    if (!validExpiry) {
      warnings.add('invalid_expiry_checksum');
    }
    if (!validComposite) {
      warnings.add('invalid_composite_checksum');
    }

    final names = _parseNames(line1.substring(5));

    return MrzResult(
      type: MrzType.td2,
      documentCode: documentCode,
      issuingCountry: issuingCountry,
      documentNumber: _normalizeField(rawDocumentNumber),
      surname: names.surname,
      givenNames: names.givenNames,
      nationality: nationality,
      dateOfBirth: _parseDate(birthRaw, birth: true),
      sex: sex,
      expiryDate: _parseDate(expiryRaw, birth: false),
      personalNumber: personalNumber,
      rawLines: lines,
      validDocumentNumberChecksum: validDocument,
      validBirthDateChecksum: validBirth,
      validExpiryDateChecksum: validExpiry,
      validCompositeChecksum: validComposite,
      confidence: _calculateConfidence(
        validChecks: [validDocument, validBirth, validExpiry, validComposite],
        warnings: warnings,
      ),
      warnings: warnings,
    );
  }

  MrzResult _parseTd1(List<String> lines) {
    final line1 = lines[0];
    final line2 = lines[1];
    final line3 = lines[2];

    final documentCode = _normalizeField(line1.substring(0, 2));
    final issuingCountry = _normalizeField(
      MrzCleaner.cleanForLetters(line1.substring(2, 5)),
    );

    final rawDocumentNumber = line1.substring(5, 14);
    final documentCheck = MrzCleaner.cleanForDigits(line1.substring(14, 15));

    final birthRaw = MrzCleaner.cleanByMask(line2.substring(0, 6), 'DDDDDD');
    final birthCheck = MrzCleaner.cleanForDigits(line2.substring(6, 7));

    final sex = _normalizeField(
      MrzCleaner.cleanForLetters(line2.substring(7, 8)),
    );

    final expiryRaw = MrzCleaner.cleanByMask(line2.substring(8, 14), 'DDDDDD');
    final expiryCheck = MrzCleaner.cleanForDigits(line2.substring(14, 15));

    final nationality = _normalizeField(
      MrzCleaner.cleanForLetters(line2.substring(15, 18)),
    );

    final personalNumber = _normalizeField(line2.substring(18, 29));
    final compositeCheck = MrzCleaner.cleanForDigits(line2.substring(29, 30));

    final validDocument = MrzValidator.validateCheckDigit(
      rawDocumentNumber,
      documentCheck,
    );
    final validBirth = MrzValidator.validateCheckDigit(birthRaw, birthCheck);
    final validExpiry = MrzValidator.validateCheckDigit(expiryRaw, expiryCheck);
    final validComposite = MrzValidator.validateCheckDigit(
      line1.substring(5, 30) +
          line2.substring(0, 7) +
          line2.substring(8, 15) +
          line2.substring(18, 29),
      compositeCheck,
    );

    final warnings = <String>[];
    if (!validDocument) {
      warnings.add('invalid_document_checksum');
    }
    if (!validBirth) {
      warnings.add('invalid_birth_checksum');
    }
    if (!validExpiry) {
      warnings.add('invalid_expiry_checksum');
    }
    if (!validComposite) {
      warnings.add('invalid_composite_checksum');
    }

    final names = _parseNames(line3);

    return MrzResult(
      type: MrzType.td1,
      documentCode: documentCode,
      issuingCountry: issuingCountry,
      documentNumber: _normalizeField(rawDocumentNumber),
      surname: names.surname,
      givenNames: names.givenNames,
      nationality: nationality,
      dateOfBirth: _parseDate(birthRaw, birth: true),
      sex: sex,
      expiryDate: _parseDate(expiryRaw, birth: false),
      personalNumber: personalNumber,
      rawLines: lines,
      validDocumentNumberChecksum: validDocument,
      validBirthDateChecksum: validBirth,
      validExpiryDateChecksum: validExpiry,
      validCompositeChecksum: validComposite,
      confidence: _calculateConfidence(
        validChecks: [validDocument, validBirth, validExpiry, validComposite],
        warnings: warnings,
      ),
      warnings: warnings,
    );
  }

  ({String? surname, String? givenNames}) _parseNames(String raw) {
    final chunks = raw.split('<<');
    final surname = _normalizeField(chunks.isEmpty ? '' : chunks.first);
    final givenRaw = chunks.length <= 1 ? '' : chunks.sublist(1).join('<');
    final givenNames = _normalizeField(givenRaw.replaceAll('<', ' '));
    return (surname: surname, givenNames: givenNames);
  }

  String? _normalizeField(String value) {
    final normalized = value
        .replaceAll('<', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _parseDate(String value, {required bool birth}) {
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      return null;
    }
    final yy = int.parse(value.substring(0, 2));
    final mm = int.parse(value.substring(2, 4));
    final dd = int.parse(value.substring(4, 6));

    if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
      return null;
    }

    final nowYear = DateTime.now().year;
    final year = birth
        ? (yy > (nowYear % 100) ? 1900 + yy : 2000 + yy)
        : 2000 + yy;
    return '${year.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}-${dd.toString().padLeft(2, '0')}';
  }

  double _calculateConfidence({
    required List<bool> validChecks,
    required List<String> warnings,
  }) {
    final passed = validChecks.where((check) => check).length;
    final ratio = validChecks.isEmpty ? 0 : passed / validChecks.length;
    var score = 0.35 + (ratio * 0.6);
    if (warnings.any((w) => w.startsWith('invalid_'))) {
      score -= 0.1;
    }
    if (score < 0) {
      return 0;
    }
    if (score > 0.99) {
      return 0.99;
    }
    return score;
  }
}
