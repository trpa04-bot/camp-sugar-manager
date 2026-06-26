import 'dart:typed_data';

import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/document_image_source_adapter.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:camp_sugar_manager/features/reservations/services/web_camera_capture_adapter.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_document_scan_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// Removed unused _NoopQualityService class

class _FakeImageSourceAdapter implements DocumentImageSourceAdapter {
  _FakeImageSourceAdapter({
    required this.isMobileWeb,
    required this.supportsWebCamera,
    this.mobileCameraResult,
    this.galleryResult,
    this.fileResult,
  });

  @override
  final bool isMobileWeb;

  @override
  final bool supportsWebCamera;

  final XFile? mobileCameraResult;
  final XFile? galleryResult;
  final XFile? fileResult;

  int mobileCalls = 0;
  int galleryCalls = 0;
  int fileCalls = 0;

  @override
  bool get isWeb => true;

  @override
  Future<XFile?> captureFromMobileCamera() async {
    mobileCalls += 1;
    return mobileCameraResult;
  }

  @override
  Future<XFile?> captureFromWebCamera() async {
    return null;
  }

  @override
  Future<XFile?> pickFromGallery() async {
    galleryCalls += 1;
    return galleryResult;
  }

  @override
  Future<XFile?> pickFromFile() async {
    fileCalls += 1;
    return fileResult;
  }
}

class _FakeWebCameraAdapter implements WebCameraCaptureAdapter {
  @override
  bool get isSecureContext => true;

  @override
  bool get isSupported => true;

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<WebCameraCaptureFrame> captureFrame() async {
    throw UnimplementedError();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<List<WebCameraDevice>> listVideoDevices() async {
    return const <WebCameraDevice>[];
  }

  @override
  Future<void> start({String? deviceId}) async {}

  @override
  Future<void> stop() async {}
}

Reservation _reservation() {
  return Reservation(
    id: 'res-web-1',
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
  final image = img.Image(width: 1200, height: 800);
  img.fill(image, color: img.ColorRgb8(245, 245, 245));
  img.fillRect(
    image,
    x1: 140,
    y1: 110,
    x2: 1060,
    y2: 690,
    color: img.ColorRgb8(40, 40, 40),
  );
  for (var y = 140; y < 670; y += 26) {
    img.drawLine(
      image,
      x1: 190,
      y1: y,
      x2: 1010,
      y2: y,
      color: img.ColorRgb8(220, 220, 220),
      thickness: 2,
    );
  }
  final bytes = Uint8List.fromList(img.encodeJpg(image));
  return XFile.fromData(bytes, name: name, mimeType: 'image/jpeg');
}

void main() {
  testWidgets('iPhone scan uses mobile camera capture source', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final reservationService = ReservationService(firestore: firestore);
    final sourceAdapter = _FakeImageSourceAdapter(
      isMobileWeb: true,
      supportsWebCamera: true,
      mobileCameraResult: _syntheticXFile('iphone.jpg'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReservationDocumentScanSheet(
          reservation: _reservation(),
          reservationService: reservationService,
          imageSourceAdapter: sourceAdapter,
          webCameraAdapter: _FakeWebCameraAdapter(),
          isWebOverride: true,
          processDocumentsOverride: () async {},
        ),
      ),
    );

    final scanButton = find.widgetWithText(OutlinedButton, 'Skeniraj dokument');
    await tester.ensureVisible(scanButton.first);
    await tester.tap(scanButton.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skeniraj dokument').last);
    await tester.pumpAndSettle();

    expect(sourceAdapter.mobileCalls, 1);
  });

  testWidgets('gallery button uses gallery source without camera capture', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final reservationService = ReservationService(firestore: firestore);
    final sourceAdapter = _FakeImageSourceAdapter(
      isMobileWeb: true,
      supportsWebCamera: true,
      galleryResult: _syntheticXFile('gallery.jpg'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReservationDocumentScanSheet(
          reservation: _reservation(),
          reservationService: reservationService,
          imageSourceAdapter: sourceAdapter,
          webCameraAdapter: _FakeWebCameraAdapter(),
          isWebOverride: true,
          processDocumentsOverride: () async {},
        ),
      ),
    );

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Odaberi iz galerije'),
    );
    await tester.pumpAndSettle();

    expect(sourceAdapter.galleryCalls, 1);
    expect(sourceAdapter.mobileCalls, 0);
  });

  testWidgets('Mac scan uses web camera dialog opener', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final reservationService = ReservationService(firestore: firestore);
    final sourceAdapter = _FakeImageSourceAdapter(
      isMobileWeb: false,
      supportsWebCamera: true,
    );

    var webDialogCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ReservationDocumentScanSheet(
          reservation: _reservation(),
          reservationService: reservationService,
          imageSourceAdapter: sourceAdapter,
          webCameraAdapter: _FakeWebCameraAdapter(),
          isWebOverride: true,
          webCameraDialogOpener: (context, adapter) async {
            webDialogCalls += 1;
            return _syntheticXFile('mac-camera.jpg');
          },
          processDocumentsOverride: () async {},
        ),
      ),
    );

    final scanButton = find.widgetWithText(OutlinedButton, 'Skeniraj dokument');
    await tester.ensureVisible(scanButton.first);
    await tester.tap(scanButton.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skeniraj dokument').last);
    await tester.pumpAndSettle();

    expect(webDialogCalls, 1);
    expect(sourceAdapter.mobileCalls, 0);
  });

  testWidgets('file button uses file source picker', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final reservationService = ReservationService(firestore: firestore);
    final sourceAdapter = _FakeImageSourceAdapter(
      isMobileWeb: false,
      supportsWebCamera: true,
      fileResult: _syntheticXFile('file.jpg'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReservationDocumentScanSheet(
          reservation: _reservation(),
          reservationService: reservationService,
          imageSourceAdapter: sourceAdapter,
          webCameraAdapter: _FakeWebCameraAdapter(),
          isWebOverride: true,
          processDocumentsOverride: () async {},
        ),
      ),
    );

    final scanButton = find.widgetWithText(OutlinedButton, 'Skeniraj dokument');
    await tester.ensureVisible(scanButton.first);
    await tester.tap(scanButton.first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dodaj PDF ili sliku').last);
    await tester.pumpAndSettle();

    expect(sourceAdapter.fileCalls, 1);
  });
}
