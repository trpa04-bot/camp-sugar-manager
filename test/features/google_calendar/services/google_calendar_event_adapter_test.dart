import 'package:camp_sugar_manager/features/google_calendar/services/google_calendar_event_adapter.dart';
import 'package:camp_sugar_manager/features/parcels/models/pitch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds import text from title, description, location', () {
    final text = buildGoogleCalendarImportText(
      title: 'Ana Horvat',
      description: 'Airbnb booking 2 guests',
      location: 'Parcela 12',
    );

    expect(text, contains('Ana Horvat'));
    expect(text, contains('Airbnb booking 2 guests'));
    expect(text, contains('Parcela 12'));
  });

  test('adapts all-day event date range', () {
    final result = adaptGoogleEventDates(
      start: DateTime(2026, 7, 10),
      end: DateTime(2026, 7, 13),
      isAllDay: true,
    );

    expect(result.isAllDay, isTrue);
    expect(result.checkInDate, DateTime(2026, 7, 10));
    expect(result.checkOutDate, DateTime(2026, 7, 13));
  });

  test('adapts timezone event and forces at least one night', () {
    final result = adaptGoogleEventDates(
      start: DateTime.parse('2026-08-01T16:00:00+02:00'),
      end: DateTime.parse('2026-08-01T17:00:00+02:00'),
      isAllDay: false,
    );

    expect(result.isAllDay, isFalse);
    expect(result.checkInDate, DateTime(2026, 8, 1));
    expect(result.checkOutDate, DateTime(2026, 8, 2));
  });

  test('detects pitch by normalized name', () {
    const pitches = <Pitch>[
      Pitch(
        id: 'p1',
        name: 'Parcela Šuma 10',
        number: 10,
        zone: 'A',
        status: PitchStatus.available,
        maxGuests: 6,
        currentGuests: 0,
        currentGuestCount: 0,
        hasElectricity: true,
        hasWater: true,
        notes: '',
      ),
    ];

    final match = detectPitchFromText(
      text: 'Rezervacija za parcela suma 10 preko Google kalendara',
      pitches: pitches,
    );

    expect(match?.id, 'p1');
  });
}
