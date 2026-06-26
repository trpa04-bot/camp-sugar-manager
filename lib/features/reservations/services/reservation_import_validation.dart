import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';

class ReservationImportValidationResult {
  const ReservationImportValidationResult({
    required this.isValid,
    required this.errors,
    required this.requiredPitchCount,
    required this.selectedPitchCount,
    required this.missingPitchCount,
  });

  final bool isValid;
  final List<String> errors;
  final int requiredPitchCount;
  final int selectedPitchCount;
  final int missingPitchCount;

  String? get firstError => errors.isEmpty ? null : errors.first;
}

ReservationImportValidationResult validateImport({
  required ReservationImportResult result,
  required List<String> selectedPitchIds,
}) {
  final errors = <String>[];

  final guestName = result.primaryGuestName.trim();
  if (guestName.isEmpty) {
    errors.add('Unesite naziv gosta.');
  }

  final checkIn = result.checkInDate;
  final checkOut = result.checkOutDate;
  if (checkIn == null) {
    errors.add('Datum dolaska je obavezan.');
  }
  if (checkOut == null) {
    errors.add('Datum odlaska je obavezan.');
  }
  if (checkIn != null && checkOut != null && !checkOut.isAfter(checkIn)) {
    errors.add('Datum odlaska mora biti nakon datuma dolaska.');
  }

  if (result.totalGuestCount < 1) {
    errors.add('Broj gostiju mora biti barem 1.');
  }

  final requiredPitchCount = result.pitchCount < 1 ? 1 : result.pitchCount;
  if (requiredPitchCount < 1) {
    errors.add('Broj parcela mora biti barem 1.');
  }

  final uniqueSelected = selectedPitchIds.toSet();
  if (uniqueSelected.length != selectedPitchIds.length) {
    errors.add('Parcele moraju biti različite.');
  }

  final missing = requiredPitchCount - uniqueSelected.length;
  if (missing > 0) {
    if (missing == 1) {
      errors.add('Potrebno je odabrati još 1 parcelu.');
    } else {
      errors.add('Potrebno je odabrati još $missing parcele.');
    }
  }

  if (uniqueSelected.length > requiredPitchCount) {
    errors.add('Odabran je prevelik broj parcela.');
  }

  return ReservationImportValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
    requiredPitchCount: requiredPitchCount,
    selectedPitchCount: uniqueSelected.length,
    missingPitchCount: missing > 0 ? missing : 0,
  );
}
