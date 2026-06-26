import 'package:flutter/material.dart';

import '../models/mrz_scan_result.dart';
import '../models/reservation.dart';
import '../models/reservation_guest.dart';

class MrzReviewResult {
  const MrzReviewResult({required this.guest, required this.scanResult});

  final ReservationGuest guest;
  final MrzScanResult scanResult;
}

Future<MrzReviewResult?> showMrzReviewDialog(
  BuildContext context, {
  required Reservation reservation,
  required MrzScanResult scanResult,
  ReservationGuest? initialGuest,
}) async {
  return showDialog<MrzReviewResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _MrzReviewDialog(
            reservation: reservation,
            scanResult: scanResult,
            initialGuest: initialGuest,
          ),
        ),
      );
    },
  );
}

class _MrzReviewDialog extends StatefulWidget {
  const _MrzReviewDialog({
    required this.reservation,
    required this.scanResult,
    required this.initialGuest,
  });

  final Reservation reservation;
  final MrzScanResult scanResult;
  final ReservationGuest? initialGuest;

  @override
  State<_MrzReviewDialog> createState() => _MrzReviewDialogState();
}

class _MrzReviewDialogState extends State<_MrzReviewDialog> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _documentNumberController;
  late final TextEditingController _nationalityController;
  late final TextEditingController _issuingCountryController;
  late final TextEditingController _documentTypeController;
  late final TextEditingController _genderController;
  DateTime? _dateOfBirth;
  DateTime? _dateOfExpiry;
  bool _isPrimaryGuest = true;

  @override
  void initState() {
    super.initState();
    final scan = widget.scanResult;
    final initial = widget.initialGuest;
    _firstNameController = TextEditingController(
      text: initial?.firstName ?? scan.firstName ?? '',
    );
    _lastNameController = TextEditingController(
      text: initial?.lastName ?? scan.lastName ?? '',
    );
    _documentNumberController = TextEditingController(
      text: initial?.documentNumber ?? scan.documentNumber ?? '',
    );
    _nationalityController = TextEditingController(
      text: initial?.nationality.isNotEmpty == true
          ? initial!.nationality
          : (scan.nationalityCode ?? scan.nationality ?? ''),
    );
    _issuingCountryController = TextEditingController(
      text: initial?.issuingCountry ?? scan.issuingCountry ?? '',
    );
    _documentTypeController = TextEditingController(
      text: initial?.documentType ?? scan.documentType ?? '',
    );
    _genderController = TextEditingController(
      text: initial?.gender ?? scan.gender ?? '',
    );
    _dateOfBirth = initial?.dateOfBirth ?? _parseDate(scan.dateOfBirth);
    _dateOfExpiry =
        initial?.documentExpiryDate ?? _parseDate(scan.dateOfExpiry);
    _isPrimaryGuest = initial?.isPrimaryGuest ?? true;
  }

  DateTime? _parseDate(String? value) {
    final text = (value ?? '').trim();
    final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(text);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _documentNumberController.dispose();
    _nationalityController.dispose();
    _issuingCountryController.dispose();
    _documentTypeController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  ReservationGuest _buildGuest() {
    return ReservationGuest(
      id: widget.initialGuest?.id ?? '',
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _dateOfBirth,
      nationality: _nationalityController.text.trim(),
      nationalityCode: _nationalityController.text.trim().toUpperCase(),
      documentType: _documentTypeController.text.trim(),
      documentNumber: _documentNumberController.text.trim(),
      documentExpiryDate: _dateOfExpiry,
      gender: _genderController.text.trim(),
      issuingCountry: _issuingCountryController.text.trim(),
      isPrimaryGuest: _isPrimaryGuest,
      documentImagePath: widget.initialGuest?.documentImagePath ?? '',
      documentImagePaths:
          widget.initialGuest?.documentImagePaths ?? const <String>[],
      ocrStatus: 'completed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scanResult;
    final checks = scan.checks;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    checks.allPassed ? 'MRZ provjera' : 'MRZ ručna provjera',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Odustani'),
                ),
              ],
            ),
            Text('Format: ${scan.format}'),
            Text(
              'Kontrolne znamenke: ${checks.allPassed ? 'OK' : 'nije ispravno'}',
            ),
            if (scan.errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  scan.errors.join(', '),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'Ime'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Prezime'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentNumberController,
              decoration: const InputDecoration(labelText: 'Broj dokumenta'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                        initialDate: _dateOfBirth ?? DateTime(1990, 1, 1),
                      );
                      if (picked != null) setState(() => _dateOfBirth = picked);
                    },
                    child: Text(
                      _dateOfBirth == null
                          ? 'Datum rođenja'
                          : _formatDate(_dateOfBirth!),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2100),
                        initialDate:
                            _dateOfExpiry ??
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _dateOfExpiry = picked);
                      }
                    },
                    child: Text(
                      _dateOfExpiry == null
                          ? 'Istek dokumenta'
                          : _formatDate(_dateOfExpiry!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nationalityController,
              decoration: const InputDecoration(labelText: 'Državljanstvo'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _issuingCountryController,
              decoration: const InputDecoration(labelText: 'Država izdavanja'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentTypeController,
              decoration: const InputDecoration(labelText: 'Vrsta dokumenta'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _genderController,
              decoration: const InputDecoration(labelText: 'Spol'),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Glavni gost'),
              value: _isPrimaryGuest,
              onChanged: (value) => setState(() => _isPrimaryGuest = value),
            ),
            if (!checks.allPassed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Kontrolne znamenke nisu ispravne. Provjeri podatke ručno prije spremanja.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pop(MrzReviewResult(guest: _buildGuest(), scanResult: scan)),
              icon: const Icon(Icons.check),
              label: const Text('Potvrdi i spremi'),
            ),
          ],
        ),
      ),
    );
  }
}
