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

List<String> _buildTd3({
  String documentNumber = 'L898902C3',
  String birth = '740812',
  String expiry = '120415',
  String surname = 'TESTER',
  String given = 'ALFA<BETA',
  String personal = 'ZE184226B<<<<<',
  String sex = 'F',
}) {
  final line1 = _pad('P<UTO$surname<<$given', 44);
  final docCheck = MrzValidator.computeCheckDigit(documentNumber);
  final birthCheck = MrzValidator.computeCheckDigit(birth);
  final expiryCheck = MrzValidator.computeCheckDigit(expiry);
  final personalCheck = MrzValidator.computeCheckDigit(personal);
  final compositeSeed =
      '$documentNumber$docCheck'
      '$birth$birthCheck'
      '$expiry$expiryCheck'
      '$personal$personalCheck';
  final compositeCheck = MrzValidator.computeCheckDigit(compositeSeed);
  final line2 =
      '$documentNumber$docCheck'
      'UTO'
      '$birth$birthCheck'
      '$sex'
      '$expiry$expiryCheck'
      '$personal$personalCheck$compositeCheck';
  return [line1, line2];
}

List<String> _buildTd2({
  String documentNumber = 'XK1234567',
  String birth = '900101',
  String expiry = '300101',
  String surname = 'SAMPLE',
  String given = 'GAMMA<DELTA',
  String optional = 'ABC1234',
  String sex = 'M',
}) {
  final line1 = _pad('I<UT0$surname<<$given', 36).replaceFirst('UT0', 'UTO');
  final docCheck = MrzValidator.computeCheckDigit(documentNumber);
  final birthCheck = MrzValidator.computeCheckDigit(birth);
  final expiryCheck = MrzValidator.computeCheckDigit(expiry);
  final compositeSeed =
      '$documentNumber$docCheck'
      '$birth$birthCheck'
      '$expiry$expiryCheck'
      '$optional';
  final compositeCheck = MrzValidator.computeCheckDigit(compositeSeed);
  final line2 =
      '$documentNumber$docCheck'
      'UTO'
      '$birth$birthCheck'
      '$sex'
      '$expiry$expiryCheck'
      '$optional$compositeCheck';
  return [line1, line2];
}

List<String> _buildTd1({
  String documentNumber = 'ABC123456',
  String birth = '900101',
  String expiry = '300101',
  String surname = 'DE<LA<CRUZ',
  String given = 'ANA<MARIA',
  String optional1 = '<<<<<<<<<<<<<<<',
  String optional2 = '<<<<<<<<<<<',
  String sex = 'F',
}) {
  final line1DocCheck = MrzValidator.computeCheckDigit(documentNumber);
  final line1 = 'IDUTO$documentNumber$line1DocCheck$optional1';
  final birthCheck = MrzValidator.computeCheckDigit(birth);
  final expiryCheck = MrzValidator.computeCheckDigit(expiry);
  final compositeSeed =
      '${line1.substring(5, 30)}'
      '$birth$birthCheck'
      '$expiry$expiryCheck'
      '$optional2';
  final compositeCheck = MrzValidator.computeCheckDigit(compositeSeed);
  final line2 =
      '$birth$birthCheck$sex$expiry$expiryCheck'
      'UTO'
      '$optional2$compositeCheck';
  final line3 = _pad('$surname<<$given', 30);
  return [line1, line2, line3];
}

void main() {
  const parser = MrzParser();

  test('valid TD1', () {
    final result = parser.parse(_buildTd1());
    expect(result.type, MrzType.td1);
    expect(result.validDocumentNumberChecksum, isTrue);
    expect(result.validBirthDateChecksum, isTrue);
    expect(result.validExpiryDateChecksum, isTrue);
    expect(result.validCompositeChecksum, isTrue);
  });

  test('valid TD2', () {
    final result = parser.parse(_buildTd2());
    expect(result.type, MrzType.td2);
    expect(result.validCompositeChecksum, isTrue);
    expect(result.surname, 'SAMPLE');
    expect(result.givenNames, 'GAMMA DELTA');
  });

  test('valid TD3', () {
    final result = parser.parse(_buildTd3());
    expect(result.type, MrzType.td3);
    expect(result.validCompositeChecksum, isTrue);
    expect(result.documentCode, 'P');
  });

  test('invalid row length', () {
    final lines = _buildTd3();
    final bad = [lines[0], lines[1].substring(0, 43)];
    final result = parser.parse(bad);
    expect(result.type, MrzType.unknown);
    expect(result.warnings, contains('invalid_row_length'));
  });

  test('missing MRZ row', () {
    final lines = _buildTd3();
    final result = parser.parse([lines.first]);
    expect(result.type, MrzType.unknown);
    expect(result.warnings, contains('missing_mrz_row'));
  });

  test('O/0 OCR grešku ispravlja na numeričkim pozicijama', () {
    final lines = _buildTd3();
    final withO = '${lines[1].substring(0, 15)}O${lines[1].substring(16)}';
    final result = parser.parse([lines[0], withO]);
    expect(result.validBirthDateChecksum, isTrue);
  });

  test('I/1 OCR grešku ispravlja na numeričkim pozicijama', () {
    final lines = _buildTd3();
    final withI = '${lines[1].substring(0, 21)}I${lines[1].substring(22)}';
    final result = parser.parse([lines[0], withI]);
    expect(result.validExpiryDateChecksum, isTrue);
  });

  test('neispravan document checksum', () {
    final lines = _buildTd3();
    final tampered = '${lines[1].substring(0, 9)}0${lines[1].substring(10)}';
    final result = parser.parse([lines[0], tampered]);
    expect(result.validDocumentNumberChecksum, isFalse);
    expect(result.warnings, contains('invalid_document_checksum'));
  });

  test('neispravan birth checksum', () {
    final lines = _buildTd3();
    final tampered = '${lines[1].substring(0, 19)}0${lines[1].substring(20)}';
    final result = parser.parse([lines[0], tampered]);
    expect(result.validBirthDateChecksum, isFalse);
    expect(result.warnings, contains('invalid_birth_checksum'));
  });

  test('neispravan expiry checksum', () {
    final lines = _buildTd3();
    final tampered = '${lines[1].substring(0, 27)}0${lines[1].substring(28)}';
    final result = parser.parse([lines[0], tampered]);
    expect(result.validExpiryDateChecksum, isFalse);
    expect(result.warnings, contains('invalid_expiry_checksum'));
  });

  test('višestruka imena', () {
    final result = parser.parse(_buildTd3(given: 'ANA<MARIA<IVANA'));
    expect(result.givenNames, 'ANA MARIA IVANA');
  });

  test('dvostruko prezime', () {
    final result = parser.parse(_buildTd1(surname: 'DE<LA<CRUZ'));
    expect(result.surname, 'DE LA CRUZ');
  });

  test('znakove << između prezimena i imena', () {
    final result = parser.parse(_buildTd3(surname: 'BETA', given: 'GAMA'));
    expect(result.surname, 'BETA');
    expect(result.givenNames, 'GAMA');
  });

  test('prazna opcionalna polja', () {
    final result = parser.parse(_buildTd3(personal: '<<<<<<<<<<<<<<'));
    expect(result.personalNumber, isNull);
  });
}
