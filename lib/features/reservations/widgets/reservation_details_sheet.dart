import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/date_utils.dart' as app_date;
import '../../parcels/models/pitch.dart';
import '../../parcels/services/pitch_service.dart';
import '../models/document_image.dart';
import '../models/document_verification_ui.dart';
import '../models/reservation.dart';
import '../models/reservation_guest.dart';
import '../services/document_scan_service.dart';
import '../services/reservation_service.dart';
import 'mrz_scanner_sheet.dart';
import 'reservation_document_scan_sheet.dart';
import 'reservation_guest_form_dialog.dart';

Future<void> showReservationDetails(
  BuildContext context, {
  required Reservation reservation,
  required ReservationService service,
  PitchService? pitchService,
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
          pitchService: pitchService,
        ),
      );
    },
  );
}

class ReservationDetailsSheet extends StatefulWidget {
  ReservationDetailsSheet({
    super.key,
    required this.reservation,
    required this.service,
    PitchService? pitchService,
  }) : pitchService = pitchService ?? PitchService();

  final PitchService pitchService;

  final Reservation reservation;
  final ReservationService service;

  @override
  State<ReservationDetailsSheet> createState() =>
      _ReservationDetailsSheetState();
}

class _ReservationDetailsSheetState extends State<ReservationDetailsSheet> {
  bool _isActionBusy = false;
  late String _vehicleImageUrl;
  late int _vehicleImageSizeBytes;
  late final DocumentScanService _scanService = DocumentScanService();

  @override
  void initState() {
    super.initState();
    widget.service.reconcileGuestState(widget.reservation.id);
    widget.service.reconcileReservationPaymentFromPayments(
      reservationId: widget.reservation.id,
      fallbackGuestName: widget.reservation.primaryGuestName,
    );
    _vehicleImageUrl = widget.reservation.vehicleImageUrl;
    _vehicleImageSizeBytes = widget.reservation.vehicleImageSizeBytes;
  }

  String _formatDate(DateTime value) {
    return app_date.formatDate(value);
  }

  bool get _canChangePitch {
    final status = widget.reservation.status;
    return status != ReservationStatus.checkedOut &&
        status != ReservationStatus.cancelled;
  }

  List<String> _updatedPitchIds(Reservation reservation, String nextPitchId) {
    final currentIds = reservation.pitchIds.isNotEmpty
        ? List<String>.from(reservation.pitchIds)
        : <String>[
            if (reservation.pitchId.trim().isNotEmpty) reservation.pitchId,
          ];
    if (currentIds.isEmpty) {
      return <String>[nextPitchId];
    }

    final currentIndex = currentIds.indexOf(reservation.pitchId);
    if (currentIndex >= 0) {
      currentIds[currentIndex] = nextPitchId;
    } else {
      currentIds[0] = nextPitchId;
    }

    return currentIds.toSet().toList(growable: false);
  }

  Future<Pitch?> _pickPitch() async {
    final pitches = await widget.pitchService.watchPitches().first;
    if (!mounted || pitches.isEmpty) {
      return null;
    }

    return showModalBottomSheet<Pitch>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Odaberi parcelu')),
            ...pitches.map((pitch) {
              final isCurrent = pitch.id == widget.reservation.pitchId;
              return ListTile(
                title: Text(pitch.name),
                subtitle: Text(
                  isCurrent
                      ? 'Trenutno odabrana'
                      : 'Status: ${pitch.status.displayLabel}',
                ),
                trailing: isCurrent ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(pitch),
              );
            }),
          ],
        );
      },
    );
  }

  Future<void> _handleChangePitch() async {
    if (_isActionBusy) {
      return;
    }

    final selectedPitch = await _pickPitch();
    if (!mounted || selectedPitch == null) {
      return;
    }
    if (selectedPitch.id == widget.reservation.pitchId) {
      return;
    }

    setState(() {
      _isActionBusy = true;
    });

    try {
      final updatedPitchIds = _updatedPitchIds(
        widget.reservation,
        selectedPitch.id,
      );

      await widget.service.updateReservation(
        widget.reservation.copyWith(
          pitchId: selectedPitch.id,
          pitchName: selectedPitch.name,
          pitchIds: updatedPitchIds,
          pitchCount: updatedPitchIds.length,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rezervacija je prebačena na parcelu ${selectedPitch.name}.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is ReservationConflictException
          ? error.message
          : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isActionBusy = false;
        });
      }
    }
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
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      await widget.service.checkOutReservation(
        reservationId: widget.reservation.id,
        checkedOutByUid: uid,
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

  Future<XFile?> _pickVehicleImage() async {
    return showModalBottomSheet<XFile>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Slikaj vozilo'),
                onTap: () async {
                  final file = await _scanService.pickCameraImage();
                  if (!sheetContext.mounted) {
                    return;
                  }
                  Navigator.of(sheetContext).pop(file);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Odaberi iz galerije'),
                onTap: () async {
                  final file = await _scanService.pickGalleryImage();
                  if (!sheetContext.mounted) {
                    return;
                  }
                  Navigator.of(sheetContext).pop(file);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleVehicleImageUpload() async {
    if (_isActionBusy) {
      return;
    }

    final selected = await _pickVehicleImage();
    if (selected == null) {
      return;
    }

    if (!_scanService.isSupportedImageFile(selected)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Podržani su samo JPG, JPEG i PNG.')),
      );
      return;
    }

    setState(() {
      _isActionBusy = true;
    });

    try {
      final upload = await _scanService.uploadVehicleImage(
        reservationId: widget.reservation.id,
        file: selected,
        maxBytes: 100 * 1024,
      );

      await widget.service.updateReservation(
        widget.reservation.copyWith(
          vehicleImageUrl: upload.downloadUrl,
          vehicleImagePath: upload.storagePath,
          vehicleImageSizeBytes: upload.bytes.lengthInBytes,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _vehicleImageUrl = upload.downloadUrl;
        _vehicleImageSizeBytes = upload.bytes.lengthInBytes;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Slika vozila je spremljena (${(_vehicleImageSizeBytes / 1024).toStringAsFixed(1)} KB).',
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
            if (_canChangePitch)
              OutlinedButton.icon(
                onPressed: _isActionBusy ? null : _handleChangePitch,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Promijeni parcelu'),
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
              onPressed: _isActionBusy
                  ? null
                  : () async {
                      if (kIsWeb) {
                        await showReservationDocumentScanFlow(
                          context,
                          reservation: reservation,
                          reservationService: widget.service,
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'U pregledniku se MRZ čita iz fotografije dokumenta. '
                              'Učitajte ili slikajte donji dio dokumenta — podaci '
                              'se prepoznaju automatski.',
                            ),
                            duration: Duration(seconds: 5),
                          ),
                        );
                        return;
                      }
                      await showMrzScannerSheet(
                        context,
                        reservation: reservation,
                        onSaveConfirmed: (guest, checksPassed) async {
                          final acceptanceStatus = checksPassed
                              ? DocumentAcceptanceStatus.accepted
                              : DocumentAcceptanceStatus.acceptedWithReview;
                          await widget.service.saveVerifiedGuest(
                            reservation: reservation,
                            guest: guest,
                            images: const <DocumentImage>[],
                            acceptanceStatus: acceptanceStatus,
                            manualReviewCompleted: true,
                            retentionPolicy:
                                DocumentRetentionPolicy.retainManually,
                            allowDuplicate: false,
                          );
                        },
                      );
                    },
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('MRZ skeniranje'),
            ),
            OutlinedButton.icon(
              onPressed: _isActionBusy ? null : _handleVehicleImageUpload,
              icon: const Icon(Icons.directions_car_outlined),
              label: Text(
                _vehicleImageUrl.trim().isEmpty
                    ? 'Dodaj sliku vozila'
                    : 'Zamijeni sliku vozila',
              ),
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
                value: reservation.departureDateUnknown
                    ? '${_formatDate(reservation.checkInDate)} - odlazak nije poznat'
                    : '${_formatDate(reservation.checkInDate)} - ${_formatDate(reservation.checkOutDate)}',
              ),
              _InfoLine(
                label: 'Gosti',
                value:
                    '${reservation.adults} odraslih, ${reservation.children} djece',
              ),
              _InfoLine(
                label: 'Ukupno planirano',
                value: '${reservation.guestCount}',
              ),
              _InfoLine(
                label: 'Kontakt',
                value:
                    '${reservation.primaryGuestPhone} / ${reservation.primaryGuestEmail}',
              ),
              _InfoLine(
                label: 'Opis vozila',
                value: reservation.vehicleDescription.trim().isEmpty
                    ? 'Nije upisano'
                    : reservation.vehicleDescription,
              ),
              if (_vehicleImageUrl.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Slika vozila',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) {
                              return Dialog(
                                child: InteractiveViewer(
                                  child: Image.network(_vehicleImageUrl),
                                ),
                              );
                            },
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _vehicleImageUrl,
                            width: 140,
                            height: 95,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      if (_vehicleImageSizeBytes > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Veličina: ${(_vehicleImageSizeBytes / 1024).toStringAsFixed(1)} KB',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
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
                value: reservation.effectivePaymentStatus.displayLabel,
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
                          onPressed: () async {
                            await showReservationDocumentScanFlow(
                              context,
                              reservation: reservation,
                              reservationService: widget.service,
                              initialGuest: guest,
                            );
                          },
                          icon: const Icon(Icons.document_scanner_outlined),
                          tooltip: 'Skeniraj dokument',
                        ),
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
