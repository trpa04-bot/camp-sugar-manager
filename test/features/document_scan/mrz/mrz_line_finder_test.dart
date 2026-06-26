import 'package:camp_sugar_manager/features/document_scan/mrz/mrz_line_finder.dart';
import 'package:camp_sugar_manager/features/document_scan/mrz/mrz_parser.dart';
import 'package:camp_sugar_manager/features/document_scan/mrz/mrz_type.dart';
import 'package:camp_sugar_manager/features/document_scan/mrz/mrz_validator.dart';
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
  group('MrzLineFinder', () {
    const finder = MrzLineFinder();

    test('finds TD3 lines surrounded by human-readable OCR text', () {
      final mrz = _buildTd3();
      final ocrText =
          'REPUBLIKA HRVATSKA\nPUTOVNICA / PASSPORT\nSurname: TESTER\n'
          '${mrz[0]}\n${mrz[1]}\nPotpis nositelja';

      final candidate = finder.find(ocrText);
      expect(candidate, isNotNull);
      expect(candidate!.type, MrzType.td3);
      expect(candidate.lines.length, 2);
      expect(candidate.lines[0].length, 44);
      expect(candidate.lines[1].length, 44);
    });

    test('cleans stray spaces and lowercase characters in MRZ rows', () {
      final mrz = _buildTd3();
      // Inject spaces and lowercase noise, as a real OCR engine might.
      final dirty1 = mrz[0].split('').join(' ').toLowerCase();
      final ocrText = '$dirty1\n${mrz[1]}';

      final candidate = finder.find(ocrText);
      expect(candidate, isNotNull);
      expect(candidate!.lines[0], mrz[0]);
    });

    test('result feeds cleanly into MrzParser and passes checksums', () {
      final mrz = _buildTd3();
      final candidate = finder.find('noise\n${mrz[0]}\n${mrz[1]}\nmore noise');
      expect(candidate, isNotNull);

      const parser = MrzParser();
      final result = parser.parse(candidate!.lines);
      expect(result.type, MrzType.td3);
      expect(result.surname, 'TESTER');
      expect(result.validDocumentNumberChecksum, isTrue);
      expect(result.validBirthDateChecksum, isTrue);
      expect(result.validExpiryDateChecksum, isTrue);
      expect(result.isHighTrust, isTrue);
    });

    test('returns null when no MRZ-like content is present', () {
      final candidate = finder.find(
        'Ovo je samo obican tekst\nbez ikakvog strojno citljivog zapisa.',
      );
      expect(candidate, isNull);
    });

    test('pads a slightly short TD3 second row to 44 characters', () {
      final mrz = _buildTd3();
      final shortSecond = mrz[1].substring(0, 42); // simulate clipped OCR
      final candidate = finder.find('${mrz[0]}\n$shortSecond');
      expect(candidate, isNotNull);
      expect(candidate!.lines[1].length, 44);
    });
  });
}
