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

  test(
    'creating primary guest syncs reservation and pitch guest name',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(
            reservation()
                .copyWith(
                  primaryGuestName: 'Lara Bruggeman',
                  primaryGuestId: 'g1',
                  registeredGuestCount: 1,
                  currentGuests: 1,
                )
                .toMap(),
          );
      await firestore.collection('pitches').doc('pitch-1').set({
        'id': 'pitch-1',
        'name': 'Parcela 1',
        'number': 1,
        'zone': 'A',
        'status': 'occupied',
        'maxGuests': 4,
        'currentGuests': 1,
        'currentGuestCount': 1,
        'currentReservationId': 'res-1',
        'currentPrimaryGuestName': 'Lara Bruggeman',
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
            'pitchId': 'pitch-1',
            'pitchName': 'Parcela 1',
            'firstName': 'Lara',
            'lastName': 'Bruggeman',
            'documentType': 'passport',
            'documentNumber': 'X1111111',
            'isPrimaryGuest': true,
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

      await service.createGuest(
        'res-1',
        guest(
          id: 'g2',
          firstName: 'Sebastiaan',
          lastName: 'Van Wijk',
          documentNumber: 'X2222222',
          isPrimary: true,
        ),
      );

      final updatedReservation = await firestore
          .collection('reservations')
          .doc('res-1')
          .get();
      final updatedPitch = await firestore
          .collection('pitches')
          .doc('pitch-1')
          .get();
      final firstGuest = await firestore
          .collection('reservations')
          .doc('res-1')
          .collection('guests')
          .doc('g1')
          .get();

      expect(
        updatedReservation.data()!['primaryGuestName'],
        'Sebastiaan Van Wijk',
      );
      expect(updatedReservation.data()!['primaryGuestId'], 'g2');
      expect(
        updatedPitch.data()!['currentPrimaryGuestName'],
        'Sebastiaan Van Wijk',
      );
      expect(updatedPitch.data()!['currentGuestCount'], 2);
      expect(firstGuest.data()!['isPrimaryGuest'], false);
    },
  );

  test(
    'updating primary guest syncs reservation and pitch guest name',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(
            reservation()
                .copyWith(
                  primaryGuestName: 'Ana Horvat',
                  primaryGuestId: 'g1',
                  registeredGuestCount: 2,
                  currentGuests: 2,
                )
                .toMap(),
          );
      await firestore.collection('pitches').doc('pitch-1').set({
        'id': 'pitch-1',
        'name': 'Parcela 1',
        'number': 1,
        'zone': 'A',
        'status': 'occupied',
        'maxGuests': 4,
        'currentGuests': 2,
        'currentGuestCount': 2,
        'currentReservationId': 'res-1',
        'currentPrimaryGuestName': 'Ana Horvat',
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
            'pitchId': 'pitch-1',
            'pitchName': 'Parcela 1',
            'firstName': 'Ana',
            'lastName': 'Horvat',
            'documentType': 'nationalIdCard',
            'documentNumber': 'L11111111',
            'isPrimaryGuest': true,
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
      await firestore
          .collection('reservations')
          .doc('res-1')
          .collection('guests')
          .doc('g2')
          .set({
            'id': 'g2',
            'reservationId': 'res-1',
            'pitchId': 'pitch-1',
            'pitchName': 'Parcela 1',
            'firstName': 'Iva',
            'lastName': 'Ivić',
            'documentType': 'nationalIdCard',
            'documentNumber': 'L22222222',
            'isPrimaryGuest': false,
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

      await service.updateGuest(
        'res-1',
        guest(
          id: 'g2',
          firstName: 'Iva',
          lastName: 'Ivić',
          documentNumber: 'L22222222',
          isPrimary: true,
        ),
      );

      final updatedReservation = await firestore
          .collection('reservations')
          .doc('res-1')
          .get();
      final updatedPitch = await firestore
          .collection('pitches')
          .doc('pitch-1')
          .get();
      final firstGuest = await firestore
          .collection('reservations')
          .doc('res-1')
          .collection('guests')
          .doc('g1')
          .get();
      final secondGuest = await firestore
          .collection('reservations')
          .doc('res-1')
          .collection('guests')
          .doc('g2')
          .get();

      expect(updatedReservation.data()!['primaryGuestName'], 'Iva Ivić');
      expect(updatedReservation.data()!['primaryGuestId'], 'g2');
      expect(updatedPitch.data()!['currentPrimaryGuestName'], 'Iva Ivić');
      expect(firstGuest.data()!['isPrimaryGuest'], false);
      expect(secondGuest.data()!['isPrimaryGuest'], true);
    },
  );

  test(
    'guest directory falls back to reservation id from document path',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(
            reservation(
              status: ReservationStatus.confirmed,
            ).copyWith(primaryGuestName: 'Lara Bruggeman').toMap(),
          );
      await firestore
          .collection('reservations')
          .doc('res-1')
          .collection('guests')
          .doc('g1')
          .set({
            'id': 'g1',
            'firstName': 'Sebastiaan',
            'lastName': 'Van Wijk',
            'pitchId': 'pitch-1',
            'pitchName': 'Parcela 1',
            'documentType': 'passport',
            'documentNumber': 'X1111111',
            'isPrimaryGuest': true,
            'verificationStatus': 'verified',
            'verificationMethod': 'ocrManual',
            'documentAcceptanceStatus': 'accepted',
            'manualReviewCompleted': true,
            'documentImagePath': '',
            'documentImagePaths': <String>[],
            'retentionPolicy': 'retainManually',
            'cleanupPending': false,
            'ocrStatus': 'completed',
            'checkInDate': DateTime(2026, 6, 20),
            'checkOutDate': DateTime(2026, 6, 24),
          });

      final entries = await service.watchGuestDirectory().firstWhere(
        (entries) => entries.isNotEmpty,
      );

      expect(entries, hasLength(1));
      expect(entries.first.guest.reservationId, 'res-1');
      expect(entries.first.guest.firstName, 'Sebastiaan');
      expect(entries.first.reservation.id, 'res-1');
    },
  );

  test('reconcileGuestState refreshes stale primary guest metadata', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(
          reservation()
              .copyWith(
                primaryGuestName: 'Lara Bruggeman',
                primaryGuestId: 'g1',
                registeredGuestCount: 2,
                currentGuests: 2,
              )
              .toMap(),
        );
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 2,
      'currentGuestCount': 2,
      'currentReservationId': 'res-1',
      'currentPrimaryGuestName': 'Lara Bruggeman',
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
          'pitchId': 'pitch-1',
          'pitchName': 'Parcela 1',
          'firstName': 'Lara',
          'lastName': 'Bruggeman',
          'documentType': 'passport',
          'documentNumber': 'X1111111',
          'isPrimaryGuest': false,
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
    await firestore
        .collection('reservations')
        .doc('res-1')
        .collection('guests')
        .doc('g2')
        .set({
          'id': 'g2',
          'reservationId': 'res-1',
          'pitchId': 'pitch-1',
          'pitchName': 'Parcela 1',
          'firstName': 'Sebastiaan',
          'lastName': 'Van Wijk',
          'documentType': 'passport',
          'documentNumber': 'X2222222',
          'isPrimaryGuest': true,
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

    await service.reconcileGuestState('res-1');

    final updatedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    final updatedPitch = await firestore
        .collection('pitches')
        .doc('pitch-1')
        .get();

    expect(
      updatedReservation.data()!['primaryGuestName'],
      'Sebastiaan Van Wijk',
    );
    expect(updatedReservation.data()!['primaryGuestId'], 'g2');
    expect(
      updatedPitch.data()!['currentPrimaryGuestName'],
      'Sebastiaan Van Wijk',
    );
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

  test('create and check-in occupies pitch in a single flow', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

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

    final incoming = reservation(status: ReservationStatus.confirmed).copyWith(
      id: '',
      primaryGuestName: 'Test Gost',
      pitchName: 'Primorje 1 istok',
      adults: 2,
      children: 1,
      guestCount: 3,
    );

    await service.createReservationAndCheckIn(incoming, checkedInByUid: 'uid');

    final reservations = await firestore.collection('reservations').get();
    expect(reservations.docs.length, 1);
    final savedReservation = reservations.docs.first.data();
    final savedReservationId = reservations.docs.first.id;
    final pitch = await firestore.collection('pitches').doc('pitch-1').get();

    expect(savedReservation['status'], ReservationStatus.checkedIn.name);
    expect(savedReservation['checkedInByUid'], 'uid');
    expect(savedReservation['currentGuests'], 3);
    expect(savedReservation['registeredGuestCount'], 3);
    expect(pitch.data()!['status'], 'occupied');
    expect(pitch.data()!['currentReservationId'], savedReservationId);
    expect(pitch.data()!['currentGuestCount'], 3);
    expect(pitch.data()!['currentPrimaryGuestName'], 'Test Gost');
  });

  test('create and check-in rejects occupied pitch', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Primorje 1 istok',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 2,
      'currentGuestCount': 2,
      'currentReservationId': 'res-existing',
      'currentPrimaryGuestName': 'Drugi Gost',
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    final incoming = reservation(
      status: ReservationStatus.confirmed,
    ).copyWith(id: '', primaryGuestName: 'Test Gost', guestCount: 2);

    await expectLater(
      () => service.createReservationAndCheckIn(incoming),
      throwsA(isA<ReservationConflictException>()),
    );

    final reservations = await firestore.collection('reservations').get();
    expect(reservations.docs, isEmpty);
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

    await service.checkOutReservation(
      reservationId: 'res-1',
      checkedOutByUid: 'test-user',
    );

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
    'updating checked-in reservation to a new pitch moves occupancy',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(
            reservation(status: ReservationStatus.checkedIn)
                .copyWith(
                  primaryGuestName: 'Sebastiaan',
                  registeredGuestCount: 2,
                  currentGuests: 2,
                )
                .toMap(),
          );
      await firestore.collection('pitches').doc('pitch-1').set({
        'id': 'pitch-1',
        'name': 'Parcela 1',
        'number': 1,
        'zone': 'A',
        'status': 'occupied',
        'maxGuests': 4,
        'currentGuests': 2,
        'currentGuestCount': 2,
        'currentReservationId': 'res-1',
        'currentPrimaryGuestName': 'Sebastiaan',
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
      });
      await firestore.collection('pitches').doc('pitch-2').set({
        'id': 'pitch-2',
        'name': 'Parcela 2',
        'number': 2,
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
            'pitchId': 'pitch-1',
            'pitchName': 'Parcela 1',
            'firstName': 'Sebastiaan',
            'lastName': 'Guest',
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

      await service.updateReservation(
        reservation(status: ReservationStatus.checkedIn).copyWith(
          id: 'res-1',
          primaryGuestName: 'Sebastiaan',
          pitchId: 'pitch-2',
          pitchName: 'Parcela 2',
          pitchIds: const ['pitch-2'],
          registeredGuestCount: 2,
          currentGuests: 2,
        ),
      );

      final oldPitch = await firestore
          .collection('pitches')
          .doc('pitch-1')
          .get();
      final newPitch = await firestore
          .collection('pitches')
          .doc('pitch-2')
          .get();
      final updatedReservation = await firestore
          .collection('reservations')
          .doc('res-1')
          .get();
      final guestDoc = await firestore
          .collection('reservations')
          .doc('res-1')
          .collection('guests')
          .doc('g1')
          .get();

      expect(updatedReservation.data()!['pitchId'], 'pitch-2');
      expect(oldPitch.data()!['status'], 'available');
      expect(oldPitch.data()!['currentReservationId'], isNull);
      expect(newPitch.data()!['status'], 'occupied');
      expect(newPitch.data()!['currentReservationId'], 'res-1');
      expect(newPitch.data()!['currentGuestCount'], 1);
      expect(guestDoc.data()!['pitchId'], 'pitch-2');
      expect(guestDoc.data()!['pitchName'], 'Parcela 2');
    },
  );

  test(
    'updating checked-in reservation on same pitch refreshes occupancy data',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(
            reservation(status: ReservationStatus.checkedIn)
                .copyWith(
                  primaryGuestName: 'Sebastiaan',
                  registeredGuestCount: 1,
                  currentGuests: 1,
                )
                .toMap(),
          );
      await firestore.collection('pitches').doc('pitch-1').set({
        'id': 'pitch-1',
        'name': 'Parcela 1',
        'number': 1,
        'zone': 'A',
        'status': 'occupied',
        'maxGuests': 4,
        'currentGuests': 1,
        'currentGuestCount': 1,
        'currentReservationId': 'res-1',
        'currentPrimaryGuestName': 'Sebastiaan',
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
      });

      await service.updateReservation(
        reservation(status: ReservationStatus.checkedIn).copyWith(
          id: 'res-1',
          primaryGuestName: 'Sebastiaan Updated',
          pitchId: 'pitch-1',
          pitchName: 'Parcela 1',
          pitchIds: const ['pitch-1'],
          checkOutDate: DateTime(2026, 6, 26),
          registeredGuestCount: 1,
          currentGuests: 1,
        ),
      );

      final pitch = await firestore.collection('pitches').doc('pitch-1').get();
      expect(pitch.data()!['status'], 'occupied');
      expect(pitch.data()!['currentReservationId'], 'res-1');
      expect(pitch.data()!['currentPrimaryGuestName'], 'Sebastiaan Updated');
    },
  );

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

  test('detects duplicate by sourceReservationId and source', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    final existing = reservation(status: ReservationStatus.confirmed).copyWith(
      id: 'res-existing',
      source: ReservationSource.booking,
      sourceReservationId: 'BK-1234',
      primaryGuestName: 'Ana Horvat',
      checkInDate: DateTime(2026, 8, 10),
      checkOutDate: DateTime(2026, 8, 12),
    );
    await firestore
        .collection('reservations')
        .doc(existing.id)
        .set(existing.toMap());

    final incoming = reservation(status: ReservationStatus.confirmed).copyWith(
      id: 'res-new',
      source: ReservationSource.booking,
      sourceReservationId: 'BK-1234',
      primaryGuestName: 'Drugo Ime',
      checkInDate: DateTime(2026, 9, 1),
      checkOutDate: DateTime(2026, 9, 3),
    );

    final result = await service.checkDuplicateBeforeCreate(incoming);

    expect(result.hasDuplicate, isTrue);
    expect(result.isHardDuplicate, isTrue);
    expect(result.reason, 'sourceReservationId');
    expect(result.match?.id, 'res-existing');
  });

  test('detects duplicate by normalized name and dates', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    final existing = reservation(status: ReservationStatus.confirmed).copyWith(
      id: 'res-existing',
      primaryGuestName: 'Čorić Ana',
      checkInDate: DateTime(2026, 9, 3),
      checkOutDate: DateTime(2026, 9, 7),
    );
    await firestore
        .collection('reservations')
        .doc(existing.id)
        .set(existing.toMap());

    final incoming = reservation(status: ReservationStatus.confirmed).copyWith(
      id: 'res-new',
      primaryGuestName: 'Coric    Ana',
      checkInDate: DateTime(2026, 9, 3),
      checkOutDate: DateTime(2026, 9, 7),
    );

    final result = await service.checkDuplicateBeforeCreate(incoming);

    expect(result.hasDuplicate, isTrue);
    expect(result.isHardDuplicate, isFalse);
    expect(result.reason, 'nameAndDates');
  });

  test(
    'returns overlap conflicts for confirmed and checked-in reservations',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      final confirmed = reservation(status: ReservationStatus.confirmed)
          .copyWith(
            id: 'res-confirmed',
            pitchId: 'pitch-7',
            pitchIds: const ['pitch-7'],
            pitchName: 'Parcela 7',
            checkInDate: DateTime(2026, 8, 10),
            checkOutDate: DateTime(2026, 8, 14),
          );
      await firestore
          .collection('reservations')
          .doc(confirmed.id)
          .set(confirmed.toMap());

      final incoming = reservation(status: ReservationStatus.confirmed)
          .copyWith(
            id: 'res-new',
            pitchId: 'pitch-7',
            pitchIds: const ['pitch-7'],
            checkInDate: DateTime(2026, 8, 12),
            checkOutDate: DateTime(2026, 8, 16),
          );

      final conflicts = await service.checkOverlapBeforeCreate(incoming);

      expect(conflicts, isNotEmpty);
      expect(conflicts.first.pitchId, 'pitch-7');
      expect(conflicts.first.existing.id, 'res-confirmed');
    },
  );

  test('ignores overlap for cancelled reservations', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    final cancelled = reservation(status: ReservationStatus.cancelled).copyWith(
      id: 'res-cancelled',
      pitchId: 'pitch-3',
      pitchIds: const ['pitch-3'],
      pitchName: 'Parcela 3',
      checkInDate: DateTime(2026, 7, 1),
      checkOutDate: DateTime(2026, 7, 6),
    );
    await firestore
        .collection('reservations')
        .doc(cancelled.id)
        .set(cancelled.toMap());

    final incoming = reservation(status: ReservationStatus.confirmed).copyWith(
      id: 'res-new',
      pitchId: 'pitch-3',
      pitchIds: const ['pitch-3'],
      checkInDate: DateTime(2026, 7, 2),
      checkOutDate: DateTime(2026, 7, 4),
    );

    final conflicts = await service.checkOverlapBeforeCreate(incoming);

    expect(conflicts, isEmpty);
  });

  test('reconciles reservation payment from linked payments', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(
          reservation(status: ReservationStatus.checkedIn)
              .copyWith(
                totalPrice: 120,
                amountPaid: 0,
                paymentStatus: PaymentStatus.unpaid,
              )
              .toMap(),
        );
    await firestore.collection('payments').doc('pay-1').set({
      'id': 'pay-1',
      'reservationId': 'res-1',
      'guestName': 'Test Guest',
      'amount': 70,
      'method': 'cash',
      'notes': 'A',
      'createdAt': DateTime(2026, 6, 25),
      'updatedAt': DateTime(2026, 6, 25),
    });
    await firestore.collection('payments').doc('pay-2').set({
      'id': 'pay-2',
      'reservationId': 'res-1',
      'guestName': 'Test Guest',
      'amount': 50,
      'method': 'cash',
      'notes': 'B',
      'createdAt': DateTime(2026, 6, 25),
      'updatedAt': DateTime(2026, 6, 25),
    });

    await service.reconcileReservationPaymentFromPayments(
      reservationId: 'res-1',
      fallbackGuestName: 'Test Guest',
    );

    final updated = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    expect(updated.data()!['amountPaid'], 120.0);
    expect(updated.data()!['paymentStatus'], PaymentStatus.paid.name);
  });

  test('reconciles orphan guest payments by assigning reservationId', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(
          reservation(status: ReservationStatus.checkedIn)
              .copyWith(
                primaryGuestName: 'trpa',
                totalPrice: 100,
                amountPaid: 0,
                paymentStatus: PaymentStatus.unpaid,
              )
              .toMap(),
        );
    await firestore.collection('payments').doc('pay-legacy').set({
      'id': 'pay-legacy',
      'reservationId': '',
      'guestName': 'trpa',
      'amount': 40,
      'method': 'cash',
      'notes': 'legacy',
      'createdAt': DateTime(2026, 6, 25),
      'updatedAt': DateTime(2026, 6, 25),
    });
    await firestore.collection('payments').doc('pay-null').set({
      'id': 'pay-null',
      'reservationId': null,
      'guestName': 'TRPA',
      'amount': 30,
      'method': 'cash',
      'notes': 'legacy-null',
      'createdAt': DateTime(2026, 6, 25),
      'updatedAt': DateTime(2026, 6, 25),
    });
    await firestore.collection('payments').doc('pay-missing').set({
      'id': 'pay-missing',
      'guestName': 'Trpa',
      'amount': 30,
      'method': 'cash',
      'notes': 'legacy-missing',
      'createdAt': DateTime(2026, 6, 25),
      'updatedAt': DateTime(2026, 6, 25),
    });

    await service.reconcileReservationPaymentFromPayments(
      reservationId: 'res-1',
      fallbackGuestName: 'trpa',
    );

    final updatedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    final updatedPayment = await firestore
        .collection('payments')
        .doc('pay-legacy')
        .get();

    expect(updatedReservation.data()!['amountPaid'], 100.0);
    expect(
      updatedReservation.data()!['paymentStatus'],
      PaymentStatus.paid.name,
    );
    expect(updatedPayment.data()!['reservationId'], 'res-1');
    final updatedNullPayment = await firestore
        .collection('payments')
        .doc('pay-null')
        .get();
    final updatedMissingPayment = await firestore
        .collection('payments')
        .doc('pay-missing')
        .get();
    expect(updatedNullPayment.data()!['reservationId'], 'res-1');
    expect(updatedMissingPayment.data()!['reservationId'], 'res-1');
  });
}
