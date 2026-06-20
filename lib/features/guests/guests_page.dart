import 'package:flutter/material.dart';

import '../reservations/models/reservation_guest.dart';
import '../reservations/services/reservation_service.dart';

class GuestsPage extends StatefulWidget {
  GuestsPage({super.key, ReservationService? reservationService})
    : reservationService = reservationService ?? ReservationService();

  final ReservationService reservationService;

  @override
  State<GuestsPage> createState() => _GuestsPageState();
}

class _GuestsPageState extends State<GuestsPage> {
  final TextEditingController _searchController = TextEditingController();

  String _query = '';
  String? _pitchFilter;
  String? _nationalityFilter;
  bool _currentlyInCampOnly = false;
  bool _arrivalsToday = false;
  bool _departuresToday = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GuestDirectoryEntry> _applyFilters(List<GuestDirectoryEntry> all) {
    final query = _query.trim().toLowerCase();
    final now = DateTime.now();

    return all
        .where((entry) {
          final guest = entry.guest;
          final reservation = entry.reservation;
          final fullName = '${guest.firstName} ${guest.lastName}'
              .trim()
              .toLowerCase();

          if (query.isNotEmpty && !fullName.contains(query)) {
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

          final today = DateTime(now.year, now.month, now.day);
          if (_arrivalsToday && guest.checkInDate != null) {
            final checkIn = DateTime(
              guest.checkInDate!.year,
              guest.checkInDate!.month,
              guest.checkInDate!.day,
            );
            if (checkIn != today) {
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
            if (checkOut != today) {
              return false;
            }
          } else if (_departuresToday && guest.checkOutDate == null) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
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

  @override
  Widget build(BuildContext context) {
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
            allEntries
                .map((item) => item.reservation.pitchName)
                .where((item) => item.trim().isNotEmpty)
                .toSet()
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

        final filtered = _applyFilters(allEntries);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Gosti',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Pretraga po imenu i prezimenu',
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
                    decoration: const InputDecoration(labelText: 'Parcela'),
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
                FilterChip(
                  label: const Text('Trenutno u kampu'),
                  selected: _currentlyInCampOnly,
                  onSelected: (value) {
                    setState(() {
                      _currentlyInCampOnly = value;
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
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const _InfoCard(
                title: 'Nema rezultata',
                subtitle: 'Promijeni filtere ili pretragu.',
                icon: Icons.filter_alt_off_outlined,
              )
            else
              ...filtered.map((entry) {
                final guest = entry.guest;
                final reservation = entry.reservation;
                final stayStatus = guest.stayStatus(
                  reservationStatus: reservation.status.name,
                );

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text('${guest.firstName} ${guest.lastName}'.trim()),
                    subtitle: Text(
                      [
                        if (guest.nationalityDisplayName.isNotEmpty)
                          guest.nationalityDisplayName
                        else if (guest.nationalityCode.isNotEmpty)
                          guest.nationalityCode
                        else
                          guest.nationality,
                        reservation.pitchName,
                        'Dolazak: ${_formatDate(guest.checkInDate)}',
                        'Odlazak: ${_formatDate(guest.checkOutDate)}',
                        'Status: ${_stayStatusLabel(stayStatus)}',
                        'Dokument: ${guest.displayDocumentNumber}',
                        'Verifikacija: ${guest.verificationStatus.name}',
                      ].where((item) => item.trim().isNotEmpty).join(' • '),
                    ),
                  ),
                );
              }),
          ],
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
