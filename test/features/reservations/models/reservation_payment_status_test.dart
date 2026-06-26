import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps explicit paid status when total price is zero', () {
    final status = derivePaymentStatus(
      totalPrice: 0,
      amountPaid: 0,
      currentStatus: PaymentStatus.paid,
    );

    expect(status, PaymentStatus.paid);
  });

  test('still derives unpaid when no explicit paid and no amounts', () {
    final status = derivePaymentStatus(
      totalPrice: 0,
      amountPaid: 0,
      currentStatus: PaymentStatus.unpaid,
    );

    expect(status, PaymentStatus.unpaid);
  });

  test('derives paid by amount when total price exists', () {
    final status = derivePaymentStatus(
      totalPrice: 100,
      amountPaid: 100,
      currentStatus: PaymentStatus.unpaid,
    );

    expect(status, PaymentStatus.paid);
  });
}
