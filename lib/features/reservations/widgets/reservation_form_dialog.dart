import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../parcels/models/pitch.dart';
import '../../payments/models/payment.dart';
import '../../payments/services/payment_service.dart';
import '../models/reservation.dart';
import '../services/document_scan_service.dart';
import '../services/reservation_service.dart';

enum ReservationSubmitAction { saveOnly, checkInNow }

Future<void> showReservationEditor(
  BuildContext context, {
  Reservation? reservation,
  required List<Pitch> pitches,
  required Future<void> Function(
    Reservation reservation,
    ReservationSubmitAction action,
  )
  onSave,
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
  final Future<void> Function(
    Reservation reservation,
    ReservationSubmitAction action,
  )
  onSave;

  @override
  State<ReservationFormDialog> createState() => _ReservationFormDialogState();
}

class _ReservationFormDialogState extends State<ReservationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isUpdatingGuestCounters = false;

  late final TextEditingController _bookingReferenceController;
  late final TextEditingController _primaryGuestNameController;
  late final TextEditingController _primaryGuestPhoneController;
  late final TextEditingController _primaryGuestEmailController;
  late final TextEditingController _adultsController;
  late final TextEditingController _childrenController;
  late final TextEditingController _totalGuestsController;
  late final TextEditingController _petsController;
  late final TextEditingController _vehiclesController;
  late final TextEditingController _vehicleDescriptionController;
  late final TextEditingController _accommodationTypeController;
  late final TextEditingController _totalPriceController;
  late final TextEditingController _pricePerNightController;
  late final TextEditingController _depositPaidController;
  late final TextEditingController _amountPaidController;
  late final TextEditingController _newPaymentAmountController;
  late final TextEditingController _newPaymentNotesController;
  late final TextEditingController _notesController;
  PaymentMethod _newPaymentMethod = PaymentMethod.cash;
  late final PaymentService _paymentService;
  late final ReservationService _reservationService;
  final DocumentScanService _scanService = DocumentScanService();
  List<Payment> _existingPayments = [];
  Set<String> _occupiedPitchIds = <String>{};

  late ReservationSource _source;
  late ReservationStatus _status;
  late PaymentStatus _paymentStatus;
  late DateTime _checkInDate;
  late DateTime _checkOutDate;
  bool _departureDateUnknown = false;
  String _selectedPitchId = '';
  bool _isSaving = false;
  bool _isUploadingVehicleImage = false;
  String? _errorMessage;
  late String _vehicleImageUrl;
  late String _vehicleImagePath;
  late int _vehicleImageSizeBytes;

  bool get _isEditing =>
      widget.reservation != null && widget.reservation!.id.isNotEmpty;

  Future<void> _syncEditingPaymentState() async {
    final reservationId = widget.reservation?.id.trim() ?? '';
    if (reservationId.isEmpty) {
      return;
    }

    try {
      final fallbackGuestName = _primaryGuestNameController.text.trim();
      await _reservationService.reconcileReservationPaymentFromPayments(
        reservationId: reservationId,
        fallbackGuestName: fallbackGuestName,
      );

      final reservationDoc = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(reservationId)
          .get();
      if (!reservationDoc.exists) {
        return;
      }

      final refreshedReservation = Reservation.fromDoc(reservationDoc);
      final payments = await _paymentService
          .watchPaymentsByReservation(reservationId)
          .first;
      final paidInHistory = payments.fold<double>(
        0,
        (total, payment) => total + payment.amount,
      );
      final effectivePaid = paidInHistory > 0
          ? paidInHistory
          : refreshedReservation.amountPaid;

      if (!mounted) {
        return;
      }

      setState(() {
        _existingPayments = payments;
        _amountPaidController.text = effectivePaid.toStringAsFixed(2);
        _paymentStatus = derivePaymentStatus(
          totalPrice: refreshedReservation.totalPrice,
          amountPaid: effectivePaid,
          currentStatus: refreshedReservation.paymentStatus,
        );
      });
    } catch (_) {
      // Keep UI usable even if sync fails.
    }
  }

  double get _totalExistingPayments {
    return _existingPayments.fold<double>(
      0,
      (accumulator, payment) => accumulator + payment.amount,
    );
  }

  double get _amountToMigrate {
    final amountPaid = _readDouble(_amountPaidController);
    final existing = _totalExistingPayments;
    final diff = amountPaid - existing;
    return diff > 0 ? diff : 0;
  }

  int _calculateNights(DateTime checkIn, DateTime checkOut) {
    final start = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final end = DateTime(checkOut.year, checkOut.month, checkOut.day);
    final nights = end.difference(start).inDays;
    return nights < 1 ? 1 : nights;
  }

  double get _computedTotalPrice {
    final baseTotal = _readDouble(_totalPriceController);
    final pricePerNight = _readDouble(_pricePerNightController);
    if (pricePerNight <= 0) {
      return baseTotal;
    }

    if (_departureDateUnknown) {
      final today = DateTime.now();
      final currentDay = DateTime(today.year, today.month, today.day);
      final nights = _calculateNights(_checkInDate, currentDay);
      return pricePerNight * nights;
    }

    final nights = _calculateNights(_checkInDate, _checkOutDate);
    return pricePerNight * nights;
  }

  double get _effectivePaidAmount {
    final formPaid = _readDouble(_amountPaidController);
    return _totalExistingPayments > formPaid
        ? _totalExistingPayments
        : formPaid;
  }

  double get _currentDebtAmount {
    final debt = _computedTotalPrice - _effectivePaidAmount;
    return debt <= 0.01 ? 0 : debt;
  }

  Future<void> _onPaymentStatusChanged(PaymentStatus newStatus) async {
    setState(() {
      _paymentStatus = newStatus;

      // Keep form state aligned with manual status selection.
      if (newStatus == PaymentStatus.paid) {
        final totalPrice = _computedTotalPrice;
        final currentPaid = _readDouble(_amountPaidController);
        if (totalPrice > 0 && currentPaid < totalPrice) {
          _amountPaidController.text = totalPrice.toStringAsFixed(2);
        }
      }
    });

    // Ako je status "Plaćeno" i ovo je editiranje, kreira Payment zapis
    if (!_isEditing || newStatus != PaymentStatus.paid) {
      return;
    }

    final guestName = _primaryGuestNameController.text.trim();
    if (guestName.isEmpty) {
      return;
    }

    final totalPrice = _computedTotalPrice;
    if (totalPrice <= 0.01) {
      return;
    }

    final paidSoFar = _effectivePaidAmount;
    final dueAmount = totalPrice - paidSoFar;
    if (dueAmount <= 0.01) {
      return;
    }

    try {
      final now = DateTime.now();
      await _paymentService.addPayment(
        Payment(
          id: '',
          reservationId: widget.reservation!.id,
          guestName: guestName,
          amount: dueAmount,
          method: _newPaymentMethod,
          notes:
              'Automatski pri potvrdi plaćeno ${now.day}.${now.month}.${now.year}',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _syncEditingPaymentState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Evidentirana uplata duga ${dueAmount.toStringAsFixed(2)} € za "$guestName".',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Greška pri kreiranju Payment zapisa: $e')),
        );
      }
    }
  }

  Future<void> _migratePayment() async {
    final guestName = _primaryGuestNameController.text.trim();
    if (guestName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unesi ime gosta')));
      return;
    }

    final amountToMigrate = _amountToMigrate;
    if (amountToMigrate <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nema iznosa za migraciju')));
      return;
    }

    try {
      final now = DateTime.now();
      await _paymentService.addPayment(
        Payment(
          id: '',
          reservationId: widget.reservation!.id,
          guestName: guestName,
          amount: amountToMigrate,
          method: PaymentMethod.bankTransfer,
          notes: 'Migrirano iz amountPaid',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _syncEditingPaymentState();
      if (mounted) {
        setState(() {
          _newPaymentAmountController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${amountToMigrate.toStringAsFixed(2)} € je migrirano u povijest plaćanja',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Greška pri migraciji: $e')));
      }
    }
  }

  Future<void> _uploadVehicleImage() async {
    if (_isSaving || _isUploadingVehicleImage) {
      return;
    }

    final reservationId = widget.reservation?.id.trim() ?? '';
    if (reservationId.isEmpty) {
      setState(() {
        _errorMessage = 'Najprije spremi rezervaciju pa dodaj sliku vozila.';
      });
      return;
    }

    setState(() {
      _isUploadingVehicleImage = true;
      _errorMessage = null;
    });

    try {
      final selected = await _scanService.pickGalleryImage();
      if (selected == null) {
        return;
      }

      final upload = await _scanService.uploadVehicleImage(
        reservationId: reservationId,
        file: selected,
        maxBytes: 100 * 1024,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _vehicleImageUrl = upload.downloadUrl;
        _vehicleImagePath = upload.storagePath;
        _vehicleImageSizeBytes = upload.bytes.lengthInBytes;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingVehicleImage = false;
        });
      }
    }
  }

  void _syncAdultsChildrenFromTotal() {
    if (_isUpdatingGuestCounters) {
      return;
    }
    final total = int.tryParse(_totalGuestsController.text.trim()) ?? 0;
    if (total < 0) {
      return;
    }

    final currentChildren = int.tryParse(_childrenController.text.trim()) ?? 0;
    final nextChildren = currentChildren.clamp(0, total);
    final nextAdults = total - nextChildren;

    _isUpdatingGuestCounters = true;
    _adultsController.text = nextAdults.toString();
    _childrenController.text = nextChildren.toString();
    _isUpdatingGuestCounters = false;
  }

  void _syncTotalFromAdultsChildren() {
    if (_isUpdatingGuestCounters) {
      return;
    }
    final adults = int.tryParse(_adultsController.text.trim()) ?? 0;
    final children = int.tryParse(_childrenController.text.trim()) ?? 0;
    final total = adults + children;

    _isUpdatingGuestCounters = true;
    _totalGuestsController.text = total.toString();
    _isUpdatingGuestCounters = false;
  }

  void _calculateTotalPriceFromPerNight() {
    // Ne računamo ako je nepoznat datum odlaska
    if (_departureDateUnknown) {
      return;
    }

    final pricePerNight =
        double.tryParse(_pricePerNightController.text.trim()) ?? 0;
    if (pricePerNight <= 0) {
      return;
    }

    final numberOfNights = _calculateNights(_checkInDate, _checkOutDate);

    final totalPrice = pricePerNight * numberOfNights;
    _totalPriceController.text = totalPrice.toStringAsFixed(2);
  }

  Future<void> _updateOccupiedPitches() async {
    final allReservations = await _reservationService.watchReservations().first;
    final occupied = <String>{};

    for (final res in allReservations) {
      // Provjeri samo active i confirmed rezervacije
      if (res.status != ReservationStatus.confirmed &&
          res.status != ReservationStatus.checkedIn) {
        continue;
      }

      // Provjeri overlap s odabranim datumima
      final periodsOverlap =
          !(_checkOutDate.isBefore(res.checkInDate) ||
              _checkInDate.isAfter(res.checkOutDate));

      if (periodsOverlap) {
        // Dodaj sve parcele iz overlapping rezervacije
        final pitchIds = res.pitchIds.isNotEmpty
            ? res.pitchIds
            : (res.pitchId.isNotEmpty ? <String>[res.pitchId] : <String>[]);
        occupied.addAll(pitchIds);
      }
    }

    if (mounted) {
      setState(() {
        _occupiedPitchIds = occupied;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _paymentService = PaymentService(FirebaseFirestore.instance);
    _reservationService = ReservationService(
      firestore: FirebaseFirestore.instance,
    );

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
    _totalGuestsController = TextEditingController(
      text: draft.guestCount > 0
          ? draft.guestCount.toString()
          : (draft.adults + draft.children).toString(),
    );
    _petsController = TextEditingController(text: draft.pets.toString());
    _vehiclesController = TextEditingController(
      text: draft.vehicles.toString(),
    );
    _vehicleDescriptionController = TextEditingController(
      text: draft.vehicleDescription,
    );
    _vehicleImageUrl = draft.vehicleImageUrl;
    _vehicleImagePath = draft.vehicleImagePath;
    _vehicleImageSizeBytes = draft.vehicleImageSizeBytes;
    _accommodationTypeController = TextEditingController(
      text: draft.accommodationType,
    );
    _totalPriceController = TextEditingController(
      text: draft.totalPrice.toStringAsFixed(2),
    );
    _pricePerNightController = TextEditingController(
      text: draft.pricePerNight.toStringAsFixed(2),
    );
    _depositPaidController = TextEditingController(
      text: draft.depositPaid.toStringAsFixed(2),
    );
    _amountPaidController = TextEditingController(
      text: draft.amountPaid.toStringAsFixed(2),
    );
    _newPaymentAmountController = TextEditingController();
    _newPaymentNotesController = TextEditingController();
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
    _departureDateUnknown = draft.departureDateUnknown;
    _selectedPitchId = draft.pitchId.trim();
    if (_selectedPitchId.isEmpty && draft.pitchIds.isNotEmpty) {
      _selectedPitchId = draft.pitchIds.first.trim();
    }
    if (_selectedPitchId.isEmpty && widget.pitches.isNotEmpty) {
      _selectedPitchId = widget.pitches.first.id;
    }

    // Učitaj postojeće Payment zapise ako editiramo
    if (_isEditing) {
      _syncEditingPaymentState();
    }

    _totalGuestsController.addListener(_syncAdultsChildrenFromTotal);
    _adultsController.addListener(_syncTotalFromAdultsChildren);
    _childrenController.addListener(_syncTotalFromAdultsChildren);
    _pricePerNightController.addListener(_calculateTotalPriceFromPerNight);

    // Učitaj zauzete parcele
    _updateOccupiedPitches();
  }

  @override
  void dispose() {
    _bookingReferenceController.dispose();
    _primaryGuestNameController.dispose();
    _primaryGuestPhoneController.dispose();
    _primaryGuestEmailController.dispose();
    _adultsController.dispose();
    _childrenController.dispose();
    _totalGuestsController.dispose();
    _petsController.dispose();
    _vehiclesController.dispose();
    _vehicleDescriptionController.dispose();
    _accommodationTypeController.dispose();
    _totalPriceController.dispose();
    _pricePerNightController.dispose();
    _depositPaidController.dispose();
    _amountPaidController.dispose();
    _newPaymentAmountController.dispose();
    _newPaymentNotesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Pitch? get _selectedPitch {
    if (_selectedPitchId.isEmpty) {
      return null;
    }
    for (final pitch in widget.pitches) {
      if (pitch.id == _selectedPitchId) {
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
        if (!_departureDateUnknown && !_checkOutDate.isAfter(_checkInDate)) {
          _checkOutDate = _checkInDate.add(const Duration(days: 1));
        }
      } else {
        _checkOutDate = DateTime(result.year, result.month, result.day);
      }
      _calculateTotalPriceFromPerNight();
    });
    await _updateOccupiedPitches();
  }

  void _extendStayByDays(int days) {
    setState(() {
      final base = _checkOutDate.isAfter(_checkInDate)
          ? _checkOutDate
          : _checkInDate.add(const Duration(days: 1));
      _checkOutDate = base.add(Duration(days: days));
      _departureDateUnknown = false;
      _calculateTotalPriceFromPerNight();
    });
    _updateOccupiedPitches();
  }

  int _readInt(TextEditingController controller, {int fallback = 0}) {
    return int.tryParse(controller.text.trim()) ?? fallback;
  }

  double _readDouble(TextEditingController controller) {
    final sanitized = controller.text.trim().replaceAll(',', '.');
    return double.tryParse(sanitized) ?? 0;
  }

  Future<void> _submit(ReservationSubmitAction action) async {
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

    if (!_departureDateUnknown && !_checkOutDate.isAfter(_checkInDate)) {
      setState(() {
        _errorMessage = 'Datum odlaska mora biti nakon datuma dolaska.';
      });
      return;
    }

    final effectiveCheckOutDate = _departureDateUnknown
        ? _checkInDate.add(const Duration(days: 1))
        : _checkOutDate;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final adults = _readInt(_adultsController, fallback: 1);
    final children = _readInt(_childrenController);
    final totalGuests = _readInt(_totalGuestsController);
    final pets = _readInt(_petsController);
    final vehicles = _readInt(_vehiclesController);
    final fallbackGuestCount = totalGuests > 0
        ? totalGuests
        : (adults + children);
    final today = DateTime.now();
    final isCheckInToday = _isSameDate(
      _checkInDate,
      DateTime(today.year, today.month, today.day),
    );
    final shouldAutoCheckInToday =
        !_isEditing &&
        action == ReservationSubmitAction.saveOnly &&
        isCheckInToday &&
        (_status == ReservationStatus.inquiry ||
            _status == ReservationStatus.confirmed);
    final shouldCheckInNow =
        action == ReservationSubmitAction.checkInNow || shouldAutoCheckInToday;

    if (fallbackGuestCount < 1) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Unesi ukupan broj gostiju ili postavi odrasle/djecu na najmanje 1.';
      });
      return;
    }

    final totalPrice = _computedTotalPrice;
    final depositPaid = _readDouble(_depositPaidController);
    var amountPaid =
        _readDouble(_amountPaidController) +
        _readDouble(_newPaymentAmountController);

    if (_paymentStatus == PaymentStatus.paid &&
        totalPrice > 0 &&
        amountPaid < totalPrice) {
      amountPaid = totalPrice;
    }

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
      checkOutDate: effectiveCheckOutDate,
      adults: adults,
      children: children,
      pets: pets,
      vehicles: vehicles,
      vehicleDescription: _vehicleDescriptionController.text.trim(),
      vehicleImageUrl: _vehicleImageUrl,
      vehicleImagePath: _vehicleImagePath,
      vehicleImageSizeBytes: _vehicleImageSizeBytes,
      accommodationType: _accommodationTypeController.text.trim(),
      status: shouldCheckInNow ? ReservationStatus.checkedIn : _status,
      totalPrice: totalPrice,
      depositPaid: depositPaid,
      amountPaid: amountPaid,
      pricePerNight: _readDouble(_pricePerNightController),
      paymentStatus: derivePaymentStatus(
        totalPrice: totalPrice,
        amountPaid: amountPaid,
        currentStatus: _paymentStatus,
      ),
      notes: _notesController.text.trim(),
      registeredGuestCount: fallbackGuestCount,
      currentGuests: shouldCheckInNow
          ? fallbackGuestCount
          : (widget.reservation?.status == ReservationStatus.checkedIn
                ? fallbackGuestCount
                : (widget.reservation?.currentGuests ?? 0)),
      guestCount: fallbackGuestCount,
      pitchCount: 1,
      pitchIds: <String>[selectedPitch.id],
      departureDateUnknown: _departureDateUnknown,
      createdAt: widget.reservation?.createdAt,
      updatedAt: widget.reservation?.updatedAt,
    );

    try {
      await widget.onSave(reservation, action);

      // Kreira Payment zapis u povijest plaćanja ako je unijeta nova uplata
      final newAmt = _readDouble(_newPaymentAmountController);
      if (newAmt > 0 && reservation.id.isNotEmpty) {
        final paymentService = PaymentService(FirebaseFirestore.instance);
        final now = DateTime.now();
        await paymentService.addPayment(
          Payment(
            id: '',
            reservationId: reservation.id,
            guestName: reservation.primaryGuestName,
            amount: newAmt,
            method: _newPaymentMethod,
            notes: _newPaymentNotesController.text.trim(),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on ReservationConflictException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
      });
    } on ReservationDuplicateException catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Rezervacija s istim gostom i datumima već postoji. Provjeri postojeće rezervacije.';
      });
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

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final dateTextStyle = Theme.of(context).textTheme.bodyLarge;
    final now = DateTime.now();
    final isCheckInToday = _isSameDate(
      _checkInDate,
      DateTime(now.year, now.month, now.day),
    );
    final saveOnlyLabel = !_isEditing && isCheckInToday
        ? 'Spremi i prijavi dolazak'
        : 'Spremi u buduće';
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
            FormField<String>(
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Odaberi parcelu.';
                }
                return null;
              },
              builder: (formFieldState) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.grid_view_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Parcela',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: widget.pitches.map((pitch) {
                        final isSelected = _selectedPitchId == pitch.id;
                        final isOccupied = _occupiedPitchIds.contains(pitch.id);
                        final isDisabled = isOccupied && !isSelected;

                        return ChoiceChip(
                          selected: isSelected,
                          onSelected: isDisabled
                              ? null
                              : (selected) {
                                  setState(() {
                                    _selectedPitchId = selected ? pitch.id : '';
                                    formFieldState.didChange(_selectedPitchId);
                                  });
                                },
                          avatar: isOccupied
                              ? Icon(
                                  Icons.lock,
                                  size: 18,
                                  color: Colors.red[700],
                                )
                              : (isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      )
                                    : Icon(
                                        Icons.radio_button_unchecked,
                                        size: 18,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      )),
                          label: isOccupied
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      pitch.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[600],
                                          ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'zauzeto',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  pitch.name,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                          backgroundColor: isOccupied ? Colors.grey[200] : null,
                        );
                      }).toList(),
                    ),
                    if (formFieldState.hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        formFieldState.errorText ?? '',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                );
              },
              initialValue: _selectedPitchId,
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
                    onTap: _departureDateUnknown
                        ? null
                        : () => _pickDate(checkIn: false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Datum odlaska',
                        prefixIcon: Icon(Icons.logout_rounded),
                      ),
                      child: Text(
                        _departureDateUnknown
                            ? 'Nije poznat'
                            : _formatDate(_checkOutDate),
                        style: dateTextStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Datum odlaska još nije poznat'),
              subtitle: const Text(
                'Koristi za goste koji ne znaju točan datum odlaska.',
              ),
              value: _departureDateUnknown,
              onChanged: (value) {
                setState(() {
                  _departureDateUnknown = value;
                  if (!value) {
                    _calculateTotalPriceFromPerNight();
                  }
                });
              },
            ),
            if (!_departureDateUnknown) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('+1 dan'),
                    onPressed: () => _extendStayByDays(1),
                  ),
                  ActionChip(
                    label: const Text('+3 dana'),
                    onPressed: () => _extendStayByDays(3),
                  ),
                  ActionChip(
                    label: const Text('+7 dana'),
                    onPressed: () => _extendStayByDays(7),
                  ),
                ],
              ),
            ],
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
                      if (parsed == null || parsed < 0) {
                        return 'Min 0';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final computedTotal = _computedTotalPrice;
                    final paid = _effectivePaidAmount;
                    final debt = _currentDebtAmount;
                    final summaryColor = debt > 0.01
                        ? Colors.red.shade700
                        : Colors.green.shade700;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: summaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: summaryColor.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        'Ukupno: ${computedTotal.toStringAsFixed(2)} € • Plaćeno: ${paid.toStringAsFixed(2)} € • Dug: ${debt.toStringAsFixed(2)} €',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: summaryColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
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
                    controller: _totalGuestsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Ukupno gostiju',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      if (parsed == null || parsed < 0) {
                        return 'Min 0';
                      }
                      return null;
                    },
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
              controller: _vehicleDescriptionController,
              decoration: const InputDecoration(
                labelText: 'Opis vozila',
                prefixIcon: Icon(Icons.directions_car_outlined),
                hintText: 'npr. VW Transporter, ZG-1234-AB, bijeli kombi',
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Slika vozila',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_vehicleImageUrl.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          _vehicleImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined),
                            );
                          },
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(child: Text('Nema slike vozila')),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _isUploadingVehicleImage
                            ? null
                            : _uploadVehicleImage,
                        icon: _isUploadingVehicleImage
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file_outlined),
                        label: Text(
                          _vehicleImageUrl.trim().isNotEmpty
                              ? 'Zamijeni sliku'
                              : 'Dodaj sliku',
                        ),
                      ),
                      if (_vehicleImageUrl.trim().isNotEmpty)
                        OutlinedButton(
                          onPressed: _isUploadingVehicleImage
                              ? null
                              : () {
                                  setState(() {
                                    _vehicleImageUrl = '';
                                    _vehicleImagePath = '';
                                    _vehicleImageSizeBytes = 0;
                                  });
                                },
                          child: const Text('Ukloni'),
                        ),
                    ],
                  ),
                  if (_vehicleImagePath.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _vehicleImagePath,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_vehicleImageSizeBytes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Veličina: ${(_vehicleImageSizeBytes / 1024).toStringAsFixed(1)} KB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
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
                    items:
                        (_isEditing
                                ? ReservationStatus.values
                                : ReservationStatus.values.where(
                                    (status) =>
                                        status != ReservationStatus.checkedIn &&
                                        status != ReservationStatus.checkedOut,
                                  ))
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
                      _onPaymentStatusChanged(value);
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
                    controller: _pricePerNightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Dogovorena cijena po noćenju',
                      prefixIcon: Icon(Icons.hotel_outlined),
                    ),
                    onChanged: (_) {
                      _calculateTotalPriceFromPerNight();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: PaymentMethod.cash,
              decoration: const InputDecoration(
                labelText: 'Način plaćanja',
                prefixIcon: Icon(Icons.payment_outlined),
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
                // Opciono: može se čuvati metoda ako trebam
              },
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
                if (!_isEditing) ...[
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
              ],
            ),
            // ── SEKCIJA PLAĆANJA za editiranje postojeće rezervacije ──
            if (_isEditing) ...[
              const SizedBox(height: 14),
              Builder(
                builder: (context) {
                  final alreadyPaid = _readDouble(_amountPaidController);
                  final colorScheme = Theme.of(context).colorScheme;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Plaćanja',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Do sada plaćeno
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: alreadyPaid > 0
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.5,
                                  )
                                : Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Naplaćeno u povijesti:',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colorScheme.outline,
                                          ),
                                    ),
                                    Text(
                                      '${_totalExistingPayments.toStringAsFixed(2)} €',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: _totalExistingPayments > 0
                                                ? colorScheme.primary
                                                : colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_amountToMigrate > 0) ...[
                                const SizedBox(width: 8),
                                Tooltip(
                                  message:
                                      'Migrira razliku (${_amountToMigrate.toStringAsFixed(2)} €) kao Payment zapis',
                                  child: FilledButton.tonalIcon(
                                    onPressed: _migratePayment,
                                    icon: const Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Migriraj'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_amountToMigrate > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Colors.orange[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Razlika od ${_amountToMigrate.toStringAsFixed(2)} € (${alreadyPaid.toStringAsFixed(2)} € - ${_totalExistingPayments.toStringAsFixed(2)} €) trebam migrirati u povijesti plaćanja.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Text(
                          'Nova uplata',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _newPaymentAmountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Iznos',
                                  hintText: '0.00',
                                  prefixIcon: Icon(Icons.euro),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<PaymentMethod>(
                                initialValue: _newPaymentMethod,
                                decoration: const InputDecoration(
                                  labelText: 'Način plaćanja',
                                  prefixIcon: Icon(Icons.payment_outlined),
                                ),
                                items: PaymentMethod.values.map((method) {
                                  return DropdownMenuItem(
                                    value: method,
                                    child: Text(
                                      '${method.icon} ${method.displayLabel}',
                                    ),
                                  );
                                }).toList(),
                                onChanged: (m) {
                                  if (m != null) {
                                    setState(() => _newPaymentMethod = m);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _newPaymentNotesController,
                          decoration: const InputDecoration(
                            labelText: 'Napomena uz uplatu (opcionalno)',
                            prefixIcon: Icon(Icons.note_outlined),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
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
            if (_isEditing)
              FilledButton(
                onPressed: _isSaving
                    ? null
                    : () => _submit(ReservationSubmitAction.saveOnly),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Spremi promjene'),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    !_isEditing && isCheckInToday
                        ? 'Datum dolaska je danas, pa će se rezervacija spremiti kao aktivan boravak.'
                        : 'Ako je datum dolaska danas, rezervaciju možeš odmah prijaviti klikom na gumb ispod.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _isSaving
                        ? null
                        : () => _submit(ReservationSubmitAction.saveOnly),
                    child: Text(saveOnlyLabel),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _submit(ReservationSubmitAction.checkInNow),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.login_rounded),
                    label: const Text('Prijavi dolazak odmah'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
