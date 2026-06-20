import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../parcels/models/pitch.dart';
import '../models/document_image.dart';
import '../models/document_verification_ui.dart';
import '../models/reservation.dart';
import '../models/reservation_guest.dart';

class GuestSaveDuplicateMatch {
  const GuestSaveDuplicateMatch({
    required this.guestId,
    required this.reason,
    required this.displayName,
  });

  final String guestId;
  final String reason;
  final String displayName;
}

class GuestSaveResult {
  const GuestSaveResult({
    required this.guest,
    required this.saved,
    this.duplicateMatch,
    this.cleanupPending = false,
    this.warningMessage,
  });

  final ReservationGuest guest;
  final bool saved;
  final GuestSaveDuplicateMatch? duplicateMatch;
  final bool cleanupPending;
  final String? warningMessage;
}

class GuestDirectoryEntry {
  const GuestDirectoryEntry({required this.guest, required this.reservation});

  final ReservationGuest guest;
  final Reservation reservation;
}

class ReservationConflictException implements Exception {
  ReservationConflictException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReservationService {
  ReservationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _reservations =>
      _firestore.collection('reservations');

  CollectionReference<Map<String, dynamic>> _guests(String reservationId) {
    return _reservations.doc(reservationId).collection('guests');
  }

  Stream<List<Reservation>> watchReservations() {
    return _reservations
        .orderBy('checkInDate', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Reservation.fromDoc).toList());
  }

  Stream<List<GuestDirectoryEntry>> watchGuestDirectory() {
    final controller = StreamController<List<GuestDirectoryEntry>>();
    Map<String, Reservation> reservationsById = const <String, Reservation>{};
    List<QueryDocumentSnapshot<Map<String, dynamic>>> guestDocs =
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    void emit() {
      final entries = <GuestDirectoryEntry>[];
      for (final guestDoc in guestDocs) {
        final guest = ReservationGuest.fromDoc(guestDoc);
        final reservationId = guest.reservationId.trim();
        if (reservationId.isEmpty) {
          continue;
        }
        final reservation = reservationsById[reservationId];
        if (reservation == null) {
          continue;
        }
        entries.add(
          GuestDirectoryEntry(guest: guest, reservation: reservation),
        );
      }
      controller.add(entries);
    }

    final reservationsSub = _reservations.snapshots().listen((snapshot) {
      reservationsById = {
        for (final doc in snapshot.docs) doc.id: Reservation.fromDoc(doc),
      };
      emit();
    });

    final guestsSub = _firestore.collectionGroup('guests').snapshots().listen((
      snapshot,
    ) {
      guestDocs = snapshot.docs;
      emit();
    });

    controller.onCancel = () async {
      await reservationsSub.cancel();
      await guestsSub.cancel();
    };

    return controller.stream;
  }

  Future<void> createReservation(Reservation reservation) async {
    final doc = reservation.id.isEmpty
        ? _reservations.doc()
        : _reservations.doc(reservation.id);

    await doc.set({
      ...reservation.toMap(),
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateReservation(Reservation reservation) async {
    await _reservations.doc(reservation.id).update({
      ...reservation.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteReservation(String reservationId) async {
    await _reservations.doc(reservationId).delete();
  }

  Stream<List<ReservationGuest>> watchGuests(String reservationId) {
    return _guests(reservationId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(ReservationGuest.fromDoc).toList(),
        );
  }

  Future<void> createGuest(String reservationId, ReservationGuest guest) async {
    final reservationDoc = await _reservations.doc(reservationId).get();
    if (!reservationDoc.exists) {
      throw StateError('Rezervacija ne postoji.');
    }
    final reservation = Reservation.fromDoc(reservationDoc);

    final collection = _guests(reservationId);
    final doc = guest.id.isEmpty ? collection.doc() : collection.doc(guest.id);

    final normalizedGuest = guest.copyWith(
      id: doc.id,
      reservationId: reservationId,
      pitchId: reservation.pitchId,
      pitchName: reservation.pitchName,
      checkInDate: reservation.checkInDate,
      checkOutDate: reservation.checkOutDate,
      maskedDocumentNumber: maskDocumentNumber(guest.documentNumber),
    );

    await doc.set({
      ...normalizedGuest.toMap(),
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _syncGuestCounters(reservationId);
  }

  Future<void> createGuestWithDocumentImages(
    String reservationId,
    ReservationGuest guest,
    List<DocumentImage> images,
  ) async {
    final collection = _guests(reservationId);
    final doc = guest.id.isEmpty ? collection.doc() : collection.doc(guest.id);
    final batch = _firestore.batch();

    batch.set(doc, {
      ...guest
          .copyWith(
            maskedDocumentNumber: maskDocumentNumber(guest.documentNumber),
          )
          .toMap(),
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final imagesCollection = doc.collection('documentImages');
    for (final image in images) {
      final imageDoc = imagesCollection.doc(image.id);
      batch.set(imageDoc, {
        ...image.toFirestoreMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    await _syncGuestCounters(reservationId);
  }

  Future<GuestSaveResult> saveVerifiedGuest({
    required Reservation reservation,
    required ReservationGuest guest,
    required List<DocumentImage> images,
    required DocumentAcceptanceStatus acceptanceStatus,
    required bool manualReviewCompleted,
    required DocumentRetentionPolicy retentionPolicy,
    bool allowDuplicate = false,
  }) async {
    final guestsCollection = _guests(reservation.id);
    final guestDoc = guest.id.trim().isEmpty
        ? guestsCollection.doc()
        : guestsCollection.doc(guest.id.trim());
    final resolvedGuestId = guestDoc.id;

    final duplicate = await _findDuplicateGuest(
      reservationId: reservation.id,
      guestId: resolvedGuestId,
      documentNumber: guest.documentNumber,
      firstName: guest.firstName,
      lastName: guest.lastName,
      dateOfBirth: guest.dateOfBirth,
    );
    if (duplicate != null && !allowDuplicate) {
      return GuestSaveResult(
        guest: guest,
        saved: false,
        duplicateMatch: duplicate,
      );
    }

    final normalizedGuest = guest.copyWith(
      id: resolvedGuestId,
      reservationId: reservation.id,
      pitchId: reservation.pitchId,
      pitchName: reservation.pitchName,
      checkInDate: reservation.checkInDate,
      checkOutDate: reservation.checkOutDate,
      maskedDocumentNumber: maskDocumentNumber(guest.documentNumber),
      verificationStatus: acceptanceStatus == DocumentAcceptanceStatus.rejected
          ? GuestVerificationStatus.rejected
          : (acceptanceStatus == DocumentAcceptanceStatus.accepted
                ? GuestVerificationStatus.verified
                : GuestVerificationStatus.pendingReview),
      verificationMethod: manualReviewCompleted
          ? GuestVerificationMethod.ocrManual
          : GuestVerificationMethod.ocrAuto,
      documentAcceptanceStatus: acceptanceStatus.name,
      manualReviewCompleted: manualReviewCompleted,
      documentImagePath: images.map((item) => item.storagePath).join(','),
      documentImagePaths: images
          .map((item) => item.storagePath)
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false),
      retentionPolicy: retentionPolicy,
      deleteAfterDate:
          retentionPolicy == DocumentRetentionPolicy.deleteAfterCheckout
          ? reservation.checkOutDate
          : null,
      cleanupPending: false,
    );

    final reservationRef = _reservations.doc(reservation.id);
    final pitchRef = _firestore.collection('pitches').doc(reservation.pitchId);

    final existingGuests = await guestsCollection.get();
    final existingIds = existingGuests.docs.map((item) => item.id).toSet();
    existingIds.add(resolvedGuestId);

    final existingPrimaryGuests = normalizedGuest.isPrimaryGuest
        ? await guestsCollection.where('isPrimaryGuest', isEqualTo: true).get()
        : null;

    await _firestore.runTransaction<void>((tx) async {
      final reservationSnap = await tx.get(reservationRef);
      if (!reservationSnap.exists) {
        throw StateError('Rezervacija ne postoji.');
      }

      if (normalizedGuest.isPrimaryGuest && existingPrimaryGuests != null) {
        for (final doc in existingPrimaryGuests.docs) {
          if (doc.id == resolvedGuestId) {
            continue;
          }
          tx.update(doc.reference, {
            'isPrimaryGuest': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      tx.set(guestDoc, {
        ...normalizedGuest.toMap(),
        'id': resolvedGuestId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final reservationPatch = <String, dynamic>{
        'registeredGuestCount': existingIds.length,
        if (reservation.status == ReservationStatus.checkedIn)
          'currentGuests': existingIds.length,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (normalizedGuest.isPrimaryGuest) {
        reservationPatch['primaryGuestName'] =
            '${normalizedGuest.firstName} ${normalizedGuest.lastName}'.trim();
        reservationPatch['primaryGuestId'] = normalizedGuest.id;
      }
      tx.update(reservationRef, reservationPatch);

      if (reservation.status == ReservationStatus.checkedIn) {
        tx.update(pitchRef, {
          'status': PitchStatus.occupied.name,
          'currentGuests': existingIds.length,
          'currentGuestCount': existingIds.length,
          'currentReservationId': reservation.id,
          'currentPrimaryGuestName':
              reservationPatch['primaryGuestName'] ??
              reservation.primaryGuestName,
          'occupiedFrom': Timestamp.fromDate(reservation.checkInDate),
          'occupiedUntil': Timestamp.fromDate(reservation.checkOutDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    final imagesCollection = guestDoc.collection('documentImages');
    final imageBatch = _firestore.batch();
    for (final image in images) {
      imageBatch.set(imagesCollection.doc(image.id), {
        ...image.toFirestoreMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await imageBatch.commit();

    return GuestSaveResult(
      guest: normalizedGuest,
      saved: true,
      cleanupPending: false,
    );
  }

  Future<GuestSaveDuplicateMatch?> _findDuplicateGuest({
    required String reservationId,
    required String guestId,
    required String documentNumber,
    required String firstName,
    required String lastName,
    required DateTime? dateOfBirth,
  }) async {
    final guestsCollection = _guests(reservationId);

    final byDocument = documentNumber.trim();
    if (byDocument.isNotEmpty) {
      final docQuery = await guestsCollection
          .where('documentNumber', isEqualTo: byDocument)
          .limit(1)
          .get();
      if (docQuery.docs.isNotEmpty && docQuery.docs.first.id != guestId) {
        final item = ReservationGuest.fromDoc(docQuery.docs.first);
        return GuestSaveDuplicateMatch(
          guestId: item.id,
          reason: 'documentNumber',
          displayName: '${item.firstName} ${item.lastName}'.trim(),
        );
      }
    }

    final normalizedFirst = firstName.trim().toUpperCase();
    final normalizedLast = lastName.trim().toUpperCase();
    if (normalizedFirst.isEmpty ||
        normalizedLast.isEmpty ||
        dateOfBirth == null) {
      return null;
    }

    final allGuests = await guestsCollection.get();
    for (final doc in allGuests.docs) {
      if (doc.id == guestId) {
        continue;
      }
      final existing = ReservationGuest.fromDoc(doc);
      if (existing.firstName.trim().toUpperCase() != normalizedFirst ||
          existing.lastName.trim().toUpperCase() != normalizedLast) {
        continue;
      }
      final existingBirth = existing.dateOfBirth;
      if (existingBirth == null) {
        continue;
      }

      final a = DateTime(
        existingBirth.year,
        existingBirth.month,
        existingBirth.day,
      );
      final b = DateTime(dateOfBirth.year, dateOfBirth.month, dateOfBirth.day);
      if (a == b) {
        return GuestSaveDuplicateMatch(
          guestId: existing.id,
          reason: 'identityTriplet',
          displayName: '${existing.firstName} ${existing.lastName}'.trim(),
        );
      }
    }

    return null;
  }

  Future<void> upsertGuestDocumentImage(
    String reservationId,
    String guestId,
    DocumentImage image,
  ) async {
    final imageDoc = _guests(
      reservationId,
    ).doc(guestId).collection('documentImages').doc(image.id);
    await imageDoc.set({
      ...image.toFirestoreMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteGuestDocumentImage(
    String reservationId,
    String guestId,
    String imageId,
  ) async {
    final imageDoc = _guests(
      reservationId,
    ).doc(guestId).collection('documentImages').doc(imageId);
    await imageDoc.delete();
  }

  Future<void> replaceGuestDocumentImage({
    required String reservationId,
    required String guestId,
    required String oldImageId,
    required DocumentImage newImage,
  }) async {
    final imagesCollection = _guests(
      reservationId,
    ).doc(guestId).collection('documentImages');
    final batch = _firestore.batch();

    batch.set(imagesCollection.doc(newImage.id), {
      ...newImage.toFirestoreMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(imagesCollection.doc(oldImageId));

    await batch.commit();
  }

  Future<void> updateGuest(String reservationId, ReservationGuest guest) async {
    await _guests(reservationId).doc(guest.id).update({
      ...guest.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGuest(String reservationId, String guestId) async {
    await _guests(reservationId).doc(guestId).delete();
    await _syncGuestCounters(reservationId);
  }

  Future<void> _syncGuestCounters(String reservationId) async {
    final reservationRef = _reservations.doc(reservationId);
    final reservationSnap = await reservationRef.get();
    if (!reservationSnap.exists) {
      return;
    }

    final reservation = Reservation.fromDoc(reservationSnap);
    final guestCount = (await _guests(reservationId).get()).docs.length;

    final reservationPatch = <String, dynamic>{
      'registeredGuestCount': guestCount,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (reservation.status == ReservationStatus.checkedIn) {
      reservationPatch['currentGuests'] = guestCount;
    }
    await reservationRef.update(reservationPatch);

    if (reservation.status == ReservationStatus.checkedIn) {
      await _firestore.collection('pitches').doc(reservation.pitchId).update({
        'currentGuests': guestCount,
        'currentGuestCount': guestCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> checkInReservation({
    required String reservationId,
    required String checkedInByUid,
  }) async {
    final reservationRef = _reservations.doc(reservationId);
    final guestCount = (await _guests(reservationId).get()).docs.length;

    await _firestore.runTransaction<void>((tx) async {
      final reservationSnap = await tx.get(reservationRef);
      if (!reservationSnap.exists) {
        throw StateError('Rezervacija ne postoji.');
      }

      final reservation = Reservation.fromDoc(reservationSnap);
      if (reservation.status == ReservationStatus.cancelled) {
        throw ReservationConflictException(
          'Rezervacija je otkazana i nije je moguće prijaviti.',
        );
      }
      if (reservation.status == ReservationStatus.checkedOut) {
        throw ReservationConflictException(
          'Rezervacija je već odjavljena i nije moguće ponovno prijaviti dolazak.',
        );
      }
      if (reservation.status == ReservationStatus.checkedIn) {
        return;
      }

      final pitchRef = _firestore
          .collection('pitches')
          .doc(reservation.pitchId);
      final pitchSnap = await tx.get(pitchRef);
      if (!pitchSnap.exists) {
        throw ReservationConflictException(
          'Parcela za ovu rezervaciju ne postoji.',
        );
      }
      final pitchData = pitchSnap.data() ?? const <String, dynamic>{};
      final pitchStatus = (pitchData['status'] as String? ?? '').trim();
      final currentReservationId =
          (pitchData['currentReservationId'] as String? ?? '').trim();

      if (pitchStatus == PitchStatus.occupied.name &&
          currentReservationId.isNotEmpty &&
          currentReservationId != reservation.id) {
        throw ReservationConflictException(
          'Parcela je već zauzeta drugom rezervacijom. Prijava dolaska nije moguća.',
        );
      }

      final checkedInOnPitch = await _reservations
          .where('pitchId', isEqualTo: reservation.pitchId)
          .where('status', isEqualTo: ReservationStatus.checkedIn.name)
          .limit(2)
          .get();
      final conflicting = checkedInOnPitch.docs.any(
        (doc) => doc.id != reservation.id,
      );
      if (conflicting) {
        throw ReservationConflictException(
          'Na odabranoj parceli već postoji aktivna prijava druge rezervacije.',
        );
      }

      tx.update(reservationRef, {
        'status': ReservationStatus.checkedIn.name,
        'actualCheckInAt': FieldValue.serverTimestamp(),
        'checkedInByUid': checkedInByUid,
        'registeredGuestCount': guestCount,
        'currentGuests': guestCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(pitchRef, {
        'status': PitchStatus.occupied.name,
        'currentReservationId': reservation.id,
        'currentGuestCount': guestCount,
        'currentGuests': guestCount,
        'currentPrimaryGuestName': reservation.primaryGuestName,
        'occupiedFrom': Timestamp.fromDate(reservation.checkInDate),
        'occupiedUntil': Timestamp.fromDate(reservation.checkOutDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> checkOutReservation({required String reservationId}) async {
    final reservationRef = _reservations.doc(reservationId);

    await _firestore.runTransaction<void>((tx) async {
      final reservationSnap = await tx.get(reservationRef);
      if (!reservationSnap.exists) {
        throw StateError('Rezervacija ne postoji.');
      }

      final reservation = Reservation.fromDoc(reservationSnap);
      if (reservation.status != ReservationStatus.checkedIn) {
        throw ReservationConflictException(
          'Odjava je moguća samo za prijavljene rezervacije.',
        );
      }

      final pitchRef = _firestore
          .collection('pitches')
          .doc(reservation.pitchId);

      tx.update(reservationRef, {
        'status': ReservationStatus.checkedOut.name,
        'actualCheckOutAt': FieldValue.serverTimestamp(),
        'currentGuests': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(pitchRef, {
        'status': PitchStatus.available.name,
        'currentReservationId': null,
        'currentGuestCount': 0,
        'currentGuests': 0,
        'currentPrimaryGuestName': null,
        'occupiedFrom': null,
        'occupiedUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
