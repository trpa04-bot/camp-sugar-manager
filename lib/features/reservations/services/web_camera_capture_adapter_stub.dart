import 'package:flutter/widgets.dart';

import 'web_camera_capture_adapter.dart';

class WebCameraCaptureAdapterStub implements WebCameraCaptureAdapter {
  @override
  bool get isSupported => false;

  @override
  bool get isSecureContext => false;

  @override
  Widget buildPreview() {
    return const SizedBox.shrink();
  }

  @override
  Future<List<WebCameraDevice>> listVideoDevices() async {
    return const <WebCameraDevice>[];
  }

  @override
  Future<void> start({String? deviceId}) async {
    throw const WebCameraException(
      WebCameraErrorCode.unsupported,
      'Skeniranje kamerom nije podržano u ovom pregledniku. Odaberite fotografiju.',
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<WebCameraCaptureFrame> captureFrame() async {
    throw const WebCameraException(
      WebCameraErrorCode.unsupported,
      'Skeniranje kamerom nije podržano u ovom pregledniku. Odaberite fotografiju.',
    );
  }

  @override
  Future<void> dispose() async {}
}

WebCameraCaptureAdapter createWebCameraCaptureAdapterImpl() {
  return WebCameraCaptureAdapterStub();
}
