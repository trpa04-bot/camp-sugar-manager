// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'document_image_source_adapter.dart';

class DocumentImageSourceAdapterWeb implements DocumentImageSourceAdapter {
  @override
  bool get isWeb => true;

  @override
  bool get isMobileWeb {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod') ||
        ua.contains('android');
  }

  @override
  bool get supportsWebCamera {
    final mediaDevices = html.window.navigator.mediaDevices;
    return mediaDevices != null;
  }

  @override
  Future<XFile?> captureFromMobileCamera() {
    return _pickUsingInput(accept: 'image/*', capture: 'environment');
  }

  @override
  Future<XFile?> captureFromWebCamera() async {
    return null;
  }

  @override
  Future<XFile?> pickFromGallery() {
    return _pickUsingInput(accept: 'image/*');
  }

  @override
  Future<XFile?> pickFromFile() {
    return _pickUsingInput(accept: 'image/*,application/pdf');
  }

  Future<XFile?> _pickUsingInput({
    required String accept,
    String? capture,
  }) async {
    debugPrint('[doc-picker] picker opened');
    final input = html.FileUploadInputElement()
      ..accept = accept
      ..multiple = false;
    input.setAttribute('type', 'file');
    input.value = '';
    if (capture != null && capture.trim().isNotEmpty) {
      input.setAttribute('capture', capture);
    }

    input.style
      ..position = 'fixed'
      ..left = '-10000px'
      ..top = '0'
      ..width = '1px'
      ..height = '1px'
      ..opacity = '0'
      ..pointerEvents = 'none';
    html.document.body?.append(input);

    final completer = Completer<html.File?>();
    late final StreamSubscription<html.Event> changeSub;
    late final StreamSubscription<html.Event> blurSub;

    void completeWith(html.File? file) {
      if (completer.isCompleted) {
        return;
      }
      completer.complete(file);
    }

    changeSub = input.onChange.listen((_) {
      final file = input.files?.isNotEmpty == true ? input.files!.first : null;
      debugPrint('[doc-picker] file selected: ${file != null}');
      completeWith(file);
    });

    // Safari can close the picker without firing change.
    blurSub = input.onBlur.listen((_) {
      if (input.files?.isNotEmpty == true) {
        return;
      }
      debugPrint('[doc-picker] file selected: false');
      completeWith(null);
    });

    input.click();

    try {
      final file = await completer.future;
      if (file == null) {
        return null;
      }

      final mimeType = file.type.trim().isEmpty ? null : file.type;
      final fileSize = file.size;
      debugPrint('[doc-picker] mime type: ${mimeType ?? '(empty)'}');
      debugPrint('[doc-picker] file size: $fileSize');

      if (_shouldTranscodeToJpeg(fileName: file.name, mimeType: mimeType)) {
        final isHeicLike = _isHeicLike(fileName: file.name, mimeType: mimeType);
        try {
          final transcoded = await _transcodeImageToJpeg(file);
          debugPrint('[doc-picker] byte length: ${transcoded.lengthInBytes}');
          return XFile.fromData(
            transcoded,
            name: _jpgFileName(file.name),
            mimeType: 'image/jpeg',
          );
        } catch (error) {
          debugPrint('[doc-picker] transcode failed: $error');
          // HEIC/HEIF cannot be decoded by most browsers. Returning the raw
          // bytes would only push an undecodable file into upload/OCR and
          // produce a confusing failure later, so fail fast with a clear,
          // actionable message instead.
          if (isHeicLike) {
            throw StateError(
              'HEIC/HEIF format nije podržan u pregledniku. '
              'Na iPhoneu uključite Postavke > Kamera > Formati > '
              '"Najkompatibilnije", ili odaberite JPG/PNG fotografiju.',
            );
          }
          // For other (non-HEIC) types, raw bytes may still be a valid image
          // the browser simply did not transcode; let it continue.
        }
      }

      final bytes = await _readBlobAsBytes(file);
      debugPrint('[doc-picker] byte length: ${bytes.lengthInBytes}');
      return XFile.fromData(bytes, name: file.name, mimeType: mimeType);
    } finally {
      await changeSub.cancel();
      await blurSub.cancel();
      input.remove();
    }
  }

  bool _shouldTranscodeToJpeg({required String fileName, String? mimeType}) {
    final normalizedName = fileName.toLowerCase();
    final normalizedMime = (mimeType ?? '').toLowerCase();

    final isPdf =
        normalizedMime == 'application/pdf' || normalizedName.endsWith('.pdf');
    if (isPdf) {
      return false;
    }

    final isJpeg =
        normalizedMime == 'image/jpeg' ||
        normalizedMime == 'image/jpg' ||
        normalizedName.endsWith('.jpg') ||
        normalizedName.endsWith('.jpeg');
    final isPng =
        normalizedMime == 'image/png' || normalizedName.endsWith('.png');

    if (isJpeg || isPng) {
      return false;
    }

    final isImageByMime = normalizedMime.startsWith('image/');
    final isLikelyHeic =
        normalizedMime.contains('heic') ||
        normalizedMime.contains('heif') ||
        normalizedName.endsWith('.heic') ||
        normalizedName.endsWith('.heif');

    // Transcode unknown image types (especially HEIC/HEIF) to JPEG.
    return isLikelyHeic || isImageByMime;
  }

  bool _isHeicLike({required String fileName, String? mimeType}) {
    final normalizedName = fileName.toLowerCase();
    final normalizedMime = (mimeType ?? '').toLowerCase();
    return normalizedMime.contains('heic') ||
        normalizedMime.contains('heif') ||
        normalizedName.endsWith('.heic') ||
        normalizedName.endsWith('.heif');
  }

  String _jpgFileName(String originalName) {
    final trimmed = originalName.trim();
    if (trimmed.isEmpty) {
      return 'captured_document.jpg';
    }
    final dot = trimmed.lastIndexOf('.');
    if (dot <= 0) {
      return '$trimmed.jpg';
    }
    return '${trimmed.substring(0, dot)}.jpg';
  }

  Future<Uint8List> _transcodeImageToJpeg(html.File file) async {
    final objectUrl = html.Url.createObjectUrl(file);
    try {
      final image = html.ImageElement();
      final loadCompleter = Completer<void>();

      StreamSubscription<html.Event>? loadSub;
      StreamSubscription<html.Event>? errorSub;

      loadSub = image.onLoad.listen((_) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.complete();
        }
      });
      errorSub = image.onError.listen((_) {
        if (!loadCompleter.isCompleted) {
          loadCompleter.completeError(
            StateError('Neuspjelo dekodiranje slike za konverziju.'),
          );
        }
      });

      image.src = objectUrl;
      await loadCompleter.future;

      await loadSub.cancel();
      await errorSub.cancel();

      final width = image.naturalWidth;
      final height = image.naturalHeight;
      if (width <= 0 || height <= 0) {
        throw StateError('Neuspjela konverzija slike.');
      }

      final canvas = html.CanvasElement(width: width, height: height);
      final context = canvas.context2D;
      context.drawImageScaled(image, 0, 0, width.toDouble(), height.toDouble());

      final blob = await canvas.toBlob('image/jpeg', 0.92);
      return _readBlobAsBytes(blob);
    } finally {
      html.Url.revokeObjectUrl(objectUrl);
    }
  }

  Future<Uint8List> _readBlobAsBytes(html.Blob blob) async {
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();

    StreamSubscription<html.ProgressEvent>? loadSub;
    StreamSubscription<html.ProgressEvent>? errorSub;

    loadSub = reader.onLoadEnd.listen((_) {
      try {
        final result = reader.result;
        if (result is ByteBuffer) {
          if (!completer.isCompleted) {
            completer.complete(Uint8List.view(result));
          }
        } else {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('Neuspjelo čitanje odabrane datoteke.'),
            );
          }
        }
      } finally {
        loadSub?.cancel();
        errorSub?.cancel();
      }
    });

    errorSub = reader.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Neuspjelo čitanje odabrane datoteke.'),
        );
      }
      loadSub?.cancel();
      errorSub?.cancel();
    });

    reader.readAsArrayBuffer(blob);
    final bytes = await completer.future;
    if (bytes.isEmpty) {
      throw StateError('Odabrana datoteka je prazna.');
    }
    return bytes;
  }
}

DocumentImageSourceAdapter createDocumentImageSourceAdapterImpl() {
  return DocumentImageSourceAdapterWeb();
}
