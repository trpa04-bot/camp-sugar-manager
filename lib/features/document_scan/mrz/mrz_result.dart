import 'mrz_type.dart';

class MrzResult {
  const MrzResult({
    required this.type,
    required this.documentCode,
    required this.issuingCountry,
    required this.documentNumber,
    required this.surname,
    required this.givenNames,
    required this.nationality,
    required this.dateOfBirth,
    required this.sex,
    required this.expiryDate,
    required this.personalNumber,
    required this.rawLines,
    required this.validDocumentNumberChecksum,
    required this.validBirthDateChecksum,
    required this.validExpiryDateChecksum,
    required this.validCompositeChecksum,
    required this.confidence,
    required this.warnings,
  });

  final MrzType type;
  final String? documentCode;
  final String? issuingCountry;
  final String? documentNumber;
  final String? surname;
  final String? givenNames;
  final String? nationality;
  final String? dateOfBirth;
  final String? sex;
  final String? expiryDate;
  final String? personalNumber;
  final List<String> rawLines;
  final bool validDocumentNumberChecksum;
  final bool validBirthDateChecksum;
  final bool validExpiryDateChecksum;
  final bool validCompositeChecksum;
  final double confidence;
  final List<String> warnings;

  bool get isHighTrust =>
      validDocumentNumberChecksum &&
      validBirthDateChecksum &&
      validExpiryDateChecksum &&
      validCompositeChecksum;

  factory MrzResult.empty({
    required List<String> rawLines,
    required List<String> warnings,
  }) {
    return MrzResult(
      type: MrzType.unknown,
      documentCode: null,
      issuingCountry: null,
      documentNumber: null,
      surname: null,
      givenNames: null,
      nationality: null,
      dateOfBirth: null,
      sex: null,
      expiryDate: null,
      personalNumber: null,
      rawLines: rawLines,
      validDocumentNumberChecksum: false,
      validBirthDateChecksum: false,
      validExpiryDateChecksum: false,
      validCompositeChecksum: false,
      confidence: 0,
      warnings: warnings,
    );
  }
}
