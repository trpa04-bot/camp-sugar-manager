import 'dart:typed_data';

import 'package:camp_sugar_manager/features/reservations/models/document_scan_quality.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/document_image_quality_service.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_document_scan_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class _DecodeFailedQualityService extends DocumentImageQualityService {
  const _DecodeFailedQualityService();

  @override
  Future<DocumentScanQualityReport> analyze(Uint8List bytes) async {
    return const DocumentScanQualityReport(
      width: 0,
      height: 0,
      blurScore: 0,
      brightnessMean: 0,
      contrastStdDev: 0,
      glareRatio: 0,
      documentCoverage: 0,
      issues: [
        DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.decodeFailed,
          message: 'decode failed',
          blocking: true,
          recommendation: 'retry',
        ),
      ],
    );
  }
}

Reservation _reservation() {
  return Reservation(
    id: 'res-heic-1',
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

void main() {
  testWidgets('HEIC decode fallback does not block add flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final firestore = FakeFirebaseFirestore();
    final reservationService = ReservationService(firestore: firestore);

    final heicBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

    await tester.pumpWidget(
      MaterialApp(
        home: ReservationDocumentScanSheet(
          reservation: _reservation(),
          reservationService: reservationService,
          qualityService: const _DecodeFailedQualityService(),
          imagePickerOverride: (_) async => XFile.fromData(
            heicBytes,
            name: 'doc.heic',
            mimeType: 'image/heic',
          ),
          processDocumentsOverride: () async {},
        ),
      ),
    );

    final addButton = find.widgetWithText(OutlinedButton, 'Skeniraj dokument');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton.first);
    await tester.pumpAndSettle();

    expect(find.text('Nema dodanih fotografija.'), findsNothing);
    expect(find.textContaining('Fotografija odabrana.'), findsOneWidget);

    final processButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Obradi dokumente'),
    );
    expect(processButton.onPressed, isNotNull);
  });

  testWidgets('read failure keeps image list empty and blocks processing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final firestore = FakeFirebaseFirestore();
    final reservationService = ReservationService(firestore: firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: ReservationDocumentScanSheet(
          reservation: _reservation(),
          reservationService: reservationService,
          imagePickerOverride: (_) async =>
              XFile('/tmp/does-not-exist-anywhere.jpg'),
          processDocumentsOverride: () async {},
        ),
      ),
    );

    final addButton = find.widgetWithText(OutlinedButton, 'Skeniraj dokument');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton.first);
    await tester.pumpAndSettle();

    expect(find.text('Nema dodanih fotografija.'), findsOneWidget);

    final processButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Obradi dokumente'),
    );
    expect(processButton.onPressed, isNull);
  });
}
