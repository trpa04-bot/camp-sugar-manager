import 'package:camp_sugar_manager/features/parcels/parcels_page.dart';
import 'package:camp_sugar_manager/features/parcels/services/pitch_service.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> seedPitches(
    FakeFirebaseFirestore firestore, {
    int count = 6,
    String namePrefix = 'Parcela',
    String guestName = 'Gost',
  }) async {
    for (var i = 1; i <= count; i++) {
      await firestore.collection('pitches').doc('pitch-$i').set({
        'id': 'pitch-$i',
        'name': '$namePrefix $i',
        'number': i,
        'zone': 'A',
        'status': i.isEven ? 'occupied' : 'available',
        'maxGuests': 4,
        'currentGuests': i.isEven ? 2 : 0,
        'currentGuestCount': i.isEven ? 2 : 0,
        'currentReservationId': i.isEven ? 'res-$i' : null,
        'currentPrimaryGuestName': i.isEven ? '$guestName $i' : null,
        'occupiedFrom': DateTime(2026, 6, 20),
        'occupiedUntil': DateTime(2026, 6, 22),
        'hasElectricity': i % 3 != 0,
        'hasWater': i % 4 != 0,
        'notes': '',
      });

      if (i.isEven) {
        await firestore.collection('reservations').doc('res-$i').set({
          'id': 'res-$i',
          'pitchId': 'pitch-$i',
          'pitchIds': ['pitch-$i'],
          'pitchName': '$namePrefix $i',
          'primaryGuestName': '$guestName $i',
          'status': 'checkedIn',
          'checkInDate': DateTime(2026, 6, 20),
          'checkOutDate': DateTime(2026, 6, 25),
          'departureDateUnknown': true,
          'source': 'manual',
          'totalPrice': 250.0,
          'pricePerNight': 50.0,
          'amountPaid': 75.0,
          'paymentStatus': 'partial',
          'totalGuests': 2,
          'adults': 2,
          'children': 0,
          'pets': 0,
          'createdAt': DateTime(2026, 6, 20),
          'updatedAt': DateTime(2026, 6, 20),
        });
      }
    }
  }

  Future<void> pumpParcels(
    WidgetTester tester, {
    required FakeFirebaseFirestore firestore,
    required Size surfaceSize,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = PitchService(firestore: firestore);
    final reservationService = ReservationService(firestore: firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: ParcelsPage(
          service: service,
          reservationService: reservationService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
  }

  testWidgets('occupied pitch shows current guest and guest count', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final firestore = FakeFirebaseFirestore();
    final service = PitchService(firestore: firestore);
    final reservationService = ReservationService(firestore: firestore);

    await firestore.collection('pitches').doc('pitch-1').set({
      'id': 'pitch-1',
      'name': 'Primorje 1 istok',
      'number': 1,
      'zone': 'A',
      'status': 'occupied',
      'maxGuests': 4,
      'currentGuests': 2,
      'currentGuestCount': 2,
      'currentReservationId': 'res-1',
      'currentPrimaryGuestName': 'Test Gost',
      'occupiedFrom': DateTime(2026, 6, 20),
      'occupiedUntil': DateTime(2026, 6, 22),
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ParcelsPage(
          service: service,
          reservationService: reservationService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.textContaining('Test Gost'), findsOneWidget);
    expect(find.text('Glavni gost nije poznat'), findsNothing);
    expect(find.text('4'), findsWidgets);
    expect(find.byIcon(Icons.groups_2_outlined), findsWidgets);
    expect(find.text('Zauzeta'), findsWidgets);
  });

  testWidgets('uses 4 columns on 1440 width', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(firestore);

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(1440, 1200),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 4);
  });

  testWidgets('uses 3 columns on 1200 width', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(firestore);

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(1200, 1200),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
  });

  testWidgets('uses 2 columns on tablet width', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(firestore);

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(900, 1200),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
  });

  testWidgets('uses 1 column on mobile width', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(firestore);

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(600, 1200),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 1);
  });

  testWidgets('status chip is in same header row and menu works', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(firestore, count: 2);

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(1440, 1200),
    );

    final headerFinder = find.byKey(const Key('pitch-header-row-pitch-1'));
    final chipFinder = find.byKey(const Key('pitch-status-chip-pitch-1'));
    expect(headerFinder, findsOneWidget);
    expect(chipFinder, findsOneWidget);

    final headerRect = tester.getRect(headerFinder);
    final chipRect = tester.getRect(chipFinder);
    expect((chipRect.top - headerRect.top).abs() < 18, isTrue);

    await tester.tap(find.byKey(const Key('pitch-menu-pitch-1')));
    await tester.pumpAndSettle();
    expect(find.text('Uredi parcelu'), findsOneWidget);
    expect(find.text('Obriši parcelu'), findsOneWidget);
  });

  testWidgets('long names do not overflow and due plus guests stay visible', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(
      firestore,
      count: 2,
      namePrefix:
          'Iznad cvjecnjaka ultradugi naziv parcele koji mora ostati stabilan',
      guestName:
          'Jako dugo ime gosta koje ne smije srusiti layout kartice u prikazu',
    );

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(900, 1200),
    );

    expect(find.textContaining('Dug:'), findsWidgets);
    expect(find.byIcon(Icons.groups_2_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick checkout button checks out reservation and frees pitch', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await seedPitches(firestore, count: 2);

    await pumpParcels(
      tester,
      firestore: firestore,
      surfaceSize: const Size(1200, 1200),
    );

    expect(find.text('Brza odjava'), findsWidgets);
    await tester.tap(find.text('Brza odjava').first);
    await tester.pumpAndSettle();

    expect(find.text('Brza odjava gosta'), findsOneWidget);
    await tester.tap(find.text('Odjavi'));
    await tester.pumpAndSettle();

    final reservation = await firestore
        .collection('reservations')
        .doc('res-2')
        .get();
    final pitch = await firestore.collection('pitches').doc('pitch-2').get();

    expect(reservation.data()?['status'], 'checkedOut');
    expect(reservation.data()?['currentGuests'], 0);
    expect(pitch.data()?['status'], 'available');
    expect(pitch.data()?['currentReservationId'], isNull);
  });
}
