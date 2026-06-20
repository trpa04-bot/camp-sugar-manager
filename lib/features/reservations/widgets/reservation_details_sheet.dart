import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../models/reservation_guest.dart';
import '../services/reservation_service.dart';
import 'reservation_document_scan_sheet.dart';
import 'reservation_guest_form_dialog.dart';

Future<void> showReservationDetails(
  BuildContext context, {
  required Reservation reservation,
  required ReservationService service,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: ReservationDetailsSheet(
          reservation: reservation,
          service: service,
        ),
      );
    },
  );
}

class ReservationDetailsSheet extends StatefulWidget {
  const ReservationDetailsSheet({
    super.key,
    required this.reservation,
    required this.service,
  });

  final Reservation reservation;
  final ReservationService service;

  @override
  State<ReservationDetailsSheet> createState() =>
      _ReservationDetailsSheetState();
}

class _ReservationDetailsSheetState extends State<ReservationDetailsSheet> {
  bool _isActionBusy = false;

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  Future<void> _handleCheckIn() async {
    final reservation = widget.reservation;
    if (_isActionBusy) {
      return;
    }

    if (reservation.status == ReservationStatus.inquiry) {
      final confirmInquiry = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Potvrda prijave dolaska'),
            content: const Text(
              'Rezervacija je još uvijek označena kao upit. Želite li je potvrditi i prijaviti dolazak?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Odustani'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Potvrdi'),
              ),
            ],
          );
        },
      );
      if (confirmInquiry != true) {
        return;
      }
    }

    setState(() {
      _isActionBusy = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await widget.service.checkInReservation(
        reservationId: reservation.id,
        checkedInByUid: uid,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gost je prijavljen, a parcela je označena kao zauzeta.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isActionBusy = false;
        });
      }
    }
  }

  Future<void> _handleCheckOut() async {
    if (_isActionBusy) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Odjavi goste?'),
          content: const Text('Želite li odjaviti goste i osloboditi parcelu?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Odjavi goste'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() {
      _isActionBusy = true;
    });
    try {
      await widget.service.checkOutReservation(
        reservationId: widget.reservation.id,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gosti su odjavljeni, a parcela je ponovno slobodna.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _isActionBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reservation = widget.reservation;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          reservation.primaryGuestName,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          reservation.bookingReference.isEmpty
              ? 'Bez reference'
              : 'Ref: ${reservation.bookingReference}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (reservation.status == ReservationStatus.confirmed ||
                reservation.status == ReservationStatus.inquiry)
              FilledButton.icon(
                onPressed: _isActionBusy ? null : _handleCheckIn,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Prijavi dolazak'),
              ),
            if (reservation.status == ReservationStatus.checkedIn)
              FilledButton.tonalIcon(
                onPressed: _isActionBusy ? null : _handleCheckOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Odjavi goste'),
              ),
            OutlinedButton.icon(
              onPressed: _isActionBusy
                  ? null
                  : () async {
                      await showReservationDocumentScanFlow(
                        context,
                        reservation: reservation,
                        reservationService: widget.service,
                      );
                    },
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Skeniraj dokument'),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Uvezi Booking rezervaciju'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Pregled rezervacije',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLine(label: 'Izvor', value: reservation.source.displayLabel),
              _InfoLine(
                label: 'Status',
                value: reservation.status.displayLabel,
              ),
              _InfoLine(label: 'Parcela', value: reservation.pitchName),
              _InfoLine(
                label: 'Datumi',
                value:
                    '${_formatDate(reservation.checkInDate)} - ${_formatDate(reservation.checkOutDate)}',
              ),
              _InfoLine(
                label: 'Gosti',
                value:
                    '${reservation.adults} odraslih, ${reservation.children} djece',
              ),
              _InfoLine(
                label: 'Kontakt',
                value:
                    '${reservation.primaryGuestPhone} / ${reservation.primaryGuestEmail}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Financije',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoLine(
                label: 'Ukupna cijena',
                value: '${reservation.totalPrice.toStringAsFixed(2)} EUR',
              ),
              _InfoLine(
                label: 'Akontacija',
                value: '${reservation.depositPaid.toStringAsFixed(2)} EUR',
              ),
              _InfoLine(
                label: 'Uplaćeno',
                value: '${reservation.amountPaid.toStringAsFixed(2)} EUR',
              ),
              _InfoLine(
                label: 'Status plaćanja',
                value: reservation.paymentStatus.displayLabel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Napomena',
          child: Text(
            reservation.notes.isEmpty ? 'Bez napomene.' : reservation.notes,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Gosti',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () {
                showReservationGuestEditor(
                  context,
                  onSave: (guest) =>
                      widget.service.createGuest(reservation.id, guest),
                );
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Dodaj gosta'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<ReservationGuest>>(
          stream: widget.service.watchGuests(reservation.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Greška pri učitavanju gostiju: ${snapshot.error}',
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final guests = snapshot.data ?? const <ReservationGuest>[];
            if (guests.isEmpty) {
              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Još nema gostiju u ovoj rezervaciji.',
                    style: textTheme.bodyMedium,
                  ),
                ),
              );
            }

            return Column(
              children: guests.map((guest) {
                return Card(
                  elevation: 0,
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        guest.firstName.isEmpty
                            ? '?'
                            : guest.firstName[0].toUpperCase(),
                      ),
                    ),
                    title: Text('${guest.firstName} ${guest.lastName}'.trim()),
                    subtitle: Text(
                      [
                        if (guest.nationality.isNotEmpty) guest.nationality,
                        if (guest.documentType.isNotEmpty)
                          '${guest.documentType}: ${maskDocumentNumber(guest.documentNumber)}',
                        if (guest.gender.isNotEmpty) guest.gender,
                        if (guest.isPrimaryGuest) 'Glavni gost',
                      ].join(' • '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () {
                            showReservationGuestEditor(
                              context,
                              guest: guest,
                              onSave: (updated) => widget.service.updateGuest(
                                reservation.id,
                                updated,
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Uredi',
                        ),
                        IconButton(
                          onPressed: () => widget.service.deleteGuest(
                            reservation.id,
                            guest.id,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Obriši',
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
