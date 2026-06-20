import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pitch.dart';

Future<void> showPitchEditor(
  BuildContext context, {
  Pitch? pitch,
  required Future<void> Function(Pitch pitch) onSave,
}) async {
  final isLargeScreen = MediaQuery.sizeOf(context).width >= 720;

  if (isLargeScreen) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: PitchFormDialog(pitch: pitch, onSave: onSave),
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: PitchFormDialog(pitch: pitch, onSave: onSave),
      );
    },
  );
}

class PitchFormDialog extends StatefulWidget {
  const PitchFormDialog({super.key, this.pitch, required this.onSave});

  final Pitch? pitch;
  final Future<void> Function(Pitch pitch) onSave;

  @override
  State<PitchFormDialog> createState() => _PitchFormDialogState();
}

class _PitchFormDialogState extends State<PitchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _numberController;
  late final TextEditingController _zoneController;
  late final TextEditingController _maxGuestsController;
  late final TextEditingController _currentGuestsController;
  late final TextEditingController _notesController;

  late PitchStatus _status;
  late bool _hasElectricity;
  late bool _hasWater;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.pitch != null && widget.pitch!.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final pitch = widget.pitch ?? Pitch.empty();
    _nameController = TextEditingController(text: pitch.name);
    _numberController = TextEditingController(
      text: pitch.number == 0 ? '' : pitch.number.toString(),
    );
    _zoneController = TextEditingController(text: pitch.zone);
    _maxGuestsController = TextEditingController(
      text: pitch.maxGuests.toString(),
    );
    _currentGuestsController = TextEditingController(
      text: pitch.currentGuests.toString(),
    );
    _notesController = TextEditingController(text: pitch.notes);
    _status = pitch.status;
    _hasElectricity = pitch.hasElectricity;
    _hasWater = pitch.hasWater;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _zoneController.dispose();
    _maxGuestsController.dispose();
    _currentGuestsController.dispose();
    _notesController.dispose();
    super.dispose();
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

    final pitch = Pitch(
      id: widget.pitch?.id ?? '',
      name: _nameController.text.trim(),
      number: int.parse(_numberController.text.trim()),
      zone: _zoneController.text.trim(),
      status: _status,
      maxGuests: int.parse(_maxGuestsController.text.trim()),
      currentGuests: int.parse(_currentGuestsController.text.trim()),
      currentGuestCount: int.parse(_currentGuestsController.text.trim()),
      hasElectricity: _hasElectricity,
      hasWater: _hasWater,
      notes: _notesController.text.trim(),
      createdAt: widget.pitch?.createdAt,
      updatedAt: widget.pitch?.updatedAt,
    );

    try {
      await widget.onSave(pitch);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Spremanje nije uspjelo. Pokušaj ponovno.';
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
    final textTheme = Theme.of(context).textTheme;
    final padding = EdgeInsets.only(
      left: 20,
      right: 20,
      top: 20,
      bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
    );

    return SingleChildScrollView(
      padding: padding,
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
                    _isEditing ? 'Uredi parcelu' : 'Dodaj parcelu',
                    style: textTheme.headlineSmall?.copyWith(
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
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Naziv parcele',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Naziv je obavezan.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _numberController,
              decoration: const InputDecoration(
                labelText: 'Broj parcele',
                prefixIcon: Icon(Icons.numbers_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Broj je obavezan.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _zoneController,
              decoration: const InputDecoration(
                labelText: 'Zona',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PitchStatus>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                prefixIcon: Icon(Icons.toggle_on_outlined),
              ),
              items: PitchStatus.values
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.displayLabel),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _status = value;
                });
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _maxGuestsController,
              decoration: const InputDecoration(
                labelText: 'Maksimalni broj gostiju',
                prefixIcon: Icon(Icons.groups_2_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 1) {
                  return 'Max guests mora biti najmanje 1.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _currentGuestsController,
              decoration: const InputDecoration(
                labelText: 'Trenutno gostiju',
                prefixIcon: Icon(Icons.person_outline),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed < 0) {
                  return 'Trenutno gostiju mora biti 0 ili više.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ima struju'),
              value: _hasElectricity,
              onChanged: (value) {
                setState(() {
                  _hasElectricity = value;
                });
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ima vodu'),
              value: _hasWater,
              onChanged: (value) {
                setState(() {
                  _hasWater = value;
                });
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Napomena',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSaving ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_isEditing ? 'Spremi promjene' : 'Dodaj parcelu'),
            ),
          ],
        ),
      ),
    );
  }
}
