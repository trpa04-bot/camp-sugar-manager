import 'dart:typed_data';

import 'package:camp_sugar_manager/features/reservations/models/document_scan_quality.dart';
import 'package:camp_sugar_manager/features/reservations/services/document_image_quality_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const service = DocumentImageQualityService();

  Uint8List encodePng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  test('blocks low resolution image', () async {
    final small = img.Image(width: 320, height: 220);
    img.fill(small, color: img.ColorRgb8(120, 120, 120));

    final report = await service.analyze(encodePng(small));

    expect(report.hasBlockingIssues, isTrue);
    expect(
      report.issues.any(
        (issue) => issue.code == DocumentScanQualityIssueCodes.lowResolution,
      ),
      isTrue,
    );
  });

  test('blocks overexposed image', () async {
    final bright = img.Image(width: 1200, height: 800);
    img.fill(bright, color: img.ColorRgb8(255, 255, 255));

    final report = await service.analyze(encodePng(bright));

    expect(report.hasBlockingIssues, isTrue);
    expect(
      report.issues.any(
        (issue) => issue.code == DocumentScanQualityIssueCodes.overexposed,
      ),
      isTrue,
    );
  });

  test('accepts synthetic readable document-like image', () async {
    final base = img.Image(width: 1400, height: 900);
    img.fill(base, color: img.ColorRgb8(200, 205, 210));

    img.fillRect(
      base,
      x1: 220,
      y1: 160,
      x2: 1180,
      y2: 740,
      color: img.ColorRgb8(245, 245, 242),
    );

    for (var y = 220; y <= 680; y += 32) {
      img.drawLine(
        base,
        x1: 280,
        y1: y,
        x2: 1100,
        y2: y,
        color: img.ColorRgb8(35, 35, 35),
        thickness: 3,
      );
    }

    final report = await service.analyze(encodePng(base));

    expect(report.acceptable, isTrue);
  });
}
