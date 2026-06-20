import 'package:flutter/material.dart';

import '../models/reservation_guest.dart';

Future<void> showReservationGuestEditor(
  BuildContext context, {
  ReservationGuest? guest,
  required Future<void> Function(ReservationGuest guest) onSave,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ReservationGuestFormDialog(guest: guest, onSave: onSave),
        ),
      );
    },
  );
}

class ReservationGuestFormDialog extends StatefulWidget {
  const ReservationGuestFormDialog({
    super.key,
    this.guest,
    required this.onSave,
  });

  final ReservationGuest? guest;
  final Future<void> Function(ReservationGuest guest) onSave;

  @override
  State<ReservationGuestFormDialog> createState() =>
      _ReservationGuestFormDialogState();
}

class _ReservationGuestFormDialogState
    extends State<ReservationGuestFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _nationalityController;
  late final TextEditingController _documentTypeController;
  late final TextEditingController _documentNumberController;
  late final TextEditingController _genderController;
  late final TextEditingController _documentImagePathController;
  late final TextEditingController _ocrStatusController;

  DateTime? _dateOfBirth;
  DateTime? _documentExpiryDate;
  bool _isPrimaryGuest = false;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.guest != null && widget.guest!.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final draft = widget.guest ?? ReservationGuest.empty();
    _firstNameController = TextEditingController(text: draft.firstName);
    _lastNameController = TextEditingController(text: draft.lastName);
    _nationalityController = TextEditingController(text: draft.nationality);
    _documentTypeController = TextEditingController(text: draft.documentType);
    _documentNumberController = TextEditingController(
      text: draft.documentNumber,
    );
    _genderController = TextEditingController(text: draft.gender);
    _documentImagePathController = TextEditingController(
      text: draft.documentImagePath,
    );
    _ocrStatusController = TextEditingController(text: draft.ocrStatus);
    _dateOfBirth = draft.dateOfBirth;
    _documentExpiryDate = draft.documentExpiryDate;
    _isPrimaryGuest = draft.isPrimaryGuest;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nationalityController.dispose();
    _documentTypeController.dispose();
    _documentNumberController.dispose();
    _genderController.dispose();
    _documentImagePathController.dispose();
    _ocrStatusController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  Future<void> _pickDate({required bool birthDate}) async {
    final initial = birthDate
        ? (_dateOfBirth ?? DateTime(1990, 1, 1))
        : (_documentExpiryDate ??
              DateTime.now().add(const Duration(days: 365)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (birthDate) {
        _dateOfBirth = picked;
      } else {
        _documentExpiryDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final guest = ReservationGuest(
      id: widget.guest?.id ?? '',
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _dateOfBirth,
      nationality: _nationalityController.text.trim(),
      documentType: _documentTypeController.text.trim(),
      documentNumber: _documentNumberController.text.trim(),
      documentExpiryDate: _documentExpiryDate,
      gender: _genderController.text.trim(),
      isPrimaryGuest: _isPrimaryGuest,
      documentImagePath: _documentImagePathController.text.trim(),
      ocrStatus: _ocrStatusController.text.trim().isEmpty
          ? 'pending'
          : _ocrStatusController.text.trim(),
      createdAt: widget.guest?.createdAt,
      updatedAt: widget.guest?.updatedAt,
    );

    try {
      await widget.onSave(guest);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Spremanje gosta nije uspjelo.';
      });
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
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'Uredi gosta' : 'Dodaj gosta',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _firstNameController,
              decoration: const InputDecoration(labelText: 'Ime'),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Ime je obavezno.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameController,
              decoration: const InputDecoration(labelText: 'Prezime'),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Prezime je obavezno.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(birthDate: true),
                    icon: const Icon(Icons.cake_outlined),
                    label: Text(
                      _dateOfBirth == null
                          ? 'Datum rođenja'
                          : _formatDate(_dateOfBirth!),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(birthDate: false),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _documentExpiryDate == null
                          ? 'Istek dokumenta'
                          : _formatDate(_documentExpiryDate!),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nationalityController,
              decoration: const InputDecoration(labelText: 'Nacionalnost'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentTypeController,
              decoration: const InputDecoration(labelText: 'Vrsta dokumenta'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentNumberController,
              decoration: const InputDecoration(labelText: 'Broj dokumenta'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _genderController,
              decoration: const InputDecoration(labelText: 'Spol'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _documentImagePathController,
              decoration: const InputDecoration(
                labelText: 'Putanja slike dokumenta',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ocrStatusController,
              decoration: const InputDecoration(labelText: 'OCR status'),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Glavni gost'),
              value: _isPrimaryGuest,
              onChanged: (value) {
                setState(() {
                  _isPrimaryGuest = value;
                });
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(_isEditing ? 'Spremi gosta' : 'Dodaj gosta'),
            ),
          ],
        ),
      ),
    );
  }
}
