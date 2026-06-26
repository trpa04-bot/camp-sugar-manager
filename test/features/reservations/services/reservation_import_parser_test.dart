import 'package:flutter_test/flutter_test.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_parser.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_validation.dart';

void main() {
  group('ReservationImportParser', () {
    group('Booking format', () {
      test('parses simple booking confirmation', () async {
        const bookingText = '''
          Booking Confirmation
          Guest: Mario Hollauf
          Check-in: 13 June 2026
          Check-out: 20 June 2026
          2 guests
          Total: €500.00
        ''';

        final result = await ReservationImportParser.parseText(bookingText);

        expect(result.primaryGuestFullName, 'Mario Hollauf');
        expect(result.checkInDate?.day, 13);
        expect(result.checkInDate?.month, 6);
        expect(result.checkInDate?.year, 2026);
        expect(result.checkOutDate?.day, 20);
        expect(result.guestCount, 2);
        expect(result.source, ReservationSource.booking);
      });
    });

    group('WhatsApp format', () {
      test('parses casual WhatsApp message', () async {
        const whatsappText = '''
          Bok, dolazimo 14.7. i ostajemo do 18.7.
          Nas je 2 odraslih i dvoje djece.
        ''';

        final result = await ReservationImportParser.parseText(whatsappText);

        expect(result.checkInDate?.day, 14);
        expect(result.checkInDate?.month, 7);
        expect(result.checkOutDate?.day, 18);
        expect(result.checkOutDate?.month, 7);
        expect(result.adults, 2);
        expect(result.children, 2);
        expect(result.source, ReservationSource.whatsapp);
      });
    });

    group('Airbnb format', () {
      test(
        'parses exact wizard airbnb sample without airbnb keyword',
        () async {
          const text = '''
          Reservation confirmed
          Guest: John Smith
          Aug 10, 2026 - Aug 15, 2026
          3 guests
          Confirmation code: HMABC123
        ''';

          final result = await ReservationImportParser.parseText(text);

          expect(result.source, ReservationSource.airbnb);
          expect(result.primaryGuestFullName, 'John Smith');
          expect(result.checkInDate, DateTime(2026, 8, 10));
          expect(result.checkOutDate, DateTime(2026, 8, 15));
          expect(result.guestCount, 3);
          expect(result.adults, 3);
          expect(result.totalGuestCount, 3);
          expect(result.sourceReservationId, 'HMABC123');

          final validation = validateImport(
            result: result,
            selectedPitchIds: const ['pitch-a'],
          );
          expect(validation.isValid, isTrue);
        },
      );

      test('parses airbnb date range in month-day format', () async {
        const airbnbText = '''
          Airbnb reservation
          Guest: Petra Novak
          August 10, 2026 - August 14, 2026
          2 guests
          Confirmation code: HMA4K9T2
        ''';

        final result = await ReservationImportParser.parseText(airbnbText);

        expect(result.source, ReservationSource.airbnb);
        expect(result.checkInDate, DateTime(2026, 8, 10));
        expect(result.checkOutDate, DateTime(2026, 8, 14));
      });

      test('sourceHint has priority over auto detection', () async {
        const text = 'Booking confirmation\nGuest: Mario Hollauf';

        final result = await ReservationImportParser.parseText(
          text,
          sourceHint: ReservationSource.whatsapp,
        );

        expect(result.source, ReservationSource.whatsapp);
      });
    });

    group('Campspace format', () {
      test('parses campspace booking with multiple pitches', () async {
        const campspaceText = '''
          Campspace Reservation
          Guest: Anna Kowalska
          Arrival 5 August
          Departure 12 August
          1 adult, 2 children
          2 pitches
        ''';

        final result = await ReservationImportParser.parseText(campspaceText);

        expect(result.primaryGuestFullName, 'Anna Kowalska');
        expect(result.checkInDate?.day, 5);
        expect(result.checkInDate?.month, 8);
        expect(result.checkOutDate?.day, 12);
        expect(result.checkOutDate?.month, 8);
        expect(result.adults, 1);
        expect(result.children, 2);
        expect(result.pitchCount, 2);
        expect(result.source, ReservationSource.campspace);
      });

      test('detects campspace from structural fields', () async {
        const campspaceText = '''
          Guest: Lara Vidović
          Arrival 5 August 2026
          Departure 9 August 2026
          2 pitches
        ''';

        final result = await ReservationImportParser.parseText(campspaceText);

        expect(result.source, ReservationSource.campspace);
        expect(result.primaryGuestFullName, 'Lara Vidović');
        expect(result.pitchCount, 2);
      });
    });

    group('Date parsing', () {
      test('parses German date format', () async {
        const germanText = '19 Juni 2026';

        final result = await ReservationImportParser.parseText(germanText);

        expect(result.checkInDate?.day, 19);
        expect(result.checkInDate?.month, 6);
        expect(result.checkInDate?.year, 2026);
      });

      test('parses Italian date format', () async {
        const italianText = '19 giugno 2026';

        final result = await ReservationImportParser.parseText(italianText);

        expect(result.checkInDate?.day, 19);
        expect(result.checkInDate?.month, 6);
        expect(result.checkInDate?.year, 2026);
      });

      test('parses Croatian date format', () async {
        const croatianText = '19 lipnja 2026';

        final result = await ReservationImportParser.parseText(croatianText);

        expect(result.checkInDate?.day, 19);
        expect(result.checkInDate?.month, 6);
        expect(result.checkInDate?.year, 2026);
      });

      test('parses Croatian genitive month rujna', () async {
        const croatianText = 'Dolazak: 3. rujna 2026';

        final result = await ReservationImportParser.parseText(croatianText);

        expect(result.checkInDate, DateTime(2026, 9, 3));
      });

      test('parses dot-separated date format DD.MM.YYYY', () async {
        const dotText = 'Dolazak: 19.06.2026';

        final result = await ReservationImportParser.parseText(dotText);

        expect(result.checkInDate?.day, 19);
        expect(result.checkInDate?.month, 6);
        expect(result.checkInDate?.year, 2026);
      });
    });

    group('Guest count parsing', () {
      test('parses adults in English', () async {
        const text = '2 adults';

        final result = await ReservationImportParser.parseText(text);

        expect(result.adults, 2);
      });

      test('parses children in Croatian', () async {
        const text = '2 djece';

        final result = await ReservationImportParser.parseText(text);

        expect(result.children, 2);
      });

      test('parses mixed guest count', () async {
        const text = '3 adults, 2 children, 1 infant';

        final result = await ReservationImportParser.parseText(text);

        expect(result.adults, 3);
        expect(result.children, 2);
      });

      test('calculates total guest count', () async {
        const text = '2 adults, 2 children';

        final result = await ReservationImportParser.parseText(text);

        expect(result.totalGuestCount, 4);
      });
    });

    group('Pitch count parsing', () {
      test('parses single pitch', () async {
        const text = '1 pitch';

        final result = await ReservationImportParser.parseText(text);

        expect(result.pitchCount, 1);
      });

      test('parses multiple pitches', () async {
        const text = '2 pitches';

        final result = await ReservationImportParser.parseText(text);

        expect(result.pitchCount, 2);
      });

      test('defaults to 1 pitch when not specified', () async {
        const text = 'No pitch info here';

        final result = await ReservationImportParser.parseText(text);

        expect(result.pitchCount, 1);
      });
    });

    group('Price parsing', () {
      test('parses euro price', () async {
        const text = 'Total: €500.00';

        final result = await ReservationImportParser.parseText(text);

        expect(result.totalPrice, 500.0);
      });
    });

    group('Edge cases', () {
      test('handles empty text', () async {
        final result = await ReservationImportParser.parseText('');

        expect(result.confidence, 0.0);
        expect(result.needsReview, true);
      });

      test('handles text without dates', () async {
        const text = 'Just some random text without dates';

        final result = await ReservationImportParser.parseText(text);

        expect(result.checkInDate, null);
        expect(result.warnings.isNotEmpty, true);
      });

      test('combines first and last names correctly', () async {
        final result = await ReservationImportParser.parseText('');

        final editedResult = result.copyWith(
          primaryGuestFirstName: 'John',
          primaryGuestLastName: 'Doe',
        );

        expect(editedResult.primaryGuestName, 'John Doe');
      });

      test('extracts free text name from reservation sentence', () async {
        const text =
            'Molim rezervacija za Petra Novak od 10.08.2026 do 12.08.2026';

        final result = await ReservationImportParser.parseText(text);

        expect(result.primaryGuestFullName, 'Petra Novak');
      });
    });
  });
}
