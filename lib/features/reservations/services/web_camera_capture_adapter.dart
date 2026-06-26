import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'web_camera_capture_adapter_stub.dart'
    if (dart.library.html) 'web_camera_capture_adapter_web.dart';

enum WebCameraErrorCode {
  notAllowed,
  notFound,
  notReadable,
  overconstrained,
  security,
  abort,
  unsupported,
  unknown,
}

class WebCameraException implements Exception {
  const WebCameraException(this.code, this.message);

  final WebCameraErrorCode code;
  final String message;

  @override
  String toString() => message;
}

class WebCameraDevice {
  const WebCameraDevice({required this.deviceId, required this.label});

  final String deviceId;
  final String label;
}

class WebCameraCaptureFrame {
  const WebCameraCaptureFrame({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  XFile toXFile({String? name}) {
    return XFile.fromData(
      bytes,
      name: name ?? 'captured_document.jpg',
      mimeType: mimeType,
    );
  }
}

abstract class WebCameraCaptureAdapter {
  bool get isSupported;

  bool get isSecureContext;

  Widget buildPreview();

  Future<List<WebCameraDevice>> listVideoDevices();

  Future<void> start({String? deviceId});

  Future<void> stop();

  Future<WebCameraCaptureFrame> captureFrame();

  Future<void> dispose();
}

WebCameraCaptureAdapter createWebCameraCaptureAdapter() {
  return createWebCameraCaptureAdapterImpl();
}
