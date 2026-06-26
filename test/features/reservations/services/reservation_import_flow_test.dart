import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_flow.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_parser.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_validation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Reservation buildReservation({
    required ReservationSource source,
    required String sourceReservationId,
    required String name,
    required DateTime checkIn,
    required DateTime checkOut,
    required List<String> pitchIds,
    required int adults,
    required int children,
  }) {
    return Reservation(
      id: '',
      bookingReference: sourceReservationId,
      source: source,
      primaryGuestName: name,
      primaryGuestId: '',
      primaryGuestPhone: '',
      primaryGuestEmail: '',
      pitchId: pitchIds.first,
      pitchName: '',
      checkInDate: checkIn,
      checkOutDate: checkOut,
      adults: adults,
      children: children,
      pets: 0,
      vehicles: 1,
      accommodationType: '',
      status: ReservationStatus.confirmed,
      totalPrice: 0,
      depositPaid: 0,
      amountPaid: 0,
      paymentStatus: PaymentStatus.unpaid,
      notes: '',
      registeredGuestCount: adults + children,
      currentGuests: 0,
      pitchIds: pitchIds,
      pitchCount: pitchIds.length,
      sourceReservationId: sourceReservationId,
    );
  }

  group('duplicate flow', () {
    test('cancel does not save', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      final existing = buildReservation(
        source: ReservationSource.booking,
        sourceReservationId: '123456789',
        name: 'Mario Hollauf',
        checkIn: DateTime(2026, 6, 13),
        checkOut: DateTime(2026, 6, 20),
        pitchIds: const ['pitch-1'],
        adults: 2,
        children: 0,
      ).copyWith(id: 'existing');
      await firestore
          .collection('reservations')
          .doc('existing')
          .set(existing.toMap());

      final incoming = buildReservation(
        source: ReservationSource.booking,
        sourceReservationId: '123456789',
        name: 'Mario Hollauf',
        checkIn: DateTime(2026, 6, 13),
        checkOut: DateTime(2026, 6, 20),
        pitchIds: const ['pitch-1'],
        adults: 2,
        children: 0,
      );

      final result = await processImportedReservation(
        service: service,
        reservation: incoming,
        onDuplicateDetected: (_) async => DuplicateImportAction.cancel,
      );

      expect(result.status, ImportFlowStatus.cancelled);
      final all = await firestore.collection('reservations').get();
      expect(all.docs.length, 1);
    });

    test('openExisting returns opened status and does not save', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      final existing = buildReservation(
        source: ReservationSource.booking,
        sourceReservationId: '123456789',
        name: 'Mario Hollauf',
        checkIn: DateTime(2026, 6, 13),
        checkOut: DateTime(2026, 6, 20),
        pitchIds: const ['pitch-1'],
        adults: 2,
        children: 0,
      ).copyWith(id: 'existing');
      await firestore
          .collection('reservations')
          .doc('existing')
          .set(existing.toMap());

      Reservation? opened;
      final incoming = existing.copyWith(id: '', pitchIds: const ['pitch-1']);

      final result = await processImportedReservation(
        service: service,
        reservation: incoming,
        onDuplicateDetected: (_) async => DuplicateImportAction.openExisting,
        onOpenExisting: (reservation) async {
          opened = reservation;
        },
      );

      expect(result.status, ImportFlowStatus.openedExisting);
      expect(opened?.id, 'existing');
      final all = await firestore.collection('reservations').get();
      expect(all.docs.length, 1);
    });

    test('saveAnyway saves exactly once', () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      final existing = buildReservation(
        source: ReservationSource.booking,
        sourceReservationId: '123456789',
        name: 'Mario Hollauf',
        checkIn: DateTime(2026, 6, 13),
        checkOut: DateTime(2026, 6, 20),
        pitchIds: const ['pitch-1'],
        adults: 2,
        children: 0,
      ).copyWith(id: 'existing');
      await firestore
          .collection('reservations')
          .doc('existing')
          .set(existing.toMap());

      final incoming = existing.copyWith(id: '', pitchIds: const ['pitch-2']);

      final result = await processImportedReservation(
        service: service,
        reservation: incoming,
        onDuplicateDetected: (_) async => DuplicateImportAction.saveAnyway,
      );

      expect(result.status, ImportFlowStatus.saved);
      final all = await firestore.collection('reservations').get();
      expect(all.docs.length, 2);
    });

    test(
      'without explicit decision createReservation refuses duplicate',
      () async {
        final firestore = FakeFirebaseFirestore();
        final service = ReservationService(firestore: firestore);

        final existing = buildReservation(
          source: ReservationSource.booking,
          sourceReservationId: '123456789',
          name: 'Mario Hollauf',
          checkIn: DateTime(2026, 6, 13),
          checkOut: DateTime(2026, 6, 20),
          pitchIds: const ['pitch-1'],
          adults: 2,
          children: 0,
        ).copyWith(id: 'existing');
        await firestore
            .collection('reservations')
            .doc('existing')
            .set(existing.toMap());

        final incoming = existing.copyWith(id: '', pitchIds: const ['pitch-2']);

        await expectLater(
          () => service.createReservation(incoming),
          throwsA(isA<ReservationDuplicateException>()),
        );

        final all = await firestore.collection('reservations').get();
        expect(all.docs.length, 1);
      },
    );
  });

  group('overlap status rules', () {
    Future<List<ReservationOverlapConflict>> runOverlap({
      required ReservationStatus existingStatus,
    }) async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      final existing = buildReservation(
        source: ReservationSource.direct,
        sourceReservationId: '',
        name: 'Existing',
        checkIn: DateTime(2026, 6, 10),
        checkOut: DateTime(2026, 6, 15),
        pitchIds: const ['pitch-x'],
        adults: 2,
        children: 0,
      ).copyWith(id: 'existing', status: existingStatus);
      await firestore
          .collection('reservations')
          .doc('existing')
          .set(existing.toMap());

      final incoming = buildReservation(
        source: ReservationSource.direct,
        sourceReservationId: '',
        name: 'Incoming',
        checkIn: DateTime(2026, 6, 12),
        checkOut: DateTime(2026, 6, 14),
        pitchIds: const ['pitch-x'],
        adults: 2,
        children: 0,
      );

      return service.checkOverlapBeforeCreate(incoming);
    }

    test('cancelled does not block', () async {
      final conflicts = await runOverlap(
        existingStatus: ReservationStatus.cancelled,
      );
      expect(conflicts, isEmpty);
    });

    test('checkedOut does not block', () async {
      final conflicts = await runOverlap(
        existingStatus: ReservationStatus.checkedOut,
      );
      expect(conflicts, isEmpty);
    });

    test('inquiry does not block', () async {
      final conflicts = await runOverlap(
        existingStatus: ReservationStatus.inquiry,
      );
      expect(conflicts, isEmpty);
    });

    test('confirmed blocks', () async {
      final conflicts = await runOverlap(
        existingStatus: ReservationStatus.confirmed,
      );
      expect(conflicts, isNotEmpty);
    });

    test('checkedIn blocks', () async {
      final conflicts = await runOverlap(
        existingStatus: ReservationStatus.checkedIn,
      );
      expect(conflicts, isNotEmpty);
    });
  });

  test(
    'integration flow without real firestore: parse -> validate -> duplicate -> overlap -> save payload',
    () async {
      final firestore = FakeFirebaseFirestore();
      final service = ReservationService(firestore: firestore);

      await firestore.collection('pitches').doc('pitch-a').set({
        'id': 'pitch-a',
        'name': 'Parcela A',
        'number': 1,
        'zone': 'A',
        'status': 'available',
        'maxGuests': 6,
        'currentGuests': 0,
        'currentGuestCount': 0,
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
      });

      const text = '''
      Reservation confirmed
      Guest: John Smith
      Aug 10, 2026 - Aug 15, 2026
      3 guests
      Confirmation code: HMABC123
    ''';

      final parsed = await ReservationImportParser.parseText(text);
      final selectedPitchIds = const ['pitch-a'];

      final validation = validateImport(
        result: parsed,
        selectedPitchIds: selectedPitchIds,
      );
      expect(validation.isValid, isTrue);

      final reservation =
          buildReservation(
            source: parsed.source ?? ReservationSource.other,
            sourceReservationId: parsed.sourceReservationId ?? '',
            name: parsed.primaryGuestName,
            checkIn: parsed.checkInDate!,
            checkOut: parsed.checkOutDate!,
            pitchIds: selectedPitchIds,
            adults: parsed.adults ?? 0,
            children: parsed.children ?? 0,
          ).copyWith(
            guestCount: parsed.totalGuestCount,
            pitchCount: selectedPitchIds.length,
          );

      final duplicateDecisionCalls = <String>[];
      final flowResult = await processImportedReservation(
        service: service,
        reservation: reservation,
        onDuplicateDetected: (_) async {
          duplicateDecisionCalls.add('called');
          return DuplicateImportAction.saveAnyway;
        },
      );

      expect(flowResult.status, ImportFlowStatus.saved);
      expect(duplicateDecisionCalls, isEmpty);

      final saved = await firestore.collection('reservations').get();
      expect(saved.docs.length, 1);

      final savedData = saved.docs.first.data();
      expect(savedData['primaryGuestName'], 'John Smith');
      expect(savedData['source'], ReservationSource.airbnb.name);
      expect(savedData['sourceReservationId'], 'HMABC123');
      expect((savedData['pitchIds'] as List<dynamic>).length, 1);
      expect(savedData['pitchIds'][0], 'pitch-a');
      expect(savedData['checkInDate'], isNotNull);
      expect(savedData['checkOutDate'], isNotNull);
    },
  );
}
