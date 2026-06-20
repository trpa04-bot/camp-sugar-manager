import 'package:camp_sugar_manager/features/reservations/models/document_ocr_result.dart';
import 'package:camp_sugar_manager/features/reservations/models/document_verification_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('localizes DEU country code to Croatian label', () {
    final label = countryDisplayLabelHr(nationalityCode: 'DEU');

    expect(label, 'Njemačka (DEU)');
  });

  test('localizes nationalIdCard document kind', () {
    final label = documentTypeDisplayLabelHr('nationalIdCard');

    expect(label, 'Osobna iskaznica');
  });

  test('returns accepted status for conflict-free verified fields', () {
    final status = resolveAcceptanceStatus(
      parsed: const DocumentOcrParsedData(
        documentKind: 'nationalIdCard',
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L628C54X8',
      ),
      fields: const <String, DocumentScanField>{
        'firstName': DocumentScanField(value: 'Ana', needsReview: false),
        'lastName': DocumentScanField(value: 'Horvat', needsReview: false),
        'documentNumber': DocumentScanField(
          value: 'L628C54X8',
          needsReview: false,
        ),
      },
      conflicts: const <String>[],
    );

    expect(status, DocumentAcceptanceStatus.accepted);
  });

  test('ignores non-critical review flags for accepted status', () {
    final status = resolveAcceptanceStatus(
      parsed: const DocumentOcrParsedData(
        documentKind: 'nationalIdCard',
        firstName: 'HANS',
        lastName: 'RAUH',
        documentNumber: 'L628C54X8',
      ),
      fields: const <String, DocumentScanField>{
        'firstName': DocumentScanField(value: 'HANS', needsReview: false),
        'lastName': DocumentScanField(value: 'RAUH', needsReview: false),
        'documentNumber': DocumentScanField(
          value: 'L628C54X8',
          needsReview: false,
        ),
        'nationality': DocumentScanField(value: 'DEU', needsReview: true),
        'documentType': DocumentScanField(
          value: 'nationalIdCard',
          needsReview: true,
        ),
      },
      conflicts: const <String>[],
    );

    expect(status, DocumentAcceptanceStatus.accepted);
  });
}
