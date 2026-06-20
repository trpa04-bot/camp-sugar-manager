class DocumentUploadDiagnostics {
  const DocumentUploadDiagnostics({
    required this.authenticated,
    required this.uidPresent,
    required this.storageBucket,
    required this.reservationIdPresent,
    required this.guestIdPresent,
    required this.sanitizedPath,
    this.plugin,
    this.code,
    this.message,
  });

  final bool authenticated;
  final bool uidPresent;
  final String storageBucket;
  final bool reservationIdPresent;
  final bool guestIdPresent;
  final String sanitizedPath;
  final String? plugin;
  final String? code;
  final String? message;

  DocumentUploadDiagnostics copyWith({
    String? plugin,
    String? code,
    String? message,
  }) {
    return DocumentUploadDiagnostics(
      authenticated: authenticated,
      uidPresent: uidPresent,
      storageBucket: storageBucket,
      reservationIdPresent: reservationIdPresent,
      guestIdPresent: guestIdPresent,
      sanitizedPath: sanitizedPath,
      plugin: plugin ?? this.plugin,
      code: code ?? this.code,
      message: message ?? this.message,
    );
  }
}
