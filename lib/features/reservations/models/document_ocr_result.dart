class DocumentOcrParsedData {
  const DocumentOcrParsedData({
    this.documentCode,
    this.documentKind,
    this.firstName,
    this.middleNames,
    this.lastName,
    this.dateOfBirth,
    this.nationality,
    this.nationalityCode,
    this.nationalityDisplayName,
    this.documentType,
    this.documentNumber,
    this.documentExpiryDate,
    this.issueDate,
    this.gender,
    this.issuingCountry,
    this.optionalData,
    this.personalNumber,
    this.mrzText,
    this.confidence,
  });

  final String? documentCode;
  final String? documentKind;
  final String? firstName;
  final String? middleNames;
  final String? lastName;
  final String? dateOfBirth;
  final String? nationality;
  final String? nationalityCode;
  final String? nationalityDisplayName;
  final String? documentType;
  final String? documentNumber;
  final String? documentExpiryDate;
  final String? issueDate;
  final String? gender;
  final String? issuingCountry;
  final String? optionalData;
  final String? personalNumber;
  final String? mrzText;
  final double? confidence;

  factory DocumentOcrParsedData.fromMap(Map<String, dynamic> map) {
    return DocumentOcrParsedData(
      firstName: _asString(map['firstName']),
      lastName: _asString(map['lastName']),
      dateOfBirth: _asString(map['dateOfBirth']),
      nationality: _asString(map['nationality']),
      nationalityCode: _asString(map['nationalityCode']),
      nationalityDisplayName: _asString(map['nationalityDisplayName']),
      documentType: _asString(map['documentType']),
      documentCode: _asString(map['documentCode']),
      documentKind: _asString(map['documentKind']),
      documentNumber: _asString(map['documentNumber']),
      documentExpiryDate: _asString(map['documentExpiryDate']),
      issueDate: _asString(map['issueDate']),
      middleNames: _asString(map['middleNames']),
      gender: _asString(map['gender']),
      issuingCountry: _asString(map['issuingCountry']),
      optionalData: _asString(map['optionalData']),
      personalNumber: _asString(map['personalNumber']),
      mrzText: _asString(map['mrzText']),
      confidence: _asDouble(map['confidence']),
    );
  }

  static String? _asString(dynamic value) {
    final text = (value as String?)?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }
}

class DocumentScanField {
  const DocumentScanField({
    this.value,
    this.confidence,
    this.sourceImageId,
    this.sourceType,
    this.needsReview = false,
  });

  final String? value;
  final double? confidence;
  final String? sourceImageId;
  final String? sourceType;
  final bool needsReview;

  factory DocumentScanField.fromMap(Map<String, dynamic> map) {
    return DocumentScanField(
      value: (map['value'] as String?)?.trim(),
      confidence: DocumentOcrParsedData._asDouble(map['confidence']),
      sourceImageId: (map['sourceImageId'] as String?)?.trim(),
      sourceType: (map['sourceType'] as String?)?.trim(),
      needsReview: map['needsReview'] as bool? ?? false,
    );
  }
}

class DocumentScanMergedResult {
  const DocumentScanMergedResult({
    required this.parsed,
    required this.fields,
    required this.conflicts,
    this.debug,
  });

  final DocumentOcrParsedData parsed;
  final Map<String, DocumentScanField> fields;
  final List<String> conflicts;
  final Map<String, DocumentScanFieldDebug>? debug;

  factory DocumentScanMergedResult.fromMap(Map<String, dynamic> map) {
    final parsedMap =
        (map['parsed'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final fieldsMap =
        (map['fields'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final resolvedFields = <String, DocumentScanField>{};
    fieldsMap.forEach((key, value) {
      if (value is Map) {
        resolvedFields[key] = DocumentScanField.fromMap(
          value.cast<String, dynamic>(),
        );
      }
    });

    final debugMap = (map['debug'] as Map?)?.cast<String, dynamic>();
    final resolvedDebug = <String, DocumentScanFieldDebug>{};
    debugMap?.forEach((key, value) {
      if (value is Map) {
        resolvedDebug[key] = DocumentScanFieldDebug.fromMap(
          value.cast<String, dynamic>(),
        );
      }
    });

    return DocumentScanMergedResult(
      parsed: DocumentOcrParsedData.fromMap(parsedMap),
      fields: resolvedFields,
      conflicts: ((map['conflicts'] as List?) ?? const <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      debug: resolvedDebug.isEmpty ? null : resolvedDebug,
    );
  }
}

class DocumentScanFieldDebug {
  const DocumentScanFieldDebug({
    this.mrzNormalizedValue,
    this.rawVisualCandidate,
    this.visualNormalizedValue,
    this.visualValid,
    this.rejectionReason,
    this.visualConfidence,
    this.visualConfidenceBeforeValidation,
    this.visualConfidenceAfterValidation,
    this.visualSourceType,
  });

  final String? mrzNormalizedValue;
  final String? rawVisualCandidate;
  final String? visualNormalizedValue;
  final bool? visualValid;
  final String? rejectionReason;
  final double? visualConfidence;
  final double? visualConfidenceBeforeValidation;
  final double? visualConfidenceAfterValidation;
  final String? visualSourceType;

  factory DocumentScanFieldDebug.fromMap(Map<String, dynamic> map) {
    return DocumentScanFieldDebug(
      mrzNormalizedValue: DocumentOcrParsedData._asString(
        map['mrzNormalizedValue'],
      ),
      rawVisualCandidate: DocumentOcrParsedData._asString(
        map['rawVisualCandidate'],
      ),
      visualNormalizedValue: DocumentOcrParsedData._asString(
        map['visualNormalizedValue'],
      ),
      visualValid: map['visualValid'] as bool?,
      rejectionReason: DocumentOcrParsedData._asString(map['rejectionReason']),
      visualConfidence: DocumentOcrParsedData._asDouble(
        map['visualConfidence'],
      ),
      visualConfidenceBeforeValidation: DocumentOcrParsedData._asDouble(
        map['visualConfidenceBeforeValidation'],
      ),
      visualConfidenceAfterValidation: DocumentOcrParsedData._asDouble(
        map['visualConfidenceAfterValidation'],
      ),
      visualSourceType: DocumentOcrParsedData._asString(
        map['visualSourceType'],
      ),
    );
  }
}

class DocumentImageOcrResult {
  const DocumentImageOcrResult({
    required this.imageId,
    required this.storagePath,
    required this.documentSide,
    required this.rawText,
    required this.parsed,
  });

  final String imageId;
  final String storagePath;
  final String documentSide;
  final String rawText;
  final DocumentOcrParsedData parsed;

  factory DocumentImageOcrResult.fromMap(Map<String, dynamic> map) {
    final parsedMap =
        (map['parsed'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return DocumentImageOcrResult(
      imageId: (map['imageId'] as String?) ?? '',
      storagePath: (map['storagePath'] as String?) ?? '',
      documentSide: (map['documentSide'] as String?) ?? 'additional',
      rawText: (map['rawText'] as String?) ?? '',
      parsed: DocumentOcrParsedData.fromMap(parsedMap),
    );
  }
}

class DocumentOcrResult {
  const DocumentOcrResult({
    required this.rawText,
    required this.parsed,
    this.images = const <DocumentImageOcrResult>[],
    this.merged,
  });

  final String rawText;
  final DocumentOcrParsedData parsed;
  final List<DocumentImageOcrResult> images;
  final DocumentScanMergedResult? merged;

  factory DocumentOcrResult.fromMap(Map<String, dynamic> map) {
    final rawText = (map['rawText'] as String?) ?? '';
    final parsed =
        (map['parsed'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return DocumentOcrResult(
      rawText: rawText,
      parsed: DocumentOcrParsedData.fromMap(parsed),
      images: ((map['images'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (entry) =>
                DocumentImageOcrResult.fromMap(entry.cast<String, dynamic>()),
          )
          .toList(growable: false),
      merged: map['merged'] is Map
          ? DocumentScanMergedResult.fromMap(
              (map['merged'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}
