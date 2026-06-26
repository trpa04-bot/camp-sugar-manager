import 'dart:typed_data';

import 'package:camp_sugar_manager/features/reservations/services/web_camera_capture_adapter.dart';
import 'package:camp_sugar_manager/features/reservations/widgets/web_document_camera_capture_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FakeWebCameraAdapter implements WebCameraCaptureAdapter {
  _FakeWebCameraAdapter({
    required this.isSupported,
    required this.isSecureContext,
    this.startError,
    this.devices = const <WebCameraDevice>[],
  });

  @override
  final bool isSupported;

  @override
  final bool isSecureContext;

  final Object? startError;
  final List<WebCameraDevice> devices;

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<List<WebCameraDevice>> listVideoDevices() async => devices;

  @override
  Future<void> start({String? deviceId}) async {
    startCalls += 1;
    if (startError != null) {
      throw startError!;
    }
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<WebCameraCaptureFrame> captureFrame() async {
    final image = img.Image(width: 1200, height: 800);
    img.fill(image, color: img.ColorRgb8(200, 200, 200));
    final encoded = Uint8List.fromList(img.encodeJpg(image));
    return WebCameraCaptureFrame(
      bytes: encoded,
      mimeType: 'image/jpeg',
      width: 1200,
      height: 800,
    );
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

void main() {
  testWidgets('shows unsupported browser fallback message', (tester) async {
    final adapter = _FakeWebCameraAdapter(
      isSupported: false,
      isSecureContext: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showWebDocumentCameraCaptureDialog(
                      context,
                      adapter: adapter,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Skeniranje kamerom nije podržano u ovom pregledniku. Odaberite fotografiju.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('permission denied maps to readable error message', (
    tester,
  ) async {
    final adapter = _FakeWebCameraAdapter(
      isSupported: true,
      isSecureContext: true,
      startError: const WebCameraException(
        WebCameraErrorCode.notAllowed,
        'Pristup kameri je odbijen. Omogućite kameru u postavkama preglednika ili odaberite fotografiju.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showWebDocumentCameraCaptureDialog(
                      context,
                      adapter: adapter,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Pristup kameri je odbijen. Omogućite kameru u postavkama preglednika ili odaberite fotografiju.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('capture, retake and dispose manage adapter lifecycle', (
    tester,
  ) async {
    final adapter = _FakeWebCameraAdapter(
      isSupported: true,
      isSecureContext: true,
      devices: const <WebCameraDevice>[
        WebCameraDevice(deviceId: 'cam-1', label: 'Front'),
        WebCameraDevice(deviceId: 'cam-2', label: 'External'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showWebDocumentCameraCaptureDialog(
                      context,
                      adapter: adapter,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(adapter.startCalls, 1);

    await tester.tap(find.text('Fotografiraj'));
    await tester.pumpAndSettle();

    expect(adapter.stopCalls, 1);

    await tester.tap(find.text('Ponovi'));
    await tester.pumpAndSettle();

    expect(adapter.startCalls, 2);

    await tester.tap(find.text('Odustani'));
    await tester.pumpAndSettle();

    expect(adapter.disposeCalls, 1);
  });
}
