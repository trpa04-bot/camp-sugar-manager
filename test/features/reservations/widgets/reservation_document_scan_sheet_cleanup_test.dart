import 'package:camp_sugar_manager/features/reservations/models/document_image.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_guest.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_document_scan_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReservationGuest baseGuest() {
    return ReservationGuest(
      id: 'g1',
      reservationId: 'res-1',
      pitchId: 'pitch-1',
      pitchName: 'Parcela 1',
      firstName: 'Ana',
      lastName: 'Horvat',
      dateOfBirth: DateTime(1990, 1, 1),
      nationality: 'DEU',
      nationalityCode: 'DEU',
      nationalityDisplayName: 'Njemačka',
      documentType: 'nationalIdCard',
      documentNumber: 'L628C54X8',
      maskedDocumentNumber: '*****54X8',
      gender: 'F',
      isPrimaryGuest: true,
      checkInDate: DateTime(2026, 6, 20),
      checkOutDate: DateTime(2026, 6, 24),
      documentImagePath: 'path/a.jpg,path/b.jpg',
      documentImagePaths: const ['path/a.jpg', 'path/b.jpg'],
      cleanupPending: false,
      ocrStatus: 'completed',
    );
  }

  List<DocumentImage> images() {
    return [
      DocumentImage(
        id: 'img-1',
        storagePath: 'path/a.jpg',
        documentSide: DocumentSide.frontIdCard,
        fileName: 'a.jpg',
        contentType: 'image/jpeg',
        uploadStatus: DocumentImageUploadStatus.uploaded,
        ocrStatus: DocumentImageOcrStatus.done,
        createdAt: DateTime(2026, 6, 20),
      ),
      DocumentImage(
        id: 'img-2',
        storagePath: 'path/b.jpg',
        documentSide: DocumentSide.backIdCard,
        fileName: 'b.jpg',
        contentType: 'image/jpeg',
        uploadStatus: DocumentImageUploadStatus.uploaded,
        ocrStatus: DocumentImageOcrStatus.done,
        createdAt: DateTime(2026, 6, 20),
      ),
    ];
  }

  Future<void> seedGuest(
    FakeFirebaseFirestore firestore,
    ReservationGuest guest,
  ) async {
    final reservation = Reservation(
      id: 'res-1',
      bookingReference: 'B1',
      source: ReservationSource.direct,
      primaryGuestName: 'Ana Horvat',
      primaryGuestId: 'g1',
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
      totalPrice: 0,
      depositPaid: 0,
      amountPaid: 0,
      paymentStatus: PaymentStatus.unpaid,
      notes: '',
      registeredGuestCount: 1,
      currentGuests: 0,
    );

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation.toMap());
    await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc(guest.id)
        .set(guest.toMap());
  }

  test('sets cleanupPending when storage delete fails', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);
    final guest = baseGuest();
    await seedGuest(firestore, guest);

    final result = await applyImmediateRetentionCleanup(
      reservationService: service,
      reservationId: 'res-1',
      guest: guest,
      images: images(),
      deleteDocumentImage: (storagePath) async {
        if (storagePath == 'path/b.jpg') {
          throw StateError('storage delete failed');
        }
      },
    );

    expect(result.cleanupFailed, isTrue);

    final saved = await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g1')
        .get();

    expect(saved.exists, isTrue);
    expect(saved.data()!['cleanupPending'], true);
    expect(saved.data()!['documentImagePaths'], isNotEmpty);
  });

  test('clears image paths when immediate cleanup succeeds', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);
    final guest = baseGuest();
    await seedGuest(firestore, guest);

    final result = await applyImmediateRetentionCleanup(
      reservationService: service,
      reservationId: 'res-1',
      guest: guest,
      images: images(),
      deleteDocumentImage: (_) async {},
    );

    expect(result.cleanupFailed, isFalse);

    final saved = await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g1')
        .get();

    expect(saved.exists, isTrue);
    expect(saved.data()!['cleanupPending'], false);
    expect(saved.data()!['documentImagePath'], '');
    expect(saved.data()!['documentImagePaths'], isEmpty);
  });
}
