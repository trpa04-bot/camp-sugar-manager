import 'package:cloud_firestore/cloud_firestore.dart';

import '../../reservations/models/reservation.dart';
import '../models/payment.dart';

class PaymentService {
  const PaymentService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _paymentsRef =>
      _firestore.collection('payments');

  /// Add new payment
  Future<Payment> addPayment(Payment payment) async {
    final docRef = _paymentsRef.doc();
    final paymentWithId = payment.copyWith(id: docRef.id);
    await docRef.set(paymentWithId.toMap());
    return paymentWithId;
  }

  /// Update existing payment
  Future<void> updatePayment(Payment payment) async {
    await _paymentsRef
        .doc(payment.id)
        .update(payment.copyWith(updatedAt: DateTime.now()).toMap());
  }

  /// Delete payment
  Future<void> deletePayment(String paymentId) async {
    await _paymentsRef.doc(paymentId).delete();
  }

  /// Get all payments
  Stream<List<Payment>> watchPayments() {
    return _paymentsRef.orderBy('createdAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) => Payment.fromDoc(doc)).toList();
    });
  }

  /// Get payments by reservation
  Stream<List<Payment>> watchPaymentsByReservation(String reservationId) {
    return _paymentsRef
        .where('reservationId', isEqualTo: reservationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Payment.fromDoc(doc)).toList();
        });
  }

  /// Get payments by guest
  Stream<List<Payment>> watchPaymentsByGuest(String guestName) {
    return _paymentsRef
        .where('guestName', isEqualTo: guestName)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Payment.fromDoc(doc)).toList();
        });
  }

  /// Get payments by method
  Stream<List<Payment>> watchPaymentsByMethod(PaymentMethod method) {
    return _paymentsRef
        .where('method', isEqualTo: method.name)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => Payment.fromDoc(doc)).toList();
        });
  }

  /// Get total paid by guest
  Future<double> getTotalPaidByGuest(String guestName) async {
    final snapshot = await _paymentsRef
        .where('guestName', isEqualTo: guestName)
        .get();

    double total = 0;
    for (final doc in snapshot.docs) {
      final payment = Payment.fromDoc(doc);
      total += payment.amount;
    }
    return total;
  }

  /// Get total paid by method
  Future<double> getTotalPaidByMethod(PaymentMethod method) async {
    final snapshot = await _paymentsRef
        .where('method', isEqualTo: method.name)
        .get();

    double total = 0;
    for (final doc in snapshot.docs) {
      final payment = Payment.fromDoc(doc);
      total += payment.amount;
    }
    return total;
  }

  /// Backfills missing payment history rows for legacy reservations where
  /// reservation-level payment state exists but no document exists in `payments`.
  Future<int> backfillMissingPaymentsFromReservations() async {
    final paidStatusSnapshot = await _firestore
        .collection('reservations')
        .where(
          'paymentStatus',
          whereIn: <String>[
            PaymentStatus.paid.name,
            PaymentStatus.partiallyPaid.name,
          ],
        )
        .get();
    final amountPaidSnapshot = await _firestore
        .collection('reservations')
        .where('amountPaid', isGreaterThan: 0)
        .get();
    final depositPaidSnapshot = await _firestore
        .collection('reservations')
        .where('depositPaid', isGreaterThan: 0)
        .get();

    final reservationDocsById =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
          for (final doc in paidStatusSnapshot.docs) doc.id: doc,
          for (final doc in amountPaidSnapshot.docs) doc.id: doc,
          for (final doc in depositPaidSnapshot.docs) doc.id: doc,
        };

    var created = 0;
    for (final reservationDoc in reservationDocsById.values) {
      final reservation = Reservation.fromDoc(reservationDoc);
      final derivedAmount = _deriveBackfillAmount(reservation);
      if (derivedAmount <= 0) {
        continue;
      }

      final guestName = reservation.primaryGuestName.trim();
      if (guestName.isEmpty) {
        continue;
      }

      final existingPayment = await _paymentsRef
          .where('reservationId', isEqualTo: reservation.id)
          .limit(1)
          .get();
      if (existingPayment.docs.isNotEmpty) {
        continue;
      }

      final docId = 'auto_backfill_${reservation.id}';
      final now = DateTime.now();
      final createdAt = reservation.createdAt ?? reservation.updatedAt ?? now;
      await _paymentsRef.doc(docId).set(<String, dynamic>{
        'id': docId,
        'reservationId': reservation.id,
        'guestName': guestName,
        'amount': derivedAmount,
        'method': PaymentMethod.cash.name,
        'notes': 'Automatski backfill iz rezervacije',
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
      created += 1;
    }

    return created;
  }

  double _deriveBackfillAmount(Reservation reservation) {
    if (reservation.amountPaid > 0) {
      return reservation.amountPaid;
    }
    if (reservation.depositPaid > 0) {
      return reservation.depositPaid;
    }
    if (reservation.paymentStatus == PaymentStatus.paid &&
        reservation.totalPrice > 0) {
      return reservation.totalPrice;
    }
    return 0;
  }
}
