import 'package:camp_sugar_manager/features/google_calendar/models/google_calendar_import_event.dart';
import 'package:camp_sugar_manager/features/google_calendar/services/google_calendar_service.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_flow.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_service.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_duplicate_dialog.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_import_review_sheet.dart';
import 'package:flutter/material.dart';

class GoogleCalendarSyncEventsPage extends StatefulWidget {
  GoogleCalendarSyncEventsPage({
    super.key,
    GoogleCalendarService? calendarService,
    ReservationService? reservationService,
  }) : calendarService = calendarService ?? GoogleCalendarService(),
       reservationService = reservationService ?? ReservationService();

  final GoogleCalendarService calendarService;
  final ReservationService reservationService;

  @override
  State<GoogleCalendarSyncEventsPage> createState() =>
      _GoogleCalendarSyncEventsPageState();
}

class _GoogleCalendarSyncEventsPageState
    extends State<GoogleCalendarSyncEventsPage> {
  Future<void> _openReview(GoogleCalendarImportEvent event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReservationImportReviewSheet(
          result: event.parsedReservation,
          fallbackGuestTitle: event.title,
          onSave: (result, pitchIds) async {
            final primaryPitchId = pitchIds?.isNotEmpty == true
                ? pitchIds![0]
                : '';

            final reservation = Reservation(
              id: '',
              bookingReference: result.sourceReservationId ?? '',
              source: result.source ?? ReservationSource.other,
              primaryGuestName: result.primaryGuestName,
              primaryGuestId: '',
              primaryGuestPhone: result.phone ?? '',
              primaryGuestEmail: result.email ?? '',
              pitchId: primaryPitchId,
              pitchName: '',
              checkInDate: result.checkInDate ?? event.startDate,
              checkOutDate: result.checkOutDate ?? event.endDate,
              adults: result.adults ?? 0,
              children: result.children ?? 0,
              pets: 0,
              vehicles: 1,
              accommodationType: result.accommodationType ?? '',
              status: ReservationStatus.confirmed,
              totalPrice: result.totalPrice ?? 0,
              depositPaid: 0,
              amountPaid: 0,
              paymentStatus: PaymentStatus.unpaid,
              notes: result.notes ?? '',
              registeredGuestCount: result.totalGuestCount,
              currentGuests: 0,
              primaryGuestFirstName: result.primaryGuestFirstName ?? '',
              primaryGuestLastName: result.primaryGuestLastName ?? '',
              infants: result.infants ?? 0,
              guestCount: result.totalGuestCount,
              pitchCount: result.pitchCount,
              pitchIds: pitchIds ?? const <String>[],
              sourceReservationId: result.sourceReservationId ?? '',
              externalSource: 'googleCalendar',
              googleCalendarEventId: event.googleEventId,
              googleCalendarId: event.calendarId,
              googleCalendarLastUpdatedAt: event.updatedAtGoogle,
              importedFromGoogleCalendar: true,
            );

            final flowResult = await processImportedReservation(
              service: widget.reservationService,
              reservation: reservation,
              onDuplicateDetected: (existing) async {
                if (!mounted) return DuplicateImportAction.cancel;
                final decision = await showReservationDuplicateDialog(
                  context,
                  existing,
                );
                if (decision == DuplicateDialogDecision.openExisting) {
                  return DuplicateImportAction.openExisting;
                }
                if (decision == DuplicateDialogDecision.saveAnyway) {
                  return DuplicateImportAction.saveAnyway;
                }
                return DuplicateImportAction.cancel;
              },
            );

            if (!mounted) return;

            switch (flowResult.status) {
              case ImportFlowStatus.saved:
                await widget.calendarService.markImported(eventId: event.id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Google događaj je uvezen u rezervacije.'),
                  ),
                );
                break;
              case ImportFlowStatus.cancelled:
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Uvoz je prekinut.')),
                );
                break;
              case ImportFlowStatus.openedExisting:
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Otvorena je postojeća rezervacija.'),
                  ),
                );
                break;
            }
          },
        ),
      ),
    );
  }

  String _statusLabel(GoogleCalendarImportStatus status) {
    switch (status) {
      case GoogleCalendarImportStatus.newEvent:
        return 'Novi događaji';
      case GoogleCalendarImportStatus.needsReview:
        return 'Potrebna provjera';
      case GoogleCalendarImportStatus.imported:
        return 'Već uvezeno';
      case GoogleCalendarImportStatus.ignored:
        return 'Ignorirano';
      case GoogleCalendarImportStatus.duplicate:
        return 'Duplikat';
      case GoogleCalendarImportStatus.cancelled:
        return 'Otkazano';
      case GoogleCalendarImportStatus.updatedAfterImport:
        return 'Promijenjeno nakon uvoza';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google događaji')),
      body: StreamBuilder<List<GoogleCalendarImportEvent>>(
        stream: widget.calendarService.watchImportEvents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data ?? const <GoogleCalendarImportEvent>[];
          if (events.isEmpty) {
            return const Center(child: Text('Nema sinkroniziranih događaja.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return Card(
                child: ListTile(
                  title: Text(
                    event.title.isEmpty ? '(Bez naslova)' : event.title,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event.startDate.day.toString().padLeft(2, '0')}.${event.startDate.month.toString().padLeft(2, '0')}.${event.startDate.year} - ${event.endDate.day.toString().padLeft(2, '0')}.${event.endDate.month.toString().padLeft(2, '0')}.${event.endDate.year}',
                      ),
                      Text(_statusLabel(event.importStatus)),
                      if (event.parseWarnings.isNotEmpty)
                        Text(
                          event.parseWarnings.join(', '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.orange[700]),
                        ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openReview(event),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
