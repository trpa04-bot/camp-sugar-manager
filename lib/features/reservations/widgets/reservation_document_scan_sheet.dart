import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/document_image.dart';
import '../models/document_ocr_result.dart';
import '../models/reservation.dart';
import '../models/reservation_document_scan_context.dart';
import '../models/reservation_guest.dart';
import '../services/document_ocr_cloud_service.dart';
import '../services/document_ocr_error_resolver.dart';
import '../services/document_image_source_adapter.dart';
import '../services/document_image_quality_service.dart';
import '../services/document_scan_quality_message_resolver.dart';
import '../services/document_scan_service.dart';
import '../services/reservation_service.dart';
import '../services/web_camera_capture_adapter.dart';
import 'document_guest_verification_dialog.dart';
import 'web_document_camera_capture_dialog.dart';

typedef DocumentScanImagePicker = Future<XFile?> Function(DocumentSide side);
typedef DocumentScanProcessOverride = Future<void> Function();
typedef DocumentScanWebCameraDialogOpener =
    Future<XFile?> Function(
      BuildContext context,
      WebCameraCaptureAdapter cameraAdapter,
    );

enum DocumentScanProcessStatus {
  selectingImages,
  uploading,
  processingImages,
  mergingResults,
  review,
  completed,
  failed,
}

DocumentScanProcessStatus statusAfterMerge({required bool hasResult}) {
  return hasResult
      ? DocumentScanProcessStatus.review
      : DocumentScanProcessStatus.mergingResults;
}

class ImmediateRetentionCleanupResult {
  const ImmediateRetentionCleanupResult({required this.cleanupFailed});

  final bool cleanupFailed;
}

Future<ImmediateRetentionCleanupResult> applyImmediateRetentionCleanup({
  required ReservationService reservationService,
  required String reservationId,
  required ReservationGuest guest,
  required List<DocumentImage> images,
  required Future<void> Function(String storagePath) deleteDocumentImage,
}) async {
  var cleanupFailed = false;

  for (final image in images) {
    if (image.storagePath.trim().isEmpty) {
      continue;
    }
    try {
      await deleteDocumentImage(image.storagePath);
    } catch (_) {
      cleanupFailed = true;
    }
  }

  if (cleanupFailed) {
    await reservationService.updateGuest(
      reservationId,
      guest.copyWith(cleanupPending: true),
    );
  } else {
    await reservationService.updateGuest(
      reservationId,
      guest.copyWith(
        cleanupPending: false,
        documentImagePath: '',
        documentImagePaths: const <String>[],
      ),
    );
  }

  return ImmediateRetentionCleanupResult(cleanupFailed: cleanupFailed);
}

Future<void> showReservationDocumentScanFlow(
  BuildContext context, {
  required Reservation reservation,
  required ReservationService reservationService,
  ReservationGuest? initialGuest,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.9,
        child: ReservationDocumentScanSheet(
          reservation: reservation,
          reservationService: reservationService,
          initialGuest: initialGuest,
        ),
      );
    },
  );
}

class ReservationDocumentScanSheet extends StatefulWidget {
  const ReservationDocumentScanSheet({
    super.key,
    required this.reservation,
    required this.reservationService,
    this.initialGuest,
    this.documentScanService,
    this.documentOcrCloudService,
    this.qualityService,
    this.qualityMessageResolver,
    this.imagePickerOverride,
    this.processDocumentsOverride,
    this.imageSourceAdapter,
    this.webCameraAdapter,
    this.webCameraDialogOpener,
    this.isWebOverride,
  });

  final Reservation reservation;
  final ReservationService reservationService;
  final ReservationGuest? initialGuest;
  final DocumentScanService? documentScanService;
  final DocumentOcrCloudService? documentOcrCloudService;
  final DocumentImageQualityService? qualityService;
  final DocumentScanQualityMessageResolver? qualityMessageResolver;
  final DocumentScanImagePicker? imagePickerOverride;
  final DocumentScanProcessOverride? processDocumentsOverride;
  final DocumentImageSourceAdapter? imageSourceAdapter;
  final WebCameraCaptureAdapter? webCameraAdapter;
  final DocumentScanWebCameraDialogOpener? webCameraDialogOpener;
  final bool? isWebOverride;

  @override
  State<ReservationDocumentScanSheet> createState() =>
      _ReservationDocumentScanSheetState();
}

class _ReservationDocumentScanSheetState
    extends State<ReservationDocumentScanSheet> {
  DocumentScanService? _documentScanService;
  DocumentOcrCloudService? _documentOcrCloudService;
  DocumentImageSourceAdapter? _imageSourceAdapter;
  WebCameraCaptureAdapter? _webCameraAdapter;
  late final DocumentImageQualityService _qualityService;
  late final DocumentScanQualityMessageResolver _qualityMessageResolver;
  final Uuid _uuid = const Uuid();

  final List<_SelectedDocumentImage> _images = <_SelectedDocumentImage>[];

  bool _isBusy = false;
  bool _isSelectingImage = false;
  DocumentSide? _selectingSide;
  String? _errorMessage;
  String _progressText = '';
  DocumentScanProcessStatus _status = DocumentScanProcessStatus.selectingImages;

  @override
  void initState() {
    super.initState();
    _documentScanService = widget.documentScanService;
    _documentOcrCloudService = widget.documentOcrCloudService;
    _imageSourceAdapter = widget.imageSourceAdapter;
    _webCameraAdapter = widget.webCameraAdapter;
    _qualityService =
        widget.qualityService ?? const DocumentImageQualityService();
    _qualityMessageResolver =
        widget.qualityMessageResolver ??
        const DocumentScanQualityMessageResolver();
  }

  DocumentScanService get _scanService {
    return _documentScanService ??= DocumentScanService();
  }

  DocumentOcrCloudService get _ocrService {
    return _documentOcrCloudService ??= DocumentOcrCloudService();
  }

  DocumentImageSourceAdapter get _imageSource {
    return _imageSourceAdapter ??= createDocumentImageSourceAdapter();
  }

  WebCameraCaptureAdapter get _cameraAdapter {
    return _webCameraAdapter ??= createWebCameraCaptureAdapter();
  }

  DocumentScanWebCameraDialogOpener get _openWebCameraDialog {
    return widget.webCameraDialogOpener ??
        ((context, cameraAdapter) {
          return showWebDocumentCameraCaptureDialog(
            context,
            adapter: cameraAdapter,
          );
        });
  }

  bool get _isWeb => widget.isWebOverride ?? kIsWeb;

  @override
  void dispose() {
    _webCameraAdapter?.dispose();
    super.dispose();
  }

  String get _statusDisplayLabel {
    switch (_status) {
      case DocumentScanProcessStatus.selectingImages:
        return 'Odabir fotografija';
      case DocumentScanProcessStatus.uploading:
        return 'Učitavanje fotografija';
      case DocumentScanProcessStatus.processingImages:
        return 'OCR obrada';
      case DocumentScanProcessStatus.mergingResults:
        return 'Spajanje rezultata';
      case DocumentScanProcessStatus.review:
        return 'Provjera rezultata';
      case DocumentScanProcessStatus.completed:
        return 'Završeno';
      case DocumentScanProcessStatus.failed:
        return 'Neuspješno';
    }
  }

  ReservationDocumentScanContext _scanContext(String guestId) {
    return ReservationDocumentScanContext(
      reservationId: widget.reservation.id,
      guestId: guestId,
      pitchId: widget.reservation.pitchId,
      pitchName: widget.reservation.pitchName,
      checkInDate: widget.reservation.checkInDate,
      checkOutDate: widget.reservation.checkOutDate,
    );
  }

  Future<void> _addImage(
    DocumentSide side, {
    String? replaceId,
    DocumentImageSourceKind? forcedSource,
  }) async {
    if (_isBusy || _isSelectingImage) {
      return;
    }

    if (_images.length >= 5 && replaceId == null) {
      setState(() {
        _errorMessage = 'Maksimalno je dopušteno 5 fotografija po gostu.';
      });
      return;
    }

    setState(() {
      _isSelectingImage = true;
      _selectingSide = side;
      _errorMessage = null;
      _progressText = 'Dodavanje fotografije: ${side.label.toLowerCase()}';
    });

    try {
      final selected = await _pickImageForSide(
        side,
        forcedSource: forcedSource,
      );
      if (selected == null) {
        debugPrint('[doc-flow] stage=file-pick code=no-file-selected');
        setState(() {
          _errorMessage = 'Nije odabrana datoteka.';
        });
        return;
      }

      debugPrint('[doc-flow] file selected: true');
      debugPrint('[doc-flow] mime type: ${selected.mimeType ?? '(empty)'}');

      final lowerName = selected.name.toLowerCase();
      final mimeType = (selected.mimeType ?? '').toLowerCase();
      final isPdf = lowerName.endsWith('.pdf') || mimeType == 'application/pdf';
      if (isPdf) {
        setState(() {
          _errorMessage =
              'PDF dokument je odabran. OCR obrada trenutno podržava samo slike (JPG, JPEG, PNG).';
        });
        return;
      }

      final supported = widget.documentScanService != null
          ? widget.documentScanService!.isSupportedImageFile(selected)
          : (widget.imagePickerOverride != null
                ? true
                : _isSupportedImage(selected));
      if (!supported) {
        debugPrint('[doc-flow] stage=file-pick code=unsupported-format');
        setState(() {
          _errorMessage = 'Nepodržan format.';
        });
        return;
      }

      Uint8List bytes;
      try {
        bytes = await selected.readAsBytes();
      } catch (_) {
        debugPrint('[doc-flow] stage=file-read code=read-failed');
        setState(() {
          _errorMessage = 'Datoteka se ne može pročitati.';
        });
        return;
      }
      debugPrint('[doc-flow] byte length: ${bytes.lengthInBytes}');
      if (bytes.isEmpty) {
        debugPrint('[doc-flow] stage=file-read code=empty-image');
        setState(() {
          _errorMessage = 'Slika je prazna.';
        });
        return;
      }

      debugPrint('[doc-flow] quality check started');
      final qualityReport = await _qualityService.analyze(bytes);
      final isHeicLike =
          mimeType.contains('heic') ||
          mimeType.contains('heif') ||
          lowerName.endsWith('.heic') ||
          lowerName.endsWith('.heif');

      final blockingIssues = qualityReport.issues
          .where((issue) => issue.blocking)
          .toList(growable: false);
      final decodeOnlyBlocking =
          blockingIssues.isNotEmpty &&
          blockingIssues.every((issue) => issue.code == 'decodeFailed');

      if (qualityReport.hasBlockingIssues &&
          !(isHeicLike && decodeOnlyBlocking)) {
        final messages = _qualityMessageResolver.resolveMessages(
          blockingIssues,
        );
        debugPrint('[doc-flow] quality check failure');
        setState(() {
          _errorMessage =
              'Provjera kvalitete nije uspjela. ${messages.join(' ')}';
        });
        return;
      }
      debugPrint('[doc-flow] quality check success');

      final imageId = replaceId ?? _uuid.v4();
      final nonBlockingIssues = qualityReport.issues
          .where((issue) => !issue.blocking)
          .toList(growable: false);
      final warningMessages = _qualityMessageResolver.resolveMessages(
        nonBlockingIssues,
      );
      final qualityWarningText = warningMessages.isEmpty
          ? null
          : warningMessages.take(2).join('\n');
      final documentImage = _SelectedDocumentImage(
        id: imageId,
        file: selected,
        bytes: bytes,
        mimeType: mimeType,
        side: side,
        uploadStatus: DocumentImageUploadStatus.pending,
        ocrStatus: DocumentImageOcrStatus.pending,
        qualityWarningText: (isHeicLike && decodeOnlyBlocking)
            ? 'Fotografija odabrana. Lokalni preview nije dostupan, obrada se nastavlja.'
            : qualityWarningText,
      );

      setState(() {
        _errorMessage = null;
        if (replaceId != null) {
          final idx = _images.indexWhere((image) => image.id == replaceId);
          if (idx >= 0) {
            _images[idx] = documentImage;
          }
        } else if (side == DocumentSide.frontIdCard ||
            side == DocumentSide.backIdCard ||
            side == DocumentSide.passport) {
          final existing = _images.indexWhere((image) => image.side == side);
          if (existing >= 0) {
            _images[existing] = documentImage;
          } else {
            _images.add(documentImage);
          }
        } else {
          _images.add(documentImage);
        }
        _status = DocumentScanProcessStatus.selectingImages;
        _progressText = 'Fotografija dodana: ${side.label.toLowerCase()}';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSelectingImage = false;
        _selectingSide = null;
      });
    }
  }

  void _removeImage(String imageId) {
    setState(() {
      _images.removeWhere((image) => image.id == imageId);
    });
  }

  bool get _hasFrontSide =>
      _images.any((image) => image.side == DocumentSide.frontIdCard);

  bool get _hasBackSide =>
      _images.any((image) => image.side == DocumentSide.backIdCard);

  bool get _hasPassport =>
      _images.any((image) => image.side == DocumentSide.passport);

  bool get _canProcessDocuments =>
      _images.isNotEmpty && (_hasPassport || (_hasFrontSide && _hasBackSide));

  String get _processButtonHint {
    if (_hasPassport) {
      return 'Putovnica dodana - spremno za obradu';
    }
    if (_hasFrontSide && !_hasBackSide) {
      return 'Dodaj još stražnju stranu dokumenta';
    }
    if (!_hasFrontSide && _hasBackSide) {
      return 'Dodaj još prednju stranu dokumenta';
    }
    if (_hasFrontSide && _hasBackSide) {
      return 'Prednja i stražnja strana su dodane';
    }
    return 'Dodaj prednju i stražnju stranu ili putovnicu';
  }

  Widget _buildRequiredSideStatus(
    String label,
    bool isAdded, {
    bool isActive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final icon = isActive
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          )
        : Icon(
            isAdded ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isAdded ? Colors.green : scheme.onSurfaceVariant,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAdded
            ? Colors.green.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isAdded
              ? Colors.green.withValues(alpha: 0.35)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon, const SizedBox(width: 6), Text(label)],
      ),
    );
  }

  Future<XFile?> _pickImageForPlatform() async {
    return _pickImageForSide(DocumentSide.additional);
  }

  bool _isSupportedImage(XFile file) {
    final lowerName = file.name.toLowerCase();
    final mimeType = (file.mimeType ?? '').toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.heif') ||
        mimeType == 'image/jpeg' ||
        mimeType == 'image/jpg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/heic' ||
        mimeType == 'image/heif';
  }

  Future<XFile?> _pickImageForSide(
    DocumentSide side, {
    DocumentImageSourceKind? forcedSource,
  }) async {
    if (widget.imagePickerOverride != null) {
      return widget.imagePickerOverride!(side);
    }

    final source = forcedSource ?? await _showDocumentSourcePicker();
    if (source == null) {
      return null;
    }
    if (!mounted) {
      return null;
    }

    try {
      debugPrint('[doc-flow] picker opened');
      switch (source) {
        case DocumentImageSourceKind.scan:
          if (_isWeb) {
            if (_imageSource.isMobileWeb) {
              return _imageSource.captureFromMobileCamera();
            }
            if (_imageSource.supportsWebCamera) {
              return _openWebCameraDialog(context, _cameraAdapter);
            }
            throw const WebCameraException(
              WebCameraErrorCode.unsupported,
              'Skeniranje kamerom nije podržano u ovom pregledniku. Odaberite fotografiju.',
            );
          }
          return _scanService.pickCameraImage();
        case DocumentImageSourceKind.gallery:
          if (_isWeb) {
            return _imageSource.pickFromGallery();
          }
          return _scanService.pickGalleryImage();
        case DocumentImageSourceKind.file:
          if (_isWeb) {
            return _imageSource.pickFromFile();
          }
          return _scanService.pickGalleryImage();
      }
    } on WebCameraException catch (error) {
      debugPrint('[doc-flow] stage=file-pick code=${error.code.name}');
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
        });
      }
      return null;
    } catch (error) {
      debugPrint('[doc-flow] stage=file-pick code=picker-failed');
      if (mounted) {
        setState(() {
          _errorMessage = 'Datoteka se ne može pročitati.';
        });
      }
      return null;
    }
  }

  Future<DocumentImageSourceKind?> _showDocumentSourcePicker() async {
    return showModalBottomSheet<DocumentImageSourceKind>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Dokument gosta',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Skeniraj dokument'),
                onTap: () =>
                    Navigator.of(context).pop(DocumentImageSourceKind.scan),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Odaberi iz galerije'),
                onTap: () =>
                    Navigator.of(context).pop(DocumentImageSourceKind.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('Dodaj PDF ili sliku'),
                onTap: () =>
                    Navigator.of(context).pop(DocumentImageSourceKind.file),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<DocumentVerificationDialogPayload> _recomputeMergedOcr({
    required ReservationDocumentScanContext scanContext,
    required List<DocumentImage> images,
    required Map<String, Uint8List> imagePreviews,
  }) async {
    if (images.isEmpty) {
      setState(() {
        _status = DocumentScanProcessStatus.review;
        _progressText = 'Nema fotografija za obradu';
      });
      return DocumentVerificationDialogPayload(
        images: images,
        imagePreviews: imagePreviews,
        ocrResult: const DocumentOcrResult(
          rawText: '',
          parsed: DocumentOcrParsedData(),
        ),
        processStatus: 'review',
      );
    }

    setState(() {
      _status = DocumentScanProcessStatus.processingImages;
      _progressText = 'OCR obrada';
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Korisnik nije prijavljen za OCR poziv.');
    }
    await user.getIdToken(true);

    final ocrResult = await _ocrService.processDocuments(
      reservationId: scanContext.reservationId,
      guestId: scanContext.guestId,
      images: images,
    );

    final byImageId = <String, DocumentImageOcrResult>{
      for (final imageResult in ocrResult.images)
        imageResult.imageId: imageResult,
    };

    final mergedImages = images
        .map((image) {
          final imageResult = byImageId[image.id];
          if (imageResult == null) {
            return image.copyWith(ocrStatus: DocumentImageOcrStatus.failed);
          }
          return image.copyWith(
            uploadStatus: DocumentImageUploadStatus.uploaded,
            ocrStatus: DocumentImageOcrStatus.done,
            rawText: imageResult.rawText,
            mrzText: imageResult.parsed.mrzText,
            confidence: imageResult.parsed.confidence,
          );
        })
        .toList(growable: false);

    setState(() {
      _status = DocumentScanProcessStatus.mergingResults;
      _progressText = 'Spajanje rezultata';
    });
    setState(() {
      _status = DocumentScanProcessStatus.review;
      _progressText = 'Spremno za provjeru';
    });

    return DocumentVerificationDialogPayload(
      images: mergedImages,
      imagePreviews: imagePreviews,
      ocrResult: ocrResult,
      processStatus: 'review',
    );
  }

  Future<void> _processDocuments() async {
    if (_images.isEmpty) {
      setState(() {
        _errorMessage = 'Dodaj barem jednu fotografiju prije obrade.';
      });
      return;
    }

    if (widget.processDocumentsOverride != null) {
      await widget.processDocumentsOverride!();
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _status = DocumentScanProcessStatus.uploading;
      _progressText = 'Upload 0 od ${_images.length}';
    });

    try {
      final initialGuestId = widget.initialGuest?.id.trim() ?? '';
      final guestId = initialGuestId.isEmpty ? _uuid.v4() : initialGuestId;
      final scanContext = _scanContext(guestId);
      final uploadedImages = <DocumentImage>[];
      final previewMap = <String, Uint8List>{};

      for (var i = 0; i < _images.length; i++) {
        final image = _images[i];
        previewMap[image.id] = image.bytes;

        _updateImageStatus(
          image.id,
          uploadStatus: DocumentImageUploadStatus.uploading,
        );

        final uploadResult = await _scanService.uploadDocumentImage(
          reservation: scanContext,
          guestId: guestId,
          documentImageId: image.id,
          documentSide: image.side,
          file: image.file,
          bytes: image.bytes,
        );

        _updateImageStatus(
          image.id,
          uploadStatus: DocumentImageUploadStatus.uploaded,
          ocrStatus: DocumentImageOcrStatus.processing,
        );

        uploadedImages.add(
          DocumentImage(
            id: image.id,
            storagePath: uploadResult.storagePath,
            documentSide: image.side,
            fileName: uploadResult.fileName,
            contentType: uploadResult.fileName.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
            uploadStatus: DocumentImageUploadStatus.uploaded,
            ocrStatus: DocumentImageOcrStatus.processing,
            createdAt: DateTime.now().toUtc(),
          ),
        );

        setState(() {
          _progressText = 'Upload ${i + 1} od ${_images.length}';
        });
      }

      setState(() {
        _status = DocumentScanProcessStatus.processingImages;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Korisnik nije prijavljen za OCR poziv.');
      }
      await user.getIdToken(true);

      debugPrint('[doc-flow] OCR call started');
      final ocrResult = await _ocrService.processDocuments(
        reservationId: scanContext.reservationId,
        guestId: guestId,
        images: uploadedImages,
      );
      debugPrint('[doc-flow] OCR call success');

      for (var i = 0; i < uploadedImages.length; i++) {
        setState(() {
          _progressText = 'OCR ${i + 1} od ${uploadedImages.length}';
        });
      }

      final byImageId = <String, DocumentImageOcrResult>{
        for (final imageResult in ocrResult.images)
          imageResult.imageId: imageResult,
      };

      final mergedImages = uploadedImages
          .map((image) {
            final imageResult = byImageId[image.id];
            if (imageResult == null) {
              return image.copyWith(ocrStatus: DocumentImageOcrStatus.failed);
            }
            return image.copyWith(
              ocrStatus: DocumentImageOcrStatus.done,
              rawText: imageResult.rawText,
              mrzText: imageResult.parsed.mrzText,
              confidence: imageResult.parsed.confidence,
            );
          })
          .toList(growable: false);

      setState(() {
        _status = DocumentScanProcessStatus.mergingResults;
        _progressText = 'Spajanje rezultata';
      });

      setState(() {
        _status = statusAfterMerge(hasResult: true);
        _progressText = 'Spremno za provjeru';
      });

      if (!mounted) {
        return;
      }

      for (final image in mergedImages) {
        await widget.reservationService.upsertGuestDocumentImage(
          scanContext.reservationId,
          scanContext.guestId,
          image,
        );
      }

      if (!mounted) {
        return;
      }

      var dialogImages = List<DocumentImage>.from(mergedImages);
      var dialogPreviewMap = Map<String, Uint8List>.from(previewMap);
      var dialogOcrResult = ocrResult;
      var dialogProcessStatus = 'review';

      Future<DocumentVerificationDialogPayload> refreshDialogOcr() async {
        final payload = await _recomputeMergedOcr(
          scanContext: scanContext,
          images: dialogImages,
          imagePreviews: dialogPreviewMap,
        );
        dialogImages = List<DocumentImage>.from(payload.images);
        dialogPreviewMap = Map<String, Uint8List>.from(payload.imagePreviews);
        dialogOcrResult = payload.ocrResult;
        dialogProcessStatus = payload.processStatus == 'mergingResults'
            ? 'review'
            : payload.processStatus;
        return payload;
      }

      await showDocumentGuestVerificationDialog(
        context,
        scanContext: scanContext,
        images: dialogImages,
        imagePreviews: dialogPreviewMap,
        ocrResult: dialogOcrResult,
        processStatus: dialogProcessStatus,
        onReprocess: () async {
          return refreshDialogOcr();
        },
        onAddMorePhotos: () async {
          final pickedFile = await _pickImageForPlatform();
          if (pickedFile == null) {
            return null;
          }
          if (!_isSupportedImage(pickedFile)) {
            throw StateError('Nepodržan format.');
          }

          final bytes = await pickedFile.readAsBytes();
          final imageId = _uuid.v4();
          final uploadResult = await _scanService.uploadDocumentImage(
            reservation: scanContext,
            guestId: scanContext.guestId,
            documentImageId: imageId,
            documentSide: DocumentSide.additional,
            file: pickedFile,
            bytes: bytes,
          );

          final newImage = DocumentImage(
            id: imageId,
            storagePath: uploadResult.storagePath,
            documentSide: DocumentSide.additional,
            fileName: uploadResult.fileName,
            contentType: uploadResult.fileName.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
            uploadStatus: DocumentImageUploadStatus.uploaded,
            ocrStatus: DocumentImageOcrStatus.processing,
            createdAt: DateTime.now().toUtc(),
          );

          await widget.reservationService.upsertGuestDocumentImage(
            scanContext.reservationId,
            scanContext.guestId,
            newImage,
          );

          dialogImages = [...dialogImages, newImage];
          dialogPreviewMap = {...dialogPreviewMap, imageId: bytes};

          return refreshDialogOcr();
        },
        onReplacePhoto: (image, onProgress) async {
          onProgress(DocumentPhotoOperationState.replacing);

          final pickedFile = await _pickImageForPlatform();
          if (pickedFile == null) {
            onProgress(DocumentPhotoOperationState.idle);
            return DocumentVerificationDialogPayload(
              images: dialogImages,
              imagePreviews: dialogPreviewMap,
              ocrResult: dialogOcrResult,
              processStatus: dialogProcessStatus,
            );
          }
          if (!_isSupportedImage(pickedFile)) {
            onProgress(
              DocumentPhotoOperationState.error,
              errorMessage: 'Nepodržan format.',
            );
            throw StateError('Nepodržan format.');
          }

          final bytes = await pickedFile.readAsBytes();
          final newImageId = _uuid.v4();
          String? uploadedStoragePath;
          var newDocSaved = false;

          try {
            final uploadResult = await _scanService.uploadDocumentImage(
              reservation: scanContext,
              guestId: scanContext.guestId,
              documentImageId: newImageId,
              documentSide: image.documentSide,
              file: pickedFile,
              bytes: bytes,
            );
            uploadedStoragePath = uploadResult.storagePath;

            final newImage = DocumentImage(
              id: newImageId,
              storagePath: uploadResult.storagePath,
              documentSide: image.documentSide,
              fileName: uploadResult.fileName,
              contentType: uploadResult.fileName.toLowerCase().endsWith('.png')
                  ? 'image/png'
                  : 'image/jpeg',
              uploadStatus: DocumentImageUploadStatus.uploaded,
              ocrStatus: DocumentImageOcrStatus.processing,
              createdAt: DateTime.now().toUtc(),
            );

            await widget.reservationService.upsertGuestDocumentImage(
              scanContext.reservationId,
              scanContext.guestId,
              newImage,
            );
            newDocSaved = true;

            await _scanService.deleteDocumentImage(image.storagePath);
            await widget.reservationService.deleteGuestDocumentImage(
              scanContext.reservationId,
              scanContext.guestId,
              image.id,
            );

            dialogImages = dialogImages
                .map((entry) => entry.id == image.id ? newImage : entry)
                .toList(growable: false);
            dialogPreviewMap.remove(image.id);
            dialogPreviewMap[newImage.id] = bytes;

            onProgress(DocumentPhotoOperationState.processingOcr);
            final payload = await refreshDialogOcr();
            onProgress(DocumentPhotoOperationState.idle);
            return payload;
          } catch (error) {
            if (newDocSaved) {
              try {
                await widget.reservationService.deleteGuestDocumentImage(
                  scanContext.reservationId,
                  scanContext.guestId,
                  newImageId,
                );
              } catch (_) {}
            }
            if (uploadedStoragePath != null && uploadedStoragePath.isNotEmpty) {
              try {
                await _scanService.deleteDocumentImage(uploadedStoragePath);
              } catch (_) {}
            }
            onProgress(
              DocumentPhotoOperationState.error,
              errorMessage: 'Greška pri zamjeni fotografije: $error',
            );
            rethrow;
          }
        },
        onRemovePhoto: (image, onProgress) async {
          onProgress(DocumentPhotoOperationState.removing);
          try {
            await _scanService.deleteDocumentImage(image.storagePath);
            await widget.reservationService.deleteGuestDocumentImage(
              scanContext.reservationId,
              scanContext.guestId,
              image.id,
            );

            dialogImages = dialogImages
                .where((entry) => entry.id != image.id)
                .toList(growable: false);
            dialogPreviewMap.remove(image.id);

            if (dialogImages.isEmpty) {
              dialogOcrResult = const DocumentOcrResult(
                rawText: '',
                parsed: DocumentOcrParsedData(),
              );
              dialogProcessStatus = 'review';
              onProgress(DocumentPhotoOperationState.idle);
              return DocumentVerificationDialogPayload(
                images: dialogImages,
                imagePreviews: dialogPreviewMap,
                ocrResult: dialogOcrResult,
                processStatus: dialogProcessStatus,
              );
            }

            onProgress(DocumentPhotoOperationState.processingOcr);
            final payload = await refreshDialogOcr();
            onProgress(DocumentPhotoOperationState.idle);
            return payload;
          } catch (error) {
            onProgress(
              DocumentPhotoOperationState.error,
              errorMessage: 'Greška pri brisanju fotografije: $error',
            );
            rethrow;
          }
        },
        onOpenPhoto: (image, preview) async {
          if (preview == null || !mounted) {
            return;
          }
          await showDialog<void>(
            context: context,
            builder: (context) {
              return Dialog(
                child: InteractiveViewer(
                  child: Image.memory(preview, fit: BoxFit.contain),
                ),
              );
            },
          );
        },
        reservationStatus: widget.reservation.status,
        onCheckIn: () async {
          if (widget.reservation.status == ReservationStatus.inquiry) {
            final shouldConfirm = await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text('Potvrda prijave dolaska'),
                  content: const Text(
                    'Rezervacija je još uvijek označena kao upit. Želite li je potvrditi i prijaviti dolazak?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Odustani'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Potvrdi'),
                    ),
                  ],
                );
              },
            );
            if (shouldConfirm != true) {
              return;
            }
          }

          final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
          await widget.reservationService.checkInReservation(
            reservationId: widget.reservation.id,
            checkedInByUid: uid,
          );
        },
        onSave:
            (
              guest,
              cleanupPolicy,
              acceptanceStatus,
              manualReviewCompleted,
              allowDuplicateSave,
            ) async {
              final retentionPolicy = switch (cleanupPolicy) {
                DocumentImageCleanupPolicy.deleteImmediately =>
                  DocumentRetentionPolicy.deleteImmediately,
                DocumentImageCleanupPolicy.deleteAfterCheckout =>
                  DocumentRetentionPolicy.deleteAfterCheckout,
                DocumentImageCleanupPolicy.retainManually =>
                  DocumentRetentionPolicy.retainManually,
              };

              final saveResult = await widget.reservationService
                  .saveVerifiedGuest(
                    reservation: widget.reservation,
                    guest: guest.copyWith(id: guestId),
                    images: dialogImages,
                    acceptanceStatus: acceptanceStatus,
                    manualReviewCompleted: manualReviewCompleted,
                    retentionPolicy: retentionPolicy,
                    allowDuplicate: allowDuplicateSave,
                  );

              if (!saveResult.saved && saveResult.duplicateMatch != null) {
                throw StateError(
                  '[DUPLICATE] Pronađen mogući duplikat (${saveResult.duplicateMatch!.displayName}). Potvrdi spremanje ako želiš nastaviti.',
                );
              }

              if (retentionPolicy ==
                  DocumentRetentionPolicy.deleteImmediately) {
                final cleanupResult = await applyImmediateRetentionCleanup(
                  reservationService: widget.reservationService,
                  reservationId: widget.reservation.id,
                  guest: saveResult.guest,
                  images: dialogImages,
                  deleteDocumentImage: _scanService.deleteDocumentImage,
                );

                if (cleanupResult.cleanupFailed) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Gost je spremljen, ali neke slike dokumenta nisu obrisane.',
                        ),
                      ),
                    );
                  }
                }
              }

              if (mounted && saveResult.warningMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(saveResult.warningMessage!)),
                );
              }
            },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _status = DocumentScanProcessStatus.completed;
      });
      Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (error) {
      debugPrint('[doc-flow] OCR call failure code=${error.code}');
      setState(() {
        _errorMessage = const DocumentOcrErrorResolver().resolve(error);
        _status = DocumentScanProcessStatus.failed;
      });
    } catch (error) {
      debugPrint('[doc-flow] stage=process code=unknown-failure error=$error');
      setState(() {
        _errorMessage = const DocumentOcrErrorResolver().resolve(error);
        _status = DocumentScanProcessStatus.failed;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          if (_status == DocumentScanProcessStatus.failed) {
            _progressText = '';
          }
        });
      }
    }
  }

  void _updateImageStatus(
    String imageId, {
    DocumentImageUploadStatus? uploadStatus,
    DocumentImageOcrStatus? ocrStatus,
  }) {
    final index = _images.indexWhere((image) => image.id == imageId);
    if (index < 0) {
      return;
    }
    setState(() {
      _images[index] = _images[index].copyWith(
        uploadStatus: uploadStatus,
        ocrStatus: ocrStatus,
      );
    });
  }

  Widget _buildImageCard(_SelectedDocumentImage image) {
    final canRenderInline =
        image.mimeType.contains('jpeg') ||
        image.mimeType.contains('jpg') ||
        image.mimeType.contains('png');

    final previewWidget = canRenderInline
        ? Image.memory(image.bytes, width: 72, height: 72, fit: BoxFit.cover)
        : Container(
            width: 72,
            height: 72,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported_outlined),
          );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: previewWidget,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(image.side.label),
                  Text(
                    image.file.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Upload: ${image.uploadStatus.name} • OCR: ${image.ocrStatus.name}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (image.qualityWarningText != null)
                    Text(
                      image.qualityWarningText!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: _isBusy
                  ? null
                  : () => _addImage(image.side, replaceId: image.id),
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Zamijeni fotografiju',
            ),
            IconButton(
              onPressed: _isBusy ? null : () => _removeImage(image.id),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Ukloni fotografiju',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: ListView(
        children: [
          Text(
            'Skeniraj dokumente gosta',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dodaj prednju i stražnju stranu osobne iskaznice, putovnicu ili dodatne fotografije. Maksimalno 5 fotografija.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Dokument gosta',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(DocumentSide.additional),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Skeniraj dokument'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(
                        DocumentSide.additional,
                        forcedSource: DocumentImageSourceKind.gallery,
                      ),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Odaberi iz galerije'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(
                        DocumentSide.additional,
                        forcedSource: DocumentImageSourceKind.file,
                      ),
                icon: const Icon(Icons.insert_drive_file_outlined),
                label: const Text('Dodaj PDF ili sliku'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(DocumentSide.frontIdCard),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Dodaj prednju stranu'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(DocumentSide.backIdCard),
                icon: const Icon(Icons.credit_card),
                label: const Text('Dodaj stražnju stranu'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(DocumentSide.passport),
                icon: const Icon(Icons.travel_explore),
                label: const Text('Dodaj putovnicu'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy || _isSelectingImage
                    ? null
                    : () => _addImage(DocumentSide.additional),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Dodaj dodatnu fotografiju'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildRequiredSideStatus(
                'Prednja strana',
                _hasFrontSide,
                isActive:
                    _isSelectingImage &&
                    _selectingSide == DocumentSide.frontIdCard,
              ),
              _buildRequiredSideStatus(
                'Stražnja strana',
                _hasBackSide,
                isActive:
                    _isSelectingImage &&
                    _selectingSide == DocumentSide.backIdCard,
              ),
              _buildRequiredSideStatus(
                'Putovnica (alternativa)',
                _hasPassport,
                isActive:
                    _isSelectingImage &&
                    _selectingSide == DocumentSide.passport,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Status: $_statusDisplayLabel'),
          if (_progressText.isNotEmpty) Text(_progressText),
          if (_isSelectingImage) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 8),
          if (_images.isNotEmpty)
            SizedBox(
              height: 260,
              child: ListView.builder(
                itemCount: _images.length,
                itemBuilder: (context, index) =>
                    _buildImageCard(_images[index]),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Nema dodanih fotografija.')),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (_isBusy || _isSelectingImage || !_canProcessDocuments)
                ? null
                : _processDocuments,
            icon: const Icon(Icons.settings_suggest_outlined),
            label: const Text('Obradi dokumente'),
          ),
          const SizedBox(height: 6),
          Text(
            _processButtonHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_isBusy) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectedDocumentImage {
  const _SelectedDocumentImage({
    required this.id,
    required this.file,
    required this.bytes,
    required this.mimeType,
    required this.side,
    required this.uploadStatus,
    required this.ocrStatus,
    this.qualityWarningText,
  });

  final String id;
  final XFile file;
  final Uint8List bytes;
  final String mimeType;
  final DocumentSide side;
  final DocumentImageUploadStatus uploadStatus;
  final DocumentImageOcrStatus ocrStatus;
  final String? qualityWarningText;

  _SelectedDocumentImage copyWith({
    String? id,
    XFile? file,
    Uint8List? bytes,
    String? mimeType,
    DocumentSide? side,
    DocumentImageUploadStatus? uploadStatus,
    DocumentImageOcrStatus? ocrStatus,
    String? qualityWarningText,
  }) {
    return _SelectedDocumentImage(
      id: id ?? this.id,
      file: file ?? this.file,
      bytes: bytes ?? this.bytes,
      mimeType: mimeType ?? this.mimeType,
      side: side ?? this.side,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      ocrStatus: ocrStatus ?? this.ocrStatus,
      qualityWarningText: qualityWarningText ?? this.qualityWarningText,
    );
  }
}
