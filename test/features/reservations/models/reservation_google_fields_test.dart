import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Reservation buildReservation() {
    return Reservation(
      id: 'res-google-1',
      bookingReference: 'G-1',
      source: ReservationSource.airbnb,
      primaryGuestName: 'Ana Horvat',
      primaryGuestId: '',
      primaryGuestPhone: '',
      primaryGuestEmail: '',
      pitchId: 'p-1',
      pitchName: 'Parcela 1',
      checkInDate: DateTime(2026, 9, 10),
      checkOutDate: DateTime(2026, 9, 13),
      adults: 2,
      children: 0,
      pets: 0,
      vehicles: 1,
      accommodationType: 'Camper',
      status: ReservationStatus.confirmed,
      totalPrice: 220,
      depositPaid: 0,
      amountPaid: 0,
      paymentStatus: PaymentStatus.unpaid,
      notes: 'Imported from Google Calendar',
      registeredGuestCount: 0,
      currentGuests: 0,
      externalSource: 'googleCalendar',
      googleCalendarEventId: 'evt_123',
      googleCalendarId: 'primary',
      importedFromGoogleCalendar: true,
      googleCalendarLastUpdatedAt: DateTime(2026, 6, 1, 12, 0),
    );
  }

  test('keeps source and externalSource in Firestore map', () {
    final map = buildReservation().toMap();

    expect(map['source'], ReservationSource.airbnb.name);
    expect(map['externalSource'], 'googleCalendar');
    expect(map['googleCalendarEventId'], 'evt_123');
    expect(map['importedFromGoogleCalendar'], isTrue);
  });

  test('reads google calendar fields from Firestore document', () async {
    final firestore = FakeFirebaseFirestore();
    final reservation = buildReservation();

    await firestore
        .collection('reservations')
        .doc(reservation.id)
        .set(reservation.toMap());

    final doc = await firestore
        .collection('reservations')
        .doc(reservation.id)
        .get();
    final loaded = Reservation.fromDoc(doc);

    expect(loaded.externalSource, 'googleCalendar');
    expect(loaded.googleCalendarEventId, 'evt_123');
    expect(loaded.googleCalendarId, 'primary');
    expect(loaded.importedFromGoogleCalendar, isTrue);
  });
}
