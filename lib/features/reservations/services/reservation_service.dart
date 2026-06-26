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

class ReservationDuplicateCheckResult {
  const ReservationDuplicateCheckResult({
    required this.hasDuplicate,
    this.match,
    this.isHardDuplicate = false,
    this.reason,
  });

  final bool hasDuplicate;
  final Reservation? match;
  final bool isHardDuplicate;
  final String? reason;
}

class ReservationDuplicateException implements Exception {
  ReservationDuplicateException(this.result);

  final ReservationDuplicateCheckResult result;

  @override
  String toString() => 'Moguća postojeća rezervacija';
}

class ReservationOverlapConflict {
  const ReservationOverlapConflict({
    required this.existing,
    required this.pitchId,
    required this.pitchName,
  });

  final Reservation existing;
  final String pitchId;
  final String pitchName;
}

class ReservationService {
  ReservationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  FirebaseFirestore get firestore => _firestore;

  String _resolveReservationIdForGuestDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> guestDoc,
    ReservationGuest guest,
  ) {
    final fieldValue = guest.reservationId.trim();
    if (fieldValue.isNotEmpty) {
      return fieldValue;
    }
    return guestDoc.reference.parent.parent?.id ?? '';
  }

  CollectionReference<Map<String, dynamic>> get _reservations =>
      _firestore.collection('reservations');

  CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');

  CollectionReference<Map<String, dynamic>> _guests(String reservationId) {
    return _reservations.doc(reservationId).collection('guests');
  }

  String _resolvePrimaryGuestName(Reservation reservation) {
    final fromPrimary = reservation.primaryGuestName.trim();
    if (fromPrimary.isNotEmpty) {
      return fromPrimary;
    }

    final fromParts = <String>[
      reservation.primaryGuestFirstName.trim(),
      reservation.primaryGuestLastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ').trim();
    if (fromParts.isNotEmpty) {
      return fromParts;
    }

    return reservation.primaryGuestName.trim();
  }

  Future<void> _createInitialPaymentIfNeeded(
    String reservationId,
    Reservation reservation,
  ) async {
    final amount = reservation.amountPaid;
    if (amount <= 0) {
      return;
    }

    final guestName = _resolvePrimaryGuestName(reservation);
    if (guestName.isEmpty) {
      return;
    }

    final paymentRef = _payments.doc();
    final now = DateTime.now();
    await paymentRef.set(<String, dynamic>{
      'id': paymentRef.id,
      'reservationId': reservationId,
      'guestName': guestName,
      'amount': amount,
      'method': 'cash',
      'notes': 'Početna uplata pri kreiranju rezervacije',
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  Stream<List<Reservation>> watchReservations() {
    final now = DateTime.now();
    final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
    final threeMonthsLater = DateTime(
      now.year,
      now.month + 3,
      now.day,
    ).add(const Duration(days: 1));

    return _reservations
        .where('checkInDate', isGreaterThanOrEqualTo: threeMonthsAgo)
        .where('checkInDate', isLessThan: threeMonthsLater)
        .orderBy('checkInDate', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Reservation.fromDoc).toList());
  }

  Stream<Reservation?> watchReservationById(String reservationId) {
    return _reservations.doc(reservationId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return Reservation.fromDoc(snapshot);
    });
  }

  Stream<List<GuestDirectoryEntry>> watchGuestDirectory() {
    final controller = StreamController<List<GuestDirectoryEntry>>();
    Map<String, Reservation> reservationsById = const <String, Reservation>{};
    List<QueryDocumentSnapshot<Map<String, dynamic>>> guestDocs =
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    void emit() {
      final entries = <GuestDirectoryEntry>[];
      for (final guestDoc in guestDocs) {
        final parsedGuest = ReservationGuest.fromDoc(guestDoc);
        final reservationId = _resolveReservationIdForGuestDoc(
          guestDoc,
          parsedGuest,
        );
        if (reservationId.isEmpty) {
          continue;
        }
        final reservation = reservationsById[reservationId];
        if (reservation == null) {
          continue;
        }
        final guest = parsedGuest.reservationId.trim().isEmpty
            ? parsedGuest.copyWith(reservationId: reservationId)
            : parsedGuest;
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

  Future<String> createReservation(
    Reservation reservation, {
    bool allowDuplicate = false,
  }) async {
    final duplicate = await checkDuplicateBeforeCreate(reservation);
    if (duplicate.hasDuplicate && !allowDuplicate) {
      throw ReservationDuplicateException(duplicate);
    }

    final overlaps = await checkOverlapBeforeCreate(reservation);
    if (overlaps.isNotEmpty) {
      final first = overlaps.first;
      final existing = first.existing;
      final existingFrom =
          '${existing.checkInDate.day.toString().padLeft(2, '0')}.${existing.checkInDate.month.toString().padLeft(2, '0')}.${existing.checkInDate.year}';
      final existingTo =
          '${existing.checkOutDate.day.toString().padLeft(2, '0')}.${existing.checkOutDate.month.toString().padLeft(2, '0')}.${existing.checkOutDate.year}';
      final incomingFrom =
          '${reservation.checkInDate.day.toString().padLeft(2, '0')}.${reservation.checkInDate.month.toString().padLeft(2, '0')}.${reservation.checkInDate.year}';
      final incomingTo =
          '${reservation.checkOutDate.day.toString().padLeft(2, '0')}.${reservation.checkOutDate.month.toString().padLeft(2, '0')}.${reservation.checkOutDate.year}';

      throw ReservationConflictException(
        'Parcela ${first.pitchName} je već zauzeta rezervacijom ${existing.primaryGuestName} ($existingFrom - $existingTo). Novi period: $incomingFrom - $incomingTo.',
      );
    }

    final doc = reservation.id.isEmpty
        ? _reservations.doc()
        : _reservations.doc(reservation.id);

    await doc.set({
      ...reservation.toMap(),
      'id': doc.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _createInitialPaymentIfNeeded(doc.id, reservation);

    return doc.id;
  }

  Future<ReservationDuplicateCheckResult> checkDuplicateBeforeCreate(
    Reservation reservation,
  ) async {
    final snapshot = await _reservations.get();
    final incomingGoogleEventId = reservation.googleCalendarEventId.trim();
    final incomingSourceId = reservation.sourceReservationId.trim();
    final incomingName = _normalizeNameForComparison(
      reservation.primaryGuestName,
    );

    for (final doc in snapshot.docs) {
      final existing = Reservation.fromDoc(doc);
      if (existing.id == reservation.id) {
        continue;
      }

      final existingGoogleEventId = existing.googleCalendarEventId.trim();
      final googleEventDuplicate =
          incomingGoogleEventId.isNotEmpty &&
          existingGoogleEventId.isNotEmpty &&
          incomingGoogleEventId == existingGoogleEventId;
      if (googleEventDuplicate) {
        return ReservationDuplicateCheckResult(
          hasDuplicate: true,
          match: existing,
          isHardDuplicate: true,
          reason: 'googleCalendarEventId',
        );
      }

      final existingSourceId = existing.sourceReservationId.trim();
      final hardDuplicate =
          incomingSourceId.isNotEmpty &&
          existingSourceId.isNotEmpty &&
          reservation.source == existing.source &&
          incomingSourceId == existingSourceId;
      if (hardDuplicate) {
        return ReservationDuplicateCheckResult(
          hasDuplicate: true,
          match: existing,
          isHardDuplicate: true,
          reason: 'sourceReservationId',
        );
      }

      final existingName = _normalizeNameForComparison(
        existing.primaryGuestName,
      );
      final probableDuplicate =
          incomingName.isNotEmpty &&
          incomingName == existingName &&
          _sameDate(reservation.checkInDate, existing.checkInDate) &&
          _sameDate(reservation.checkOutDate, existing.checkOutDate);
      if (probableDuplicate) {
        return ReservationDuplicateCheckResult(
          hasDuplicate: true,
          match: existing,
          reason: 'nameAndDates',
        );
      }
    }

    return const ReservationDuplicateCheckResult(hasDuplicate: false);
  }

  Future<List<ReservationOverlapConflict>> checkOverlapBeforeCreate(
    Reservation reservation,
  ) async {
    final incomingPitchIds = reservation.pitchIds.isNotEmpty
        ? reservation.pitchIds
        : (reservation.pitchId.trim().isEmpty
              ? <String>[]
              : <String>[reservation.pitchId]);
    if (incomingPitchIds.isEmpty) {
      return const <ReservationOverlapConflict>[];
    }

    final snapshot = await _reservations.get();
    final conflicts = <ReservationOverlapConflict>[];

    for (final doc in snapshot.docs) {
      final existing = Reservation.fromDoc(doc);
      if (existing.id == reservation.id) {
        continue;
      }
      if (existing.status != ReservationStatus.confirmed &&
          existing.status != ReservationStatus.checkedIn) {
        continue;
      }

      final existingPitchIds = existing.pitchIds.isNotEmpty
          ? existing.pitchIds
          : (existing.pitchId.trim().isEmpty
                ? <String>[]
                : <String>[existing.pitchId]);

      if (existingPitchIds.isEmpty) {
        continue;
      }

      if (!_periodsOverlap(
        existing.checkInDate,
        existing.checkOutDate,
        reservation.checkInDate,
        reservation.checkOutDate,
      )) {
        continue;
      }

      for (final pitchId in incomingPitchIds) {
        if (!existingPitchIds.contains(pitchId)) {
          continue;
        }
        final pitchName = existing.pitchName.isNotEmpty
            ? existing.pitchName
            : pitchId;
        conflicts.add(
          ReservationOverlapConflict(
            existing: existing,
            pitchId: pitchId,
            pitchName: pitchName,
          ),
        );
      }
    }

    return conflicts;
  }

  bool _periodsOverlap(
    DateTime existingStart,
    DateTime existingEnd,
    DateTime newStart,
    DateTime newEnd,
  ) {
    return existingStart.isBefore(newEnd) && existingEnd.isAfter(newStart);
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _normalizeNameForComparison(String value) {
    final lowered = value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    return _stripDiacritics(lowered);
  }

  String _stripDiacritics(String value) {
    const replacements = {
      'č': 'c',
      'ć': 'c',
      'đ': 'd',
      'š': 's',
      'ž': 'z',
      'ä': 'a',
      'ö': 'o',
      'ü': 'u',
      'ß': 'ss',
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ñ': 'n',
    };

    var normalized = value;
    replacements.forEach((key, replacement) {
      normalized = normalized.replaceAll(key, replacement);
    });
    return normalized;
  }

  Future<void> updateReservation(Reservation reservation) async {
    final overlaps = await checkOverlapBeforeCreate(reservation);
    if (overlaps.isNotEmpty) {
      final first = overlaps.first;
      final existing = first.existing;
      final existingFrom =
          '${existing.checkInDate.day.toString().padLeft(2, '0')}.${existing.checkInDate.month.toString().padLeft(2, '0')}.${existing.checkInDate.year}';
      final existingTo =
          '${existing.checkOutDate.day.toString().padLeft(2, '0')}.${existing.checkOutDate.month.toString().padLeft(2, '0')}.${existing.checkOutDate.year}';
      final incomingFrom =
          '${reservation.checkInDate.day.toString().padLeft(2, '0')}.${reservation.checkInDate.month.toString().padLeft(2, '0')}.${reservation.checkInDate.year}';
      final incomingTo =
          '${reservation.checkOutDate.day.toString().padLeft(2, '0')}.${reservation.checkOutDate.month.toString().padLeft(2, '0')}.${reservation.checkOutDate.year}';

      throw ReservationConflictException(
        'Parcela ${first.pitchName} je već zauzeta rezervacijom ${existing.primaryGuestName} ($existingFrom - $existingTo). Novi period: $incomingFrom - $incomingTo.',
      );
    }

    final reservationRef = _reservations.doc(reservation.id);
    final guestDocs = await _guests(reservation.id).get();
    final registeredGuestCount = guestDocs.docs.length;
    final effectiveGuestCount = registeredGuestCount > 0
        ? registeredGuestCount
        : (reservation.registeredGuestCount > 0
              ? reservation.registeredGuestCount
              : (reservation.guestCount > 0
                    ? reservation.guestCount
                    : (reservation.adults + reservation.children)));

    await _firestore.runTransaction<void>((tx) async {
      final existingSnap = await tx.get(reservationRef);
      if (!existingSnap.exists) {
        throw StateError('Rezervacija ne postoji.');
      }

      final existingReservation = Reservation.fromDoc(existingSnap);
      final previousPitchId = existingReservation.pitchId.trim();
      final nextPitchId = reservation.pitchId.trim();
      final previousPitchRef = previousPitchId.isEmpty
          ? null
          : _firestore.collection('pitches').doc(previousPitchId);
      final nextPitchRef = nextPitchId.isEmpty
          ? null
          : _firestore.collection('pitches').doc(nextPitchId);

      final wasCheckedIn =
          existingReservation.status == ReservationStatus.checkedIn;
      final willBeCheckedIn = reservation.status == ReservationStatus.checkedIn;

      if (willBeCheckedIn) {
        if (nextPitchRef == null) {
          throw ReservationConflictException(
            'Parcela za ovu rezervaciju ne postoji.',
          );
        }

        final nextPitchSnap = await tx.get(nextPitchRef);
        if (!nextPitchSnap.exists) {
          throw ReservationConflictException(
            'Parcela za ovu rezervaciju ne postoji.',
          );
        }

        final nextPitchData = nextPitchSnap.data() ?? const <String, dynamic>{};
        final nextPitchStatus = (nextPitchData['status'] as String? ?? '')
            .trim();
        final nextCurrentReservationId =
            (nextPitchData['currentReservationId'] as String? ?? '').trim();

        if (nextPitchStatus == PitchStatus.occupied.name &&
            nextCurrentReservationId.isNotEmpty &&
            nextCurrentReservationId != reservation.id) {
          throw ReservationConflictException(
            'Parcela je već zauzeta drugom rezervacijom. Promjena parcele nije moguća.',
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
      }

      final nextVehicleImageUrl = reservation.vehicleImageUrl.trim().isNotEmpty
          ? reservation.vehicleImageUrl
          : existingReservation.vehicleImageUrl;
      final nextVehicleImagePath =
          reservation.vehicleImagePath.trim().isNotEmpty
          ? reservation.vehicleImagePath
          : existingReservation.vehicleImagePath;
      final nextVehicleImageSizeBytes = reservation.vehicleImageSizeBytes > 0
          ? reservation.vehicleImageSizeBytes
          : existingReservation.vehicleImageSizeBytes;

      tx.update(reservationRef, {
        ...reservation.toMap(),
        'vehicleImageUrl': nextVehicleImageUrl,
        'vehicleImagePath': nextVehicleImagePath,
        'vehicleImageSizeBytes': nextVehicleImageSizeBytes,
        'registeredGuestCount': effectiveGuestCount,
        'currentGuests': willBeCheckedIn ? effectiveGuestCount : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (wasCheckedIn &&
          previousPitchRef != null &&
          previousPitchId != nextPitchId) {
        tx.update(previousPitchRef, {
          'status': PitchStatus.available.name,
          'currentReservationId': null,
          'currentGuestCount': 0,
          'currentGuests': 0,
          'currentPrimaryGuestName': null,
          'occupiedFrom': null,
          'occupiedUntil': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (willBeCheckedIn && nextPitchRef != null) {
        tx.update(nextPitchRef, {
          'status': PitchStatus.occupied.name,
          'currentReservationId': reservation.id,
          'currentGuestCount': effectiveGuestCount,
          'currentGuests': effectiveGuestCount,
          'currentPrimaryGuestName': reservation.primaryGuestName,
          'occupiedFrom': Timestamp.fromDate(reservation.checkInDate),
          'occupiedUntil': Timestamp.fromDate(reservation.checkOutDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (!willBeCheckedIn && wasCheckedIn && previousPitchRef != null) {
        tx.update(previousPitchRef, {
          'status': PitchStatus.available.name,
          'currentReservationId': null,
          'currentGuestCount': 0,
          'currentGuests': 0,
          'currentPrimaryGuestName': null,
          'occupiedFrom': null,
          'occupiedUntil': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    final batch = _firestore.batch();
    for (final guestDoc in guestDocs.docs) {
      batch.update(guestDoc.reference, {
        'pitchId': reservation.pitchId,
        'pitchName': reservation.pitchName,
        'checkInDate': Timestamp.fromDate(reservation.checkInDate),
        'checkOutDate': Timestamp.fromDate(reservation.checkOutDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (guestDocs.docs.isNotEmpty) {
      await batch.commit();
    }
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

    if (normalizedGuest.isPrimaryGuest) {
      final existingPrimaryGuests = await collection
          .where('isPrimaryGuest', isEqualTo: true)
          .get();
      final primaryGuestName =
          '${normalizedGuest.firstName} ${normalizedGuest.lastName}'.trim();
      final batch = _firestore.batch();

      for (final primaryDoc in existingPrimaryGuests.docs) {
        if (primaryDoc.id == doc.id) {
          continue;
        }
        batch.update(primaryDoc.reference, {
          'isPrimaryGuest': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      batch.update(_reservations.doc(reservationId), {
        'primaryGuestName': primaryGuestName,
        'primaryGuestId': doc.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (reservation.status == ReservationStatus.checkedIn) {
        batch
            .update(_firestore.collection('pitches').doc(reservation.pitchId), {
              'currentPrimaryGuestName': primaryGuestName,
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }

      await batch.commit();
    }

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
    final reservationRef = _reservations.doc(reservationId);
    final guestRef = _guests(reservationId).doc(guest.id);

    await _firestore.runTransaction<void>((tx) async {
      final reservationSnap = await tx.get(reservationRef);
      if (!reservationSnap.exists) {
        throw StateError('Rezervacija ne postoji.');
      }

      final reservation = Reservation.fromDoc(reservationSnap);
      final currentGuestSnap = await tx.get(guestRef);
      if (!currentGuestSnap.exists) {
        throw StateError('Gost ne postoji.');
      }

      final currentGuest = ReservationGuest.fromDoc(currentGuestSnap);
      final normalizedGuest = guest.copyWith(
        reservationId: reservationId,
        pitchId: reservation.pitchId,
        pitchName: reservation.pitchName,
        checkInDate: reservation.checkInDate,
        checkOutDate: reservation.checkOutDate,
        maskedDocumentNumber: maskDocumentNumber(guest.documentNumber),
      );

      tx.update(guestRef, {
        ...normalizedGuest.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final becomingPrimary = normalizedGuest.isPrimaryGuest;
      final wasPrimary = currentGuest.isPrimaryGuest;
      final primaryGuestName =
          '${normalizedGuest.firstName} ${normalizedGuest.lastName}'.trim();

      if (becomingPrimary) {
        final existingPrimaryGuests = await _guests(
          reservationId,
        ).where('isPrimaryGuest', isEqualTo: true).get();
        for (final doc in existingPrimaryGuests.docs) {
          if (doc.id == normalizedGuest.id) {
            continue;
          }
          tx.update(doc.reference, {
            'isPrimaryGuest': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        tx.update(reservationRef, {
          'primaryGuestName': primaryGuestName,
          'primaryGuestId': normalizedGuest.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (reservation.status == ReservationStatus.checkedIn) {
          tx.update(_firestore.collection('pitches').doc(reservation.pitchId), {
            'currentPrimaryGuestName': primaryGuestName,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }

      if (wasPrimary) {
        tx.update(reservationRef, {'updatedAt': FieldValue.serverTimestamp()});
      }
    });

    await _syncGuestCounters(reservationId);
  }

  Future<void> deleteGuest(String reservationId, String guestId) async {
    await _guests(reservationId).doc(guestId).delete();
    await _syncGuestCounters(reservationId);
  }

  Future<void> reconcileGuestState(String reservationId) {
    return _syncGuestCounters(reservationId);
  }

  Future<void> _syncGuestCounters(String reservationId) async {
    final reservationRef = _reservations.doc(reservationId);
    final reservationSnap = await reservationRef.get();
    if (!reservationSnap.exists) {
      return;
    }

    final reservation = Reservation.fromDoc(reservationSnap);
    final guestSnapshot = await _guests(reservationId).get();
    final guests = guestSnapshot.docs
        .map(ReservationGuest.fromDoc)
        .toList(growable: false);
    final guestCount = guests.length;

    ReservationGuest? primaryGuest;
    for (final guest in guests) {
      if (guest.isPrimaryGuest) {
        primaryGuest = guest;
        break;
      }
    }

    final nextPrimaryGuestName = primaryGuest == null
        ? ''
        : '${primaryGuest.firstName} ${primaryGuest.lastName}'.trim();
    final nextPrimaryGuestId = primaryGuest?.id ?? '';

    final reservationPatch = <String, dynamic>{
      'registeredGuestCount': guestCount,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (primaryGuest != null) {
      reservationPatch['primaryGuestName'] = nextPrimaryGuestName;
      reservationPatch['primaryGuestId'] = nextPrimaryGuestId;
    }
    if (reservation.status == ReservationStatus.checkedIn) {
      reservationPatch['currentGuests'] = guestCount;
    }
    await reservationRef.update(reservationPatch);

    if (reservation.status == ReservationStatus.checkedIn) {
      await _firestore.collection('pitches').doc(reservation.pitchId).update({
        'currentGuests': guestCount,
        'currentGuestCount': guestCount,
        'currentPrimaryGuestName': nextPrimaryGuestName.isNotEmpty
            ? nextPrimaryGuestName
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> createReservationAndCheckIn(
    Reservation reservation, {
    String checkedInByUid = 'frontdesk',
  }) async {
    final reservationRef = reservation.id.trim().isEmpty
        ? _reservations.doc()
        : _reservations.doc(reservation.id);
    final pitchRef = _firestore.collection('pitches').doc(reservation.pitchId);
    final guestCount = reservation.guestCount > 0
        ? reservation.guestCount
        : (reservation.adults + reservation.children);
    final primaryGuestName = _resolvePrimaryGuestName(reservation);

    await _firestore.runTransaction<void>((tx) async {
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
          currentReservationId != reservationRef.id) {
        throw ReservationConflictException(
          'Parcela je već zauzeta drugom rezervacijom. Prijava dolaska nije moguća.',
        );
      }

      final existingReservationSnap = await tx.get(reservationRef);
      if (existingReservationSnap.exists) {
        final existing = Reservation.fromDoc(existingReservationSnap);
        if (existing.status == ReservationStatus.cancelled) {
          throw ReservationConflictException(
            'Rezervacija je otkazana i nije je moguće prijaviti.',
          );
        }
        if (existing.status == ReservationStatus.checkedOut) {
          throw ReservationConflictException(
            'Rezervacija je već odjavljena i nije moguće ponovno prijaviti dolazak.',
          );
        }
      }

      tx.set(reservationRef, {
        ...reservation.toMap(),
        'id': reservationRef.id,
        'status': ReservationStatus.checkedIn.name,
        'actualCheckInAt': FieldValue.serverTimestamp(),
        'actualCheckOutAt': null,
        'checkedInByUid': checkedInByUid,
        'registeredGuestCount': guestCount,
        'currentGuests': guestCount,
        'guestCount': guestCount,
        'pitchCount': reservation.pitchCount < 1 ? 1 : reservation.pitchCount,
        'pitchIds': reservation.pitchIds.isEmpty
            ? <String>[reservation.pitchId]
            : reservation.pitchIds,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!existingReservationSnap.exists)
          'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.update(pitchRef, {
        'status': PitchStatus.occupied.name,
        'currentReservationId': reservationRef.id,
        'currentGuestCount': guestCount,
        'currentGuests': guestCount,
        'currentPrimaryGuestName': primaryGuestName.isNotEmpty
            ? primaryGuestName
            : null,
        'occupiedFrom': Timestamp.fromDate(reservation.checkInDate),
        'occupiedUntil': Timestamp.fromDate(reservation.checkOutDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (reservation.id.trim().isEmpty) {
      await _createInitialPaymentIfNeeded(reservationRef.id, reservation);
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
      final primaryGuestName = _resolvePrimaryGuestName(reservation);
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
        'currentPrimaryGuestName': primaryGuestName.isNotEmpty
            ? primaryGuestName
            : null,
        'occupiedFrom': Timestamp.fromDate(reservation.checkInDate),
        'occupiedUntil': Timestamp.fromDate(reservation.checkOutDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> checkOutReservation({
    required String reservationId,
    required String checkedOutByUid,
  }) async {
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
        'checkedOutByUid': checkedOutByUid,
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

  Stream<List<Reservation>> watchCheckedInReservations() {
    return _reservations
        .where('status', isEqualTo: 'checkedIn')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Reservation.fromDoc).toList());
  }

  Future<void> updateReservationPayment({
    required String reservationId,
    required double amountPaidIncrement,
  }) async {
    final docRef = _reservations.doc(reservationId);
    final doc = await docRef.get();
    if (!doc.exists) {
      return;
    }

    final reservation = Reservation.fromDoc(doc);
    final newAmountPaid = reservation.amountPaid + amountPaidIncrement;
    final newPaymentStatus = derivePaymentStatus(
      totalPrice: reservation.totalPrice,
      amountPaid: newAmountPaid,
      currentStatus: reservation.paymentStatus,
    );

    await docRef.update({
      'amountPaid': newAmountPaid,
      'paymentStatus': newPaymentStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reconcileReservationPaymentFromPayments({
    required String reservationId,
    String? fallbackGuestName,
  }) async {
    final reservationRef = _reservations.doc(reservationId);
    final reservationSnap = await reservationRef.get();
    if (!reservationSnap.exists) {
      return;
    }

    final reservation = Reservation.fromDoc(reservationSnap);
    final linkedPayments = await _payments
        .where('reservationId', isEqualTo: reservationId)
        .get();

    final normalizedGuestName = _normalizeNameForComparison(
      (fallbackGuestName ?? '').trim(),
    );
    List<QueryDocumentSnapshot<Map<String, dynamic>>> orphanGuestPayments =
        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    if (linkedPayments.docs.isEmpty && normalizedGuestName.isNotEmpty) {
      final allPayments = await _payments.get();
      final orphanDocs = allPayments.docs
          .where((doc) {
            final data = doc.data();
            final dynamic reservationIdRaw = data['reservationId'];
            final paymentReservationId =
                (reservationIdRaw as String?)?.trim() ?? '';
            if (paymentReservationId.isNotEmpty) {
              return false;
            }

            final guestName = _normalizeNameForComparison(
              (data['guestName'] as String? ?? '').trim(),
            );
            return guestName.isNotEmpty && guestName == normalizedGuestName;
          })
          .toList(growable: false);

      orphanGuestPayments = orphanDocs;
    }

    var allPaymentDocs = linkedPayments.docs;
    if (orphanGuestPayments.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in orphanGuestPayments) {
        batch.update(doc.reference, {
          'reservationId': reservationId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      allPaymentDocs = [...allPaymentDocs, ...orphanGuestPayments];
    }

    final totalPaid = allPaymentDocs.fold<double>(
      0,
      (total, doc) => total + ((doc.data()['amount'] as num?)?.toDouble() ?? 0),
    );

    final nextStatus = derivePaymentStatus(
      totalPrice: reservation.totalPrice,
      amountPaid: totalPaid,
      currentStatus: reservation.paymentStatus,
    );

    await reservationRef.update({
      'amountPaid': totalPaid,
      'paymentStatus': nextStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reconcilePaymentsForVisibleReservations() async {
    final now = DateTime.now();
    final threeMonthsAgo = DateTime(now.year, now.month - 3, now.day);
    final threeMonthsLater = DateTime(
      now.year,
      now.month + 3,
      now.day,
    ).add(const Duration(days: 1));

    final snapshot = await _reservations
        .where('checkInDate', isGreaterThanOrEqualTo: threeMonthsAgo)
        .where('checkInDate', isLessThan: threeMonthsLater)
        .orderBy('checkInDate', descending: false)
        .get();

    for (final doc in snapshot.docs) {
      final reservation = Reservation.fromDoc(doc);
      await reconcileReservationPaymentFromPayments(
        reservationId: reservation.id,
        fallbackGuestName: reservation.primaryGuestName,
      );
    }
  }

  Future<Reservation?> getReservationByGuestName(String guestName) async {
    final snapshot = await _reservations
        .where('primaryGuestName', isEqualTo: guestName)
        .where('status', isEqualTo: 'checkedIn')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return Reservation.fromDoc(snapshot.docs.first);
  }
}
