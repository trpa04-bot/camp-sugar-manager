import 'package:flutter_test/flutter_test.dart';

import 'package:camp_sugar_manager/core/utils/date_utils.dart' as date_utils;

void main() {
  group('dateOnly', () {
    test('uklanja vremensku komponentu', () {
      final result = date_utils.dateOnly(DateTime(2026, 7, 5, 14, 30, 45));
      expect(result, DateTime(2026, 7, 5));
    });
  });

  group('today', () {
    test('vraća ponoć danas koristeći injektirani now', () {
      final now = DateTime(2026, 7, 5, 23, 59);
      expect(date_utils.today(now: now), DateTime(2026, 7, 5));
    });
  });

  group('isSameDate', () {
    test('isti dan, različito vrijeme -> true', () {
      expect(
        date_utils.isSameDate(
          DateTime(2026, 7, 5, 1),
          DateTime(2026, 7, 5, 23),
        ),
        isTrue,
      );
    });

    test('različiti dan -> false', () {
      expect(
        date_utils.isSameDate(DateTime(2026, 7, 5), DateTime(2026, 7, 6)),
        isFalse,
      );
    });
  });

  group('formatDate', () {
    test('formatira kao dd.MM.yyyy s vodećim nulama', () {
      expect(date_utils.formatDate(DateTime(2026, 7, 5)), '05.07.2026');
    });

    test('dvoznamenkasti dan i mjesec', () {
      expect(date_utils.formatDate(DateTime(2026, 12, 25)), '25.12.2026');
    });
  });

  group('formatDateOrDash', () {
    test('null -> zadani fallback', () {
      expect(date_utils.formatDateOrDash(null), '-');
    });

    test('null -> prilagođeni fallback', () {
      expect(
        date_utils.formatDateOrDash(null, fallback: 'Nepoznato'),
        'Nepoznato',
      );
    });

    test('valjan datum -> formatirani string', () {
      expect(
        date_utils.formatDateOrDash(DateTime(2026, 1, 9)),
        '09.01.2026',
      );
    });
  });

  group('formatDateRange', () {
    test('formatira raspon datuma', () {
      expect(
        date_utils.formatDateRange(
          DateTime(2026, 7, 5),
          DateTime(2026, 7, 12),
        ),
        '05.07.2026 - 12.07.2026',
      );
    });
  });

  group('nightsBetween', () {
    test('računa razliku u danima', () {
      expect(
        date_utils.nightsBetween(
          DateTime(2026, 7, 5),
          DateTime(2026, 7, 12),
        ),
        7,
      );
    });

    test('ignorira vremensku komponentu', () {
      expect(
        date_utils.nightsBetween(
          DateTime(2026, 7, 5, 23),
          DateTime(2026, 7, 6, 1),
        ),
        1,
      );
    });

    test('zadani minimum je 0', () {
      expect(
        date_utils.nightsBetween(
          DateTime(2026, 7, 5),
          DateTime(2026, 7, 5),
        ),
        0,
      );
    });

    test('minimum 1 primjenjuje barem jednu noć', () {
      expect(
        date_utils.nightsBetween(
          DateTime(2026, 7, 5),
          DateTime(2026, 7, 5),
          minimum: 1,
        ),
        1,
      );
    });

    test('minimum se primjenjuje i kada je razlika negativna', () {
      expect(
        date_utils.nightsBetween(
          DateTime(2026, 7, 10),
          DateTime(2026, 7, 5),
          minimum: 1,
        ),
        1,
      );
    });
  });
}
