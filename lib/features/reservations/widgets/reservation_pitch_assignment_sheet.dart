import 'package:flutter/material.dart';
import 'package:camp_sugar_manager/features/parcels/models/pitch.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_validation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReservationPitchAssignmentSheet extends StatefulWidget {
  final ReservationImportResult result;
  final Function(ReservationImportResult result, List<String>? pitchIds) onSave;
  final FirebaseFirestore firestore;

  ReservationPitchAssignmentSheet({
    required this.result,
    required this.onSave,
    FirebaseFirestore? firestore,
    super.key,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  @override
  State<ReservationPitchAssignmentSheet> createState() =>
      _ReservationPitchAssignmentSheetState();
}

class _ReservationPitchAssignmentSheetState
    extends State<ReservationPitchAssignmentSheet> {
  late List<String> _selectedPitchIds;
  late DateTime _checkIn;
  late DateTime _checkOut;
  late int _requiredPitchCount;

  @override
  void initState() {
    super.initState();
    _selectedPitchIds = [];
    _checkIn = widget.result.checkInDate!;
    _checkOut = widget.result.checkOutDate!;
    _requiredPitchCount = widget.result.pitchCount < 1
        ? 1
        : widget.result.pitchCount;
  }

  Future<List<Pitch>> _getAvailablePitches() async {
    final pitchesRef = widget.firestore.collection('pitches');
    final snapshot = await pitchesRef.get();

    final pitches = snapshot.docs.map((doc) => Pitch.fromDoc(doc)).toList();

    // Filter out pitches with conflicts
    final availablePitches = <Pitch>[];

    for (final pitch in pitches) {
      final hasConflict = await _checkPitchConflict(pitch.id);
      if (!hasConflict) {
        availablePitches.add(pitch);
      }
    }

    return availablePitches;
  }

  Future<bool> _checkPitchConflict(String pitchId) async {
    final reservationsRef = widget.firestore.collection('reservations');

    final query = reservationsRef
        .where('pitchIds', arrayContains: pitchId)
        .where('status', whereIn: ['confirmed', 'checkedIn']);

    final snapshot = await query.get();

    for (final doc in snapshot.docs) {
      final reservation = Reservation.fromDoc(doc);

      // Check if periods overlap
      if (_datesOverlap(
        _checkIn,
        _checkOut,
        reservation.checkInDate,
        reservation.checkOutDate,
      )) {
        return true;
      }
    }

    return false;
  }

  bool _datesOverlap(
    DateTime start1,
    DateTime end1,
    DateTime start2,
    DateTime end2,
  ) {
    return start1.isBefore(end2) && end1.isAfter(start2);
  }

  void _togglePitch(String pitchId) {
    setState(() {
      if (_selectedPitchIds.contains(pitchId)) {
        _selectedPitchIds.remove(pitchId);
      } else {
        if (_selectedPitchIds.length >= _requiredPitchCount) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Potrebno je odabrati točno $_requiredPitchCount parcele.',
              ),
            ),
          );
          return;
        }
        _selectedPitchIds.add(pitchId);
      }
    });
  }

  Future<void> _save() async {
    final validation = validateImport(
      result: widget.result,
      selectedPitchIds: _selectedPitchIds,
    );
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validation.firstError ?? 'Neispravan unos.')),
      );
      return;
    }

    // Get pitch names
    final pitchesRef = widget.firestore.collection('pitches');
    final pitchNames = <String>[];

    for (final pitchId in _selectedPitchIds) {
      final doc = await pitchesRef.doc(pitchId).get();
      if (doc.exists) {
        final pitch = Pitch.fromDoc(doc);
        pitchNames.add(pitch.name);
      }
    }

    if (!mounted) return;

    widget.onSave(
      widget.result.copyWith(pitchCount: _requiredPitchCount),
      _selectedPitchIds,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final validation = validateImport(
      result: widget.result,
      selectedPitchIds: _selectedPitchIds,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Odaberi parcele'), centerTitle: true),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Pitch>>(
              future: _getAvailablePitches(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Greška: ${snapshot.error}'));
                }

                final pitches = snapshot.data ?? [];

                if (pitches.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        const Text('Nema dostupnih parcela za ovaj period'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pitches.length,
                  itemBuilder: (context, index) {
                    final pitch = pitches[index];
                    final isSelected = _selectedPitchIds.contains(pitch.id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (value) => _togglePitch(pitch.id),
                        title: Text(pitch.name),
                        subtitle: Text(
                          'Zona: ${pitch.zone}, Kapacitet: ${pitch.maxGuests}',
                        ),
                        contentPadding: const EdgeInsets.all(8),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_selectedPitchIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Odabrano: ${_selectedPitchIds.length} / $_requiredPitchCount parcela',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (validation.missingPitchCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      validation.missingPitchCount == 1
                          ? 'Potrebno je odabrati još 1 parcelu.'
                          : 'Potrebno je odabrati još ${validation.missingPitchCount} parcele.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.orange),
                    ),
                  ),
                FilledButton(
                  onPressed: validation.isValid ? _save : null,
                  child: const Text('Spremi rezervaciju'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Odustani'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
