import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../parcels/models/pitch.dart';
import '../models/reservation.dart';

Future<void> showReservationEditor(
  BuildContext context, {
  Reservation? reservation,
  required List<Pitch> pitches,
  required Future<void> Function(Reservation reservation) onSave,
}) async {
  final isLargeScreen = MediaQuery.sizeOf(context).width >= 880;

  if (isLargeScreen) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ReservationFormDialog(
              reservation: reservation,
              pitches: pitches,
              onSave: onSave,
            ),
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
        child: ReservationFormDialog(
          reservation: reservation,
          pitches: pitches,
          onSave: onSave,
        ),
      );
    },
  );
}

class ReservationFormDialog extends StatefulWidget {
  const ReservationFormDialog({
    super.key,
    this.reservation,
    required this.pitches,
    required this.onSave,
  });

  final Reservation? reservation;
  final List<Pitch> pitches;
  final Future<void> Function(Reservation reservation) onSave;

  @override
  State<ReservationFormDialog> createState() => _ReservationFormDialogState();
}

class _ReservationFormDialogState extends State<ReservationFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _bookingReferenceController;
  late final TextEditingController _primaryGuestNameController;
  late final TextEditingController _primaryGuestPhoneController;
  late final TextEditingController _primaryGuestEmailController;
  late final TextEditingController _adultsController;
  late final TextEditingController _childrenController;
  late final TextEditingController _petsController;
  late final TextEditingController _vehiclesController;
  late final TextEditingController _accommodationTypeController;
  late final TextEditingController _totalPriceController;
  late final TextEditingController _depositPaidController;
  late final TextEditingController _amountPaidController;
  late final TextEditingController _notesController;

  late ReservationSource _source;
  late ReservationStatus _status;
  late PaymentStatus _paymentStatus;
  late DateTime _checkInDate;
  late DateTime _checkOutDate;
  String? _selectedPitchId;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing =>
      widget.reservation != null && widget.reservation!.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final draft = widget.reservation ?? Reservation.empty();
    _bookingReferenceController = TextEditingController(
      text: draft.bookingReference,
    );
    _primaryGuestNameController = TextEditingController(
      text: draft.primaryGuestName,
    );
    _primaryGuestPhoneController = TextEditingController(
      text: draft.primaryGuestPhone,
    );
    _primaryGuestEmailController = TextEditingController(
      text: draft.primaryGuestEmail,
    );
    _adultsController = TextEditingController(text: draft.adults.toString());
    _childrenController = TextEditingController(
      text: draft.children.toString(),
    );
    _petsController = TextEditingController(text: draft.pets.toString());
    _vehiclesController = TextEditingController(
      text: draft.vehicles.toString(),
    );
    _accommodationTypeController = TextEditingController(
      text: draft.accommodationType,
    );
    _totalPriceController = TextEditingController(
      text: draft.totalPrice.toStringAsFixed(2),
    );
    _depositPaidController = TextEditingController(
      text: draft.depositPaid.toStringAsFixed(2),
    );
    _amountPaidController = TextEditingController(
      text: draft.amountPaid.toStringAsFixed(2),
    );
    _notesController = TextEditingController(text: draft.notes);

    _source = draft.source;
    _status = draft.status;
    _paymentStatus = draft.paymentStatus;
    _checkInDate = DateTime(
      draft.checkInDate.year,
      draft.checkInDate.month,
      draft.checkInDate.day,
    );
    _checkOutDate = DateTime(
      draft.checkOutDate.year,
      draft.checkOutDate.month,
      draft.checkOutDate.day,
    );
    _selectedPitchId = draft.pitchId.isEmpty ? null : draft.pitchId;

    if (_selectedPitchId == null && widget.pitches.isNotEmpty) {
      _selectedPitchId = widget.pitches.first.id;
    }
  }

  @override
  void dispose() {
    _bookingReferenceController.dispose();
    _primaryGuestNameController.dispose();
    _primaryGuestPhoneController.dispose();
    _primaryGuestEmailController.dispose();
    _adultsController.dispose();
    _childrenController.dispose();
    _petsController.dispose();
    _vehiclesController.dispose();
    _accommodationTypeController.dispose();
    _totalPriceController.dispose();
    _depositPaidController.dispose();
    _amountPaidController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Pitch? get _selectedPitch {
    final selectedId = _selectedPitchId;
    if (selectedId == null) {
      return null;
    }
    for (final pitch in widget.pitches) {
      if (pitch.id == selectedId) {
        return pitch;
      }
    }
    return null;
  }

  Future<void> _pickDate({required bool checkIn}) async {
    final initial = checkIn ? _checkInDate : _checkOutDate;
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (result == null) {
      return;
    }

    setState(() {
      if (checkIn) {
        _checkInDate = DateTime(result.year, result.month, result.day);
        if (!_checkOutDate.isAfter(_checkInDate)) {
          _checkOutDate = _checkInDate.add(const Duration(days: 1));
        }
      } else {
        _checkOutDate = DateTime(result.year, result.month, result.day);
      }
    });
  }

  int _readInt(TextEditingController controller, {int fallback = 0}) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  double _readDouble(TextEditingController controller) {
    final sanitized = controller.text.trim().replaceAll(',', '.');
    return double.tryParse(sanitized) ?? 0;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final selectedPitch = _selectedPitch;
    if (selectedPitch == null) {
      setState(() {
        _errorMessage = 'Odaberi parcelu prije spremanja.';
      });
      return;
    }

    if (!_checkOutDate.isAfter(_checkInDate)) {
      setState(() {
        _errorMessage = 'Datum odlaska mora biti nakon datuma dolaska.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final reservation = Reservation(
      id: widget.reservation?.id ?? '',
      bookingReference: _bookingReferenceController.text.trim(),
      source: _source,
      primaryGuestName: _primaryGuestNameController.text.trim(),
      primaryGuestId: widget.reservation?.primaryGuestId ?? '',
      primaryGuestPhone: _primaryGuestPhoneController.text.trim(),
      primaryGuestEmail: _primaryGuestEmailController.text.trim(),
      pitchId: selectedPitch.id,
      pitchName: selectedPitch.name,
      checkInDate: _checkInDate,
      checkOutDate: _checkOutDate,
      adults: _readInt(_adultsController, fallback: 1),
      children: _readInt(_childrenController),
      pets: _readInt(_petsController),
      vehicles: _readInt(_vehiclesController),
      accommodationType: _accommodationTypeController.text.trim(),
      status: _status,
      totalPrice: _readDouble(_totalPriceController),
      depositPaid: _readDouble(_depositPaidController),
      amountPaid: _readDouble(_amountPaidController),
      paymentStatus: _paymentStatus,
      notes: _notesController.text.trim(),
      registeredGuestCount: widget.reservation?.registeredGuestCount ?? 0,
      currentGuests: widget.reservation?.currentGuests ?? 0,
      createdAt: widget.reservation?.createdAt,
      updatedAt: widget.reservation?.updatedAt,
    );

    try {
      await widget.onSave(reservation);
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

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dateTextStyle = Theme.of(context).textTheme.bodyLarge;
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
                    _isEditing ? 'Uredi rezervaciju' : 'Nova rezervacija',
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
            DropdownButtonFormField<ReservationSource>(
              initialValue: _source,
              decoration: const InputDecoration(
                labelText: 'Izvor rezervacije',
                prefixIcon: Icon(Icons.hub_outlined),
              ),
              items: ReservationSource.values
                  .map(
                    (source) => DropdownMenuItem(
                      value: source,
                      child: Text(source.displayLabel),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _source = value;
                });
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _bookingReferenceController,
              decoration: const InputDecoration(
                labelText: 'Booking ili vanjski broj rezervacije',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _primaryGuestNameController,
              decoration: const InputDecoration(
                labelText: 'Ime glavnog gosta',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Ime gosta je obavezno.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _primaryGuestPhoneController,
              decoration: const InputDecoration(
                labelText: 'Telefon',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _primaryGuestEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedPitchId,
              decoration: const InputDecoration(
                labelText: 'Parcela',
                prefixIcon: Icon(Icons.grid_view_rounded),
              ),
              items: widget.pitches
                  .map(
                    (pitch) => DropdownMenuItem(
                      value: pitch.id,
                      child: Text('${pitch.name} (#${pitch.number})'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPitchId = value;
                });
              },
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Parcela je obavezna.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(checkIn: true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum dolaska',
                        prefixIcon: Icon(Icons.login_rounded),
                      ),
                      child: Text(
                        _formatDate(_checkInDate),
                        style: dateTextStyle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(checkIn: false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum odlaska',
                        prefixIcon: Icon(Icons.logout_rounded),
                      ),
                      child: Text(
                        _formatDate(_checkOutDate),
                        style: dateTextStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _adultsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Odrasli'),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 1) {
                        return 'Min 1';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _childrenController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Djeca'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _petsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Pasi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _vehiclesController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Vozila'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _accommodationTypeController,
              decoration: const InputDecoration(
                labelText: 'Tip smještaja',
                prefixIcon: Icon(Icons.cabin_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ReservationStatus>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status rezervacije',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                    items: ReservationStatus.values
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
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<PaymentStatus>(
                    initialValue: _paymentStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status plaćanja',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                    items: PaymentStatus.values
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
                        _paymentStatus = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _totalPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Ukupna cijena',
                      prefixIcon: Icon(Icons.euro_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _depositPaidController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Akontacija',
                      prefixIcon: Icon(Icons.savings_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _amountPaidController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Uplaćeni iznos',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Napomena',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
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
                  : Text(_isEditing ? 'Spremi promjene' : 'Spremi rezervaciju'),
            ),
          ],
        ),
      ),
    );
  }
}
