import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/reservation_pitch_assignment_sheet.dart';
import 'package:camp_sugar_manager/features/google_calendar/services/google_calendar_title_parser.dart';

class ReservationImportReviewSheet extends StatefulWidget {
  final ReservationImportResult result;
  final Function(ReservationImportResult result, List<String>? pitchIds) onSave;
  final FirebaseFirestore firestore;
  final String? fallbackGuestTitle;

  ReservationImportReviewSheet({
    required this.result,
    required this.onSave,
    FirebaseFirestore? firestore,
    this.fallbackGuestTitle,
    super.key,
  }) : firestore = firestore ?? FirebaseFirestore.instance;

  @override
  State<ReservationImportReviewSheet> createState() =>
      _ReservationImportReviewSheetState();
}

class _ReservationImportReviewSheetState
    extends State<ReservationImportReviewSheet> {
  late ReservationImportResult _result;

  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _contactCtrl;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    // If backend already extracted names, use them; otherwise derive from full name.
    final storedFirst = _result.primaryGuestFirstName;
    final storedLast = _result.primaryGuestLastName;
    final needsFallback =
        (storedFirst == null || storedFirst.isEmpty) &&
        (storedLast == null || storedLast.isEmpty);
    final fallbackName = needsFallback
        ? _firstNonEmpty(<String?>[
            _result.primaryGuestFullName,
            _result.primaryGuestName,
            widget.fallbackGuestTitle,
          ])
        : null;
    final parts = needsFallback && (fallbackName?.isNotEmpty ?? false)
        ? GoogleCalendarTitleParser.extractNameParts(fallbackName)
        : null;

    // Keep internal result aligned with prefilled inputs so validation works.
    if (needsFallback && parts != null) {
      final derivedFullName = <String>[
        parts.firstName ?? '',
        parts.lastName ?? '',
      ].where((p) => p.isNotEmpty).join(' ').trim();
      _result = _result.copyWith(
        primaryGuestFirstName: parts.firstName,
        primaryGuestLastName: parts.lastName,
        primaryGuestFullName: derivedFullName.isEmpty ? null : derivedFullName,
      );
    }

    _firstNameCtrl = TextEditingController(
      text: _result.primaryGuestFirstName ?? '',
    );
    _lastNameCtrl = TextEditingController(
      text: _result.primaryGuestLastName ?? '',
    );
    _contactCtrl = TextEditingController(
      text: _result.phone ?? _result.email ?? '',
    );
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  void _editField(String fieldName, dynamic value) {
    setState(() {
      switch (fieldName) {
        case 'firstName':
          _result = _result.copyWith(primaryGuestFirstName: value);
          break;
        case 'lastName':
          _result = _result.copyWith(primaryGuestLastName: value);
          break;
        case 'checkInDate':
          _result = _result.copyWith(checkInDate: value);
          break;
        case 'checkOutDate':
          _result = _result.copyWith(checkOutDate: value);
          break;
        case 'adults':
          _result = _result.copyWith(adults: value);
          break;
        case 'children':
          _result = _result.copyWith(children: value);
          break;
        case 'source':
          _result = _result.copyWith(source: value);
          break;
        case 'phone':
          _result = _result.copyWith(phone: value);
          break;
        case 'email':
          _result = _result.copyWith(email: value);
          break;
        case 'totalPrice':
          _result = _result.copyWith(totalPrice: value);
          break;
        case 'notes':
          _result = _result.copyWith(notes: value);
          break;
      }
    });
  }

  Future<void> _selectDate(String fieldName) async {
    final current = fieldName == 'checkInDate'
        ? _result.checkInDate
        : _result.checkOutDate;

    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (selected != null) {
      _editField(fieldName, selected);
    }
  }

  void _selectSource() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: ReservationSource.values.length,
        itemBuilder: (context, index) {
          final source = ReservationSource.values[index];
          return ListTile(
            title: Text(source.displayLabel),
            onTap: () {
              _editField('source', source);
              Navigator.of(context).pop();
            },
          );
        },
      ),
    );
  }

  Future<void> _proceedToAssignment() async {
    if (_result.primaryGuestName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unesite naziv gosta')));
      return;
    }

    if (_result.checkInDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Odaberite datum dolaska')));
      return;
    }

    if (_result.checkOutDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Odaberite datum odlaska')));
      return;
    }

    if (!_result.checkOutDate!.isAfter(_result.checkInDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datum odlaska mora biti nakon datuma dolaska'),
        ),
      );
      return;
    }

    if (_result.totalGuestCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Broj gostiju mora biti barem 1')),
      );
      return;
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReservationPitchAssignmentSheet(
          result: _result,
          onSave: widget.onSave,
          firestore: widget.firestore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pregledaj podatke'), centerTitle: true),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Confidence indicator
              if (_result.needsReview)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Potrebna provjera'),
                            if (_result.warnings.isNotEmpty)
                              Text(
                                _result.warnings.join(', '),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.orange[700]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              // Guest info section
              _buildSection('Gost', [
                _buildEditableField(
                  label: 'Ime',
                  controller: _firstNameCtrl,
                  onChanged: (value) => _editField('firstName', value),
                ),
                _buildEditableField(
                  label: 'Prezime',
                  controller: _lastNameCtrl,
                  onChanged: (value) => _editField('lastName', value),
                ),
                _buildEditableField(
                  label: 'Kontakt',
                  controller: _contactCtrl,
                  onChanged: (value) => _editField('phone', value),
                ),
              ]),
              const SizedBox(height: 16),
              // Dates section
              _buildSection('Datumi', [
                _buildDateField(
                  label: 'Dolazak',
                  date: _result.checkInDate,
                  onTap: () => _selectDate('checkInDate'),
                ),
                _buildDateField(
                  label: 'Odlazak',
                  date: _result.checkOutDate,
                  onTap: () => _selectDate('checkOutDate'),
                ),
              ]),
              const SizedBox(height: 16),
              // Guest count section
              _buildSection('Broj gostiju', [
                _buildCountField(
                  label: 'Odrasli',
                  value: _result.adults?.toString() ?? '',
                  onChanged: (value) =>
                      _editField('adults', int.tryParse(value)),
                ),
                _buildCountField(
                  label: 'Djeca',
                  value: _result.children?.toString() ?? '',
                  onChanged: (value) =>
                      _editField('children', int.tryParse(value)),
                ),
              ]),
              const SizedBox(height: 16),
              // Source section
              _buildSection('Izvor', [
                _buildSelectableField(
                  label: 'Izvor rezervacije',
                  value: _result.source?.displayLabel ?? 'Nije odabrano',
                  onTap: _selectSource,
                ),
              ]),
              const SizedBox(height: 16),
              // Price section
              if (_result.totalPrice != null) ...[
                _buildSection('Financije', [
                  _buildReadonlyField(
                    label: 'Cijena',
                    value:
                        '${_result.totalPrice?.toStringAsFixed(2) ?? 'N/A'} ${_result.currency ?? 'EUR'}',
                  ),
                ]),
                const SizedBox(height: 16),
              ],
              // Actions
              FilledButton(
                onPressed: _proceedToAssignment,
                child: const Text('Nastavi na dodjelu parcele'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Odustani'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        controller: controller,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Text(
            date != null
                ? '${date.day}.${date.month}.${date.year}'
                : 'Nije odabrano',
          ),
        ),
      ),
    );
  }

  Widget _buildCountField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.number,
        controller: TextEditingController(text: value),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSelectableField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(value), const Icon(Icons.arrow_drop_down)],
          ),
        ),
      ),
    );
  }

  Widget _buildReadonlyField({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          enabled: false,
        ),
        child: Text(value),
      ),
    );
  }
}
