enum DocumentSide {
  frontIdCard,
  backIdCard,
  passport,
  additional;

  String get label {
    switch (this) {
      case DocumentSide.frontIdCard:
        return 'Prednja strana';
      case DocumentSide.backIdCard:
        return 'Stražnja strana';
      case DocumentSide.passport:
        return 'Putovnica';
      case DocumentSide.additional:
        return 'Dodatno';
    }
  }

  String get apiValue {
    switch (this) {
      case DocumentSide.frontIdCard:
        return 'frontIdCard';
      case DocumentSide.backIdCard:
        return 'backIdCard';
      case DocumentSide.passport:
        return 'passport';
      case DocumentSide.additional:
        return 'additional';
    }
  }

  static DocumentSide fromApiValue(String value) {
    switch (value) {
      case 'frontIdCard':
        return DocumentSide.frontIdCard;
      case 'backIdCard':
        return DocumentSide.backIdCard;
      case 'passport':
        return DocumentSide.passport;
      default:
        return DocumentSide.additional;
    }
  }
}

enum DocumentImageUploadStatus { pending, uploading, uploaded, failed }

enum DocumentImageOcrStatus { pending, processing, done, failed }

class DocumentImage {
  const DocumentImage({
    required this.id,
    required this.storagePath,
    required this.documentSide,
    required this.fileName,
    required this.contentType,
    required this.uploadStatus,
    required this.ocrStatus,
    this.rawText,
    this.mrzText,
    this.confidence,
    this.createdAt,
  });

  final String id;
  final String storagePath;
  final DocumentSide documentSide;
  final String fileName;
  final String contentType;
  final DocumentImageUploadStatus uploadStatus;
  final DocumentImageOcrStatus ocrStatus;
  final String? rawText;
  final String? mrzText;
  final double? confidence;
  final DateTime? createdAt;

  DocumentImage copyWith({
    String? id,
    String? storagePath,
    DocumentSide? documentSide,
    String? fileName,
    String? contentType,
    DocumentImageUploadStatus? uploadStatus,
    DocumentImageOcrStatus? ocrStatus,
    String? rawText,
    String? mrzText,
    double? confidence,
    DateTime? createdAt,
  }) {
    return DocumentImage(
      id: id ?? this.id,
      storagePath: storagePath ?? this.storagePath,
      documentSide: documentSide ?? this.documentSide,
      fileName: fileName ?? this.fileName,
      contentType: contentType ?? this.contentType,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      ocrStatus: ocrStatus ?? this.ocrStatus,
      rawText: rawText ?? this.rawText,
      mrzText: mrzText ?? this.mrzText,
      confidence: confidence ?? this.confidence,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'storagePath': storagePath,
      'documentSide': documentSide.apiValue,
      'uploadStatus': uploadStatus.name,
      'ocrStatus': ocrStatus.name,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
