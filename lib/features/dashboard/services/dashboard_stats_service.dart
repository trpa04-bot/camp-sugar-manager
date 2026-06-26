import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/date_utils.dart' as app_date;
import '../../parcels/models/pitch.dart';
import '../../reservations/models/reservation.dart';
import '../../reservations/services/reservation_service.dart';

class DashboardStats {
  const DashboardStats({
    required this.totalPitches,
    required this.occupiedPitches,
    required this.availablePitches,
    required this.currentGuests,
    required this.arrivalsToday,
    required this.departuresToday,
    required this.openDebtReservations,
    required this.openDebtAmount,
    required this.myCheckedOutPitchesToday,
    required this.myCheckedOutGuestsToday,
    required this.plannedDeparturesToday,
    required this.overdueCheckedOutPending,
    required this.totalGuestsThroughCamp,
  });

  final int totalPitches;
  final int occupiedPitches;
  final int availablePitches;
  final int currentGuests;
  final int arrivalsToday;
  final int departuresToday;
  final int openDebtReservations;
  final double openDebtAmount;
  final int myCheckedOutPitchesToday;
  final int myCheckedOutGuestsToday;
  final int plannedDeparturesToday;
  final int overdueCheckedOutPending;
  final int totalGuestsThroughCamp;

  String get occupiedLabel => '$occupiedPitches / $totalPitches';

  static const empty = DashboardStats(
    totalPitches: 0,
    occupiedPitches: 0,
    availablePitches: 0,
    currentGuests: 0,
    arrivalsToday: 0,
    departuresToday: 0,
    openDebtReservations: 0,
    openDebtAmount: 0,
    myCheckedOutPitchesToday: 0,
    myCheckedOutGuestsToday: 0,
    plannedDeparturesToday: 0,
    overdueCheckedOutPending: 0,
    totalGuestsThroughCamp: 0,
  );
}

class DashboardStatsService {
  DashboardStatsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  int _resolveGuestCount(Reservation reservation) {
    if (reservation.registeredGuestCount > 0) {
      return reservation.registeredGuestCount;
    }
    if (reservation.guestCount > 0) {
      return reservation.guestCount;
    }
    final fallback =
        reservation.adults + reservation.children + reservation.infants;
    return fallback < 0 ? 0 : fallback;
  }

  double _effectiveGrossAmount(Reservation reservation) {
    if (reservation.departureDateUnknown && reservation.pricePerNight > 0) {
      final billedNights = app_date.nightsBetween(
        reservation.checkInDate,
        DateTime.now(),
        minimum: 1,
      );
      return reservation.pricePerNight * billedNights;
    }

    return reservation.totalPrice;
  }

  double _openDebtAmount(Reservation reservation) {
    final due = _effectiveGrossAmount(reservation) - reservation.amountPaid;
    return due <= 0.01 ? 0 : due;
  }

  bool _hasOpenDebt(Reservation reservation) {
    final effectiveStatus = reservation.effectivePaymentStatus;
    if (effectiveStatus == PaymentStatus.paid ||
        effectiveStatus == PaymentStatus.refunded) {
      return false;
    }

    return _openDebtAmount(reservation) > 0;
  }

  Stream<DashboardStats> watchStats({String? currentUserUid}) {
    final reservationService = ReservationService(firestore: _firestore);
    final controller = StreamController<DashboardStats>();

    List<Pitch> latestPitches = const <Pitch>[];
    List<Reservation> latestReservations = const <Reservation>[];

    void emit() {
      final occupiedPitches = latestPitches
          .where((pitch) => pitch.status == PitchStatus.occupied)
          .length;
      final availablePitches = latestPitches
          .where((pitch) => pitch.status == PitchStatus.available)
          .length;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final currentGuests = latestReservations
          .where(
            (reservation) => reservation.status == ReservationStatus.checkedIn,
          )
          .fold<int>(
            0,
            (total, reservation) => total + _resolveGuestCount(reservation),
          );

      // Ukupno gostiju kroz kamp = trenutno checkedIn + svi koji su checkedOut
      final totalGuestsThroughCamp = latestReservations
          .where(
            (reservation) =>
                reservation.status == ReservationStatus.checkedIn ||
                reservation.status == ReservationStatus.checkedOut,
          )
          .fold<int>(
            0,
            (total, reservation) => total + _resolveGuestCount(reservation),
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

      final plannedDeparturesToday = latestReservations.where((reservation) {
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

      final actualDeparturesToday = latestReservations.where((reservation) {
        if (reservation.status != ReservationStatus.checkedOut) {
          return false;
        }

        final actualCheckOutAt = reservation.actualCheckOutAt;
        if (actualCheckOutAt == null) {
          return false;
        }

        final checkedOutOn = DateTime(
          actualCheckOutAt.year,
          actualCheckOutAt.month,
          actualCheckOutAt.day,
        );
        return checkedOutOn == today;
      }).length;

      final openDebtReservations = latestReservations.where((reservation) {
        if (reservation.status == ReservationStatus.cancelled) {
          return false;
        }
        return _hasOpenDebt(reservation);
      }).length;

      final openDebtAmount = latestReservations.fold<double>(0, (
        total,
        reservation,
      ) {
        if (reservation.status == ReservationStatus.cancelled) {
          return total;
        }

        if (!_hasOpenDebt(reservation)) {
          return total;
        }

        return total + _openDebtAmount(reservation);
      });

      final myCheckedOutPitchesToday = latestReservations.where((reservation) {
        if (reservation.status != ReservationStatus.checkedOut) {
          return false;
        }
        if ((currentUserUid ?? '').trim().isEmpty) {
          return false;
        }
        if ((reservation.checkedOutByUid ?? '').trim() !=
            currentUserUid!.trim()) {
          return false;
        }
        final actualCheckOutAt = reservation.actualCheckOutAt;
        if (actualCheckOutAt == null) {
          return false;
        }
        final checkedOutOn = DateTime(
          actualCheckOutAt.year,
          actualCheckOutAt.month,
          actualCheckOutAt.day,
        );
        return checkedOutOn == today;
      }).length;

      final myCheckedOutGuestsToday = latestReservations
          .where((reservation) {
            if (reservation.status != ReservationStatus.checkedOut) {
              return false;
            }
            if ((currentUserUid ?? '').trim().isEmpty) {
              return false;
            }
            if ((reservation.checkedOutByUid ?? '').trim() !=
                currentUserUid!.trim()) {
              return false;
            }
            final actualCheckOutAt = reservation.actualCheckOutAt;
            if (actualCheckOutAt == null) {
              return false;
            }
            final checkedOutOn = DateTime(
              actualCheckOutAt.year,
              actualCheckOutAt.month,
              actualCheckOutAt.day,
            );
            return checkedOutOn == today;
          })
          .fold<int>(
            0,
            (total, reservation) => total + _resolveGuestCount(reservation),
          );

      final overdueCheckedOutPending = latestReservations.where((reservation) {
        if (reservation.status != ReservationStatus.checkedIn) {
          return false;
        }
        if (reservation.departureDateUnknown) {
          return false;
        }
        final checkOut = DateTime(
          reservation.checkOutDate.year,
          reservation.checkOutDate.month,
          reservation.checkOutDate.day,
        );
        return checkOut.isBefore(today);
      }).length;

      controller.add(
        DashboardStats(
          totalPitches: latestPitches.length,
          occupiedPitches: occupiedPitches,
          availablePitches: availablePitches,
          currentGuests: currentGuests,
          arrivalsToday: arrivalsToday,
          departuresToday: actualDeparturesToday,
          openDebtReservations: openDebtReservations,
          openDebtAmount: openDebtAmount,
          myCheckedOutPitchesToday: myCheckedOutPitchesToday,
          myCheckedOutGuestsToday: myCheckedOutGuestsToday,
          plannedDeparturesToday: plannedDeparturesToday,
          overdueCheckedOutPending: overdueCheckedOutPending,
          totalGuestsThroughCamp: totalGuestsThroughCamp,
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
