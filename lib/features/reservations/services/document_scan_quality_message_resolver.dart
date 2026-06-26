import '../models/document_scan_quality.dart';

class DocumentScanQualityMessageResolver {
  const DocumentScanQualityMessageResolver();

  static const Map<String, Map<String, String>> _localizedMessages = {
    'hr': {
      DocumentScanQualityIssueCodes.blur:
          'Slika je mutna. Mirno držite kameru i pokušajte ponovno.',
      DocumentScanQualityIssueCodes.lowResolution:
          'Rezolucija fotografije je preniska. Približite dokument.',
      DocumentScanQualityIssueCodes.glare:
          'Na dokumentu je previše odsjaja. Promijenite kut ili osvjetljenje.',
      DocumentScanQualityIssueCodes.documentCutOff:
          'Dokument nije cijeli unutar okvira.',
      DocumentScanQualityIssueCodes.skewed:
          'Dokument je previše ukošen. Poravnajte ga s okvirom.',
      DocumentScanQualityIssueCodes.tooDark:
          'Slika je pretamna. Poboljšajte osvjetljenje.',
      DocumentScanQualityIssueCodes.overexposed:
          'Dio dokumenta je presvijetao.',
      DocumentScanQualityIssueCodes.decodeFailed:
          'Fotografija nije valjana ili je oštećena.',
      DocumentScanQualityIssueCodes.lowContrast:
          'Kontrast je slab pa je tekst teže čitljiv.',
      DocumentScanQualityIssueCodes.documentFar:
          'Dokument je premalen u kadru.',
    },
  };

  List<String> resolveMessages(
    List<DocumentScanQualityIssue> issues, {
    String locale = 'hr',
  }) {
    final catalog = _localizedMessages[locale] ?? _localizedMessages['hr']!;
    return issues
        .map((issue) => catalog[issue.code] ?? issue.message)
        .toList(growable: false);
  }
}
