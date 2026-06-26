import 'package:flutter/material.dart';

import '../../reservations/models/reservation.dart';
import '../../reservations/services/reservation_service.dart';
import '../models/payment.dart';
import '../services/payment_service.dart';

class PaymentEditorDialog extends StatefulWidget {
  const PaymentEditorDialog({
    super.key,
    this.payment,
    required this.paymentService,
  });

  final Payment? payment;
  final PaymentService paymentService;

  @override
  State<PaymentEditorDialog> createState() => _PaymentEditorDialogState();
}

class _PaymentEditorDialogState extends State<PaymentEditorDialog> {
  late final TextEditingController _guestNameController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  late final ReservationService _reservationService;
  late PaymentMethod _method;
  bool _isSaving = false;
  String? _errorMessage;
  List<Reservation> _guestSuggestions = [];
  bool _showSuggestions = false;
  String _selectedReservationId = '';

  bool get _isEditing =>
      widget.payment != null && widget.payment!.id.isNotEmpty;

  void _updateSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() {
        _guestSuggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    try {
      final allReservations = await _reservationService
          .watchCheckedInReservations()
          .first;

      final filtered = allReservations
          .where(
            (r) =>
                r.primaryGuestName.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();

      setState(() {
        _guestSuggestions = filtered;
        _showSuggestions = filtered.isNotEmpty;
      });
    } catch (e) {
      // Ignore errors
    }
  }

  void _selectGuest(Reservation reservation) {
    setState(() {
      _guestNameController.text = reservation.primaryGuestName;
      _selectedReservationId = reservation.id;
      _showSuggestions = false;
      _guestSuggestions = [];
    });
  }

  @override
  void initState() {
    super.initState();
    _reservationService = ReservationService();
    final payment = widget.payment ?? Payment.empty();
    _guestNameController = TextEditingController(text: payment.guestName);
    _amountController = TextEditingController(
      text: payment.amount > 0 ? payment.amount.toStringAsFixed(2) : '',
    );
    _notesController = TextEditingController(text: payment.notes);
    _method = payment.method;
    _selectedReservationId = payment.reservationId;

    _guestNameController.addListener(() {
      _updateSuggestions(_guestNameController.text.trim());
    });
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final guestName = _guestNameController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (guestName.isEmpty) {
      setState(() => _errorMessage = 'Unesite ime gosta');
      return;
    }

    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Unesite validan iznos');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      var reservationId = _selectedReservationId.trim();
      if (reservationId.isEmpty && _isEditing) {
        reservationId = widget.payment!.reservationId.trim();
      }
      if (reservationId.isEmpty) {
        final reservation = await _reservationService.getReservationByGuestName(
          guestName,
        );
        if (reservation != null) {
          reservationId = reservation.id;
        }
      }

      final payment = (widget.payment ?? Payment.empty()).copyWith(
        reservationId: reservationId,
        guestName: guestName,
        amount: amount,
        method: _method,
        notes: _notesController.text.trim(),
      );

      if (_isEditing) {
        await widget.paymentService.updatePayment(payment);
        if (reservationId.isNotEmpty) {
          await _reservationService.reconcileReservationPaymentFromPayments(
            reservationId: reservationId,
            fallbackGuestName: guestName,
          );
        }
      } else {
        await widget.paymentService.addPayment(payment);

        if (reservationId.isNotEmpty) {
          await _reservationService.reconcileReservationPaymentFromPayments(
            reservationId: reservationId,
            fallbackGuestName: guestName,
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Plaćanje je ažurirano' : 'Plaćanje je dodano',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Greška: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEditing ? 'Uredi plaćanje' : 'Novo plaćanje',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _guestNameController,
                    decoration: const InputDecoration(
                      labelText: 'Ime gosta',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_showSuggestions && _guestSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _guestSuggestions.length,
                        itemBuilder: (context, index) {
                          final reservation = _guestSuggestions[index];
                          return ListTile(
                            title: Text(reservation.primaryGuestName),
                            subtitle: Text('Parcela: ${reservation.pitchName}'),
                            onTap: () => _selectGuest(reservation),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Iznos (€)',
                  prefixIcon: Icon(Icons.euro_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Način plaćanja',
                  prefixIcon: Icon(Icons.payment_outlined),
                  border: OutlineInputBorder(),
                ),
                items: PaymentMethod.values
                    .map(
                      (method) => DropdownMenuItem(
                        value: method,
                        child: Text('${method.icon} ${method.displayLabel}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _method = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Napomena (opciono)',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('Otkaži'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEditing ? 'Ažuriraj' : 'Dodaj'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
