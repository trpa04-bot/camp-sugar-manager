import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../google_calendar/google_calendar_sync_events_page.dart';
import '../parcels/models/pitch.dart';
import '../parcels/services/pitch_service.dart';
import 'models/reservation.dart';
import 'services/reservation_service.dart';
import 'widgets/reservation_details_sheet.dart';
import 'widgets/reservation_duplicate_dialog.dart';
import 'widgets/reservation_form_dialog.dart';
import 'widgets/reservation_import_sheet.dart';

enum _ReservationPreset {
  none,
  arrivalsToday,
  departuresToday,
  openStays,
  overdueCheckouts,
  debts,
}

extension on _ReservationPreset {
  String get label {
    switch (this) {
      case _ReservationPreset.none:
        return 'Svi';
      case _ReservationPreset.arrivalsToday:
        return 'Dolasci danas';
      case _ReservationPreset.departuresToday:
        return 'Odlasci danas';
      case _ReservationPreset.openStays:
        return 'Otvoreni boravak';
      case _ReservationPreset.overdueCheckouts:
        return 'Neodjavljeni odlasci';
      case _ReservationPreset.debts:
        return 'Dugovanja';
    }
  }
}

class ReservationsPage extends StatefulWidget {
  const ReservationsPage({super.key, this.initialDebtOnly = false});

  final bool initialDebtOnly;

  @override
  State<ReservationsPage> createState() => _ReservationsPageState();
}

class _ReservationsPageState extends State<ReservationsPage>
    with SingleTickerProviderStateMixin {
  final ReservationService _reservationService = ReservationService();
  final PitchService _pitchService = PitchService();
  late final TextEditingController _searchController;
  late final Stream<List<Pitch>> _pitchesStream;
  late final Stream<List<Reservation>> _reservationsStream;

  String _query = '';
  ReservationStatus? _statusFilter;
  ReservationSource? _sourceFilter;
  DateTimeRange? _dateRange;
  late bool _showOnlyDebt;
  _ReservationPreset _activePreset = _ReservationPreset.none;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController = TextEditingController(text: _query);
    _pitchesStream = _pitchService.watchPitches();
    _reservationsStream = _reservationService.watchReservations();
    _triggerPaymentReconciliationSweep();
    _showOnlyDebt = widget.initialDebtOnly;
    if (_showOnlyDebt) {
      _activePreset = _ReservationPreset.debts;
    }
  }

  void _triggerPaymentReconciliationSweep() {
    Future<void>(() async {
      try {
        await _reservationService.reconcilePaymentsForVisibleReservations();
      } catch (_) {
        // Ignore transient reconciliation errors to avoid blocking list render.
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReservationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDebtOnly != oldWidget.initialDebtOnly) {
      _showOnlyDebt = widget.initialDebtOnly;
    }
  }

  bool _hasOpenDebt(Reservation reservation) {
    final effectiveStatus = reservation.effectivePaymentStatus;
    if (effectiveStatus == PaymentStatus.paid ||
        effectiveStatus == PaymentStatus.refunded) {
      return false;
    }

    final dueAmount = _openDebtAmount(reservation);
    return dueAmount > 0.01;
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _matchesPreset(Reservation reservation) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_activePreset) {
      case _ReservationPreset.none:
        return true;
      case _ReservationPreset.arrivalsToday:
        if (reservation.status == ReservationStatus.cancelled) {
          return false;
        }
        return _isSameDate(reservation.checkInDate, today);
      case _ReservationPreset.departuresToday:
        if (reservation.status == ReservationStatus.cancelled ||
            reservation.departureDateUnknown) {
          return false;
        }
        return _isSameDate(reservation.checkOutDate, today);
      case _ReservationPreset.openStays:
        return reservation.status == ReservationStatus.checkedIn &&
            reservation.departureDateUnknown;
      case _ReservationPreset.overdueCheckouts:
        if (reservation.status != ReservationStatus.checkedIn ||
            reservation.departureDateUnknown) {
          return false;
        }
        final checkOut = DateTime(
          reservation.checkOutDate.year,
          reservation.checkOutDate.month,
          reservation.checkOutDate.day,
        );
        return checkOut.isBefore(today);
      case _ReservationPreset.debts:
        return _hasOpenDebt(reservation);
    }
  }

  void _applyPreset(_ReservationPreset preset) {
    setState(() {
      _activePreset = preset;
      _showOnlyDebt = preset == _ReservationPreset.debts;
    });

    final targetTabIndex = _tabIndexForPreset(preset);
    if (_tabController.index != targetTabIndex) {
      _tabController.animateTo(targetTabIndex);
    }
  }

  int _tabIndexForPreset(_ReservationPreset preset) {
    switch (preset) {
      case _ReservationPreset.arrivalsToday:
        return 1;
      case _ReservationPreset.departuresToday:
      case _ReservationPreset.openStays:
      case _ReservationPreset.overdueCheckouts:
      case _ReservationPreset.debts:
        return 0;
      case _ReservationPreset.none:
        return _tabController.index;
    }
  }

  double _openDebtAmount(Reservation reservation) {
    if (reservation.departureDateUnknown && reservation.pricePerNight > 0) {
      final today = DateTime.now();
      final currentDay = DateTime(today.year, today.month, today.day);
      final startDay = DateTime(
        reservation.checkInDate.year,
        reservation.checkInDate.month,
        reservation.checkInDate.day,
      );

      final elapsedNights = currentDay.difference(startDay).inDays;
      final billedNights = elapsedNights < 1 ? 1 : elapsedNights;
      final runningGross = reservation.pricePerNight * billedNights;
      return runningGross - reservation.amountPaid;
    }

    return reservation.totalPrice - reservation.amountPaid;
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  Future<void> _openReservationEditor(
    List<Pitch> pitches, {
    Reservation? reservation,
  }) async {
    Reservation? hydratedReservation = reservation;
    if (reservation != null && reservation.id.isNotEmpty) {
      try {
        await _reservationService.reconcileReservationPaymentFromPayments(
          reservationId: reservation.id,
          fallbackGuestName: reservation.primaryGuestName,
        );
      } catch (_) {
        // Keep editor accessible even if reconciliation transiently fails.
      }
    }

    if (!mounted) {
      return;
    }

    await showReservationEditor(
      context,
      reservation: hydratedReservation,
      pitches: pitches,
      onSave: (draft, action) async {
        if (action == ReservationSubmitAction.checkInNow) {
          await _reservationService.createReservationAndCheckIn(draft);
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Gosti su prijavljeni na parcelu ${draft.pitchName}.',
              ),
            ),
          );
          return;
        }

        if (draft.id.isEmpty) {
          final duplicate = await _reservationService
              .checkDuplicateBeforeCreate(draft);
          if (duplicate.hasDuplicate && duplicate.match != null) {
            if (!mounted) return;
            final decision = await showReservationDuplicateDialog(
              context,
              duplicate.match!,
            );
            if (!mounted) return;
            if (decision == null ||
                decision == DuplicateDialogDecision.cancel) {
              throw ReservationDuplicateException(duplicate);
            }
            if (decision == DuplicateDialogDecision.openExisting) {
              await showReservationDetails(
                context,
                reservation: duplicate.match!,
                service: _reservationService,
              );
              throw ReservationDuplicateException(duplicate);
            }
            // saveAnyway
            await _reservationService.createReservation(
              draft,
              allowDuplicate: true,
            );
            return;
          }
          await _reservationService.createReservation(draft);
          return;
        }
        await _reservationService.updateReservation(draft);
      },
    );
  }

  Future<void> _openImportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ReservationImportSheet(
          onSave: (result, pitchIds) async {
            try {
              final primaryPitchId = pitchIds?.isNotEmpty == true
                  ? pitchIds![0]
                  : '';

              final reservation = Reservation(
                id: '',
                bookingReference: result.sourceReservationId ?? '',
                primaryGuestName: result.primaryGuestName,
                primaryGuestId: '',
                primaryGuestPhone: result.phone ?? '',
                primaryGuestEmail: result.email ?? '',
                pitchId: primaryPitchId,
                pitchName: '',
                checkInDate: result.checkInDate ?? DateTime.now(),
                checkOutDate:
                    result.checkOutDate ??
                    DateTime.now().add(const Duration(days: 1)),
                adults: result.adults ?? 0,
                children: result.children ?? 0,
                pets: 0,
                vehicles: 1,
                accommodationType: result.accommodationType ?? '',
                status: ReservationStatus.confirmed,
                totalPrice: result.totalPrice ?? 0.0,
                depositPaid: 0.0,
                amountPaid: 0.0,
                paymentStatus: PaymentStatus.unpaid,
                notes: result.notes ?? '',
                registeredGuestCount: result.totalGuestCount,
                currentGuests: 0,
                primaryGuestFirstName: result.primaryGuestFirstName ?? '',
                primaryGuestLastName: result.primaryGuestLastName ?? '',
                infants: result.infants ?? 0,
                guestCount: result.totalGuestCount,
                pitchCount: result.pitchCount < 1 ? 1 : result.pitchCount,
                pitchIds: pitchIds ?? const <String>[],
                sourceReservationId: result.sourceReservationId ?? '',
                country: result.country ?? '',
                language: result.language ?? '',
                currency: result.currency ?? 'EUR',
                prepaidAmount: result.prepaidAmount ?? 0.0,
                balanceDue: result.balanceDue ?? 0.0,
                source: result.source ?? ReservationSource.other,
              );

              final duplicate = await _reservationService
                  .checkDuplicateBeforeCreate(reservation);

              var allowDuplicate = false;
              if (duplicate.hasDuplicate && duplicate.match != null) {
                if (!sheetContext.mounted || !mounted) {
                  return;
                }
                final decision = await showReservationDuplicateDialog(
                  sheetContext,
                  duplicate.match!,
                );
                if (!sheetContext.mounted || !mounted) {
                  return;
                }
                if (decision == null ||
                    decision == DuplicateDialogDecision.cancel) {
                  return;
                }
                if (decision == DuplicateDialogDecision.openExisting) {
                  Navigator.of(sheetContext).pop();
                  await showReservationDetails(
                    context,
                    reservation: duplicate.match!,
                    service: _reservationService,
                  );
                  return;
                }
                allowDuplicate = true;
              }

              await _reservationService.createReservation(
                reservation,
                allowDuplicate: allowDuplicate,
              );

              if (!sheetContext.mounted || !mounted) {
                return;
              }
              Navigator.of(sheetContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rezervacija je uspješno importana'),
                ),
              );
            } on ReservationConflictException catch (e) {
              if (!sheetContext.mounted || !mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(e.message)));
            } on ReservationDuplicateException catch (_) {
              if (!sheetContext.mounted || !mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Moguća postojeća rezervacija')),
              );
            } catch (e) {
              if (!sheetContext.mounted || !mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Greška pri spremanju: $e')),
              );
            }
          },
        );
      },
    );
  }

  Future<void> _checkOutReservation(Reservation reservation) async {
    final shouldCheckOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Potvrdi odlazak?'),
          content: Text(
            'Želiš li potvrditi odlazak za ${reservation.primaryGuestName}? Parcela će biti ponovno slobodna.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Potvrdi odlazak'),
            ),
          ],
        );
      },
    );

    if (shouldCheckOut == true) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        await _reservationService.checkOutReservation(
          reservationId: reservation.id,
          checkedOutByUid: uid,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${reservation.primaryGuestName} je odjavljen, a parcela je ponovno slobodna.',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Greška pri odjavljivanju: $e')));
      }
    }
  }

  Future<void> _checkInReservation(Reservation reservation) async {
    final shouldCheckIn = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Potvrdi dolazak?'),
          content: Text(
            'Želiš li potvrditi dolazak za ${reservation.primaryGuestName}? Rezervacija će prijeći u trenutne.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Gosti su došli'),
            ),
          ],
        );
      },
    );

    if (shouldCheckIn == true) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
        await _reservationService.checkInReservation(
          reservationId: reservation.id,
          checkedInByUid: uid,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${reservation.primaryGuestName} je prijavljen i rezervacija je premještena u trenutne.',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Greška pri prijavi: $e')));
      }
    }
  }

  Future<void> _cancelReservation(Reservation reservation) async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Otkazati rezervaciju?'),
          content: Text(
            'Želiš li označiti rezervaciju za ${reservation.primaryGuestName} kao otkazanu?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Otkazali su'),
            ),
          ],
        );
      },
    );

    if (shouldCancel == true) {
      try {
        await _reservationService.updateReservation(
          reservation.copyWith(
            status: ReservationStatus.cancelled,
            currentGuests: 0,
          ),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rezervacija za ${reservation.primaryGuestName} je prebačena u otkazane.',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Greška pri otkazivanju: $e')));
      }
    }
  }

  Future<void> _extendStay(Reservation reservation) async {
    if (reservation.departureDateUnknown) {
      return;
    }

    final initialDate = reservation.checkOutDate.add(const Duration(days: 1));
    final result = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: initialDate,
      lastDate: DateTime(2100),
    );

    if (result == null) {
      return;
    }

    final nextCheckOut = DateTime(result.year, result.month, result.day);
    try {
      await _reservationService.updateReservation(
        reservation.copyWith(
          checkOutDate: nextCheckOut,
          departureDateUnknown: false,
        ),
      );
      if (!mounted) return;
      final day = nextCheckOut.day.toString().padLeft(2, '0');
      final month = nextCheckOut.month.toString().padLeft(2, '0');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Boravak za ${reservation.primaryGuestName} je produljen do $day.$month.${nextCheckOut.year}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri produljenju: $e')));
    }
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
      final guestName = reservation.primaryGuestName.trim().isNotEmpty
          ? reservation.primaryGuestName
          : <String>[
              reservation.primaryGuestFirstName.trim(),
              reservation.primaryGuestLastName.trim(),
            ].where((part) => part.isNotEmpty).join(' ');
      final matchesQuery =
          query.isEmpty ||
          guestName.toLowerCase().contains(query) ||
          reservation.bookingReference.toLowerCase().contains(query) ||
          reservation.pitchName.toLowerCase().contains(query) ||
          reservation.pitchId.toLowerCase().contains(query) ||
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

      final matchesDebt = !_showOnlyDebt || _hasOpenDebt(reservation);
      final matchesPreset = _matchesPreset(reservation);

      return matchesQuery &&
          matchesStatus &&
          matchesSource &&
          matchesDate &&
          matchesDebt &&
          matchesPreset;
    }).toList();
  }

  Widget _buildReservationList(
    BuildContext context, {
    required List<Reservation> reservations,
    required List<Pitch> pitches,
    required String emptyTitle,
    required String emptyMessage,
    VoidCallback Function(Reservation reservation)? onCheckIn,
    VoidCallback Function(Reservation reservation)? onCancel,
    VoidCallback Function(Reservation reservation)? onExtendStay,
  }) {
    if (reservations.isEmpty) {
      return _StateCard(
        icon: Icons.inbox_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }

    return Column(
      children: reservations
          .map(
            (reservation) => _ReservationCard(
              reservation: reservation,
              pitches: pitches,
              onOpen: () => showReservationDetails(
                context,
                reservation: reservation,
                service: _reservationService,
              ),
              onEdit: () =>
                  _openReservationEditor(pitches, reservation: reservation),
              onDelete: () => _deleteReservation(reservation),
              onCheckOut: () => _checkOutReservation(reservation),
              onCheckIn: onCheckIn?.call(reservation),
              onCancel: onCancel?.call(reservation),
              onExtendStay: onExtendStay?.call(reservation),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Pitch>>(
      stream: _pitchesStream,
      builder: (context, pitchesSnapshot) {
        final pitches = pitchesSnapshot.data ?? const <Pitch>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Rezervacije'),
            centerTitle: true,
            actions: [
              Tooltip(
                message: 'Google kalendar',
                child: IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GoogleCalendarSyncEventsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_month),
                ),
              ),
              Tooltip(
                message: 'Uvezi rezervaciju',
                child: IconButton(
                  onPressed: _openImportSheet,
                  icon: const Icon(Icons.upload_file),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: pitches.isEmpty
                ? null
                : () => _openReservationEditor(pitches),
            icon: const Icon(Icons.add),
            label: const Text('Nova rezervacija'),
          ),
          body: StreamBuilder<List<Reservation>>(
            stream: _reservationsStream,
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
              final futureReservations = filtered
                  .where(
                    (reservation) =>
                        reservation.status == ReservationStatus.confirmed ||
                        reservation.status == ReservationStatus.inquiry,
                  )
                  .toList(growable: false);
              final activeReservations = filtered
                  .where(
                    (reservation) =>
                        reservation.status == ReservationStatus.checkedIn,
                  )
                  .toList(growable: false);
              final checkedOutReservations = filtered
                  .where(
                    (reservation) =>
                        reservation.status == ReservationStatus.checkedOut,
                  )
                  .toList(growable: false);
              final cancelledReservations = filtered
                  .where(
                    (reservation) =>
                        reservation.status == ReservationStatus.cancelled,
                  )
                  .toList(growable: false);

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
                    controller: _searchController,
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
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
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
                                  (status) =>
                                      DropdownMenuItem<ReservationStatus?>(
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
                                  (source) =>
                                      DropdownMenuItem<ReservationSource?>(
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
                          FilterChip(
                            selected: _showOnlyDebt,
                            onSelected: (selected) {
                              setState(() {
                                _showOnlyDebt = selected;
                                _activePreset = selected
                                    ? _ReservationPreset.debts
                                    : _ReservationPreset.none;
                              });

                              if (selected && _tabController.index != 0) {
                                _tabController.animateTo(0);
                              }
                            },
                            avatar: const Icon(Icons.warning_amber_rounded),
                            label: const Text('Samo dugovanja'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in _ReservationPreset.values)
                        FilterChip(
                          selected: _activePreset == preset,
                          onSelected: (_) => _applyPreset(preset),
                          label: Text(preset.label),
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
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TabBar(
                          controller: _tabController,
                          tabs: [
                            Tab(
                              text: 'Trenutne (${activeReservations.length})',
                            ),
                            Tab(text: 'Buduće (${futureReservations.length})'),
                            Tab(
                              text:
                                  'Odjavljene (${checkedOutReservations.length})',
                            ),
                            Tab(
                              text:
                                  'Otkazane (${cancelledReservations.length})',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              SingleChildScrollView(
                                child: _buildReservationList(
                                  context,
                                  reservations: activeReservations,
                                  pitches: pitches,
                                  emptyTitle: 'Nema trenutnih rezervacija',
                                  emptyMessage:
                                      'Kad potvrdiš dolazak, rezervacija će biti prikazana ovdje.',
                                  onExtendStay: (reservation) =>
                                      () => _extendStay(reservation),
                                ),
                              ),
                              SingleChildScrollView(
                                child: _buildReservationList(
                                  context,
                                  reservations: futureReservations,
                                  pitches: pitches,
                                  emptyTitle: 'Nema budućih rezervacija',
                                  emptyMessage:
                                      'Nove rezervacije su ovdje dok ne potvrdiš dolazak ili otkazivanje.',
                                  onCheckIn: (reservation) =>
                                      () => _checkInReservation(reservation),
                                  onCancel: (reservation) =>
                                      () => _cancelReservation(reservation),
                                ),
                              ),
                              SingleChildScrollView(
                                child: _buildReservationList(
                                  context,
                                  reservations: checkedOutReservations,
                                  pitches: pitches,
                                  emptyTitle: 'Nema odjavljenih rezervacija',
                                  emptyMessage:
                                      'Kad odjaviš gosta, rezervacija će biti prikazana ovdje.',
                                ),
                              ),
                              SingleChildScrollView(
                                child: _buildReservationList(
                                  context,
                                  reservations: cancelledReservations,
                                  pitches: pitches,
                                  emptyTitle: 'Nema otkazanih rezervacija',
                                  emptyMessage:
                                      'Otkazane rezervacije su odvojene radi preglednosti.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
    required this.pitches,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.onCheckOut,
    this.onCheckIn,
    this.onCancel,
    this.onExtendStay,
  });

  final Reservation reservation;
  final List<Pitch> pitches;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onCheckOut;
  final VoidCallback? onCheckIn;
  final VoidCallback? onCancel;
  final VoidCallback? onExtendStay;

  String _getPitchName() {
    if (reservation.pitchId.isEmpty) {
      return 'Parcela';
    }
    try {
      return pitches.firstWhere((p) => p.id == reservation.pitchId).name;
    } catch (_) {
      return 'Parcela ${reservation.pitchId}';
    }
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  bool _isCheckOutOverdue() {
    if (reservation.departureDateUnknown) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkOut = DateTime(
      reservation.checkOutDate.year,
      reservation.checkOutDate.month,
      reservation.checkOutDate.day,
    );
    return checkOut.isBefore(today) &&
        reservation.status == ReservationStatus.checkedIn;
  }

  String _getGuestCountLabel() {
    final total = _resolveTotalGuests();
    if (total <= 0) return '';
    if (total == 1) return '1 gost';
    if (total <= 4) return '$total gosta';
    return '$total gostiju';
  }

  int _resolveTotalGuests() {
    if (reservation.registeredGuestCount > 0) {
      return reservation.registeredGuestCount;
    }
    if (reservation.guestCount > 0) {
      return reservation.guestCount;
    }
    return reservation.adults + reservation.children + reservation.infants;
  }

  double _openDebtAmount() {
    final effectiveStatus = reservation.effectivePaymentStatus;
    if (effectiveStatus == PaymentStatus.paid ||
        effectiveStatus == PaymentStatus.refunded) {
      return 0;
    }

    if (reservation.departureDateUnknown && reservation.pricePerNight > 0) {
      final today = DateTime.now();
      final currentDay = DateTime(today.year, today.month, today.day);
      final startDay = DateTime(
        reservation.checkInDate.year,
        reservation.checkInDate.month,
        reservation.checkInDate.day,
      );

      final elapsedNights = currentDay.difference(startDay).inDays;
      final billedNights = elapsedNights < 1 ? 1 : elapsedNights;
      return (reservation.pricePerNight * billedNights) -
          reservation.amountPaid;
    }

    return reservation.totalPrice - reservation.amountPaid;
  }

  Color _statusColor(ReservationStatus status) {
    switch (status) {
      case ReservationStatus.checkedIn:
        return const Color(0xFF0B8F6A);
      case ReservationStatus.confirmed:
      case ReservationStatus.inquiry:
        return const Color(0xFF1565C0);
      case ReservationStatus.checkedOut:
        return const Color(0xFF546E7A);
      case ReservationStatus.cancelled:
        return const Color(0xFFC62828);
    }
  }

  Color _paymentColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return const Color(0xFF2E7D32);
      case PaymentStatus.partiallyPaid:
        return const Color(0xFFEF6C00);
      case PaymentStatus.unpaid:
        return const Color(0xFFC62828);
      case PaymentStatus.refunded:
        return const Color(0xFF6A1B9A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectivePaymentStatus = reservation.effectivePaymentStatus;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onOpen,
        title: Text(
          '${reservation.primaryGuestName} • ${_getGuestCountLabel()}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  _getPitchName(),
                  reservation.departureDateUnknown
                      ? '${_formatDate(reservation.checkInDate)} - odlazak nije poznat'
                      : '${_formatDate(reservation.checkInDate)} - ${_formatDate(reservation.checkOutDate)}',
                  reservation.source.displayLabel,
                  reservation.bookingReference.isEmpty
                      ? null
                      : 'Ref: ${reservation.bookingReference}',
                ].whereType<String>().join(' • '),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(reservation.status.displayLabel),
                    labelStyle: TextStyle(
                      color: _statusColor(reservation.status),
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: _statusColor(
                        reservation.status,
                      ).withValues(alpha: 0.35),
                    ),
                    backgroundColor: _statusColor(
                      reservation.status,
                    ).withValues(alpha: 0.1),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(effectivePaymentStatus.displayLabel),
                    labelStyle: TextStyle(
                      color: _paymentColor(effectivePaymentStatus),
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: _paymentColor(
                        effectivePaymentStatus,
                      ).withValues(alpha: 0.35),
                    ),
                    backgroundColor: _paymentColor(
                      effectivePaymentStatus,
                    ).withValues(alpha: 0.1),
                  ),
                ],
              ),
              if (reservation.departureDateUnknown) ...[
                const SizedBox(height: 6),
                Chip(
                  label: const Text('Otvoren boravak'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                if (reservation.pricePerNight <= 0) ...[
                  const SizedBox(height: 6),
                  Chip(
                    label: const Text('Nedostaje cijena po noći'),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    backgroundColor: Colors.amber.withValues(alpha: 0.2),
                    side: BorderSide(
                      color: Colors.amber.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ],
              if (reservation.effectivePaymentStatus == PaymentStatus.paid &&
                  _openDebtAmount() > 0.01) ...[
                const SizedBox(height: 6),
                Chip(
                  label: const Text('Status plaćanja i saldo nisu usklađeni'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.red.withValues(alpha: 0.16),
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.45)),
                ),
              ],
              if (_isCheckOutOverdue()) ...[
                const SizedBox(height: 6),
                Chip(
                  label: const Text('Gosti nisu odjavljeni'),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.red.withValues(alpha: 0.2),
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onExtendStay != null)
                      FilledButton.tonalIcon(
                        onPressed: onExtendStay,
                        icon: const Icon(Icons.event_repeat_outlined),
                        label: const Text('Produlji boravak'),
                      ),
                    if (onCheckOut != null)
                      OutlinedButton.icon(
                        onPressed: onCheckOut,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Odjavi goste'),
                      ),
                  ],
                ),
              ],
              if (onCheckIn != null || onCancel != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onCheckIn != null)
                      FilledButton.tonalIcon(
                        onPressed: onCheckIn,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Gosti su došli'),
                      ),
                    if (onCancel != null)
                      OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.event_busy_outlined),
                        label: const Text('Gosti nisu došli'),
                      ),
                  ],
                ),
              ],
            ],
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
