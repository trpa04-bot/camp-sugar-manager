import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/web_camera_capture_adapter.dart';

Future<XFile?> showWebDocumentCameraCaptureDialog(
  BuildContext context, {
  required WebCameraCaptureAdapter adapter,
}) {
  return showDialog<XFile>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
          child: _WebDocumentCameraCaptureDialog(adapter: adapter),
        ),
      );
    },
  );
}

class _WebDocumentCameraCaptureDialog extends StatefulWidget {
  const _WebDocumentCameraCaptureDialog({required this.adapter});

  final WebCameraCaptureAdapter adapter;

  @override
  State<_WebDocumentCameraCaptureDialog> createState() =>
      _WebDocumentCameraCaptureDialogState();
}

class _WebDocumentCameraCaptureDialogState
    extends State<_WebDocumentCameraCaptureDialog> {
  List<WebCameraDevice> _devices = const <WebCameraDevice>[];
  String? _selectedDeviceId;
  WebCameraCaptureFrame? _capturedFrame;
  bool _isLoading = true;
  bool _isCapturing = false;
  bool _isStarting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    widget.adapter.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (!widget.adapter.isSupported) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Skeniranje kamerom nije podržano u ovom pregledniku. Odaberite fotografiju.';
      });
      return;
    }

    if (!widget.adapter.isSecureContext) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Skeniranje kamerom radi samo preko sigurnog HTTPS pristupa ili localhosta.';
      });
      return;
    }

    try {
      final devices = await widget.adapter.listVideoDevices();
      String? initialDevice;
      if (devices.isNotEmpty) {
        initialDevice = devices.first.deviceId;
      }

      await widget.adapter.start(deviceId: initialDevice);
      if (!mounted) {
        return;
      }

      setState(() {
        _devices = devices;
        _selectedDeviceId = initialDevice;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = _messageForError(error);
      });
    }
  }

  Future<void> _switchCamera(String? deviceId) async {
    if (deviceId == null || deviceId == _selectedDeviceId || _isStarting) {
      return;
    }

    setState(() {
      _isStarting = true;
      _errorMessage = null;
      _capturedFrame = null;
    });

    try {
      await widget.adapter.start(deviceId: deviceId);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedDeviceId = deviceId;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _messageForError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_isCapturing || _isStarting) {
      return;
    }

    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });

    try {
      final frame = await widget.adapter.captureFrame();
      await widget.adapter.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _capturedFrame = frame;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _messageForError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _retake() async {
    setState(() {
      _capturedFrame = null;
      _errorMessage = null;
      _isStarting = true;
    });
    try {
      await widget.adapter.start(deviceId: _selectedDeviceId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = _messageForError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  String _messageForError(Object error) {
    if (error is WebCameraException) {
      return error.message;
    }
    return 'Dogodila se nepoznata greška pri pristupu kameri.';
  }

  @override
  Widget build(BuildContext context) {
    final frame = _capturedFrame;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Skeniranje dokumenta',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Odustani',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Postavite cijeli dokument unutar okvira'),
          const SizedBox(height: 12),
          if (_devices.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedDeviceId,
                onChanged: _isStarting ? null : _switchCamera,
                decoration: const InputDecoration(labelText: 'Odaberi kameru'),
                items: _devices
                    .map(
                      (device) => DropdownMenuItem<String>(
                        value: device.deviceId,
                        child: Text(device.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : frame != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(frame.bytes, fit: BoxFit.contain),
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.all(10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${frame.width}x${frame.height}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.adapter.buildPreview(),
                        Center(
                          child: IgnorePointer(
                            child: Container(
                              width: 360,
                              height: 240,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white70,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Odustani'),
              ),
              if (frame == null)
                FilledButton.icon(
                  onPressed: (_isLoading || _isStarting || _isCapturing)
                      ? null
                      : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Fotografiraj'),
                )
              else ...[
                OutlinedButton(
                  onPressed: _isStarting ? null : _retake,
                  child: const Text('Ponovi'),
                ),
                FilledButton(
                  onPressed: () {
                    final selectedFrame = _capturedFrame;
                    if (selectedFrame == null) {
                      return;
                    }
                    final name =
                        'document_${DateTime.now().millisecondsSinceEpoch}.jpg';
                    Navigator.of(
                      context,
                    ).pop(selectedFrame.toXFile(name: name));
                  },
                  child: const Text('Koristi fotografiju'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
