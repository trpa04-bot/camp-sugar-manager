import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReservationImportResult validResult() {
    return ReservationImportResult(
      primaryGuestFullName: 'Petra Novak',
      checkInDate: DateTime(2026, 8, 10),
      checkOutDate: DateTime(2026, 8, 12),
      adults: 2,
      pitchCount: 2,
    );
  }

  group('validateImport', () {
    test('is invalid when checkOutDate is missing', () {
      final missingCheckOut = ReservationImportResult(
        primaryGuestFullName: 'Petra Novak',
        checkInDate: DateTime(2026, 8, 10),
        adults: 2,
        pitchCount: 2,
      );

      final result = validateImport(
        result: missingCheckOut,
        selectedPitchIds: const ['p1', 'p2'],
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Datum odlaska je obavezan.'));
    });

    test('is invalid when checkOutDate is before or equal to checkInDate', () {
      final result = validateImport(
        result: validResult().copyWith(checkOutDate: DateTime(2026, 8, 10)),
        selectedPitchIds: const ['p1', 'p2'],
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors,
        contains('Datum odlaska mora biti nakon datuma dolaska.'),
      );
    });

    test('is invalid when selected pitch count is lower than required', () {
      final result = validateImport(
        result: validResult(),
        selectedPitchIds: const ['p1'],
      );

      expect(result.isValid, isFalse);
      expect(result.requiredPitchCount, 2);
      expect(result.selectedPitchCount, 1);
      expect(result.missingPitchCount, 1);
      expect(result.errors, contains('Potrebno je odabrati još 1 parcelu.'));
    });

    test('is invalid when selected pitch count is higher than required', () {
      final result = validateImport(
        result: validResult().copyWith(pitchCount: 1),
        selectedPitchIds: const ['p1', 'p2'],
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Odabran je prevelik broj parcela.'));
    });

    test('is invalid when selected pitches contain duplicates', () {
      final result = validateImport(
        result: validResult(),
        selectedPitchIds: const ['p1', 'p1'],
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains('Parcele moraju biti različite.'));
    });

    test(
      'is valid when all required fields are present and pitch count matches',
      () {
        final result = validateImport(
          result: validResult(),
          selectedPitchIds: const ['p1', 'p2'],
        );

        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      },
    );
  });
}
