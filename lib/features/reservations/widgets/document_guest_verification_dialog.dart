import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/document_image.dart';
import '../models/document_ocr_result.dart';
import '../models/reservation_document_scan_context.dart';
import '../models/reservation.dart';
import '../models/reservation_guest.dart';
import '../models/document_verification_ui.dart';

enum DocumentImageCleanupPolicy {
  deleteImmediately,
  deleteAfterCheckout,
  retainManually,
}

enum DocumentPhotoOperationState {
  idle,
  replacing,
  removing,
  processingOcr,
  error,
}

class DocumentVerificationDialogPayload {
  const DocumentVerificationDialogPayload({
    required this.images,
    required this.imagePreviews,
    required this.ocrResult,
    required this.processStatus,
  });

  final List<DocumentImage> images;
  final Map<String, Uint8List> imagePreviews;
  final DocumentOcrResult ocrResult;
  final String processStatus;
}

typedef DocumentPhotoActionCallback =
    Future<DocumentVerificationDialogPayload> Function(
      DocumentImage image,
      void Function(DocumentPhotoOperationState state, {String? errorMessage})
      onProgress,
    );

typedef DocumentOpenPhotoCallback =
    Future<void> Function(DocumentImage image, Uint8List? preview);

typedef ReservationCheckInCallback = Future<void> Function();

Future<void> showDocumentGuestVerificationDialog(
  BuildContext context, {
  required ReservationDocumentScanContext scanContext,
  required List<DocumentImage> images,
  required Map<String, Uint8List> imagePreviews,
  required DocumentOcrResult ocrResult,
  required String processStatus,
  required Future<DocumentVerificationDialogPayload> Function() onReprocess,
  required Future<DocumentVerificationDialogPayload?> Function()
  onAddMorePhotos,
  required DocumentPhotoActionCallback onReplacePhoto,
  required DocumentPhotoActionCallback onRemovePhoto,
  required DocumentOpenPhotoCallback onOpenPhoto,
  required ReservationStatus reservationStatus,
  required ReservationCheckInCallback onCheckIn,
  required Future<void> Function(
    ReservationGuest guest,
    DocumentImageCleanupPolicy cleanupPolicy,
    DocumentAcceptanceStatus acceptanceStatus,
    bool manualReviewCompleted,
    bool allowDuplicateSave,
  )
  onSave,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: DocumentGuestVerificationDialog(
            scanContext: scanContext,
            images: images,
            imagePreviews: imagePreviews,
            ocrResult: ocrResult,
            processStatus: processStatus,
            onReprocess: onReprocess,
            onAddMorePhotos: onAddMorePhotos,
            onReplacePhoto: onReplacePhoto,
            onRemovePhoto: onRemovePhoto,
            onOpenPhoto: onOpenPhoto,
            reservationStatus: reservationStatus,
            onCheckIn: onCheckIn,
            onSave: onSave,
          ),
        ),
      );
    },
  );
}

class DocumentGuestVerificationDialog extends StatefulWidget {
  const DocumentGuestVerificationDialog({
    super.key,
    required this.scanContext,
    required this.images,
    required this.imagePreviews,
    required this.ocrResult,
    required this.processStatus,
    required this.onReprocess,
    required this.onAddMorePhotos,
    required this.onReplacePhoto,
    required this.onRemovePhoto,
    required this.onOpenPhoto,
    required this.reservationStatus,
    required this.onCheckIn,
    required this.onSave,
  });

  final ReservationDocumentScanContext scanContext;
  final List<DocumentImage> images;
  final Map<String, Uint8List> imagePreviews;
  final DocumentOcrResult ocrResult;
  final String processStatus;
  final Future<DocumentVerificationDialogPayload> Function() onReprocess;
  final Future<DocumentVerificationDialogPayload?> Function() onAddMorePhotos;
  final DocumentPhotoActionCallback onReplacePhoto;
  final DocumentPhotoActionCallback onRemovePhoto;
  final DocumentOpenPhotoCallback onOpenPhoto;
  final ReservationStatus reservationStatus;
  final ReservationCheckInCallback onCheckIn;
  final Future<void> Function(
    ReservationGuest guest,
    DocumentImageCleanupPolicy cleanupPolicy,
    DocumentAcceptanceStatus acceptanceStatus,
    bool manualReviewCompleted,
    bool allowDuplicateSave,
  )
  onSave;

  @override
  State<DocumentGuestVerificationDialog> createState() =>
      _DocumentGuestVerificationDialogState();
}

class _DocumentGuestVerificationDialogState
    extends State<DocumentGuestVerificationDialog> {
  static const bool _enableInternalOcrDebug = false;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _nationalityController;
  late final TextEditingController _issuingCountryController;
  late final TextEditingController _documentTypeController;
  late final TextEditingController _documentNumberController;
  late final TextEditingController _genderController;

  DateTime? _dateOfBirth;
  DateTime? _documentExpiryDate;
  bool _isPrimaryGuest = true;
  bool _manualReviewConfirmed = false;
  bool _allowDuplicateSave = false;
  bool _checkInAfterSave = false;
  bool _isSaving = false;
  String? _errorMessage;
  String? _duplicateWarning;
  DocumentImageCleanupPolicy _cleanupPolicy =
      DocumentImageCleanupPolicy.deleteImmediately;
  String? _rawNationalityCode;
  String? _rawDocumentType;
  late List<DocumentImage> _images;
  late Map<String, Uint8List> _imagePreviews;
  late DocumentOcrResult _ocrResult;
  late String _processStatus;
  late ReservationStatus _reservationStatus;
  final Map<String, DocumentPhotoOperationState> _photoOperationStateById =
      <String, DocumentPhotoOperationState>{};
  final Map<String, String> _photoErrorById = <String, String>{};

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController();
    _lastNameController = TextEditingController();
    _nationalityController = TextEditingController();
    _issuingCountryController = TextEditingController();
    _documentTypeController = TextEditingController();
    _documentNumberController = TextEditingController();
    _genderController = TextEditingController();
    _images = List<DocumentImage>.from(widget.images);
    _imagePreviews = Map<String, Uint8List>.from(widget.imagePreviews);
    _ocrResult = widget.ocrResult;
    _processStatus = _normalizedProcessStatus(widget.processStatus, _ocrResult);
    _reservationStatus = widget.reservationStatus;
    _applyOcrPrefill();
  }

  void _applyOcrPrefill() {
    final parsed = _ocrResult.merged?.parsed ?? _ocrResult.parsed;

    if ((parsed.firstName ?? '').isNotEmpty) {
      _firstNameController.text = parsed.firstName!;
    }
    if ((parsed.lastName ?? '').isNotEmpty) {
      _lastNameController.text = parsed.lastName!;
    }
    if ((parsed.nationality ?? '').isNotEmpty) {
      _rawNationalityCode = (parsed.nationalityCode ?? parsed.nationality)
          ?.trim();
      _nationalityController.text = countryDisplayLabelHr(
        nationalityCode: parsed.nationalityCode ?? parsed.nationality,
        fallback: parsed.nationalityDisplayName,
      );
    }
    if ((parsed.issuingCountry ?? '').isNotEmpty) {
      _issuingCountryController.text = parsed.issuingCountry!;
    }
    _rawDocumentType = (parsed.documentKind ?? parsed.documentType)?.trim();
    _documentTypeController.text = documentTypeDisplayLabelHr(
      parsed.documentKind ?? parsed.documentType,
    );
    if ((parsed.documentNumber ?? '').isNotEmpty) {
      _documentNumberController.text = parsed.documentNumber!;
    }
    if ((parsed.gender ?? '').isNotEmpty && parsed.gender != '<') {
      _genderController.text = parsed.gender!;
    }

    _dateOfBirth = _tryParseDate(parsed.dateOfBirth);
    _documentExpiryDate = _tryParseDate(parsed.documentExpiryDate);
  }

  DateTime? _tryParseDate(String? rawDate) {
    final value = (rawDate ?? '').trim();
    if (value.isEmpty) {
      return null;
    }

    final eu = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(value);
    if (eu != null) {
      return DateTime(
        int.parse(eu.group(3)!),
        int.parse(eu.group(2)!),
        int.parse(eu.group(1)!),
      );
    }

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }

    return null;
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }

  Future<void> _pickDate({required bool birthDate}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: birthDate
          ? (_dateOfBirth ?? DateTime(now.year - 25, now.month, now.day))
          : (_documentExpiryDate ?? DateTime(now.year + 5, now.month, now.day)),
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

  DocumentScanField? _fieldMeta(String fieldName) {
    return _ocrResult.merged?.fields[fieldName];
  }

  bool get _showDebugInfo => kDebugMode && _enableInternalOcrDebug;

  String _normalizedProcessStatus(String status, DocumentOcrResult result) {
    if (status != 'mergingResults') {
      return status;
    }

    final parsed = result.merged?.parsed ?? result.parsed;
    final hasEditableFields =
        (parsed.firstName ?? '').trim().isNotEmpty ||
        (parsed.lastName ?? '').trim().isNotEmpty ||
        (parsed.documentNumber ?? '').trim().isNotEmpty;

    return hasEditableFields ? 'review' : status;
  }

  Color? _fieldColor(String fieldName, {required bool isOptional}) {
    final field = _fieldMeta(fieldName);
    if (field == null) {
      return isOptional ? Colors.blueGrey.withValues(alpha: 0.06) : null;
    }
    if ((field.value ?? '').trim().isEmpty) {
      return isOptional ? Colors.blueGrey.withValues(alpha: 0.06) : null;
    }
    if (field.needsReview) {
      return Colors.orange.withValues(alpha: 0.15);
    }
    if (_isFieldInConflict(fieldName)) {
      return Colors.red.withValues(alpha: 0.12);
    }
    return Colors.green.withValues(alpha: 0.12);
  }

  bool _isFieldInConflict(String fieldName) {
    final conflicts = _ocrResult.merged?.conflicts ?? const <String>[];
    final key = fieldName.toLowerCase();
    return conflicts.any((conflict) => conflict.toLowerCase().contains(key));
  }

  String _fieldStatusLabel(String fieldName, {required bool isOptional}) {
    final field = _fieldMeta(fieldName);
    final value = (field?.value ?? '').trim();
    if (value.isEmpty) {
      return isOptional ? 'Opcionalno polje' : 'Nije popunjeno';
    }
    if (_isFieldInConflict(fieldName)) {
      return 'Konflikt podataka';
    }
    if (field?.needsReview ?? false) {
      return 'Potrebna provjera';
    }
    return 'Automatski potvrđeno';
  }

  String _processStatusLabel(String status) {
    switch (status) {
      case 'selectingImages':
        return 'Odabir fotografija';
      case 'uploading':
        return 'Učitavanje fotografija';
      case 'processingImages':
        return 'OCR obrada';
      case 'mergingResults':
        return 'Spajanje rezultata';
      case 'review':
        return 'Provjera rezultata';
      case 'completed':
        return 'Završeno';
      case 'failed':
        return 'Neuspješno';
      default:
        return status;
    }
  }

  String _acceptanceStatusCodeLabel(DocumentAcceptanceStatus status) {
    switch (status) {
      case DocumentAcceptanceStatus.accepted:
        return 'accepted';
      case DocumentAcceptanceStatus.acceptedWithReview:
        return 'acceptedWithReview';
      case DocumentAcceptanceStatus.manualOnly:
        return 'manualOnly';
      case DocumentAcceptanceStatus.rejected:
        return 'rejected';
    }
  }

  void _applyGuestPreset(String label) {
    setState(() {
      _firstNameController.text = label;
      _lastNameController.text = '';
      _isPrimaryGuest = false;
    });
  }

  Widget _nameDebugInfo(String fieldName) {
    final debug = _ocrResult.merged?.debug?[fieldName];
    if (debug == null) {
      return const SizedBox.shrink();
    }

    final label = fieldName == 'firstName' ? 'Ime' : 'Prezime';
    final mrz = debug.mrzNormalizedValue ?? '-';
    final rawVisual = debug.rawVisualCandidate ?? '-';
    final visual = debug.visualNormalizedValue ?? '-';
    final valid = debug.visualValid == null
        ? '-'
        : (debug.visualValid! ? 'true' : 'false');
    final reason = debug.rejectionReason ?? '-';
    final confidenceBefore = debug.visualConfidenceBeforeValidation == null
        ? '-'
        : (debug.visualConfidenceBeforeValidation! * 100).toStringAsFixed(0);
    final confidenceAfter = debug.visualConfidenceAfterValidation == null
        ? '-'
        : (debug.visualConfidenceAfterValidation! * 100).toStringAsFixed(0);
    final sourceType = debug.visualSourceType ?? '-';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label MRZ: $mrz • rawVisual: $rawVisual • visual: $visual • valid: $valid • rejection: $reason • source: $sourceType • confBefore: $confidenceBefore% • confAfter: $confidenceAfter%',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Widget _sourceInfo(String fieldName) {
    final field = _fieldMeta(fieldName);
    if (field == null) {
      return const SizedBox.shrink();
    }

    if (_showDebugInfo &&
        (fieldName == 'firstName' || fieldName == 'lastName')) {
      return _nameDebugInfo(fieldName);
    }

    if (!_showDebugInfo) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _fieldStatusLabel(
            fieldName,
            isOptional: fieldName == 'gender' || fieldName == 'issueDate',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final source = field.sourceType ?? 'unknown';
    final confidence = field.confidence == null
        ? '-'
        : (field.confidence! * 100).toStringAsFixed(0);
    final review = field.needsReview ? ' • Potrebna ručna provjera' : '';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Izvor: $source • confidence: $confidence%$review',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  DocumentPhotoOperationState _photoState(String imageId) {
    return _photoOperationStateById[imageId] ??
        DocumentPhotoOperationState.idle;
  }

  bool _photoActionBusy(String imageId) {
    final state = _photoState(imageId);
    return state == DocumentPhotoOperationState.replacing ||
        state == DocumentPhotoOperationState.removing ||
        state == DocumentPhotoOperationState.processingOcr;
  }

  String? _photoStateLabel(String imageId) {
    final state = _photoState(imageId);
    switch (state) {
      case DocumentPhotoOperationState.replacing:
        return 'Zamjena u tijeku';
      case DocumentPhotoOperationState.removing:
        return 'Brisanje u tijeku';
      case DocumentPhotoOperationState.processingOcr:
        return 'OCR u tijeku';
      case DocumentPhotoOperationState.error:
      case DocumentPhotoOperationState.idle:
        return null;
    }
  }

  void _updatePhotoState(
    String imageId,
    DocumentPhotoOperationState state, {
    String? errorMessage,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _photoOperationStateById[imageId] = state;
      if (errorMessage != null && errorMessage.trim().isNotEmpty) {
        _photoErrorById[imageId] = errorMessage.trim();
      } else if (state != DocumentPhotoOperationState.error) {
        _photoErrorById.remove(imageId);
      }
    });
  }

  void _applyPhotoPayload(DocumentVerificationDialogPayload payload) {
    if (!mounted) {
      return;
    }
    setState(() {
      _images = List<DocumentImage>.from(payload.images);
      _imagePreviews = Map<String, Uint8List>.from(payload.imagePreviews);
      _ocrResult = payload.ocrResult;
      _processStatus = _normalizedProcessStatus(
        payload.processStatus,
        payload.ocrResult,
      );
    });
  }

  Future<void> _handleReplacePhoto(DocumentImage image) async {
    if (_isSaving || _photoActionBusy(image.id)) {
      return;
    }

    _updatePhotoState(image.id, DocumentPhotoOperationState.replacing);
    try {
      final payload = await widget.onReplacePhoto(image, (
        state, {
        String? errorMessage,
      }) {
        _updatePhotoState(image.id, state, errorMessage: errorMessage);
      });
      _applyPhotoPayload(payload);
      _updatePhotoState(image.id, DocumentPhotoOperationState.idle);
    } catch (_) {
      _updatePhotoState(
        image.id,
        DocumentPhotoOperationState.error,
        errorMessage: 'Greška pri zamjeni fotografije.',
      );
    }
  }

  Future<void> _handleRemovePhoto(DocumentImage image) async {
    if (_isSaving || _photoActionBusy(image.id)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Uklanjanje fotografije'),
          content: const Text('Želite li ukloniti ovu fotografiju dokumenta?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ukloni'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    _updatePhotoState(image.id, DocumentPhotoOperationState.removing);
    try {
      final payload = await widget.onRemovePhoto(image, (
        state, {
        String? errorMessage,
      }) {
        _updatePhotoState(image.id, state, errorMessage: errorMessage);
      });
      _applyPhotoPayload(payload);
      _photoOperationStateById.remove(image.id);
      _photoErrorById.remove(image.id);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      _updatePhotoState(
        image.id,
        DocumentPhotoOperationState.error,
        errorMessage: 'Greška pri brisanju fotografije.',
      );
    }
  }

  Future<void> _handleAddMorePhotos() async {
    if (_isSaving) {
      return;
    }
    try {
      final payload = await widget.onAddMorePhotos();
      if (payload != null) {
        _applyPhotoPayload(payload);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Greška pri dodavanju fotografije.';
      });
    }
  }

  Future<void> _handleReprocess() async {
    if (_isSaving || _images.isEmpty) {
      return;
    }
    setState(() {
      _errorMessage = null;
    });
    try {
      final payload = await widget.onReprocess();
      _applyPhotoPayload(payload);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Obrada dokumenata nije uspjela.';
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final acceptance = _acceptanceStatus;
    if (acceptance == DocumentAcceptanceStatus.rejected) {
      setState(() {
        _errorMessage =
            'Dokument je označen kao nevažeći i ne može se spremiti kao verificiran gost.';
      });
      return;
    }
    if ((acceptance == DocumentAcceptanceStatus.acceptedWithReview ||
            acceptance == DocumentAcceptanceStatus.manualOnly) &&
        !_manualReviewConfirmed) {
      setState(() {
        _errorMessage =
            'Potvrdi ručnu provjeru dokumenta prije spremanja podataka gosta.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _duplicateWarning = null;
    });

    final guest = ReservationGuest(
      id: '',
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _dateOfBirth,
      nationality: (_rawNationalityCode ?? '').trim(),
      documentType: (_rawDocumentType ?? '').trim(),
      documentNumber: _documentNumberController.text.trim(),
      documentExpiryDate: _documentExpiryDate,
      gender: _genderController.text.trim(),
      issuingCountry: _issuingCountryController.text.trim(),
      isPrimaryGuest: _isPrimaryGuest,
      documentImagePath: _images.map((image) => image.storagePath).join(','),
      ocrStatus: 'completed',
    );

    try {
      await widget.onSave(
        guest,
        _cleanupPolicy,
        acceptance,
        _manualReviewConfirmed,
        _allowDuplicateSave,
      );
      if (!mounted) {
        return;
      }
      if (_checkInAfterSave &&
          _reservationStatus != ReservationStatus.checkedIn) {
        await widget.onCheckIn();
        if (!mounted) {
          return;
        }
        setState(() {
          _reservationStatus = ReservationStatus.checkedIn;
        });
      }
      await _showSuccessDialog(guest);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        final message = error.toString();
        if (message.contains('[DUPLICATE]')) {
          _duplicateWarning = message.replaceAll('[DUPLICATE]', '').trim();
          _errorMessage = null;
        } else {
          _errorMessage = 'Spremanje podataka gosta nije uspjelo.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _showSuccessDialog(ReservationGuest guest) async {
    final canCheckIn =
        _reservationStatus == ReservationStatus.inquiry ||
        _reservationStatus == ReservationStatus.confirmed;
    final nationality = _nationalityController.text.trim();
    final maskedDocument = maskDocumentNumber(guest.documentNumber);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('GOST JE USPJEŠNO DODAN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gost ${guest.firstName} ${guest.lastName} uspješno je dodan.',
              ),
              const SizedBox(height: 8),
              Text('${guest.firstName} ${guest.lastName}'.trim()),
              Text('Parcela: ${widget.scanContext.pitchName}'),
              Text('Dolazak: ${_formatDate(widget.scanContext.checkInDate)}'),
              Text('Odlazak: ${_formatDate(widget.scanContext.checkOutDate)}'),
              if (nationality.isNotEmpty) Text('Nacionalnost: $nationality'),
              if (maskedDocument.isNotEmpty) Text('Dokument: $maskedDocument'),
            ],
          ),
          actions: [
            if (canCheckIn)
              FilledButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await widget.onCheckIn();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _reservationStatus = ReservationStatus.checkedIn;
                    });
                    await showDialog<void>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          content: const Text(
                            'Gost je prijavljen, a parcela je označena kao zauzeta.',
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('U redu'),
                            ),
                          ],
                        );
                      },
                    );
                  } catch (error) {
                    if (!mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                },
                child: const Text('Prijavi dolazak'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Zatvori'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _nationalityController.dispose();
    _issuingCountryController.dispose();
    _documentTypeController.dispose();
    _documentNumberController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = _ocrResult.merged?.conflicts ?? const <String>[];
    final acceptance = _acceptanceStatus;
    final duplicateConfirmed = _duplicateWarning == null || _allowDuplicateSave;
    final canSave =
        acceptance == DocumentAcceptanceStatus.accepted ||
        ((acceptance == DocumentAcceptanceStatus.acceptedWithReview ||
                acceptance == DocumentAcceptanceStatus.manualOnly) &&
            _manualReviewConfirmed);
    final canSubmit = canSave && duplicateConfirmed;

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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Provjera podataka gosta',
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
            const SizedBox(height: 8),
            Text('Status procesa: ${_processStatusLabel(_processStatus)}'),
            const SizedBox(height: 8),
            Card(
              color: _acceptanceColor(acceptance),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status dokumenta: ${_acceptanceStatusCodeLabel(acceptance)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(acceptanceMessageHr(acceptance)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _images
                  .map((image) {
                    final preview = _imagePreviews[image.id];
                    final cardStatus = _photoStateLabel(image.id);
                    final cardError = _photoErrorById[image.id];
                    return InkWell(
                      onTap: (_isSaving || _photoActionBusy(image.id))
                          ? null
                          : () => widget.onOpenPhoto(image, preview),
                      child: SizedBox(
                        width: 130,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (preview != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      preview,
                                      height: 80,
                                      width: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Text(image.documentSide.label),
                                if (image.ocrStatus ==
                                    DocumentImageOcrStatus.done)
                                  const Text(
                                    'OCR uspješan',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                TextButton(
                                  onPressed:
                                      (_isSaving || _photoActionBusy(image.id))
                                      ? null
                                      : () =>
                                            widget.onOpenPhoto(image, preview),
                                  child: const Text('Otvori veći pregled'),
                                ),
                                Wrap(
                                  spacing: 2,
                                  runSpacing: 2,
                                  children: [
                                    TextButton(
                                      onPressed:
                                          (_isSaving ||
                                              _photoActionBusy(image.id))
                                          ? null
                                          : () => _handleReplacePhoto(image),
                                      child: const Text('Zamijeni'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          (_isSaving ||
                                              _photoActionBusy(image.id))
                                          ? null
                                          : () => _handleRemovePhoto(image),
                                      child: const Text('Ukloni'),
                                    ),
                                  ],
                                ),
                                if (cardStatus != null)
                                  Text(
                                    cardStatus,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                if (cardError != null)
                                  Text(
                                    cardError,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            if (_images.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Nema dodanih fotografija dokumenta.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            if (_images.isEmpty) const SizedBox(height: 10),
            if (conflicts.isNotEmpty)
              Card(
                color: Colors.orange.withValues(alpha: 0.15),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Potrebna ručna provjera'),
                      const SizedBox(height: 6),
                      ...conflicts.map(Text.new),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              color: _fieldColor('firstName', isOptional: false),
              child: Column(
                children: [
                  TextFormField(
                    controller: _firstNameController,
                    decoration: const InputDecoration(
                      labelText: 'Ime ili opis (npr. Dijete)',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Ime ili opis je obavezno.';
                      }
                      return null;
                    },
                  ),
                  _sourceInfo('firstName'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Odrasli'),
                  onPressed: () => _applyGuestPreset('Odrasli'),
                ),
                ActionChip(
                  label: const Text('Dijete'),
                  onPressed: () => _applyGuestPreset('Dijete'),
                ),
                ActionChip(
                  label: const Text('Beba'),
                  onPressed: () => _applyGuestPreset('Beba'),
                ),
                ActionChip(
                  label: const Text('Pratnja'),
                  onPressed: () => _applyGuestPreset('Pratnja'),
                ),
                ActionChip(
                  label: const Text('Vozač'),
                  onPressed: () => _applyGuestPreset('Vozač'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              color: _fieldColor('lastName', isOptional: true),
              child: Column(
                children: [
                  TextFormField(
                    controller: _lastNameController,
                    decoration: const InputDecoration(
                      labelText: 'Prezime (opcionalno)',
                    ),
                  ),
                  _sourceInfo('lastName'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(birthDate: true),
                    child: Text(
                      _dateOfBirth == null
                          ? 'Datum rođenja'
                          : _formatDate(_dateOfBirth!),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(birthDate: false),
                    child: Text(
                      _documentExpiryDate == null
                          ? 'Istek dokumenta'
                          : _formatDate(_documentExpiryDate!),
                    ),
                  ),
                ),
              ],
            ),
            _sourceInfo('dateOfBirth'),
            _sourceInfo('documentExpiryDate'),
            if (_showDebugInfo &&
                _ocrResult.merged?.debug != null &&
                (_ocrResult.merged!.debug!.containsKey('firstName') ||
                    _ocrResult.merged!.debug!.containsKey('lastName')))
              const SizedBox(height: 4),
            const SizedBox(height: 10),
            Container(
              color: _fieldColor('nationality', isOptional: false),
              child: Column(
                children: [
                  TextFormField(
                    controller: _nationalityController,
                    decoration: const InputDecoration(
                      labelText: 'Nacionalnost',
                    ),
                  ),
                  _sourceInfo('nationality'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              color: _fieldColor('issuingCountry', isOptional: false),
              child: Column(
                children: [
                  TextFormField(
                    controller: _issuingCountryController,
                    decoration: const InputDecoration(
                      labelText: 'Država izdavanja',
                    ),
                  ),
                  _sourceInfo('issuingCountry'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _documentTypeController,
              decoration: const InputDecoration(labelText: 'Vrsta dokumenta'),
            ),
            _sourceInfo('documentType'),
            const SizedBox(height: 10),
            Container(
              color: _fieldColor('documentNumber', isOptional: false),
              child: Column(
                children: [
                  TextFormField(
                    controller: _documentNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Broj dokumenta',
                    ),
                  ),
                  _sourceInfo('documentNumber'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              color: _fieldColor('gender', isOptional: true),
              child: Column(
                children: [
                  TextFormField(
                    controller: _genderController,
                    decoration: const InputDecoration(labelText: 'Spol'),
                  ),
                  _sourceInfo('gender'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Glavni gost'),
              value: _isPrimaryGuest,
              onChanged: (value) => setState(() => _isPrimaryGuest = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<DocumentImageCleanupPolicy>(
              initialValue: _cleanupPolicy,
              decoration: const InputDecoration(
                labelText: 'Politika brisanja slika',
              ),
              items: const [
                DropdownMenuItem(
                  value: DocumentImageCleanupPolicy.deleteImmediately,
                  child: Text('Obriši odmah nakon potvrde'),
                ),
                DropdownMenuItem(
                  value: DocumentImageCleanupPolicy.deleteAfterCheckout,
                  child: Text('Obriši nakon odlaska'),
                ),
                DropdownMenuItem(
                  value: DocumentImageCleanupPolicy.retainManually,
                  child: Text('Zadrži ručno'),
                ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _cleanupPolicy = value;
                });
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_duplicateWarning != null) ...[
              const SizedBox(height: 10),
              Text(
                _duplicateWarning!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _allowDuplicateSave,
                onChanged: (value) {
                  setState(() {
                    _allowDuplicateSave = value ?? false;
                  });
                },
                title: const Text('Potvrđujem spremanje unatoč duplikatu'),
              ),
            ],
            if (acceptance == DocumentAcceptanceStatus.acceptedWithReview ||
                acceptance == DocumentAcceptanceStatus.manualOnly) ...[
              const SizedBox(height: 10),
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _manualReviewConfirmed,
                onChanged: (value) {
                  setState(() {
                    _manualReviewConfirmed = value ?? false;
                  });
                },
                title: const Text('Ručno sam provjerio dokument'),
              ),
            ],
            if (_reservationStatus != ReservationStatus.checkedIn &&
                _reservationStatus != ReservationStatus.checkedOut &&
                _reservationStatus != ReservationStatus.cancelled) ...[
              const SizedBox(height: 10),
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _checkInAfterSave,
                onChanged: (value) {
                  setState(() {
                    _checkInAfterSave = value ?? false;
                  });
                },
                title: const Text('Odmah prijavi dolazak'),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _handleAddMorePhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Dodaj fotografiju'),
                ),
                OutlinedButton.icon(
                  onPressed: (_isSaving || _images.isEmpty)
                      ? null
                      : _handleReprocess,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Obradi dokumente'),
                ),
                FilledButton.icon(
                  onPressed: (_isSaving || !canSubmit) ? null : _submit,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Spremi podatke gosta'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DocumentAcceptanceStatus get _acceptanceStatus {
    return resolveAcceptanceStatus(
      parsed: _ocrResult.merged?.parsed ?? _ocrResult.parsed,
      fields: _ocrResult.merged?.fields ?? const <String, DocumentScanField>{},
      conflicts: _ocrResult.merged?.conflicts ?? const <String>[],
    );
  }

  Color _acceptanceColor(DocumentAcceptanceStatus status) {
    switch (status) {
      case DocumentAcceptanceStatus.accepted:
        return Colors.green.withValues(alpha: 0.12);
      case DocumentAcceptanceStatus.acceptedWithReview:
      case DocumentAcceptanceStatus.manualOnly:
        return Colors.orange.withValues(alpha: 0.14);
      case DocumentAcceptanceStatus.rejected:
        return Colors.red.withValues(alpha: 0.12);
    }
  }
}
