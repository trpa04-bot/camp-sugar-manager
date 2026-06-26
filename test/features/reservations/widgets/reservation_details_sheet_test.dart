import 'package:camp_sugar_manager/features/parcels/services/pitch_service.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_details_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Reservation reservation({
    String id = 'res-1',
    String pitchId = 'pitch-1',
    String pitchName = 'Parcela 1',
    ReservationStatus status = ReservationStatus.checkedIn,
    String primaryGuestName = 'Sebastiaan',
  }) {
    return Reservation(
      id: id,
      bookingReference: 'B1',
      source: ReservationSource.direct,
      primaryGuestName: primaryGuestName,
      primaryGuestId: '',
      primaryGuestPhone: '',
      primaryGuestEmail: '',
      pitchId: pitchId,
      pitchName: pitchName,
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
      registeredGuestCount: 2,
      currentGuests: status == ReservationStatus.checkedIn ? 2 : 0,
      pitchIds: <String>[pitchId],
      pitchCount: 1,
    );
  }

  Future<void> openDetails(
    WidgetTester tester, {
    required Reservation reservation,
    required ReservationService service,
    required PitchService pitchService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showReservationDetails(
                    context,
                    reservation: reservation,
                    service: service,
                    pitchService: pitchService,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('change pitch from details moves checked-in reservation', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);
    final pitchService = PitchService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation().toMap());
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
      'currentPrimaryGuestName': null,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await openDetails(
      tester,
      reservation: reservation(),
      service: service,
      pitchService: pitchService,
    );

    await tester.tap(find.text('Promijeni parcelu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parcela 2'));
    await tester.pumpAndSettle();

    expect(
      find.text('Rezervacija je prebačena na parcelu Parcela 2.'),
      findsOneWidget,
    );

    final movedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    final oldPitch = await firestore.collection('pitches').doc('pitch-1').get();
    final newPitch = await firestore.collection('pitches').doc('pitch-2').get();

    expect(movedReservation.data()!['pitchId'], 'pitch-2');
    expect(oldPitch.data()!['status'], 'available');
    expect(newPitch.data()!['status'], 'occupied');
    expect(newPitch.data()!['currentReservationId'], 'res-1');
  });

  testWidgets('change pitch from details shows conflict on occupied pitch', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);
    final pitchService = PitchService(firestore: firestore);

    await firestore
        .collection('reservations')
        .doc('res-1')
        .set(reservation().toMap());
    await firestore
        .collection('reservations')
        .doc('res-2')
        .set(
          reservation(
            id: 'res-2',
            pitchId: 'pitch-2',
            pitchName: 'Parcela 2',
            primaryGuestName: 'Drugi Gost',
          ).toMap(),
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
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 2,
      'currentGuestCount': 2,
      'currentReservationId': 'res-2',
      'currentPrimaryGuestName': 'Drugi Gost',
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await openDetails(
      tester,
      reservation: reservation(),
      service: service,
      pitchService: pitchService,
    );

    await tester.tap(find.text('Promijeni parcelu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parcela 2'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Parcela Parcela 2 je već zauzeta rezervacijom Drugi Gost (20.06.2026 - 24.06.2026). Novi period: 20.06.2026 - 24.06.2026.',
      ),
      findsOneWidget,
    );

    final unchangedReservation = await firestore
        .collection('reservations')
        .doc('res-1')
        .get();
    expect(unchangedReservation.data()!['pitchId'], 'pitch-1');
  });
}
