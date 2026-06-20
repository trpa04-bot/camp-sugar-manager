import 'package:camp_sugar_manager/features/reservations/models/document_image.dart';
import 'package:camp_sugar_manager/features/reservations/models/document_verification_ui.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_guest.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Reservation reservation({
    ReservationStatus status = ReservationStatus.checkedIn,
  }) {
    return Reservation(
      id: 'res-1',
      bookingReference: 'B1',
      source: ReservationSource.direct,
      primaryGuestName: '',
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
      status: status,
      totalPrice: 100,
      depositPaid: 0,
      amountPaid: 0,
      paymentStatus: PaymentStatus.unpaid,
      notes: '',
      registeredGuestCount: 0,
      currentGuests: status == ReservationStatus.checkedIn ? 1 : 0,
    );
  }

  ReservationGuest guest({
    required String id,
    required String firstName,
    required String lastName,
    required String documentNumber,
    bool isPrimary = false,
  }) {
    return ReservationGuest(
      id: id,
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: DateTime(1990, 1, 1),
      nationality: 'DEU',
      nationalityCode: 'DEU',
      nationalityDisplayName: 'Njemačka',
      documentType: 'nationalIdCard',
      documentNumber: documentNumber,
      gender: 'M',
      isPrimaryGuest: isPrimary,
      documentImagePath: '',
      ocrStatus: 'completed',
    );
  }

  DocumentImage image(String id) {
    return DocumentImage(
      id: id,
      storagePath: 'reservations/res-1/documents/g1/$id.jpg',
      documentSide: DocumentSide.frontIdCard,
      fileName: '$id.jpg',
      contentType: 'image/jpeg',
      uploadStatus: DocumentImageUploadStatus.uploaded,
      ocrStatus: DocumentImageOcrStatus.done,
      createdAt: DateTime(2026, 6, 20),
    );
  }

  test('saves guest and links reservation and pitch fields', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation().toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'reserved',
      'maxGuests': 4,
      'currentGuests': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    final result = await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g1',
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L628C54X8',
        isPrimary: true,
      ),
      images: [image('img-1')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.deleteImmediately,
    );

    expect(result.saved, isTrue);
    final saved = await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g1')
        .get();
    expect(saved.exists, isTrue);
    expect(saved.data()!['reservationId'], 'res-1');
    expect(saved.data()!['pitchId'], 'pitch-1');
    expect(saved.data()!['pitchName'], 'Parcela 1');
    expect(saved.data()!['maskedDocumentNumber'], '*****54X8');
  });

  test('enforces only one primary guest per reservation', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation().toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'reserved',
      'maxGuests': 4,
      'currentGuests': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g1',
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L11111111',
        isPrimary: true,
      ),
      images: [image('img-1')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g2',
        firstName: 'Iva',
        lastName: 'Ivić',
        documentNumber: 'L22222222',
        isPrimary: true,
      ),
      images: [image('img-2')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    final first = await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g1')
        .get();
    final second = await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g2')
        .get();
    final res = await firestore.collection('reservations').doc('res-1').get();

    expect(first.data()!['isPrimaryGuest'], false);
    expect(second.data()!['isPrimaryGuest'], true);
    expect(res.data()!['primaryGuestId'], 'g2');
  });

  test('recalculates registeredGuestCount from real guests', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation().toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'reserved',
      'maxGuests': 4,
      'currentGuests': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g1',
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L11111111',
      ),
      images: [image('img-1')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g2',
        firstName: 'Ivo',
        lastName: 'Horvat',
        documentNumber: 'L22222222',
      ),
      images: [image('img-2')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    final res = await firestore.collection('reservations').doc('res-1').get();
    expect(res.data()!['registeredGuestCount'], 2);
  });

  test('detects duplicate by document number', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation().toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'reserved',
      'maxGuests': 4,
      'currentGuests': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g1',
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L11111111',
      ),
      images: [image('img-1')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    final duplicate = await service.saveVerifiedGuest(
      reservation: reservation(),
      guest: guest(
        id: 'g2',
        firstName: 'Ivo',
        lastName: 'Horvat',
        documentNumber: 'L11111111',
      ),
      images: [image('img-2')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    expect(duplicate.saved, isFalse);
    expect(duplicate.duplicateMatch?.reason, 'documentNumber');
  });

  test('updates pitch occupancy for checked-in reservation', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation(status: ReservationStatus.checkedIn).toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'reserved',
      'maxGuests': 4,
      'currentGuests': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await service.saveVerifiedGuest(
      reservation: reservation(status: ReservationStatus.checkedIn),
      guest: guest(
        id: 'g1',
        firstName: 'Ana',
        lastName: 'Horvat',
        documentNumber: 'L11111111',
      ),
      images: [image('img-1')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    final pitch = await firestore.collection('pitches').doc('pitch-1').get();
    expect(pitch.data()!['status'], 'occupied');
    expect(pitch.data()!['currentGuests'], 1);
  });

  test('saving guest for inquiry reservation does not occupy pitch', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation(status: ReservationStatus.inquiry).toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'available',
      'maxGuests': 4,
      'currentGuests': 0,
      'currentGuestCount': 0,
      'currentReservationId': null,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await service.saveVerifiedGuest(
      reservation: reservation(status: ReservationStatus.inquiry),
      guest: guest(
        id: 'g1',
        firstName: 'Hans',
        lastName: 'Rauh',
        documentNumber: 'L11111111',
      ),
      images: [image('img-1')],
      acceptanceStatus: DocumentAcceptanceStatus.accepted,
      manualReviewCompleted: true,
      retentionPolicy: DocumentRetentionPolicy.retainManually,
    );

    final pitch = await firestore.collection('pitches').doc('pitch-1').get();
    expect(pitch.data()!['status'], 'available');
    expect(pitch.data()!['currentReservationId'], isNull);
  });

  test('check-in updates reservation and pitch atomically', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    final inquiryReservation = reservation(
      status: ReservationStatus.inquiry,
    ).copyWith(primaryGuestName: 'HANS RAUH', registeredGuestCount: 1);
    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(inquiryReservation.toMap());
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Primorje 1 istok',
      'number': 1,
      'zone': 'A',
      'status': 'available',
      'maxGuests': 4,
      'currentGuests': 0,
      'currentGuestCount': 0,
      'currentReservationId': null,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });
    await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g1')
        .set({
          'id': 'g1',
          'reservationId': 'res-1',
          'firstName': 'Hans',
          'lastName': 'Rauh',
          'documentType': 'nationalIdCard',
          'documentNumber': 'L628C54X8',
          'verificationStatus': 'verified',
          'verificationMethod': 'ocrManual',
          'documentAcceptanceStatus': 'accepted',
          'manualReviewCompleted': true,
          'documentImagePath': '',
          'documentImagePaths': <String>[],
          'retentionPolicy': 'retainManually',
          'cleanupPending': false,
          'ocrStatus': 'completed',
        });

    await service.checkInReservation(
      reservationId: 'res-1',
      checkedInByUid: 'uid-123',
    );

    final savedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    final pitch = await firestore.collection('pitches').doc('pitch-1').get();

    expect(
      savedReservation.data()!['status'],
      ReservationStatus.checkedIn.name,
    );
    expect(savedReservation.data()!['checkedInByUid'], 'uid-123');
    expect(savedReservation.data()!['currentGuests'], 1);
    expect(pitch.data()!['status'], 'occupied');
    expect(pitch.data()!['currentReservationId'], 'res-1');
    expect(pitch.data()!['currentGuestCount'], 1);
  });

  test('check-out resets occupancy and current guests', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(
          reservation(
            status: ReservationStatus.checkedIn,
          ).copyWith(registeredGuestCount: 1, currentGuests: 1).toMap(),
        );
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Primorje 1 istok',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 1,
      'currentGuestCount': 1,
      'currentReservationId': 'res-1',
      'currentPrimaryGuestName': 'HANS RAUH',
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await service.checkOutReservation(reservationId: 'res-1');

    final savedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    final pitch = await firestore.collection('pitches').doc('pitch-1').get();

    expect(
      savedReservation.data()!['status'],
      ReservationStatus.checkedOut.name,
    );
    expect(savedReservation.data()!['currentGuests'], 0);
    expect(pitch.data()!['status'], 'available');
    expect(pitch.data()!['currentReservationId'], isNull);
    expect(pitch.data()!['currentGuestCount'], 0);
  });

  test(
    'prevents check-in on already occupied pitch by another reservation',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(
            reservation(
              status: ReservationStatus.confirmed,
            ).copyWith(registeredGuestCount: 1).toMap(),
          );
      await firestore
          .collection('reservations')
          .doc('res-2')
          .set(
            reservation(status: ReservationStatus.checkedIn)
                .copyWith(
                  id: 'res-2',
                  pitchId: 'pitch-1',
                  pitchName: 'Primorje 1 istok',
                  registeredGuestCount: 2,
                  currentGuests: 2,
                )
                .toMap(),
          );
      await firestore.collection('pitches').doc('pitch-1').set({
        'id': 'pitch-1',
        'name': 'Primorje 1 istok',
        'number': 1,
        'zone': 'A',
        'status': 'occupied',
        'maxGuests': 4,
        'currentGuests': 2,
        'currentGuestCount': 2,
        'currentReservationId': 'res-2',
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
      });

      await expectLater(
        () => service.checkInReservation(
          reservationId: 'res-1',
          checkedInByUid: 'uid-1',
        ),
        throwsA(isA<ReservationConflictException>()),
      );
    },
  );

  test('failed check-in leaves reservation and pitch unchanged', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(
          reservation(
            status: ReservationStatus.inquiry,
          ).copyWith(registeredGuestCount: 1).toMap(),
        );
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Primorje 1 istok',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 2,
      'currentGuestCount': 2,
      'currentReservationId': 'res-2',
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await expectLater(
      () => service.checkInReservation(
        reservationId: 'res-1',
        checkedInByUid: 'uid-1',
      ),
      throwsA(isA<ReservationConflictException>()),
    );

    final savedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    final pitch = await firestore.collection('pitches').doc('pitch-1').get();

    expect(savedReservation.data()!['status'], ReservationStatus.inquiry.name);
    expect(savedReservation.data()!['currentGuests'], 0);
    expect(pitch.data()!['status'], 'occupied');
    expect(pitch.data()!['currentReservationId'], 'res-2');
  });
}
