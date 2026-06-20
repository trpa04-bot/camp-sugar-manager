import 'dart:typed_data';

import 'package:camp_sugar_manager/features/reservations/models/document_image.dart';
import 'package:camp_sugar_manager/features/reservations/models/document_ocr_result.dart';
import 'package:camp_sugar_manager/features/reservations/models/document_verification_ui.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_document_scan_context.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_guest.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/document_guest_verification_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReservationDocumentScanContext context() {
    return ReservationDocumentScanContext(
      reservationId: 'r1',
      guestId: 'g1',
      pitchId: 'p1',
      pitchName: 'Pitch 1',
      checkInDate: DateTime(2026, 6, 20),
      checkOutDate: DateTime(2026, 6, 21),
    );
  }

  DocumentOcrResult ocrResult() {
    return const DocumentOcrResult(
      rawText: 'x',
      parsed: DocumentOcrParsedData(
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L628C54X8',
        documentKind: 'nationalIdCard',
      ),
    );
  }

  DocumentImage image(String id, DocumentSide side, String path) {
    return DocumentImage(
      id: id,
      storagePath: path,
      documentSide: side,
      fileName: '$id.jpg',
      contentType: 'image/jpeg',
      uploadStatus: DocumentImageUploadStatus.uploaded,
      ocrStatus: DocumentImageOcrStatus.done,
      createdAt: DateTime(2026, 6, 20),
    );
  }

  Map<String, Uint8List> previews(List<DocumentImage> images) {
    const pngBytes = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x04,
      0x00,
      0x00,
      0x00,
      0xB5,
      0x1C,
      0x0C,
      0x02,
      0x00,
      0x00,
      0x00,
      0x0B,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0xDA,
      0x63,
      0xFC,
      0xFF,
      0x1F,
      0x00,
      0x03,
      0x03,
      0x02,
      0x00,
      0xEF,
      0xA6,
      0xE3,
      0xC5,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ];
    return {for (final item in images) item.id: Uint8List.fromList(pngBytes)};
  }

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<DocumentImage> images,
    required Future<DocumentVerificationDialogPayload> Function() onReprocess,
    required Future<DocumentVerificationDialogPayload?> Function()
    onAddMorePhotos,
    required DocumentPhotoActionCallback onReplacePhoto,
    required DocumentPhotoActionCallback onRemovePhoto,
    required Future<void> Function(
      ReservationGuest,
      DocumentImageCleanupPolicy,
      DocumentAcceptanceStatus,
      bool,
      bool,
    )
    onSave,
    String processStatus = 'review',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentGuestVerificationDialog(
            scanContext: context(),
            images: images,
            imagePreviews: previews(images),
            ocrResult: ocrResult(),
            processStatus: processStatus,
            onReprocess: onReprocess,
            onAddMorePhotos: onAddMorePhotos,
            onReplacePhoto: onReplacePhoto,
            onRemovePhoto: onRemovePhoto,
            onOpenPhoto: (imageArg, previewArg) async {},
            reservationStatus: ReservationStatus.confirmed,
            onCheckIn: () async {},
            onSave: onSave,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('replace callback for front side is separate action', (
    tester,
  ) async {
    final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');
    final back = image('back', DocumentSide.backIdCard, 's/back.jpg');
    final replaced = image(
      'front-new',
      DocumentSide.frontIdCard,
      's/front2.jpg',
    );
    var replacedId = '';

    await pumpDialog(
      tester,
      images: [front, back],
      onReprocess: () async => DocumentVerificationDialogPayload(
        images: [front, back],
        imagePreviews: previews([front, back]),
        ocrResult: ocrResult(),
        processStatus: 'review',
      ),
      onAddMorePhotos: () async => null,
      onReplacePhoto: (image, onProgress) async {
        replacedId = image.id;
        return DocumentVerificationDialogPayload(
          images: [replaced, back],
          imagePreviews: previews([replaced, back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onRemovePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [front, back],
          imagePreviews: previews([front, back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onSave:
          (
            guestArg,
            cleanupPolicyArg,
            statusArg,
            manualArg,
            duplicateArg,
          ) async {},
    );

    await tester.tap(find.text('Zamijeni').first);
    await tester.pumpAndSettle();

    expect(replacedId, 'front');
    expect(find.text('Prednja strana'), findsOneWidget);
    expect(find.text('Stražnja strana'), findsOneWidget);
  });

  testWidgets('replace callback for back side is separate action', (
    tester,
  ) async {
    final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');
    final back = image('back', DocumentSide.backIdCard, 's/back.jpg');
    final replaced = image('back-new', DocumentSide.backIdCard, 's/back2.jpg');
    var replacedId = '';

    await pumpDialog(
      tester,
      images: [front, back],
      onReprocess: () async => DocumentVerificationDialogPayload(
        images: [front, back],
        imagePreviews: previews([front, back]),
        ocrResult: ocrResult(),
        processStatus: 'review',
      ),
      onAddMorePhotos: () async => null,
      onReplacePhoto: (image, onProgress) async {
        replacedId = image.id;
        return DocumentVerificationDialogPayload(
          images: [front, replaced],
          imagePreviews: previews([front, replaced]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onRemovePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [front, back],
          imagePreviews: previews([front, back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onSave:
          (
            guestArg,
            cleanupPolicyArg,
            statusArg,
            manualArg,
            duplicateArg,
          ) async {},
    );

    await tester.tap(find.text('Zamijeni').at(1));
    await tester.pumpAndSettle();

    expect(replacedId, 'back');
  });

  testWidgets('failed replace keeps old image and shows error', (tester) async {
    final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');
    final back = image('back', DocumentSide.backIdCard, 's/back.jpg');

    await pumpDialog(
      tester,
      images: [front, back],
      onReprocess: () async => DocumentVerificationDialogPayload(
        images: [front, back],
        imagePreviews: previews([front, back]),
        ocrResult: ocrResult(),
        processStatus: 'review',
      ),
      onAddMorePhotos: () async => null,
      onReplacePhoto: (image, onProgress) async {
        throw StateError('Upload failed');
      },
      onRemovePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [front, back],
          imagePreviews: previews([front, back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onSave:
          (
            guestArg,
            cleanupPolicyArg,
            statusArg,
            manualArg,
            duplicateArg,
          ) async {},
    );

    await tester.tap(find.text('Zamijeni').first);
    await tester.pumpAndSettle();

    expect(find.text('Greška pri zamjeni fotografije.'), findsOneWidget);
    expect(find.text('Prednja strana'), findsOneWidget);
    expect(find.text('Stražnja strana'), findsOneWidget);
  });

  testWidgets('remove one of two images keeps dialog state', (tester) async {
    final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');
    final back = image('back', DocumentSide.backIdCard, 's/back.jpg');

    await pumpDialog(
      tester,
      images: [front, back],
      onReprocess: () async => DocumentVerificationDialogPayload(
        images: [front, back],
        imagePreviews: previews([front, back]),
        ocrResult: ocrResult(),
        processStatus: 'review',
      ),
      onAddMorePhotos: () async => null,
      onReplacePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [front, back],
          imagePreviews: previews([front, back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onRemovePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [back],
          imagePreviews: previews([back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onSave:
          (
            guestArg,
            cleanupPolicyArg,
            statusArg,
            manualArg,
            duplicateArg,
          ) async {},
    );

    await tester.tap(find.text('Ukloni').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ukloni'));
    await tester.pumpAndSettle();

    expect(find.text('Prednja strana'), findsNothing);
    expect(find.text('Stražnja strana'), findsOneWidget);
  });

  testWidgets(
    'remove last image shows empty state and disables process button',
    (tester) async {
      final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');

      await pumpDialog(
        tester,
        images: [front],
        onReprocess: () async => DocumentVerificationDialogPayload(
          images: [front],
          imagePreviews: previews([front]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        ),
        onAddMorePhotos: () async => null,
        onReplacePhoto: (image, onProgress) async {
          return DocumentVerificationDialogPayload(
            images: [front],
            imagePreviews: previews([front]),
            ocrResult: ocrResult(),
            processStatus: 'review',
          );
        },
        onRemovePhoto: (image, onProgress) async {
          return DocumentVerificationDialogPayload(
            images: const [],
            imagePreviews: const {},
            ocrResult: const DocumentOcrResult(
              rawText: '',
              parsed: DocumentOcrParsedData(),
            ),
            processStatus: 'review',
          );
        },
        onSave:
            (
              guestArg,
              cleanupPolicyArg,
              statusArg,
              manualArg,
              duplicateArg,
            ) async {},
      );

      await tester.tap(find.text('Ukloni').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ukloni'));
      await tester.pumpAndSettle();

      expect(find.text('Nema dodanih fotografija dokumenta.'), findsOneWidget);
      final processButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Obradi dokumente'),
      );
      expect(processButton.onPressed, isNull);
    },
  );

  testWidgets('removed image is not included in saved guest paths', (
    tester,
  ) async {
    final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');
    final back = image('back', DocumentSide.backIdCard, 's/back.jpg');
    String savedPath = '';

    await pumpDialog(
      tester,
      images: [front, back],
      onReprocess: () async => DocumentVerificationDialogPayload(
        images: [front, back],
        imagePreviews: previews([front, back]),
        ocrResult: ocrResult(),
        processStatus: 'review',
      ),
      onAddMorePhotos: () async => null,
      onReplacePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [front, back],
          imagePreviews: previews([front, back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onRemovePhoto: (image, onProgress) async {
        return DocumentVerificationDialogPayload(
          images: [back],
          imagePreviews: previews([back]),
          ocrResult: ocrResult(),
          processStatus: 'review',
        );
      },
      onSave: (guest, cleanup, statusArg, manualArg, duplicateArg) async {
        savedPath = guest.documentImagePath;
      },
    );

    await tester.tap(find.text('Ukloni').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ukloni'));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(
      FilledButton,
      'Spremi podatke gosta',
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(FilledButton, 'Zatvori'));
    await tester.pumpAndSettle();

    expect(savedPath, 's/back.jpg');
  });

  testWidgets(
    'accepted document has active save button without manual review checkbox',
    (tester) async {
      final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');

      final acceptedResult = DocumentOcrResult(
        rawText: 'x',
        parsed: const DocumentOcrParsedData(
          firstName: 'HANS',
          lastName: 'RAUH',
          documentNumber: 'L628C54X8',
          documentKind: 'nationalIdCard',
        ),
        merged: DocumentScanMergedResult(
          parsed: const DocumentOcrParsedData(
            firstName: 'HANS',
            lastName: 'RAUH',
            documentNumber: 'L628C54X8',
            documentKind: 'nationalIdCard',
          ),
          fields: const {
            'firstName': DocumentScanField(
              value: 'HANS',
              needsReview: false,
              sourceType: 'mrz',
            ),
            'lastName': DocumentScanField(
              value: 'RAUH',
              needsReview: false,
              sourceType: 'mrz',
            ),
            'documentNumber': DocumentScanField(
              value: 'L628C54X8',
              needsReview: false,
              sourceType: 'mrz',
            ),
          },
          conflicts: const <String>[],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentGuestVerificationDialog(
              scanContext: context(),
              images: [front],
              imagePreviews: previews([front]),
              ocrResult: acceptedResult,
              processStatus: 'review',
              onReprocess: () async => DocumentVerificationDialogPayload(
                images: [front],
                imagePreviews: previews([front]),
                ocrResult: acceptedResult,
                processStatus: 'review',
              ),
              onAddMorePhotos: () async => null,
              onReplacePhoto: (imageArg, onProgress) async {
                return DocumentVerificationDialogPayload(
                  images: [front],
                  imagePreviews: previews([front]),
                  ocrResult: acceptedResult,
                  processStatus: 'review',
                );
              },
              onRemovePhoto: (imageArg, onProgress) async {
                return DocumentVerificationDialogPayload(
                  images: [front],
                  imagePreviews: previews([front]),
                  ocrResult: acceptedResult,
                  processStatus: 'review',
                );
              },
              onOpenPhoto: (imageArg, previewArg) async {},
              reservationStatus: ReservationStatus.confirmed,
              onCheckIn: () async {},
              onSave:
                  (
                    guestArg,
                    cleanupPolicyArg,
                    statusArg,
                    manualArg,
                    duplicateArg,
                  ) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ručno sam provjerio dokument'), findsNothing);
      final saveButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Spremi podatke gosta'),
      );
      expect(saveButton.onPressed, isNotNull);
      expect(find.textContaining('Status dokumenta: accepted'), findsOneWidget);
    },
  );

  testWidgets(
    'shows review status after merge and hides technical source info',
    (tester) async {
      final front = image('front', DocumentSide.frontIdCard, 's/front.jpg');

      await pumpDialog(
        tester,
        images: [front],
        processStatus: 'mergingResults',
        onReprocess: () async => DocumentVerificationDialogPayload(
          images: [front],
          imagePreviews: previews([front]),
          ocrResult: ocrResult(),
          processStatus: 'mergingResults',
        ),
        onAddMorePhotos: () async => null,
        onReplacePhoto: (imageArg, onProgress) async {
          return DocumentVerificationDialogPayload(
            images: [front],
            imagePreviews: previews([front]),
            ocrResult: ocrResult(),
            processStatus: 'review',
          );
        },
        onRemovePhoto: (imageArg, onProgress) async {
          return DocumentVerificationDialogPayload(
            images: [front],
            imagePreviews: previews([front]),
            ocrResult: ocrResult(),
            processStatus: 'review',
          );
        },
        onSave:
            (
              guestArg,
              cleanupPolicyArg,
              statusArg,
              manualArg,
              duplicateArg,
            ) async {},
      );

      expect(
        find.textContaining('Status procesa: Provjera rezultata'),
        findsOneWidget,
      );
      expect(find.textContaining('Izvor:'), findsNothing);
      expect(find.textContaining('confidence'), findsNothing);
    },
  );
}
