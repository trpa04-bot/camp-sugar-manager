import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../parcels/models/pitch.dart';
import '../../reservations/models/reservation.dart';
import '../../reservations/services/reservation_service.dart';

class DashboardStats {
  const DashboardStats({
    required this.totalPitches,
    required this.occupiedPitches,
    required this.currentGuests,
    required this.arrivalsToday,
    required this.departuresToday,
  });

  final int totalPitches;
  final int occupiedPitches;
  final int currentGuests;
  final int arrivalsToday;
  final int departuresToday;

  String get occupiedLabel => '$occupiedPitches / $totalPitches';

  static const empty = DashboardStats(
    totalPitches: 0,
    occupiedPitches: 0,
    currentGuests: 0,
    arrivalsToday: 0,
    departuresToday: 0,
  );
}

class DashboardStatsService {
  DashboardStatsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<DashboardStats> watchStats() {
    final reservationService = ReservationService(firestore: _firestore);
    final controller = StreamController<DashboardStats>();

    List<Pitch> latestPitches = const <Pitch>[];
    List<Reservation> latestReservations = const <Reservation>[];

    void emit() {
      final occupiedPitches = latestPitches
          .where(
            (pitch) =>
                pitch.status == PitchStatus.occupied &&
                (pitch.currentReservationId ?? '').trim().isNotEmpty,
          )
          .length;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final currentGuests = latestReservations
          .where(
            (reservation) => reservation.status == ReservationStatus.checkedIn,
          )
          .fold<int>(
            0,
            (total, reservation) => total + reservation.registeredGuestCount,
          );

      final arrivalsToday = latestReservations.where((reservation) {
        if (reservation.status == ReservationStatus.cancelled) {
          return false;
        }
        final checkIn = DateTime(
          reservation.checkInDate.year,
          reservation.checkInDate.month,
          reservation.checkInDate.day,
        );
        return checkIn == today;
      }).length;

      final departuresToday = latestReservations.where((reservation) {
        if (reservation.status == ReservationStatus.cancelled) {
          return false;
        }
        final checkOut = DateTime(
          reservation.checkOutDate.year,
          reservation.checkOutDate.month,
          reservation.checkOutDate.day,
        );
        return checkOut == today;
      }).length;

      controller.add(
        DashboardStats(
          totalPitches: latestPitches.length,
          occupiedPitches: occupiedPitches,
          currentGuests: currentGuests,
          arrivalsToday: arrivalsToday,
          departuresToday: departuresToday,
        ),
      );
    }

    final pitchesSub = _firestore.collection('pitches').snapshots().listen((
      snapshot,
    ) {
      latestPitches = snapshot.docs.map(Pitch.fromDoc).toList(growable: false);
      emit();
    });

    final reservationsSub = reservationService.watchReservations().listen((
      reservations,
    ) {
      latestReservations = reservations;
      emit();
    });

    controller.onCancel = () async {
      await pitchesSub.cancel();
      await reservationsSub.cancel();
    };

    return controller.stream;
  }
}
