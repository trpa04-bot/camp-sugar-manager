import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../models/reservation_guest.dart';
import '../services/mrz_scanner_service.dart';
import 'mrz_review_dialog.dart';

Future<void> showMrzScannerSheet(
  BuildContext context, {
  required Reservation reservation,
  required Future<void> Function(ReservationGuest guest, bool checksPassed)
  onSaveConfirmed,
  ReservationGuest? initialGuest,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.95,
        child: _MrzScannerSheet(
          reservation: reservation,
          onSaveConfirmed: onSaveConfirmed,
          initialGuest: initialGuest,
        ),
      );
    },
  );
}

class _MrzScannerSheet extends StatefulWidget {
  const _MrzScannerSheet({
    required this.reservation,
    required this.onSaveConfirmed,
    this.initialGuest,
  });

  final Reservation reservation;
  final Future<void> Function(ReservationGuest guest, bool checksPassed)
  onSaveConfirmed;
  final ReservationGuest? initialGuest;

  @override
  State<_MrzScannerSheet> createState() => _MrzScannerSheetState();
}

class _MrzScannerSheetState extends State<_MrzScannerSheet> {
  final MrzScannerService _scannerService = MrzScannerService();
  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isInitializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Kamera nije dostupna: $error';
        _isInitializing = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _scannerService.dispose();
    super.dispose();
  }

  Future<void> _captureAndScan() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }
    setState(() {
      _isCapturing = true;
      _errorMessage = null;
    });
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      final scanResult = await _scannerService.scanCapturedBytes(bytes);
      if (!mounted) return;
      final review = await showMrzReviewDialog(
        context,
        reservation: widget.reservation,
        scanResult: scanResult,
        initialGuest: widget.initialGuest,
      );
      if (review == null) return;
      await widget.onSaveConfirmed(
        review.guest,
        review.scanResult.allChecksPassed,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cameraController == null) {
      return Center(child: Text(_errorMessage ?? 'Kamera nije dostupna.'));
    }

    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_cameraController!)),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _MrzOverlayPainter()),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isCapturing ? null : _captureAndScan,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_isCapturing ? 'Skeniranje...' : 'Snimi MRZ zonu'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MrzOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final borderPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.68,
      size.width * 0.84,
      size.height * 0.18,
    );
    canvas.drawRect(Offset.zero & size, overlayPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      borderPaint,
    );

    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Poravnaj donji MRZ dio dokumenta unutar okvira',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.9);
    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, rect.top - 34),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
