import 'document_ocr_result.dart';

enum DocumentAcceptanceStatus {
  accepted,
  acceptedWithReview,
  manualOnly,
  rejected,
}

String countryDisplayLabelHr({String? nationalityCode, String? fallback}) {
  final code = (nationalityCode ?? '').trim().toUpperCase();
  if (code.isEmpty) {
    return (fallback ?? '').trim();
  }
  final name = _countryNameHr[code];
  if (name == null) {
    return code;
  }
  return '$name ($code)';
}

String documentTypeDisplayLabelHr(String? value) {
  switch ((value ?? '').trim()) {
    case 'passport':
      return 'Putovnica';
    case 'nationalIdCard':
      return 'Osobna iskaznica';
    case 'residencePermit':
      return 'Boravišna iskaznica';
    case 'drivingLicence':
      return 'Vozačka dozvola';
    default:
      return 'Nepoznati dokument';
  }
}

DocumentAcceptanceStatus resolveAcceptanceStatus({
  required DocumentOcrParsedData parsed,
  required Map<String, DocumentScanField> fields,
  required List<String> conflicts,
}) {
  final kind = (parsed.documentKind ?? parsed.documentType ?? '').trim();
  final hasDocumentNumber = (parsed.documentNumber ?? '').trim().isNotEmpty;

  // For passports: only document number is required (can redo names manually)
  if (kind == 'passport') {
    if (!hasDocumentNumber) {
      return DocumentAcceptanceStatus.rejected;
    }
    // Passport with document number but missing names = manual only
    return DocumentAcceptanceStatus.manualOnly;
  }

  final hasCoreData =
      (parsed.firstName ?? '').trim().isNotEmpty &&
      (parsed.lastName ?? '').trim().isNotEmpty &&
      hasDocumentNumber;
  if (!hasCoreData) {
    return DocumentAcceptanceStatus.rejected;
  }

  if (kind == 'drivingLicence') {
    return DocumentAcceptanceStatus.manualOnly;
  }
  if (kind == 'unknownIdentityDocument') {
    return DocumentAcceptanceStatus.manualOnly;
  }

  const criticalReviewFields = <String>{
    'firstName',
    'lastName',
    'documentNumber',
    'dateOfBirth',
    'documentExpiryDate',
    'nationalityCode',
  };
  final hasFieldReview = fields.entries.any(
    (entry) =>
        criticalReviewFields.contains(entry.key) && entry.value.needsReview,
  );
  if (conflicts.isNotEmpty || hasFieldReview) {
    return DocumentAcceptanceStatus.acceptedWithReview;
  }
  return DocumentAcceptanceStatus.accepted;
}

String acceptanceMessageHr(DocumentAcceptanceStatus status) {
  switch (status) {
    case DocumentAcceptanceStatus.accepted:
      return 'Dokument je uspješno prepoznat i valjan.';
    case DocumentAcceptanceStatus.acceptedWithReview:
      return 'Dokument je prepoznat, ali je potrebna ručna provjera.';
    case DocumentAcceptanceStatus.manualOnly:
      return 'Dokument zahtijeva ručnu provjeru prije potvrde.';
    case DocumentAcceptanceStatus.rejected:
      return 'Dokument nije moguće potvrditi. Potrebna je nova provjera.';
  }
}

const Map<String, String> _countryNameHr = <String, String>{
  'HRV': 'Hrvatska',
  'DEU': 'Njemačka',
  'ITA': 'Italija',
  'AUT': 'Austrija',
  'SVN': 'Slovenija',
  'POL': 'Poljska',
  'CZE': 'Češka',
  'SVK': 'Slovačka',
  'HUN': 'Mađarska',
  'FRA': 'Francuska',
  'NLD': 'Nizozemska',
  'BEL': 'Belgija',
  'ESP': 'Španjolska',
  'PRT': 'Portugal',
  'CHE': 'Švicarska',
  'GBR': 'Ujedinjeno Kraljevstvo',
  'USA': 'Sjedinjene Američke Države',
  'CAN': 'Kanada',
  'AUS': 'Australija',
};
