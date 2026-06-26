import 'dart:typed_data';

import 'package:camp_sugar_manager/features/reservations/models/document_scan_quality.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/document_image_quality_service.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_document_scan_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class _SequencedQualityService extends DocumentImageQualityService {
  _SequencedQualityService(this._reports);

  final List<DocumentScanQualityReport> _reports;
  var _index = 0;

  @override
  Future<DocumentScanQualityReport> analyze(Uint8List bytes) async {
    final safeIndex = _index >= _reports.length ? _reports.length - 1 : _index;
    _index += 1;
    return _reports[safeIndex];
  }
}

Reservation _reservation() {
  return Reservation(
    id: 'res-ocr-1',
    bookingReference: 'B-1',
    source: ReservationSource.direct,
    primaryGuestName: 'Test Guest',
    primaryGuestId: '',
    primaryGuestPhone: '',
    primaryGuestEmail: '',
    pitchId: 'pitch-1',
    pitchName: 'Parcela 1',
    checkInDate: DateTime(2026, 6, 20),
    checkOutDate: DateTime(2026, 6, 24),
    adults: 2,
    children: 0,
    pets: 0,
    vehicles: 1,
    accommodationType: 'Camper',
    status: ReservationStatus.confirmed,
    totalPrice: 100,
    depositPaid: 0,
    amountPaid: 0,
    paymentStatus: PaymentStatus.unpaid,
    notes: '',
    registeredGuestCount: 0,
    currentGuests: 0,
  );
}

XFile _syntheticXFile(String name) {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  final bytes = Uint8List.fromList(img.encodeJpg(image));
  return XFile.fromData(bytes, name: name, mimeType: 'image/jpeg');
}

DocumentScanQualityReport _blockingBlurReport() {
  return const DocumentScanQualityReport(
    width: 1200,
    height: 800,
    blurScore: 10,
    brightnessMean: 120,
    contrastStdDev: 30,
    glareRatio: 0,
    documentCoverage: 0.4,
    issues: [
      DocumentScanQualityIssue(
        code: DocumentScanQualityIssueCodes.blur,
        message: 'internal',
        blocking: true,
        recommendation: 'internal',
      ),
    ],
  );
}

DocumentScanQualityReport _acceptableReport() {
  return const DocumentScanQualityReport(
    width: 1600,
    height: 1000,
    blurScore: 120,
    brightnessMean: 120,
    contrastStdDev: 48,
    glareRatio: 0.02,
    documentCoverage: 0.36,
    issues: [],
  );
}

void main() {
  testWidgets(
    'blocking issue shows localized message, disables processing, allows retake',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final firestore = FakeFirebaseFirestore();
      final reservationService = ReservationService(firestore: firestore);
      final qualityService = _SequencedQualityService([
        _blockingBlurReport(),
        _acceptableReport(),
      ]);

      var processCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ReservationDocumentScanSheet(
            reservation: _reservation(),
            reservationService: reservationService,
            qualityService: qualityService,
            imagePickerOverride: (_) async => _syntheticXFile('doc.jpg'),
            processDocumentsOverride: () async {
              processCalls += 1;
            },
          ),
        ),
      );

      final addFrontButton = find.widgetWithText(
        OutlinedButton,
        'Dodaj prednju stranu',
      );
      await tester.ensureVisible(addFrontButton);
      await tester.tap(addFrontButton);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Provjera kvalitete nije uspjela.'),
        findsOneWidget,
      );
      expect(find.text('Nema dodanih fotografija.'), findsOneWidget);

      final processButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Obradi dokumente'),
      );
      expect(processButton.onPressed, isNull);

      await tester.ensureVisible(addFrontButton);
      await tester.tap(addFrontButton);
      await tester.pumpAndSettle();

      expect(find.text('Prednja strana'), findsOneWidget);
      expect(processCalls, 0);
    },
  );

  testWidgets(
    'no blocking issue enables processing and allows OCR flow to continue',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final firestore = FakeFirebaseFirestore();
      final reservationService = ReservationService(firestore: firestore);
      final qualityService = _SequencedQualityService([_acceptableReport()]);

      var processCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ReservationDocumentScanSheet(
            reservation: _reservation(),
            reservationService: reservationService,
            qualityService: qualityService,
            imagePickerOverride: (_) async => _syntheticXFile('doc2.jpg'),
            processDocumentsOverride: () async {
              processCalls += 1;
            },
          ),
        ),
      );

      final addPassportButton = find.widgetWithText(
        OutlinedButton,
        'Dodaj putovnicu',
      );
      await tester.ensureVisible(addPassportButton);
      await tester.tap(addPassportButton);
      await tester.pumpAndSettle();

      final processButtonBeforeTap = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Obradi dokumente'),
      );
      expect(processButtonBeforeTap.onPressed, isNotNull);

      final processButtonFinder = find.widgetWithText(
        FilledButton,
        'Obradi dokumente',
      );
      await tester.ensureVisible(processButtonFinder);
      await tester.tap(processButtonFinder);
      await tester.pumpAndSettle();

      expect(processCalls, 1);
    },
  );
}
