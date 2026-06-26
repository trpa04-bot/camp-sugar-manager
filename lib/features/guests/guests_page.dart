import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart' as app_date;
import '../parcels/models/pitch.dart';
import '../parcels/services/pitch_service.dart';
import '../reservations/models/reservation.dart';
import '../reservations/models/reservation_guest.dart';
import '../reservations/services/reservation_service.dart';
import '../reservations/widgets/reservation_details_sheet.dart';
import '../reservations/widgets/reservation_guest_form_dialog.dart';

class GuestsPage extends StatefulWidget {
  GuestsPage({
    super.key,
    ReservationService? reservationService,
    PitchService? pitchService,
    FirebaseFirestore? firestore,
  }) : reservationService =
           reservationService ?? ReservationService(firestore: firestore),
       pitchService =
           pitchService ??
           PitchService(firestore: firestore ?? reservationService?.firestore);

  final ReservationService reservationService;
  final PitchService pitchService;

  @override
  State<GuestsPage> createState() => _GuestsPageState();
}

class _GuestsPageState extends State<GuestsPage> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  String? _pitchFilter;
  String? _nationalityFilter;
  DateTimeRange? _dateRange;
  bool _currentlyInCampOnly = false;
  bool _departedOnly = false;
  bool _arrivalsToday = false;
  bool _departuresToday = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _effectiveStayEndDate(Reservation reservation, {DateTime? now}) {
    if (reservation.departureDateUnknown &&
        reservation.status == ReservationStatus.checkedIn) {
      final reference = now ?? DateTime.now();
      return DateTime(reference.year, reference.month, reference.day);
    }
    return reservation.checkOutDate;
  }

  bool _matchesDateRange(DateTime start, DateTime end) {
    final range = _dateRange;
    if (range == null) {
      return true;
    }

    final from = DateTime(range.start.year, range.start.month, range.start.day);
    final to = DateTime(
      range.end.year,
      range.end.month,
      range.end.day,
    ).add(const Duration(days: 1));
    final periodStart = DateTime(start.year, start.month, start.day);
    final periodEnd = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));

    return periodStart.isBefore(to) && periodEnd.isAfter(from);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialStart = _dateRange?.start ?? now;
    final initialEnd = _dateRange?.end ?? now.add(const Duration(days: 7));
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      _dateRange = picked;
    });
  }

  Future<void> _editGuest(GuestDirectoryEntry entry) async {
    try {
      await showReservationGuestEditor(
        context,
        guest: entry.guest,
        onSave: (guest) {
          return widget.reservationService.updateGuest(
            entry.reservation.id,
            guest,
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri uređivanju: $error')));
    }
  }

  Future<void> _deleteGuest(GuestDirectoryEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final guestName = '${entry.guest.firstName} ${entry.guest.lastName}'
            .trim();
        return AlertDialog(
          title: const Text('Obriši gosta?'),
          content: Text(
            'Želiš li obrisati gosta ${guestName.isEmpty ? '-' : guestName}?',
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

    if (shouldDelete != true) {
      return;
    }

    try {
      await widget.reservationService.deleteGuest(
        entry.reservation.id,
        entry.guest.id,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Gost je obrisan.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri brisanju: $error')));
    }
  }

  List<GuestDirectoryEntry> _applyFilters(List<GuestDirectoryEntry> all) {
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return all
        .where((entry) {
          final guest = entry.guest;
          final reservation = entry.reservation;
          final fullName = '${guest.firstName} ${guest.lastName}'
              .trim()
              .toLowerCase();

          final searchableText = [
            fullName,
            guest.documentNumber.toLowerCase(),
            guest.maskedDocumentNumber.toLowerCase(),
            reservation.primaryGuestName.toLowerCase(),
            reservation.pitchName.toLowerCase(),
          ].join(' ');

          if (query.isNotEmpty && !searchableText.contains(query)) {
            return false;
          }
          if (_pitchFilter != null &&
              _pitchFilter!.isNotEmpty &&
              reservation.pitchName != _pitchFilter) {
            return false;
          }
          if (_nationalityFilter != null && _nationalityFilter!.isNotEmpty) {
            if (guest.nationalityCode != _nationalityFilter &&
                guest.nationality != _nationalityFilter) {
              return false;
            }
          }

          final stayStatus = guest.stayStatus(
            reservationStatus: reservation.status.name,
            now: now,
          );
          if (_currentlyInCampOnly &&
              stayStatus != GuestStayStatus.currentlyStaying) {
            return false;
          }
          if (_departedOnly && stayStatus != GuestStayStatus.departed) {
            return false;
          }

          final start = guest.checkInDate ?? reservation.checkInDate;
          final end = guest.checkOutDate ?? reservation.checkOutDate;
          if (!_matchesDateRange(start, end)) {
            return false;
          }

          if (_arrivalsToday && guest.checkInDate != null) {
            final checkIn = DateTime(
              guest.checkInDate!.year,
              guest.checkInDate!.month,
              guest.checkInDate!.day,
            );
            if (!_sameDate(checkIn, today)) {
              return false;
            }
          } else if (_arrivalsToday && guest.checkInDate == null) {
            return false;
          }

          if (_departuresToday && guest.checkOutDate != null) {
            final checkOut = DateTime(
              guest.checkOutDate!.year,
              guest.checkOutDate!.month,
              guest.checkOutDate!.day,
            );
            if (!_sameDate(checkOut, today)) {
              return false;
            }
          } else if (_departuresToday && guest.checkOutDate == null) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  List<Reservation> _applyStayFilters(
    List<Reservation> all, {
    required Map<String, Set<String>> nationalitiesByReservation,
  }) {
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return all
        .where((reservation) {
          // Boravci tab prikazuje samo goste koji su trenutno prijavljeni.
          if (reservation.status != ReservationStatus.checkedIn) {
            return false;
          }

          final searchableText = [
            reservation.primaryGuestName,
            reservation.pitchName,
            reservation.bookingReference,
          ].join(' ').toLowerCase();
          if (query.isNotEmpty && !searchableText.contains(query)) {
            return false;
          }

          if (_pitchFilter != null &&
              _pitchFilter!.isNotEmpty &&
              reservation.pitchName != _pitchFilter) {
            return false;
          }

          if (_nationalityFilter != null && _nationalityFilter!.isNotEmpty) {
            final set =
                nationalitiesByReservation[reservation.id] ?? const <String>{};
            if (!set.contains(_nationalityFilter!)) {
              return false;
            }
          }

          if (!_matchesDateRange(
            reservation.checkInDate,
            _effectiveStayEndDate(reservation, now: now),
          )) {
            return false;
          }

          if (_currentlyInCampOnly &&
              reservation.status != ReservationStatus.checkedIn) {
            return false;
          }

          if (_arrivalsToday && !_sameDate(reservation.checkInDate, today)) {
            return false;
          }

          if (_departuresToday && reservation.departureDateUnknown) {
            return false;
          }

          if (_departuresToday &&
              !_sameDate(_effectiveStayEndDate(reservation, now: now), today)) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  String _formatDate(DateTime? value) {
    return app_date.formatDateOrDash(value);
  }

  String _formatDateRange(DateTimeRange? range) {
    if (range == null) {
      return 'Svi datumi';
    }
    return app_date.formatDateRange(range.start, range.end);
  }

  int _calculateNights(Reservation reservation) {
    final now = DateTime.now();
    final checkIn = DateTime(
      reservation.checkInDate.year,
      reservation.checkInDate.month,
      reservation.checkInDate.day,
    );
    final effectiveEnd = _effectiveStayEndDate(reservation, now: now);
    final checkOut = DateTime(
      effectiveEnd.year,
      effectiveEnd.month,
      effectiveEnd.day,
    );
    final nights = checkOut.difference(checkIn).inDays;
    return nights < 0 ? 0 : nights;
  }

  String _formatStayRange(Reservation reservation) {
    final checkIn = _formatDate(reservation.checkInDate);
    if (reservation.departureDateUnknown &&
        reservation.status == ReservationStatus.checkedIn) {
      return '$checkIn - otvoreni boravak';
    }
    return '$checkIn - ${_formatDate(reservation.checkOutDate)}';
  }

  int _resolveTotalGuests(Reservation reservation, int guestsFromArchive) {
    if (reservation.registeredGuestCount > 0) {
      return reservation.registeredGuestCount;
    }
    if (guestsFromArchive > 0) {
      return guestsFromArchive;
    }
    return reservation.guestCount;
  }

  int _countGuestsForReservations(
    List<Reservation> reservations,
    List<GuestDirectoryEntry> allEntries,
  ) {
    return reservations.fold<int>(0, (total, reservation) {
      final guestsFromArchive = allEntries
          .where((entry) => entry.reservation.id == reservation.id)
          .length;
      return total + _resolveTotalGuests(reservation, guestsFromArchive);
    });
  }

  String _stayStatusLabel(GuestStayStatus status) {
    switch (status) {
      case GuestStayStatus.upcoming:
        return 'Dolazak očekivan';
      case GuestStayStatus.awaitingCheckIn:
        return 'Čeka prijavu';
      case GuestStayStatus.currentlyStaying:
        return 'Trenutno u kampu';
      case GuestStayStatus.departed:
        return 'Otišao';
      case GuestStayStatus.cancelled:
        return 'Otkazano';
    }
  }

  String _getPitchName(String pitchId, List<Pitch> pitches) {
    if (pitchId.isEmpty) {
      return 'Parcela';
    }
    try {
      return pitches.firstWhere((p) => p.id == pitchId).name;
    } catch (_) {
      return 'Parcela $pitchId';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Pitch>>(
      stream: widget.pitchService.watchPitches(),
      builder: (context, pitchesSnapshot) {
        final pitchesFromService = pitchesSnapshot.data ?? const <Pitch>[];

        return StreamBuilder<List<GuestDirectoryEntry>>(
          stream: widget.reservationService.watchGuestDirectory(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: _InfoCard(
                  title: 'Greška',
                  subtitle: 'Nije moguće učitati goste. ${snapshot.error}',
                  icon: Icons.error_outline,
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final allEntries = snapshot.data ?? const <GuestDirectoryEntry>[];
            final pitches =
                pitchesFromService
                    .map((p) => p.name)
                    .where((item) => item.trim().isNotEmpty)
                    .toList()
                  ..sort();
            final nationalities =
                allEntries
                    .map((item) {
                      final code = item.guest.nationalityCode.trim();
                      if (code.isNotEmpty) {
                        return code;
                      }
                      return item.guest.nationality.trim();
                    })
                    .where((item) => item.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort();

            final nationalitiesByReservation = <String, Set<String>>{};
            for (final entry in allEntries) {
              final reservationId = entry.reservation.id;
              final code = entry.guest.nationalityCode.trim();
              final fallback = entry.guest.nationality.trim();
              final value = code.isNotEmpty ? code : fallback;
              if (value.isEmpty) {
                continue;
              }
              nationalitiesByReservation.putIfAbsent(
                reservationId,
                () => <String>{},
              );
              nationalitiesByReservation[reservationId]!.add(value);
            }

            final filtered = _applyFilters(allEntries);
            final now = DateTime.now();
            final departedGuestsCount = allEntries
                .where(
                  (entry) =>
                      entry.guest.stayStatus(
                        reservationStatus: entry.reservation.status.name,
                        now: now,
                      ) ==
                      GuestStayStatus.departed,
                )
                .length;

            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Arhiva gostiju',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Pretraga (ime, dokument, parcela...)',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _query = value;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String?>(
                                isExpanded: true,
                                initialValue: _pitchFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Parcela',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sve parcele'),
                                  ),
                                  ...pitches.map(
                                    (pitch) => DropdownMenuItem<String?>(
                                      value: pitch,
                                      child: Text(pitch),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _pitchFilter = value;
                                  });
                                },
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String?>(
                                isExpanded: true,
                                initialValue: _nationalityFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Nacionalnost',
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sve nacionalnosti'),
                                  ),
                                  ...nationalities.map(
                                    (value) => DropdownMenuItem<String?>(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _nationalityFilter = value;
                                  });
                                },
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickDateRange,
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(_formatDateRange(_dateRange)),
                            ),
                            if (_dateRange != null)
                              TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _dateRange = null;
                                  });
                                },
                                icon: const Icon(Icons.clear),
                                label: const Text('Očisti datume'),
                              ),
                            StreamBuilder<List<Reservation>>(
                              stream: widget.reservationService
                                  .watchCheckedInReservations(),
                              builder: (context, checkedInSnapshot) {
                                final checkedInReservations =
                                    checkedInSnapshot.data ??
                                    const <Reservation>[];
                                final currentlyInCampGuestsCount =
                                    _countGuestsForReservations(
                                      checkedInReservations,
                                      allEntries,
                                    );

                                return FilterChip(
                                  label: Text(
                                    'Trenutno u kampu ($currentlyInCampGuestsCount)',
                                  ),
                                  selected: _currentlyInCampOnly,
                                  onSelected: (value) {
                                    setState(() {
                                      _currentlyInCampOnly = value;
                                      if (value) {
                                        _departedOnly = false;
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                            FilterChip(
                              label: Text(
                                'Odjavljeni gosti ($departedGuestsCount)',
                              ),
                              selected: _departedOnly,
                              onSelected: (value) {
                                setState(() {
                                  _departedOnly = value;
                                  if (value) {
                                    _currentlyInCampOnly = false;
                                  }
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('Dolasci danas'),
                              selected: _arrivalsToday,
                              onSelected: (value) {
                                setState(() {
                                  _arrivalsToday = value;
                                });
                              },
                            ),
                            FilterChip(
                              label: const Text('Odlasci danas'),
                              selected: _departuresToday,
                              onSelected: (value) {
                                setState(() {
                                  _departuresToday = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const TabBar(
                          tabs: [
                            Tab(text: 'Boravci u kampu'),
                            Tab(text: 'Gosti'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.6,
                          child: TabBarView(
                            children: [
                              StreamBuilder<List<Reservation>>(
                                stream: widget.reservationService
                                    .watchReservations(),
                                builder: (context, reservationsSnapshot) {
                                  if (reservationsSnapshot.hasError) {
                                    return _InfoCard(
                                      title: 'Greška',
                                      subtitle:
                                          'Nije moguće učitati boravke. ${reservationsSnapshot.error}',
                                      icon: Icons.error_outline,
                                    );
                                  }

                                  if (reservationsSnapshot.connectionState ==
                                          ConnectionState.waiting &&
                                      !reservationsSnapshot.hasData) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final reservations =
                                      reservationsSnapshot.data ??
                                      const <Reservation>[];
                                  final filteredReservations =
                                      _applyStayFilters(
                                        reservations,
                                        nationalitiesByReservation:
                                            nationalitiesByReservation,
                                      );

                                  if (filteredReservations.isEmpty) {
                                    return const _InfoCard(
                                      title: 'Nema trenutnih boravaka',
                                      subtitle:
                                          'Odjavljeni gosti ostaju u arhivi na tabu Gosti.',
                                      icon: Icons.hotel_outlined,
                                    );
                                  }

                                  return ListView.builder(
                                    itemCount: filteredReservations.length,
                                    itemBuilder: (context, index) {
                                      final reservation =
                                          filteredReservations[index];
                                      final guestsFromArchive = allEntries
                                          .where(
                                            (entry) =>
                                                entry.reservation.id ==
                                                reservation.id,
                                          )
                                          .length;
                                      final totalGuests = _resolveTotalGuests(
                                        reservation,
                                        guestsFromArchive,
                                      );
                                      final isOpenStay =
                                          reservation.departureDateUnknown &&
                                          reservation.status ==
                                              ReservationStatus.checkedIn;

                                      return Card(
                                        elevation: 0,
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: ListTile(
                                          onTap: () async {
                                            await showReservationDetails(
                                              context,
                                              reservation: reservation,
                                              service:
                                                  widget.reservationService,
                                            );
                                          },
                                          title: Text(
                                            reservation.primaryGuestName.isEmpty
                                                ? '(bez naziva)'
                                                : reservation.primaryGuestName,
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                [
                                                  'Parcela: ${_getPitchName(reservation.pitchId, pitchesFromService)}',
                                                  'Boravak: ${_formatStayRange(reservation)}',
                                                  'Noćenja: ${_calculateNights(reservation)}',
                                                  'Ukupno gostiju: $totalGuests',
                                                ].join(' • '),
                                              ),
                                              if (isOpenStay) ...[
                                                const SizedBox(height: 6),
                                                Chip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  label: const Text(
                                                    'Otvoreni boravak',
                                                  ),
                                                  side: BorderSide(
                                                    color: Colors.orange
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                  backgroundColor: Colors.orange
                                                      .withValues(alpha: 0.15),
                                                ),
                                              ],
                                            ],
                                          ),
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              if (filtered.isEmpty)
                                const _InfoCard(
                                  title: 'Nema rezultata',
                                  subtitle: 'Promijeni filtere ili pretragu.',
                                  icon: Icons.filter_alt_off_outlined,
                                )
                              else
                                ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final entry = filtered[index];
                                    final guest = entry.guest;
                                    final reservation = entry.reservation;
                                    final stayStatus = guest.stayStatus(
                                      reservationStatus:
                                          reservation.status.name,
                                    );

                                    return Card(
                                      elevation: 0,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      child: ListTile(
                                        title: Text(
                                          '${guest.firstName} ${guest.lastName}'
                                              .trim(),
                                        ),
                                        subtitle: Text(
                                          [
                                            if (guest
                                                .nationalityDisplayName
                                                .isNotEmpty)
                                              guest.nationalityDisplayName
                                            else if (guest
                                                .nationalityCode
                                                .isNotEmpty)
                                              guest.nationalityCode
                                            else
                                              guest.nationality,
                                            _getPitchName(
                                              reservation.pitchId,
                                              pitchesFromService,
                                            ),
                                            'Dolazak: ${_formatDate(guest.checkInDate)}',
                                            'Odlazak: ${_formatDate(guest.checkOutDate)}',
                                            'Status: ${_stayStatusLabel(stayStatus)}',
                                            'Dokument: ${guest.displayDocumentNumber}',
                                            'Verifikacija: ${guest.verificationStatus.name}',
                                          ].where((item) => item.trim().isNotEmpty).join(' • '),
                                        ),
                                        trailing: PopupMenuButton<String>(
                                          onSelected: (value) async {
                                            if (value == 'edit') {
                                              await _editGuest(entry);
                                              return;
                                            }
                                            if (value == 'delete') {
                                              await _deleteGuest(entry);
                                            }
                                          },
                                          itemBuilder: (context) {
                                            return const [
                                              PopupMenuItem<String>(
                                                value: 'edit',
                                                child: Text('Uredi'),
                                              ),
                                              PopupMenuItem<String>(
                                                value: 'delete',
                                                child: Text('Obriši'),
                                              ),
                                            ];
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        margin: const EdgeInsets.all(20),
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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
