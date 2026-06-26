import 'package:camp_sugar_manager/features/google_calendar/services/google_calendar_title_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoogleCalendarTitleParser.extractNameParts', () {
    test('"Nadia Cusin kamper" → Nadia / Cusin', () {
      final r = GoogleCalendarTitleParser.extractNameParts(
        'Nadia Cusin kamper',
      );
      expect(r.firstName, 'Nadia');
      expect(r.lastName, 'Cusin');
      expect(r.extractedFromTitle, isTrue);
    });

    test('"Gabriela Senčakova" → Gabriela / Senčakova', () {
      final r = GoogleCalendarTitleParser.extractNameParts(
        'Gabriela Senčakova',
      );
      expect(r.firstName, 'Gabriela');
      expect(r.lastName, 'Senčakova');
    });

    test('"Timothy White campspace" → Timothy / White', () {
      final r = GoogleCalendarTitleParser.extractNameParts(
        'Timothy White campspace',
      );
      expect(r.firstName, 'Timothy');
      expect(r.lastName, 'White');
    });

    test('"Marina Stankovic Bg" → Marina / Stankovic', () {
      final r = GoogleCalendarTitleParser.extractNameParts(
        'Marina Stankovic Bg',
      );
      expect(r.firstName, 'Marina');
      expect(r.lastName, 'Stankovic');
    });

    test(
      '"Alessio sa kamper" → Alessio / null (sa and kamper are descriptors)',
      () {
        final r = GoogleCalendarTitleParser.extractNameParts(
          'Alessio sa kamper',
        );
        expect(r.firstName, 'Alessio');
        expect(r.lastName, isNull);
        expect(r.extractedFromTitle, isTrue);
      },
    );

    test('"Nina Kavsek booking dole kut rez" → Nina / Kavsek', () {
      final r = GoogleCalendarTitleParser.extractNameParts(
        'Nina Kavsek booking dole kut rez',
      );
      expect(r.firstName, 'Nina');
      expect(r.lastName, 'Kavsek');
    });

    test('"poljaci 2 satora" → null / null (not a personal name)', () {
      final r = GoogleCalendarTitleParser.extractNameParts('poljaci 2 satora');
      expect(r.firstName, isNull);
      expect(r.lastName, isNull);
      expect(r.extractedFromTitle, isFalse);
    });

    test('empty title → null / null', () {
      final r = GoogleCalendarTitleParser.extractNameParts('');
      expect(r.firstName, isNull);
      expect(r.lastName, isNull);
    });

    test('null title → null / null', () {
      final r = GoogleCalendarTitleParser.extractNameParts(null);
      expect(r.firstName, isNull);
      expect(r.lastName, isNull);
    });

    test(
      '"Anna-Maria Kowalski" → Anna-Maria / Kowalski (hyphenated first name)',
      () {
        final r = GoogleCalendarTitleParser.extractNameParts(
          'Anna-Maria Kowalski',
        );
        expect(r.firstName, 'Anna-Maria');
        expect(r.lastName, 'Kowalski');
      },
    );

    test('rawTitleSuffix captures descriptors after last name', () {
      final r = GoogleCalendarTitleParser.extractNameParts(
        'Nadia Cusin kamper booking',
      );
      expect(r.firstName, 'Nadia');
      expect(r.lastName, 'Cusin');
      expect(r.rawTitleSuffix, isNotNull);
    });
  });
}
