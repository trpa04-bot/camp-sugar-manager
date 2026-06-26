import 'package:camp_sugar_manager/features/dashboard/services/dashboard_stats_service.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dashboard stats uses real guests for current/arrivals/departures',
    () async {
      final firestore = FakeFirebaseFirestore();

      await firestore.collection('pitches').doc('pitch-1').set({
        'id': 'pitch-1',
        'name': 'Parcela 1',
        'number': 1,
        'zone': 'A',
        'status': 'occupied',
        'maxGuests': 4,
        'currentGuests': 99,
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
      });

      final today = DateTime.now();
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
        checkInDate: DateTime(today.year, today.month, today.day),
        checkOutDate: DateTime(today.year, today.month, today.day),
        adults: 2,
        children: 0,
        pets: 0,
        vehicles: 1,
        accommodationType: 'Camper',
        status: ReservationStatus.checkedIn,
        totalPrice: 0,
        depositPaid: 0,
        amountPaid: 0,
        paymentStatus: PaymentStatus.unpaid,
        notes: '',
        registeredGuestCount: 1,
        currentGuests: 1,
      );

      await firestore
          .collection('reservations')
          .doc('res-1')
          .set(reservation.toMap());

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
            'nationality': 'DEU',
            'nationalityCode': 'DEU',
            'documentType': 'nationalIdCard',
            'documentNumber': 'L628C54X8',
            'maskedDocumentNumber': '*****54X8',
            'gender': 'F',
            'isPrimaryGuest': true,
            'verificationStatus': 'verified',
            'verificationMethod': 'ocrManual',
            'documentAcceptanceStatus': 'accepted',
            'manualReviewCompleted': true,
            'checkInDate': DateTime(today.year, today.month, today.day),
            'checkOutDate': DateTime(today.year, today.month, today.day),
            'documentImagePath': '',
            'documentImagePaths': <String>[],
            'retentionPolicy': 'retainManually',
            'cleanupPending': false,
            'ocrStatus': 'completed',
          });

      final service = DashboardStatsService(firestore: firestore);
      final stats = await service.watchStats().firstWhere(
        (item) =>
            item.totalPitches == 1 &&
            item.currentGuests == 1 &&
            item.arrivalsToday == 1 &&
            item.plannedDeparturesToday == 1,
      );

      expect(stats.currentGuests, 1);
      expect(stats.arrivalsToday, 1);
      expect(stats.departuresToday, 0);
      expect(stats.plannedDeparturesToday, 1);
    },
  );

  test(
    'inquiry reservation with saved guest is not counted as current guest',
    () async {
      final firestore = FakeFirebaseFirestore();

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

      final today = DateTime.now();
      final reservation = Reservation(
        id: 'res-1',
        bookingReference: 'B1',
        source: ReservationSource.direct,
        primaryGuestName: 'Hans Rauh',
        primaryGuestId: 'g1',
        primaryGuestPhone: '',
        primaryGuestEmail: '',
        pitchId: 'pitch-1',
        pitchName: 'Parcela 1',
        checkInDate: DateTime(today.year, today.month, today.day),
        checkOutDate: DateTime(today.year, today.month, today.day + 1),
        adults: 2,
        children: 0,
        pets: 0,
        vehicles: 1,
        accommodationType: 'Camper',
        status: ReservationStatus.inquiry,
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

      final service = DashboardStatsService(firestore: firestore);
      final stats = await service.watchStats().first;

      expect(stats.currentGuests, 0);
      expect(stats.occupiedPitches, 0);
    },
  );

  test('dashboard shows 1/45 occupied after check-in', () async {
    final firestore = FakeFirebaseFirestore();

    for (var i = 1; i <= 45; i++) {
      final isOccupied = i == 1;
      await firestore.collection('pitches').doc('pitch-$i').set({
        'id': 'pitch-$i',
        'name': 'Parcela $i',
        'number': i,
        'zone': 'A',
        'status': isOccupied ? 'occupied' : 'available',
        'maxGuests': 4,
        'currentGuests': isOccupied ? 1 : 0,
        'currentGuestCount': isOccupied ? 1 : 0,
        'currentReservationId': isOccupied ? 'res-1' : null,
        'hasElectricity': true,
        'hasWater': true,
        'notes': '',
      });
    }

    final reservation = Reservation(
      id: 'res-1',
      bookingReference: 'B1',
      source: ReservationSource.direct,
      primaryGuestName: 'Hans Rauh',
      primaryGuestId: 'g1',
      primaryGuestPhone: '',
      primaryGuestEmail: '',
      pitchId: 'pitch-1',
      pitchName: 'Parcela 1',
      checkInDate: DateTime(2026, 6, 20),
      checkOutDate: DateTime(2026, 6, 21),
      adults: 2,
      children: 0,
      pets: 0,
      vehicles: 1,
      accommodationType: 'Camper',
      status: ReservationStatus.checkedIn,
      totalPrice: 0,
      depositPaid: 0,
      amountPaid: 0,
      paymentStatus: PaymentStatus.unpaid,
      notes: '',
      registeredGuestCount: 1,
      currentGuests: 1,
    );

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation.toMap());

    final service = DashboardStatsService(firestore: firestore);
    final stats = await service.watchStats().firstWhere(
      (item) => item.totalPitches == 45 && item.currentGuests == 1,
    );

    expect(stats.currentGuests, 1);
    expect(stats.occupiedLabel, '1 / 45');
  });

  test(
    'checked-out reservation does not contribute to current guests',
    () async {
      final firestore = FakeFirebaseFirestore();

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

      final reservation = Reservation(
        id: 'res-1',
        bookingReference: 'B1',
        source: ReservationSource.direct,
        primaryGuestName: 'Hans Rauh',
        primaryGuestId: 'g1',
        primaryGuestPhone: '',
        primaryGuestEmail: '',
        pitchId: 'pitch-1',
        pitchName: 'Parcela 1',
        checkInDate: DateTime(2026, 6, 20),
        checkOutDate: DateTime(2026, 6, 21),
        adults: 2,
        children: 0,
        pets: 0,
        vehicles: 1,
        accommodationType: 'Camper',
        status: ReservationStatus.checkedOut,
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

      final service = DashboardStatsService(firestore: firestore);
      final stats = await service.watchStats().first;

      expect(stats.currentGuests, 0);
    },
  );
}
