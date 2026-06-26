// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

import 'web_camera_capture_adapter.dart';

class WebCameraCaptureAdapterWeb implements WebCameraCaptureAdapter {
  WebCameraCaptureAdapterWeb()
    : _viewType = 'document-camera-${DateTime.now().microsecondsSinceEpoch}' {
    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.backgroundColor = '#111';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _video;
    });
  }

  final String _viewType;
  late final html.VideoElement _video;
  html.MediaStream? _stream;
  bool _starting = false;

  @override
  bool get isSupported => html.window.navigator.mediaDevices != null;

  @override
  bool get isSecureContext => html.window.isSecureContext ?? false;

  @override
  Widget buildPreview() {
    return HtmlElementView(viewType: _viewType);
  }

  @override
  Future<List<WebCameraDevice>> listVideoDevices() async {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      return const <WebCameraDevice>[];
    }

    final devices = await mediaDevices.enumerateDevices();
    final cameras = devices
        .where((device) => device.kind == 'videoinput')
        .map(
          (device) => WebCameraDevice(
            deviceId: device.deviceId,
            label: device.label.isEmpty ? 'Kamera' : device.label,
          ),
        )
        .toList(growable: false);
    return cameras;
  }

  @override
  Future<void> start({String? deviceId}) async {
    if (_starting) {
      return;
    }
    _starting = true;
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw const WebCameraException(
          WebCameraErrorCode.unsupported,
          'Skeniranje kamerom nije podržano u ovom pregledniku. Odaberite fotografiju.',
        );
      }

      await stop();

      final constraints = _buildConstraints(deviceId: deviceId);
      try {
        final stream = await mediaDevices.getUserMedia(constraints);
        _stream = stream;
        _video.srcObject = stream;
      } catch (error) {
        if (deviceId != null && deviceId.trim().isNotEmpty) {
          final fallbackConstraints = _buildConstraints(deviceId: null);
          final stream = await mediaDevices.getUserMedia(fallbackConstraints);
          _stream = stream;
          _video.srcObject = stream;
        } else {
          rethrow;
        }
      }
    } on html.DomException catch (error) {
      throw _mapDomException(error);
    } catch (error) {
      if (error is WebCameraException) {
        rethrow;
      }
      throw const WebCameraException(
        WebCameraErrorCode.unknown,
        'Dogodila se nepoznata greška pri pristupu kameri.',
      );
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    final stream = _stream;
    if (stream != null) {
      final tracks = stream.getTracks();
      for (final track in tracks) {
        track.stop();
      }
    }
    _video.srcObject = null;
    _stream = null;
  }

  @override
  Future<WebCameraCaptureFrame> captureFrame() async {
    if (_stream == null) {
      throw const WebCameraException(
        WebCameraErrorCode.notReadable,
        'Kameru trenutno koristi druga aplikacija.',
      );
    }

    final width = _video.videoWidth;
    final height = _video.videoHeight;
    if (width <= 0 || height <= 0) {
      throw const WebCameraException(
        WebCameraErrorCode.unknown,
        'Nije moguće snimiti fotografiju iz kamere.',
      );
    }

    final canvas = html.CanvasElement(width: width, height: height);
    final context = canvas.context2D;
    context.drawImageScaled(_video, 0, 0, width.toDouble(), height.toDouble());

    final blob = await _canvasToBlob(canvas, 'image/jpeg', 0.92);
    if (blob == null) {
      throw const WebCameraException(
        WebCameraErrorCode.unknown,
        'Nije moguće snimiti fotografiju iz kamere.',
      );
    }

    final bytes = await _blobToBytes(blob);
    return WebCameraCaptureFrame(
      bytes: bytes,
      mimeType: blob.type.isNotEmpty ? blob.type : 'image/jpeg',
      width: width,
      height: height,
    );
  }

  @override
  Future<void> dispose() {
    return stop();
  }

  Map<String, dynamic> _buildConstraints({String? deviceId}) {
    final video = <String, dynamic>{
      'width': <String, dynamic>{'ideal': 1920},
      'height': <String, dynamic>{'ideal': 1080},
      'facingMode': <String, dynamic>{'ideal': 'environment'},
    };
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      video['deviceId'] = <String, dynamic>{'exact': deviceId.trim()};
    }

    return <String, dynamic>{'video': video, 'audio': false};
  }

  Future<html.Blob?> _canvasToBlob(
    html.CanvasElement canvas,
    String mimeType,
    double quality,
  ) {
    return canvas.toBlob(mimeType, quality);
  }

  Future<Uint8List> _blobToBytes(html.Blob blob) async {
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
              StateError('Neuspjelo čitanje snimljene fotografije.'),
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
          StateError('Neuspjelo čitanje snimljene fotografije.'),
        );
      }
      loadSub?.cancel();
      errorSub?.cancel();
    });

    reader.readAsArrayBuffer(blob);
    return completer.future;
  }

  WebCameraException _mapDomException(html.DomException error) {
    switch (error.name) {
      case 'NotAllowedError':
        return const WebCameraException(
          WebCameraErrorCode.notAllowed,
          'Pristup kameri je odbijen. Omogućite kameru u postavkama preglednika ili odaberite fotografiju.',
        );
      case 'NotFoundError':
        return const WebCameraException(
          WebCameraErrorCode.notFound,
          'Kamera nije pronađena.',
        );
      case 'NotReadableError':
        return const WebCameraException(
          WebCameraErrorCode.notReadable,
          'Kameru trenutno koristi druga aplikacija.',
        );
      case 'OverconstrainedError':
        return const WebCameraException(
          WebCameraErrorCode.overconstrained,
          'Odabrani način snimanja nije dostupan. Pokušajte s drugom kamerom.',
        );
      case 'SecurityError':
        return const WebCameraException(
          WebCameraErrorCode.security,
          'Za skeniranje dokumenta dopustite pristup kameri.',
        );
      case 'AbortError':
        return const WebCameraException(
          WebCameraErrorCode.abort,
          'Snimanje je prekinuto. Pokušajte ponovno.',
        );
      default:
        return const WebCameraException(
          WebCameraErrorCode.unknown,
          'Dogodila se nepoznata greška pri pristupu kameri.',
        );
    }
  }
}

WebCameraCaptureAdapter createWebCameraCaptureAdapterImpl() {
  return WebCameraCaptureAdapterWeb();
}
