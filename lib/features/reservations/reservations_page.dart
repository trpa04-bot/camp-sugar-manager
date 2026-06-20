import 'package:flutter/material.dart';

import '../parcels/models/pitch.dart';
import '../parcels/services/pitch_service.dart';
import 'models/reservation.dart';
import 'services/reservation_service.dart';
import 'widgets/reservation_details_sheet.dart';
import 'widgets/reservation_form_dialog.dart';

class ReservationsPage extends StatefulWidget {
  const ReservationsPage({super.key});

  @override
  State<ReservationsPage> createState() => _ReservationsPageState();
}

class _ReservationsPageState extends State<ReservationsPage> {
  final ReservationService _reservationService = ReservationService();
  final PitchService _pitchService = PitchService();

  String _query = '';
  ReservationStatus? _statusFilter;
  ReservationSource? _sourceFilter;
  DateTimeRange? _dateRange;

  Future<void> _openReservationEditor(
    List<Pitch> pitches, {
    Reservation? reservation,
  }) async {
    await showReservationEditor(
      context,
      reservation: reservation,
      pitches: pitches,
      onSave: (draft) async {
        if (draft.id.isEmpty) {
          await _reservationService.createReservation(draft);
          return;
        }
        await _reservationService.updateReservation(draft);
      },
    );
  }

  Future<void> _deleteReservation(Reservation reservation) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Obriši rezervaciju?'),
          content: Text(
            'Želiš li obrisati rezervaciju za ${reservation.primaryGuestName}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Obriši'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _reservationService.deleteReservation(reservation.id);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange =
        _dateRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day + 7),
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: initialRange,
    );

    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  List<Reservation> _applyFilters(List<Reservation> reservations) {
    final query = _query.trim().toLowerCase();
    return reservations.where((reservation) {
      final matchesQuery =
          query.isEmpty ||
          reservation.primaryGuestName.toLowerCase().contains(query) ||
          reservation.bookingReference.toLowerCase().contains(query) ||
          reservation.pitchName.toLowerCase().contains(query) ||
          reservation.primaryGuestPhone.toLowerCase().contains(query) ||
          reservation.primaryGuestEmail.toLowerCase().contains(query);

      final matchesStatus =
          _statusFilter == null || reservation.status == _statusFilter;
      final matchesSource =
          _sourceFilter == null || reservation.source == _sourceFilter;

      final matchesDate =
          _dateRange == null ||
          (!reservation.checkInDate.isBefore(_dateRange!.start) &&
              !reservation.checkInDate.isAfter(_dateRange!.end));

      return matchesQuery && matchesStatus && matchesSource && matchesDate;
    }).toList();
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Pitch>>(
      stream: _pitchService.watchPitches(),
      builder: (context, pitchesSnapshot) {
        final pitches = pitchesSnapshot.data ?? const <Pitch>[];

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: pitches.isEmpty
                ? null
                : () => _openReservationEditor(pitches),
            icon: const Icon(Icons.add),
            label: const Text('Nova rezervacija'),
          ),
          body: StreamBuilder<List<Reservation>>(
            stream: _reservationService.watchReservations(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _StateCard(
                  icon: Icons.error_outline,
                  title: 'Greška pri učitavanju',
                  message: '${snapshot.error}',
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final reservations = snapshot.data ?? const <Reservation>[];
              final filtered = _applyFilters(reservations);

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Rezervacije',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (pitchesSnapshot.hasError)
                    _StateCard(
                      icon: Icons.warning_amber_rounded,
                      title: 'Greška pri učitavanju parcela',
                      message:
                          'Nije moguće učitati parcele za novu rezervaciju. ${pitchesSnapshot.error}',
                    )
                  else if (pitches.isEmpty)
                    const _StateCard(
                      icon: Icons.grid_view_rounded,
                      title: 'Nema parcela',
                      message:
                          'Prvo dodaj parcele pa ćeš moći unijeti rezervacije.',
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Pretraga',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 210,
                        child: DropdownButtonFormField<ReservationStatus?>(
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            prefixIcon: Icon(Icons.flag_outlined),
                          ),
                          items: [
                            const DropdownMenuItem<ReservationStatus?>(
                              value: null,
                              child: Text('Svi statusi'),
                            ),
                            ...ReservationStatus.values.map(
                              (status) => DropdownMenuItem<ReservationStatus?>(
                                value: status,
                                child: Text(status.displayLabel),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _statusFilter = value;
                            });
                          },
                        ),
                      ),
                      SizedBox(
                        width: 210,
                        child: DropdownButtonFormField<ReservationSource?>(
                          initialValue: _sourceFilter,
                          decoration: const InputDecoration(
                            labelText: 'Izvor',
                            prefixIcon: Icon(Icons.hub_outlined),
                          ),
                          items: [
                            const DropdownMenuItem<ReservationSource?>(
                              value: null,
                              child: Text('Svi izvori'),
                            ),
                            ...ReservationSource.values.map(
                              (source) => DropdownMenuItem<ReservationSource?>(
                                value: source,
                                child: Text(source.displayLabel),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _sourceFilter = value;
                            });
                          },
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.date_range_outlined),
                        label: Text(
                          _dateRange == null
                              ? 'Filter po datumu'
                              : '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}',
                        ),
                      ),
                      if (_dateRange != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _dateRange = null;
                            });
                          },
                          child: const Text('Ukloni datum filter'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (reservations.isEmpty)
                    const _StateCard(
                      icon: Icons.inbox_outlined,
                      title: 'Nema rezervacija',
                      message:
                          'Klikni Nova rezervacija za unos prve rezervacije.',
                    )
                  else if (filtered.isEmpty)
                    const _StateCard(
                      icon: Icons.filter_alt_off_outlined,
                      title: 'Nema rezultata',
                      message: 'Promijeni pretragu ili filtere.',
                    )
                  else
                    ...filtered.map(
                      (reservation) => _ReservationCard(
                        reservation: reservation,
                        onOpen: () => showReservationDetails(
                          context,
                          reservation: reservation,
                          service: _reservationService,
                        ),
                        onEdit: () => _openReservationEditor(
                          pitches,
                          reservation: reservation,
                        ),
                        onDelete: () => _deleteReservation(reservation),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Reservation reservation;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onOpen,
        title: Text(
          reservation.primaryGuestName,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            [
              reservation.pitchName,
              '${_formatDate(reservation.checkInDate)} - ${_formatDate(reservation.checkOutDate)}',
              reservation.source.displayLabel,
              reservation.status.displayLabel,
              reservation.bookingReference.isEmpty
                  ? null
                  : 'Ref: ${reservation.bookingReference}',
            ].whereType<String>().join(' • '),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Uredi',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Obriši',
            ),
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
