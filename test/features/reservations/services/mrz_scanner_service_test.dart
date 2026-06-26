import 'package:camp_sugar_manager/features/document_scan/mrz/mrz_validator.dart';
import 'package:camp_sugar_manager/features/reservations/services/mrz_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _pad(String value, int length) {
  if (value.length >= length) {
    return value.substring(0, length);
  }
  return value.padRight(length, '<');
}

List<String> _buildTd3() {
  const documentNumber = 'L898902C3';
  const birth = '740812';
  const expiry = '120415';
  const personal = 'ZE184226B<<<<<';
  const sex = 'F';
  final line1 = _pad('P<UTOTESTER<<ALFA<BETA', 44);
  final docCheck = MrzValidator.computeCheckDigit(documentNumber);
  final birthCheck = MrzValidator.computeCheckDigit(birth);
  final expiryCheck = MrzValidator.computeCheckDigit(expiry);
  final personalCheck = MrzValidator.computeCheckDigit(personal);
  final compositeSeed =
      '$documentNumber$docCheck$birth$birthCheck$expiry$expiryCheck$personal$personalCheck';
  final compositeCheck = MrzValidator.computeCheckDigit(compositeSeed);
  final line2 =
      '$documentNumber${docCheck}UTO$birth$birthCheck$sex$expiry$expiryCheck$personal$personalCheck$compositeCheck';
  return [line1, line2];
}

void main() {
  group('MrzScannerService.scanRecognizedText (web-safe)', () {
    final service = MrzScannerService();

    test('parses a TD3 passport from noisy OCR text', () {
      final mrz = _buildTd3();
      final ocrText =
          'REPUBLIKA HRVATSKA / PASSPORT\nTESTER ALFA BETA\n'
          '${mrz[0]}\n${mrz[1]}';

      final result = service.scanRecognizedText(ocrText);

      expect(result.format, 'TD3');
      expect(result.documentType, 'passport');
      expect(result.lastName, 'TESTER');
      expect(result.firstName, 'ALFA');
      expect(result.middleNames, 'BETA');
      expect(result.documentNumber, 'L898902C3');
      expect(result.gender, 'F');
      // Date is converted to the app display format dd.MM.yyyy.
      expect(result.dateOfBirth, '12.08.1974');
      expect(result.dateOfExpiry, '15.04.2012');
      expect(result.checks.allPassed, isTrue);
      expect(result.confidence, greaterThan(0.8));
    });

    test('throws a clear error when no MRZ is present', () {
      expect(
        () => service.scanRecognizedText('Samo obican tekst bez MRZ zapisa.'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
