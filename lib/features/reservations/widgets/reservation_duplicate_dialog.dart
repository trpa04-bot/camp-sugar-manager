import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:flutter/material.dart';

enum DuplicateDialogDecision { openExisting, saveAnyway, cancel }

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

Future<DuplicateDialogDecision?> showReservationDuplicateDialog(
  BuildContext context,
  Reservation duplicate,
) {
  final reference = duplicate.sourceReservationId.isNotEmpty
      ? duplicate.sourceReservationId
      : duplicate.bookingReference;
  final parcelInfo = duplicate.pitchIds.isNotEmpty
      ? duplicate.pitchIds.join(', ')
      : duplicate.pitchName;

  return showDialog<DuplicateDialogDecision>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Moguća postojeća rezervacija'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ime: ${duplicate.primaryGuestName}'),
            Text(
              'Datumi: ${_formatDate(duplicate.checkInDate)} - ${_formatDate(duplicate.checkOutDate)}',
            ),
            Text('Izvor: ${duplicate.source.displayLabel}'),
            Text('ID: ${reference.isEmpty ? '-' : reference}'),
            Text('Parcele: ${parcelInfo.isEmpty ? '-' : parcelInfo}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(DuplicateDialogDecision.cancel),
            child: const Text('Odustani'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(DuplicateDialogDecision.openExisting),
            child: const Text('Otvori postojeću'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(DuplicateDialogDecision.saveAnyway),
            child: const Text('Svejedno spremi'),
          ),
        ],
      );
    },
  );
}
