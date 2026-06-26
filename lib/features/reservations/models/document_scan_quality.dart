class DocumentScanQualityIssueCodes {
  static const String decodeFailed = 'decodeFailed';
  static const String blur = 'blur';
  static const String lowResolution = 'lowResolution';
  static const String glare = 'glare';
  static const String documentCutOff = 'documentCutOff';
  static const String skewed = 'skewed';
  static const String tooDark = 'tooDark';
  static const String overexposed = 'overexposed';
  static const String lowContrast = 'lowContrast';
  static const String documentFar = 'documentFar';
}

class DocumentScanQualityIssue {
  const DocumentScanQualityIssue({
    required this.code,
    required this.message,
    required this.blocking,
    required this.recommendation,
  });

  final String code;
  final String message;
  final bool blocking;
  final String recommendation;
}

class DocumentScanQualityReport {
  const DocumentScanQualityReport({
    required this.width,
    required this.height,
    required this.blurScore,
    required this.brightnessMean,
    required this.contrastStdDev,
    required this.glareRatio,
    required this.documentCoverage,
    required this.issues,
  });

  final int width;
  final int height;
  final double blurScore;
  final double brightnessMean;
  final double contrastStdDev;
  final double glareRatio;
  final double documentCoverage;
  final List<DocumentScanQualityIssue> issues;

  bool get hasBlockingIssues => issues.any((issue) => issue.blocking);

  bool get acceptable => !hasBlockingIssues;

  List<String> get blockingMessages => issues
      .where((issue) => issue.blocking)
      .map((issue) => issue.message)
      .toList(growable: false);

  List<String> get recommendations => issues
      .map((issue) => issue.recommendation)
      .toSet()
      .toList(growable: false);
}
