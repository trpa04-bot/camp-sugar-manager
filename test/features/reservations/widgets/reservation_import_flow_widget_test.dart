import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_parser.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_import_review_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> seedPitches(FakeFirebaseFirestore firestore) async {
    await firestore.collection('pitches').doc('pitch-a').set({
      'id': 'pitch-a',
      'name': 'Parcela A',
      'number': 1,
      'zone': 'A',
      'status': 'available',
      'maxGuests': 6,
      'currentGuests': 0,
      'currentGuestCount': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });

    await firestore.collection('pitches').doc('pitch-b').set({
      'id': 'pitch-b',
      'name': 'Parcela B',
      'number': 2,
      'zone': 'A',
      'status': 'available',
      'maxGuests': 6,
      'currentGuests': 0,
      'currentGuestCount': 0,
      'hasElectricity': true,
      'hasWater': true,
      'notes': '',
    });
  }

  testWidgets(
    'Campspace flow enforces exact 2-pitch selection and saves 2 unique pitch ids',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedPitches(firestore);

      const text = '''
      Guest: Anna Kowalska
      Arrival: 5 August 2026
      Departure: 12 August 2026
      1 adult, 2 children
      2 pitches
    ''';

      final parsed = await ReservationImportParser.parseText(text);

      ReservationImportResult? savedResult;
      List<String>? savedPitchIds;

      await tester.pumpWidget(
        MaterialApp(
          home: ReservationImportReviewSheet(
            result: parsed,
            firestore: firestore,
            onSave: (result, pitchIds) {
              savedResult = result;
              savedPitchIds = pitchIds;
            },
          ),
        ),
      );

      expect(parsed.primaryGuestFullName, 'Anna Kowalska');
      expect(parsed.checkInDate, DateTime(2026, 8, 5));
      expect(parsed.checkOutDate, DateTime(2026, 8, 12));
      expect(parsed.adults, 1);
      expect(parsed.children, 2);
      expect(parsed.totalGuestCount, 3);
      expect(parsed.source, ReservationSource.campspace);
      expect(parsed.pitchCount, 2);

      final continueFinder = find.text('Nastavi na dodjelu parcele');
      await tester.ensureVisible(continueFinder);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(find.text('Odaberi parcele'), findsOneWidget);
      expect(find.text('Potrebno je odabrati još 2 parcele.'), findsOneWidget);

      final saveButtonFinder = find.widgetWithText(
        FilledButton,
        'Spremi rezervaciju',
      );
      FilledButton saveButton = tester.widget<FilledButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNull);

      await tester.tap(find.text('Parcela A'));
      await tester.pumpAndSettle();

      expect(find.text('Potrebno je odabrati još 1 parcelu.'), findsOneWidget);
      saveButton = tester.widget<FilledButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNull);

      await tester.tap(find.text('Parcela B'));
      await tester.pumpAndSettle();

      saveButton = tester.widget<FilledButton>(saveButtonFinder);
      expect(saveButton.onPressed, isNotNull);

      await tester.tap(find.text('Parcela A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcela A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Spremi rezervaciju'));
      await tester.pumpAndSettle();

      expect(savedResult, isNotNull);
      expect(savedResult!.pitchCount, 2);
      expect(savedPitchIds, isNotNull);
      expect(savedPitchIds!.length, 2);
      expect(savedPitchIds!.toSet().length, 2);

      final selectedDocs = await Future.wait(
        savedPitchIds!.map(
          (id) => firestore.collection('pitches').doc(id).get(),
        ),
      );
      final selectedNames = selectedDocs
          .where((doc) => doc.exists)
          .map((doc) => doc.data()!['name'] as String)
          .toList(growable: false);
      expect(selectedNames.length, 2);
      expect(selectedNames.toSet().length, 2);
    },
  );

  testWidgets(
    'Email Croatian dates parse and review is valid without manual correction',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedPitches(firestore);

      const emailText = '''
      Poštovani,
      rezervacija za Petra Novak,
      dolazak 3. rujna 2026.,
      odlazak 9. rujna 2026.,
      2 odrasle osobe i 1 dijete.
    ''';

      final parsed = await ReservationImportParser.parseText(emailText);
      final parsedWithOtherHint = await ReservationImportParser.parseText(
        emailText,
        sourceHint: ReservationSource.other,
      );

      expect(parsed.primaryGuestFullName, 'Petra Novak');
      expect(parsed.checkInDate, DateTime(2026, 9, 3));
      expect(parsed.checkOutDate, DateTime(2026, 9, 9));
      expect(parsed.adults, 2);
      expect(parsed.children, 1);
      expect(parsed.totalGuestCount, 3);
      expect(parsed.source, ReservationSource.email);
      expect(parsedWithOtherHint.source, ReservationSource.other);

      await tester.pumpWidget(
        MaterialApp(
          home: ReservationImportReviewSheet(
            result: parsed,
            firestore: firestore,
            onSave: (ignoredResult, ignoredPitchIds) {},
          ),
        ),
      );

      final continueFinder = find.text('Nastavi na dodjelu parcele');
      await tester.ensureVisible(continueFinder);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(find.text('Odaberi parcele'), findsOneWidget);
      expect(find.textContaining('Unesite naziv gosta'), findsNothing);
      expect(find.textContaining('Odaberite datum dolaska'), findsNothing);
      expect(find.textContaining('Odaberite datum odlaska'), findsNothing);
    },
  );

  testWidgets(
    'Google title fallback pre-fills first and last name when parsed names are empty',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedPitches(firestore);

      final result = ReservationImportResult(
        primaryGuestFirstName: '',
        primaryGuestLastName: '',
        primaryGuestFullName: '',
        checkInDate: DateTime(2026, 9, 3),
        checkOutDate: DateTime(2026, 9, 9),
        adults: 2,
        pitchCount: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReservationImportReviewSheet(
            result: result,
            fallbackGuestTitle: 'Nadia Cusin kamper',
            firestore: firestore,
            onSave: (ignoredResult, ignoredPitchIds) {},
          ),
        ),
      );

      final firstNameField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Ime',
      );
      final lastNameField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Prezime',
      );

      expect(firstNameField, findsOneWidget);
      expect(lastNameField, findsOneWidget);

      final ime = tester.widget<TextField>(firstNameField).controller?.text;
      final prezime = tester.widget<TextField>(lastNameField).controller?.text;
      expect(ime, 'Nadia');
      expect(prezime, 'Cusin');

      final continueFinder = find.text('Nastavi na dodjelu parcele');
      await tester.ensureVisible(continueFinder);
      await tester.tap(continueFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('Unesite naziv gosta'), findsNothing);
    },
  );
}
