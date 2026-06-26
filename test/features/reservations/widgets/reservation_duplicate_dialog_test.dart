import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_duplicate_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Reservation sampleReservation() {
    return Reservation(
      id: 'res-1',
      bookingReference: '123456789',
      source: ReservationSource.booking,
      primaryGuestName: 'Mario Hollauf',
      primaryGuestId: '',
      primaryGuestPhone: '',
      primaryGuestEmail: '',
      pitchId: 'pitch-1',
      pitchName: 'Parcela 1',
      checkInDate: DateTime(2026, 6, 13),
      checkOutDate: DateTime(2026, 6, 20),
      adults: 2,
      children: 0,
      pets: 0,
      vehicles: 1,
      accommodationType: '',
      status: ReservationStatus.confirmed,
      totalPrice: 500,
      depositPaid: 0,
      amountPaid: 0,
      paymentStatus: PaymentStatus.unpaid,
      notes: '',
      registeredGuestCount: 2,
      currentGuests: 0,
      sourceReservationId: '123456789',
      pitchIds: const ['pitch-1'],
    );
  }

  Future<void> pumpDialog(
    WidgetTester tester,
    void Function(BuildContext context) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => show(context),
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

  testWidgets('shows duplicate dialog with required actions', (tester) async {
    await pumpDialog(tester, (context) {
      showReservationDuplicateDialog(context, sampleReservation());
    });

    expect(find.text('Moguća postojeća rezervacija'), findsOneWidget);
    expect(find.text('Otvori postojeću'), findsOneWidget);
    expect(find.text('Svejedno spremi'), findsOneWidget);
    expect(find.text('Odustani'), findsOneWidget);
  });

  testWidgets('returns cancel decision', (tester) async {
    DuplicateDialogDecision? decision;

    await pumpDialog(tester, (context) async {
      decision = await showReservationDuplicateDialog(
        context,
        sampleReservation(),
      );
    });

    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();

    expect(decision, DuplicateDialogDecision.cancel);
  });

  testWidgets('returns open existing decision', (tester) async {
    DuplicateDialogDecision? decision;

    await pumpDialog(tester, (context) async {
      decision = await showReservationDuplicateDialog(
        context,
        sampleReservation(),
      );
    });

    await tester.tap(find.text('Otvori postojeću'));
    await tester.pumpAndSettle();

    expect(decision, DuplicateDialogDecision.openExisting);
  });

  testWidgets('returns save anyway decision', (tester) async {
    DuplicateDialogDecision? decision;

    await pumpDialog(tester, (context) async {
      decision = await showReservationDuplicateDialog(
        context,
        sampleReservation(),
      );
    });

    await tester.tap(find.text('Svejedno spremi'));
    await tester.pumpAndSettle();

    expect(decision, DuplicateDialogDecision.saveAnyway);
  });
}
