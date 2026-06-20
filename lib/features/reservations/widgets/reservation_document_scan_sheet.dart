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
import '../services/document_scan_service.dart';
import '../services/reservation_service.dart';
import 'document_guest_verification_dialog.dart';

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
  });

  final Reservation reservation;
  final ReservationService reservationService;

  @override
  State<ReservationDocumentScanSheet> createState() =>
      _ReservationDocumentScanSheetState();
}

class _ReservationDocumentScanSheetState
    extends State<ReservationDocumentScanSheet> {
  final DocumentScanService _documentScanService = DocumentScanService();
  final DocumentOcrCloudService _documentOcrCloudService =
      DocumentOcrCloudService();
  final Uuid _uuid = const Uuid();

  final List<_SelectedDocumentImage> _images = <_SelectedDocumentImage>[];

  bool _isBusy = false;
  String? _errorMessage;
  String _progressText = '';
  DocumentScanProcessStatus _status = DocumentScanProcessStatus.selectingImages;

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

  Future<void> _addImage(DocumentSide side, {String? replaceId}) async {
    if (_images.length >= 5 && replaceId == null) {
      setState(() {
        _errorMessage = 'Maksimalno je dopušteno 5 fotografija po gostu.';
      });
      return;
    }

    final selected = await _documentScanService.pickGalleryImage();
    if (selected == null) {
      return;
    }

    if (!_documentScanService.isSupportedImageFile(selected)) {
      setState(() {
        _errorMessage = 'Podržani su samo JPG, JPEG i PNG formati.';
      });
      return;
    }

    final bytes = await selected.readAsBytes();
    final imageId = replaceId ?? _uuid.v4();
    final documentImage = _SelectedDocumentImage(
      id: imageId,
      file: selected,
      bytes: bytes,
      side: side,
      uploadStatus: DocumentImageUploadStatus.pending,
      ocrStatus: DocumentImageOcrStatus.pending,
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
    });
  }

  void _removeImage(String imageId) {
    setState(() {
      _images.removeWhere((image) => image.id == imageId);
    });
  }

  Future<XFile?> _pickImageForPlatform() async {
    if (kIsWeb) {
      return _documentScanService.pickGalleryImage();
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Odaberi iz galerije'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Snimi kamerom'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      return null;
    }
    if (source == ImageSource.camera) {
      return _documentScanService.pickCameraImage();
    }
    return _documentScanService.pickGalleryImage();
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

    final ocrResult = await _documentOcrCloudService.processDocuments(
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

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _status = DocumentScanProcessStatus.uploading;
      _progressText = 'Upload 0 od ${_images.length}';
    });

    try {
      final guestId = _uuid.v4();
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

        final uploadResult = await _documentScanService.uploadDocumentImage(
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

      final ocrResult = await _documentOcrCloudService.processDocuments(
        reservationId: scanContext.reservationId,
        guestId: guestId,
        images: uploadedImages,
      );

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
          if (!_documentScanService.isSupportedImageFile(pickedFile)) {
            throw StateError('Podržani su samo JPG, JPEG i PNG formati.');
          }

          final bytes = await pickedFile.readAsBytes();
          final imageId = _uuid.v4();
          final uploadResult = await _documentScanService.uploadDocumentImage(
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
          if (!_documentScanService.isSupportedImageFile(pickedFile)) {
            onProgress(
              DocumentPhotoOperationState.error,
              errorMessage: 'Podržani su samo JPG, JPEG i PNG formati.',
            );
            throw StateError('Podržani su samo JPG, JPEG i PNG formati.');
          }

          final bytes = await pickedFile.readAsBytes();
          final newImageId = _uuid.v4();
          String? uploadedStoragePath;
          var newDocSaved = false;

          try {
            final uploadResult = await _documentScanService.uploadDocumentImage(
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

            await _documentScanService.deleteDocumentImage(image.storagePath);
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
                await _documentScanService.deleteDocumentImage(
                  uploadedStoragePath,
                );
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
            await _documentScanService.deleteDocumentImage(image.storagePath);
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
                  deleteDocumentImage: _documentScanService.deleteDocumentImage,
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
      setState(() {
        _errorMessage =
            'OCR nije uspio (${error.code}): ${error.message ?? 'Nepoznata greška.'}';
        _status = DocumentScanProcessStatus.failed;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Obrada dokumenata nije uspjela: $error';
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
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                image.bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Skeniraj dokumente gosta',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Dodaj prednju i stražnju stranu osobne iskaznice ili dodatne fotografije. Maksimalno 5 fotografija.',
          ),
          const SizedBox(height: 8),
          Text('Status: $_statusDisplayLabel'),
          if (_progressText.isNotEmpty) Text(_progressText),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _addImage(DocumentSide.frontIdCard),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Dodaj prednju stranu'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _addImage(DocumentSide.backIdCard),
                icon: const Icon(Icons.credit_card),
                label: const Text('Dodaj stražnju stranu'),
              ),
              OutlinedButton.icon(
                onPressed: _isBusy
                    ? null
                    : () => _addImage(DocumentSide.additional),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Dodaj dodatnu fotografiju'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_images.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _images.length,
                itemBuilder: (context, index) =>
                    _buildImageCard(_images[index]),
              ),
            )
          else
            const Expanded(
              child: Center(child: Text('Nema dodanih fotografija.')),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _isBusy ? null : _processDocuments,
            icon: const Icon(Icons.settings_suggest_outlined),
            label: const Text('Obradi dokumente'),
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
    required this.side,
    required this.uploadStatus,
    required this.ocrStatus,
  });

  final String id;
  final XFile file;
  final Uint8List bytes;
  final DocumentSide side;
  final DocumentImageUploadStatus uploadStatus;
  final DocumentImageOcrStatus ocrStatus;

  _SelectedDocumentImage copyWith({
    String? id,
    XFile? file,
    Uint8List? bytes,
    DocumentSide? side,
    DocumentImageUploadStatus? uploadStatus,
    DocumentImageOcrStatus? ocrStatus,
  }) {
    return _SelectedDocumentImage(
      id: id ?? this.id,
      file: file ?? this.file,
      bytes: bytes ?? this.bytes,
      side: side ?? this.side,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      ocrStatus: ocrStatus ?? this.ocrStatus,
    );
  }
}
