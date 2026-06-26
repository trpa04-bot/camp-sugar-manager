import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';

enum DuplicateImportAction { cancel, openExisting, saveAnyway }

enum ImportFlowStatus { saved, cancelled, openedExisting }

class ImportFlowResult {
  const ImportFlowResult({required this.status, this.duplicateMatch});

  final ImportFlowStatus status;
  final Reservation? duplicateMatch;
}

Future<ImportFlowResult> processImportedReservation({
  required ReservationService service,
  required Reservation reservation,
  required Future<DuplicateImportAction> Function(Reservation existing)
  onDuplicateDetected,
  Future<void> Function(Reservation existing)? onOpenExisting,
}) async {
  final duplicate = await service.checkDuplicateBeforeCreate(reservation);

  var allowDuplicate = false;
  if (duplicate.hasDuplicate && duplicate.match != null) {
    final action = await onDuplicateDetected(duplicate.match!);
    if (action == DuplicateImportAction.cancel) {
      return ImportFlowResult(
        status: ImportFlowStatus.cancelled,
        duplicateMatch: duplicate.match,
      );
    }
    if (action == DuplicateImportAction.openExisting) {
      if (onOpenExisting != null) {
        await onOpenExisting(duplicate.match!);
      }
      return ImportFlowResult(
        status: ImportFlowStatus.openedExisting,
        duplicateMatch: duplicate.match,
      );
    }
    allowDuplicate = true;
  }

  await service.createReservation(reservation, allowDuplicate: allowDuplicate);
  return ImportFlowResult(status: ImportFlowStatus.saved);
}
