import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Reservation _reservation({
  required String id,
  required String name,
  required DateTime checkIn,
  required DateTime checkOut,
  String googleEventId = '',
  String sourceReservationId = '',
}) {
  return Reservation(
    id: id,
    bookingReference: id,
    source: ReservationSource.other,
    primaryGuestName: name,
    primaryGuestId: '',
    primaryGuestPhone: '',
    primaryGuestEmail: '',
    pitchId: 'pitch-1',
    pitchName: 'Parcela 1',
    checkInDate: checkIn,
    checkOutDate: checkOut,
    adults: 2,
    children: 0,
    pets: 0,
    vehicles: 1,
    accommodationType: 'Camper',
    status: ReservationStatus.confirmed,
    totalPrice: 120,
    depositPaid: 0,
    amountPaid: 0,
    paymentStatus: PaymentStatus.unpaid,
    notes: '',
    registeredGuestCount: 0,
    currentGuests: 0,
    googleCalendarEventId: googleEventId,
    sourceReservationId: sourceReservationId,
  );
}

void main() {
  test('detects hard duplicate by googleCalendarEventId', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await service.createReservation(
      _reservation(
        id: 'existing',
        name: 'Ana Horvat',
        checkIn: DateTime(2026, 9, 10),
        checkOut: DateTime(2026, 9, 12),
        googleEventId: 'evt_1',
      ),
      allowDuplicate: true,
    );

    final result = await service.checkDuplicateBeforeCreate(
      _reservation(
        id: 'incoming',
        name: 'Ana Horvat',
        checkIn: DateTime(2026, 10, 1),
        checkOut: DateTime(2026, 10, 3),
        googleEventId: 'evt_1',
      ),
    );

    expect(result.hasDuplicate, isTrue);
    expect(result.isHardDuplicate, isTrue);
    expect(result.reason, 'googleCalendarEventId');
  });

  test('detects probable duplicate by normalized name and dates', () async {
    final firestore = FakeFirebaseFirestore();
    final service = ReservationService(firestore: firestore);

    await service.createReservation(
      _reservation(
        id: 'existing',
        name: 'Ana Horvat',
        checkIn: DateTime(2026, 9, 10),
        checkOut: DateTime(2026, 9, 12),
      ),
      allowDuplicate: true,
    );

    final result = await service.checkDuplicateBeforeCreate(
      _reservation(
        id: 'incoming',
        name: '  ana   horvat  ',
        checkIn: DateTime(2026, 9, 10),
        checkOut: DateTime(2026, 9, 12),
      ),
    );

    expect(result.hasDuplicate, isTrue);
    expect(result.isHardDuplicate, isFalse);
    expect(result.reason, 'nameAndDates');
  });
}
