class MrzCheckResult {
  const MrzCheckResult({
    required this.documentNumber,
    required this.birthDate,
    required this.expiryDate,
    required this.composite,
  });

  final bool documentNumber;
  final bool birthDate;
  final bool expiryDate;
  final bool composite;

  bool get allPassed => documentNumber && birthDate && expiryDate && composite;
}

class MrzScanResult {
  const MrzScanResult({
    required this.format,
    required this.rawLines,
    required this.cleanedLines,
    required this.normalizedText,
    required this.documentCode,
    required this.documentType,
    required this.firstName,
    required this.lastName,
    required this.middleNames,
    required this.documentNumber,
    required this.nationality,
    required this.nationalityCode,
    required this.issuingCountry,
    required this.dateOfBirth,
    required this.gender,
    required this.dateOfExpiry,
    required this.optionalData,
    required this.personalNumber,
    required this.checks,
    required this.errors,
    required this.correctedCharacterCount,
    required this.confidence,
  });

  final String format;
  final List<String> rawLines;
  final List<String> cleanedLines;
  final String normalizedText;
  final String? documentCode;
  final String? documentType;
  final String? firstName;
  final String? lastName;
  final String? middleNames;
  final String? documentNumber;
  final String? nationality;
  final String? nationalityCode;
  final String? issuingCountry;
  final String? dateOfBirth;
  final String? gender;
  final String? dateOfExpiry;
  final String? optionalData;
  final String? personalNumber;
  final MrzCheckResult checks;
  final List<String> errors;
  final int correctedCharacterCount;
  final double confidence;

  bool get allChecksPassed => checks.allPassed;
  bool get requiresManualReview => !allChecksPassed;
}
