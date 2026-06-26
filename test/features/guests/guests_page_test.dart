import 'package:camp_sugar_manager/features/guests/guests_page.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guests page shows saved guest with masked document number', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

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
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 1,
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
          'nationality': 'DEU',
          'nationalityCode': 'DEU',
          'nationalityDisplayName': 'Njemačka',
          'documentType': 'nationalIdCard',
          'documentNumber': 'L628C54X8',
          'maskedDocumentNumber': '*****54X8',
          'gender': 'F',
          'isPrimaryGuest': true,
          'verificationStatus': 'verified',
          'verificationMethod': 'ocrManual',
          'documentAcceptanceStatus': 'accepted',
          'manualReviewCompleted': true,
          'checkInDate': DateTime(2026, 6, 20),
          'checkOutDate': DateTime(2026, 6, 24),
          'documentImagePath': '',
          'documentImagePaths': <String>[],
          'retentionPolicy': 'retainManually',
          'cleanupPending': false,
          'ocrStatus': 'completed',
        });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuestsPage(reservationService: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gosti'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Horvat'), findsOneWidget);
    expect(find.textContaining('*****54X8'), findsOneWidget);
    expect(find.textContaining('Parcela 1'), findsWidgets);
  });

  testWidgets('inquiry reservation guest is shown as Čeka prijavu', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

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
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'available',
      'maxGuests': 4,
      'currentGuests': 0,
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
          'firstName': 'Hans',
          'lastName': 'Rauh',
          'nationality': 'DEU',
          'nationalityCode': 'DEU',
          'documentType': 'nationalIdCard',
          'documentNumber': 'L628C54X8',
          'maskedDocumentNumber': '*****54X8',
          'gender': 'M',
          'isPrimaryGuest': true,
          'verificationStatus': 'verified',
          'verificationMethod': 'ocrManual',
          'documentAcceptanceStatus': 'accepted',
          'manualReviewCompleted': true,
          'checkInDate': DateTime(today.year, today.month, today.day),
          'checkOutDate': DateTime(today.year, today.month, today.day + 1),
          'documentImagePath': '',
          'documentImagePaths': <String>[],
          'retentionPolicy': 'retainManually',
          'cleanupPending': false,
          'ocrStatus': 'completed',
        });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuestsPage(reservationService: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gosti'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Status: Čeka prijavu'), findsOneWidget);
  });

  testWidgets('checked-in reservation guest is shown as Trenutno u kampu', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

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
    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Parcela 1',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 1,
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
          'firstName': 'Hans',
          'lastName': 'Rauh',
          'nationality': 'DEU',
          'nationalityCode': 'DEU',
          'documentType': 'nationalIdCard',
          'documentNumber': 'L628C54X8',
          'maskedDocumentNumber': '*****54X8',
          'gender': 'M',
          'isPrimaryGuest': true,
          'verificationStatus': 'verified',
          'verificationMethod': 'ocrManual',
          'documentAcceptanceStatus': 'accepted',
          'manualReviewCompleted': true,
          'checkInDate': DateTime(today.year, today.month, today.day),
          'checkOutDate': DateTime(today.year, today.month, today.day + 1),
          'documentImagePath': '',
          'documentImagePaths': <String>[],
          'retentionPolicy': 'retainManually',
          'cleanupPending': false,
          'ocrStatus': 'completed',
        });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GuestsPage(reservationService: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gosti'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Status: Trenutno u kampu'), findsOneWidget);
  });
}
