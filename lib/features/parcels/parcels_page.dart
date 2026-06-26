import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../reservations/models/reservation.dart';
import '../reservations/services/reservation_service.dart';
import 'models/pitch.dart';
import 'services/pitch_service.dart';
import 'widgets/pitch_form_dialog.dart';

enum _PitchSortOption { numberAsc, numberDesc, statusThenNumber }

extension on _PitchSortOption {
  String get label {
    switch (this) {
      case _PitchSortOption.numberAsc:
        return 'Broj: od manjeg';
      case _PitchSortOption.numberDesc:
        return 'Broj: od većeg';
      case _PitchSortOption.statusThenNumber:
        return 'Status pa broj';
    }
  }
}

class ParcelsPage extends StatefulWidget {
  const ParcelsPage({super.key, this.service, this.reservationService});

  final PitchService? service;
  final ReservationService? reservationService;

  @override
  State<ParcelsPage> createState() => _ParcelsPageState();
}

class _ParcelsPageState extends State<ParcelsPage> {
  late final PitchService _service;
  late final ReservationService _reservationService;
  late final TextEditingController _searchController;
  late final Stream<List<Pitch>> _pitchesStream;
  late final ValueNotifier<int> _searchTick;

  PitchStatus? _selectedStatus;
  _PitchSortOption _selectedSort = _PitchSortOption.numberAsc;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PitchService();
    _reservationService = widget.reservationService ?? ReservationService();
    _searchController = TextEditingController();
    _pitchesStream = _service.watchPitches();
    _searchTick = ValueNotifier<int>(0);
    _searchController.addListener(() {
      _searchTick.value++;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchTick.dispose();
    super.dispose();
  }

  Future<void> _openEditor({Pitch? pitch}) async {
    await showPitchEditor(
      context,
      pitch: pitch,
      onSave: (draft) async {
        if (draft.id.isEmpty) {
          await _service.createPitch(draft);
          return;
        }

        await _service.updatePitch(draft);
      },
    );
  }

  Future<void> _confirmDelete(Pitch pitch) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Obriši parcelu?'),
          content: Text(
            'Želiš li stvarno obrisati ${pitch.name} (${pitch.number})?',
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
      await _service.deletePitch(pitch.id);
    }
  }

  Future<void> _seedPitches() async {
    await _service.seedDefaultPitches();
  }

  List<Pitch> _filterPitches(List<Pitch> pitches) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = pitches.where((pitch) {
      final matchesQuery =
          query.isEmpty ||
          pitch.name.toLowerCase().contains(query) ||
          pitch.number.toString().contains(query) ||
          pitch.zone.toLowerCase().contains(query);
      final matchesStatus =
          _selectedStatus == null || pitch.status == _selectedStatus;
      return matchesQuery && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      switch (_selectedSort) {
        case _PitchSortOption.numberAsc:
          return a.number.compareTo(b.number);
        case _PitchSortOption.numberDesc:
          return b.number.compareTo(a.number);
        case _PitchSortOption.statusThenNumber:
          final statusCompare = a.status.index.compareTo(b.status.index);
          if (statusCompare != 0) {
            return statusCompare;
          }
          return a.number.compareTo(b.number);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Dodaj parcelu'),
      ),
      body: StreamBuilder<List<Pitch>>(
        stream: _pitchesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline,
              title: 'Greška pri učitavanju',
              message: 'Nije moguće dohvatiti parcele iz Firestorea.',
              actionLabel: 'Pokušaj ponovno',
              onAction: () async {
                setState(() {});
              },
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allPitches = snapshot.data ?? const <Pitch>[];
          final availableCount = allPitches
              .where((pitch) => pitch.status == PitchStatus.available)
              .length;
          final occupiedCount = allPitches
              .where(
                (pitch) =>
                    pitch.status == PitchStatus.occupied &&
                    (pitch.currentReservationId ?? '').trim().isNotEmpty,
              )
              .length;
          final isEmptyCollection = allPitches.isEmpty;

          return ValueListenableBuilder<int>(
            valueListenable: _searchTick,
            builder: (context, tick, child) {
              final filteredPitches = _filterPitches(allPitches);
              final visibleOccupied = filteredPitches
                  .where((pitch) => pitch.status == PitchStatus.occupied)
                  .length;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ParcelsHeroCard(
                    total: allPitches.length,
                    shown: filteredPitches.length,
                    occupiedShown: visibleOccupied,
                    availableTotal: availableCount,
                  ),
                  const SizedBox(height: 12),
                  if (isEmptyCollection) ...[
                    FilledButton.icon(
                      onPressed: _seedPitches,
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Kreiraj početnih 45 parcela'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 900;
                          final searchField = TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Tražilica',
                              prefixIcon: Icon(Icons.search),
                            ),
                          );

                          final filterField =
                              DropdownButtonFormField<PitchStatus?>(
                                isExpanded: true,
                                initialValue: _selectedStatus,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                  prefixIcon: Icon(Icons.tune),
                                ),
                                items: [
                                  const DropdownMenuItem<PitchStatus?>(
                                    value: null,
                                    child: Text('Svi statusi'),
                                  ),
                                  ...PitchStatus.values.map(
                                    (status) => DropdownMenuItem<PitchStatus?>(
                                      value: status,
                                      child: Text(status.displayLabel),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedStatus = value;
                                  });
                                },
                              );

                          final sortField =
                              DropdownButtonFormField<_PitchSortOption>(
                                isExpanded: true,
                                initialValue: _selectedSort,
                                decoration: const InputDecoration(
                                  labelText: 'Sortiranje',
                                  prefixIcon: Icon(Icons.sort),
                                ),
                                items: _PitchSortOption.values
                                    .map(
                                      (option) =>
                                          DropdownMenuItem<_PitchSortOption>(
                                            value: option,
                                            child: Text(option.label),
                                          ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedSort = value;
                                  });
                                },
                              );

                          if (isWide) {
                            return Row(
                              children: [
                                Expanded(child: searchField),
                                const SizedBox(width: 12),
                                SizedBox(width: 220, child: filterField),
                                const SizedBox(width: 12),
                                SizedBox(width: 240, child: sortField),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              searchField,
                              const SizedBox(height: 12),
                              filterField,
                              const SizedBox(height: 12),
                              sortField,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth = constraints.maxWidth >= 1100
                          ? (constraints.maxWidth - 30) / 4
                          : constraints.maxWidth >= 720
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth;

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: cardWidth,
                            child: _SummaryCard(
                              title: 'Ukupno parcela',
                              value: allPitches.length.toString(),
                              icon: Icons.grid_view_rounded,
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _SummaryCard(
                              title: 'Slobodne parcele',
                              value: availableCount.toString(),
                              icon: Icons.check_circle_outline,
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _SummaryCard(
                              title: 'Zauzete parcele',
                              value: occupiedCount.toString(),
                              icon: Icons.block_rounded,
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _SummaryCard(
                              title: 'Aktivni filter',
                              value: _selectedStatus?.displayLabel ?? 'Svi',
                              icon: Icons.filter_alt_outlined,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (filteredPitches.isEmpty)
                    _StateMessage(
                      icon: Icons.inbox_outlined,
                      title: isEmptyCollection
                          ? 'Nema parcela'
                          : 'Nema rezultata',
                      message: isEmptyCollection
                          ? 'Kolekcija pitches je prazna. Možeš kreirati početnih 45 parcela.'
                          : 'Pokušaj promijeniti filter ili tražilicu.',
                      actionLabel: isEmptyCollection
                          ? 'Kreiraj početnih 45 parcela'
                          : null,
                      onAction: isEmptyCollection ? _seedPitches : null,
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        int crossAxisCount;
                        if (width >= 1400) {
                          crossAxisCount = 4;
                        } else if (width >= 1050) {
                          crossAxisCount = 3;
                        } else if (width >= 700) {
                          crossAxisCount = 2;
                        } else {
                          crossAxisCount = 1;
                        }

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredPitches.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 11,
                                mainAxisSpacing: 11,
                                childAspectRatio: crossAxisCount >= 4
                                    ? 1.62
                                    : (crossAxisCount == 3
                                          ? 1.5
                                          : (crossAxisCount == 2 ? 1.34 : 2.0)),
                              ),
                          itemBuilder: (context, index) {
                            final pitch = filteredPitches[index];
                            return _PitchCard(
                              pitch: pitch,
                              reservationService: _reservationService,
                              onEdit: () => _openEditor(pitch: pitch),
                              onDelete: () => _confirmDelete(pitch),
                            );
                          },
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ParcelsHeroCard extends StatelessWidget {
  const _ParcelsHeroCard({
    required this.total,
    required this.shown,
    required this.occupiedShown,
    required this.availableTotal,
  });

  final int total;
  final int shown;
  final int occupiedShown;
  final int availableTotal;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF134F44), Color(0xFF1F7A6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parcele - operativni pregled',
            style: textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$shown prikazano od $total • $occupiedShown zauzetih u prikazu • $availableTotal slobodnih ukupno',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              child: Icon(icon, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PitchCard extends StatelessWidget {
  const _PitchCard({
    required this.pitch,
    required this.reservationService,
    required this.onEdit,
    required this.onDelete,
  });

  final Pitch pitch;
  final ReservationService reservationService;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String? _resolveActorUid() {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim();
      if ((uid ?? '').isNotEmpty) {
        return uid;
      }
    } catch (_) {
      // Fallbacks below keep quick checkout usable in tests and offline flows.
    }
    return null;
  }

  Future<void> _quickCheckOut(
    BuildContext context,
    Reservation reservation,
  ) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Brza odjava gosta'),
          content: Text(
            'Odjaviti gosta ${reservation.primaryGuestName} i osloboditi parcelu?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Odjavi'),
            ),
          ],
        );
      },
    );

    if (shouldProceed != true) {
      return;
    }

    try {
      final actorUid = _resolveActorUid();
      await reservationService.checkOutReservation(
        reservationId: reservation.id,
        checkedOutByUid: (actorUid ?? '').isNotEmpty
            ? actorUid!
            : ((reservation.checkedInByUid ?? '').trim().isNotEmpty
                  ? reservation.checkedInByUid!.trim()
                  : 'quick-checkout'),
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gost je odjavljen, parcela je oslobođena.'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška: $error')));
    }
  }

  String _getDaysUntilCheckOut(DateTime checkOutDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkOut = DateTime(
      checkOutDate.year,
      checkOutDate.month,
      checkOutDate.day,
    );
    final difference = checkOut.difference(today).inDays;

    if (difference < 0) {
      return 'Trebala bi se osloboditi';
    } else if (difference == 0) {
      return 'Oslobađa se danas';
    } else if (difference == 1) {
      return 'Oslobađa se sutra';
    } else {
      return 'Oslobađa se za $difference dana';
    }
  }

  int _daysUntilCheckOut(DateTime checkOutDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkOut = DateTime(
      checkOutDate.year,
      checkOutDate.month,
      checkOutDate.day,
    );
    return checkOut.difference(today).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = pitch.status.color;
    final textTheme = Theme.of(context).textTheme;
    final isMobileCard = MediaQuery.sizeOf(context).width < 700;
    final titleSize = isMobileCard ? 18.0 : 16.0;
    final detailSize = isMobileCard ? 15.0 : 13.0;
    final compactIconSize = isMobileCard ? 17.0 : 15.0;
    final guestName = pitch.status == PitchStatus.occupied
        ? (pitch.currentPrimaryGuestName?.trim().isNotEmpty == true
              ? pitch.currentPrimaryGuestName!
              : 'Glavni gost nije poznat')
        : 'Parcela je trenutno ${pitch.status.displayLabel.toLowerCase()}';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              key: Key('pitch-header-row-${pitch.id}'),
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          pitch.name,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: titleSize,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 7),
                      _StatusChip(
                        key: Key('pitch-status-chip-${pitch.id}'),
                        label: pitch.status.displayLabel,
                        color: statusColor,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: Key('pitch-menu-${pitch.id}'),
                  tooltip: 'Akcije',
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Uredi parcelu')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Obriši parcelu'),
                    ),
                  ],
                  padding: const EdgeInsets.all(4),
                  iconSize: 18,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              'Broj ${pitch.number} • Zona ${pitch.zone}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: detailSize,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Text(
              guestName,
              style: textTheme.bodySmall?.copyWith(fontSize: detailSize),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            if (pitch.status == PitchStatus.occupied &&
                (pitch.currentReservationId?.trim().isNotEmpty == true))
              StreamBuilder<Reservation?>(
                stream: reservationService.watchReservationById(
                  pitch.currentReservationId!,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data != null) {
                    final reservation = snapshot.data!;
                    final isOpenStay = reservation.departureDateUnknown;
                    final daysLeft = isOpenStay
                        ? 999
                        : _daysUntilCheckOut(reservation.checkOutDate);
                    final isUrgentDeparture = !isOpenStay && daysLeft <= 0;
                    final daysText = isOpenStay
                        ? 'Otvoren boravak'
                        : _getDaysUntilCheckOut(reservation.checkOutDate);

                    final dueAmount = _dueAmount(
                      totalPrice: reservation.totalPrice,
                      pricePerNight: reservation.pricePerNight,
                      amountPaid: reservation.amountPaid,
                      paymentStatus: reservation.paymentStatus,
                      checkInDate: reservation.checkInDate,
                      departureDateUnknown: reservation.departureDateUnknown,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 7,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              daysText,
                              style: textTheme.bodySmall?.copyWith(
                                color: isUrgentDeparture
                                    ? Colors.red.shade700
                                    : Colors.orange.shade700,
                                fontSize: detailSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (dueAmount > 0.01)
                              Text(
                                'Dug: ${dueAmount.toStringAsFixed(2)} EUR',
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade700,
                                  fontSize: detailSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else
                              Text(
                                'Plaćeno',
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.green.shade700,
                                  fontSize: detailSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.groups_2_outlined,
                                  size: compactIconSize,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${pitch.maxGuests}',
                                  style: textTheme.bodySmall?.copyWith(
                                    fontSize: detailSize,
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              pitch.hasElectricity
                                  ? Icons.electric_bolt_rounded
                                  : Icons.electric_bolt_outlined,
                              size: compactIconSize,
                              color: pitch.hasElectricity
                                  ? Colors.amber.shade700
                                  : colorScheme.onSurfaceVariant,
                            ),
                            Icon(
                              pitch.hasWater
                                  ? Icons.water_drop_rounded
                                  : Icons.water_drop_outlined,
                              size: compactIconSize,
                              color: pitch.hasWater
                                  ? Colors.lightBlue
                                  : colorScheme.onSurfaceVariant,
                            ),
                            if (reservation.status ==
                                ReservationStatus.checkedIn)
                              FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () =>
                                    _quickCheckOut(context, reservation),
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  size: 14,
                                ),
                                label: Text(
                                  'Brza odjava',
                                  style: TextStyle(
                                    fontSize: isMobileCard ? 13 : 12,
                                  ),
                                ),
                              ),
                            if (isUrgentDeparture)
                              Text(
                                'Hitno za odjavu',
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade700,
                                  fontSize: isMobileCard ? 13 : 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Otvoren boravak',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: detailSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.groups_2_outlined, size: compactIconSize),
                          const SizedBox(width: 3),
                          Text(
                            '${pitch.maxGuests}',
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: detailSize,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            if (!(pitch.status == PitchStatus.occupied &&
                (pitch.currentReservationId?.trim().isNotEmpty == true)))
              Wrap(
                spacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.groups_2_outlined, size: compactIconSize),
                      const SizedBox(width: 3),
                      Text(
                        '${pitch.maxGuests}',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: detailSize,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    pitch.hasElectricity
                        ? Icons.electric_bolt_rounded
                        : Icons.electric_bolt_outlined,
                    size: compactIconSize,
                    color: pitch.hasElectricity
                        ? Colors.amber.shade700
                        : colorScheme.onSurfaceVariant,
                  ),
                  Icon(
                    pitch.hasWater
                        ? Icons.water_drop_rounded
                        : Icons.water_drop_outlined,
                    size: compactIconSize,
                    color: pitch.hasWater
                        ? Colors.lightBlue
                        : colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  double _dueAmount({
    required double totalPrice,
    required double pricePerNight,
    required double amountPaid,
    required PaymentStatus paymentStatus,
    required DateTime checkInDate,
    required bool departureDateUnknown,
  }) {
    if (paymentStatus == PaymentStatus.refunded) {
      return 0;
    }

    var baseAmount = totalPrice;
    if (departureDateUnknown && pricePerNight > 0) {
      final today = DateTime.now();
      final stayStart = DateTime(
        checkInDate.year,
        checkInDate.month,
        checkInDate.day,
      );
      final currentDay = DateTime(today.year, today.month, today.day);
      final elapsedNights = currentDay.difference(stayStart).inDays;
      final billedNights = elapsedNights < 1 ? 1 : elapsedNights;
      baseAmount = pricePerNight * billedNights;
    }

    final due = baseAmount - amountPaid;
    return due <= 0.01 ? 0 : due;
  }
}

class _ReservationQuickActions extends StatefulWidget {
  const _ReservationQuickActions({
    required this.reservation,
    required this.reservationService,
  });

  final Reservation reservation;
  final ReservationService reservationService;

  @override
  State<_ReservationQuickActions> createState() =>
      _ReservationQuickActionsState();
}

class _ReservationQuickActionsState extends State<_ReservationQuickActions> {
  bool _isSaving = false;

  Future<void> _applyStatus(ReservationStatus targetStatus) async {
    final isCheckIn = targetStatus == ReservationStatus.checkedIn;
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(isCheckIn ? 'Brza prijava gosta' : 'Brza odjava gosta'),
          content: Text(
            isCheckIn
                ? 'Želiš li odmah prijaviti gosta na ovoj parceli?'
                : 'Želiš li odmah odjaviti gosta i osloboditi parcelu?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(isCheckIn ? 'Prijavi' : 'Odjavi'),
            ),
          ],
        );
      },
    );

    if (shouldProceed != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.reservationService.updateReservation(
        widget.reservation.copyWith(
          status: targetStatus,
          currentGuests: targetStatus == ReservationStatus.checkedIn
              ? widget.reservation.currentGuests
              : 0,
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            targetStatus == ReservationStatus.checkedIn
                ? 'Gost je prijavljen.'
                : 'Gost je odjavljen, parcela je oslobođena.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.reservation.status;
    final canCheckIn =
        status == ReservationStatus.confirmed ||
        status == ReservationStatus.inquiry ||
        status == ReservationStatus.checkedOut;
    final canCheckOut = status == ReservationStatus.checkedIn;

    if (!canCheckIn && !canCheckOut) {
      return const SizedBox.shrink();
    }

    if (canCheckOut) {
      return FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onPressed: _isSaving
            ? null
            : () => _applyStatus(ReservationStatus.checkedOut),
        icon: _isSaving
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout_rounded, size: 16),
        label: const Text('Brza odjava'),
      );
    }

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onPressed: _isSaving
          ? null
          : () => _applyStatus(ReservationStatus.checkedIn),
      icon: _isSaving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login_rounded, size: 16),
      label: const Text('Brza prijava'),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          height: 1.1,
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 42),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await onAction!.call();
                    },
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
