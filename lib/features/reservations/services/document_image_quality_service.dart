import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/document_scan_quality.dart';

class DocumentImageQualityService {
  const DocumentImageQualityService();

  Future<DocumentScanQualityReport> analyze(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const DocumentScanQualityReport(
        width: 0,
        height: 0,
        blurScore: 0,
        brightnessMean: 0,
        contrastStdDev: 0,
        glareRatio: 0,
        documentCoverage: 0,
        issues: [
          DocumentScanQualityIssue(
            code: DocumentScanQualityIssueCodes.decodeFailed,
            message: 'Fotografija nije valjana ili je oštećena.',
            blocking: true,
            recommendation: 'Snimite fotografiju ponovno i pokušajte opet.',
          ),
        ],
      );
    }

    final width = decoded.width;
    final height = decoded.height;
    final totalPixels = width * height;
    final sampleStep = totalPixels > 3000000 ? 3 : 2;

    final borderMean = _computeBorderMean(decoded, sampleStep);
    final blurScore = _computeLaplacianVariance(decoded, sampleStep);
    final brightnessMean = _computeBrightnessMean(decoded, sampleStep);
    final contrastStdDev = _computeContrastStdDev(
      decoded,
      brightnessMean,
      sampleStep,
    );
    final glareRatio = _computeGlareRatio(decoded, sampleStep);
    final documentCoverage = _computeDocumentCoverage(
      decoded,
      borderMean,
      sampleStep,
    );
    final skewAngleDegrees = _computeSkewAngle(decoded, borderMean, sampleStep);

    final issues = <DocumentScanQualityIssue>[];

    if (width < 900 || height < 600) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.lowResolution,
          message: 'Fotografija ima prenisku rezoluciju.',
          blocking: true,
          recommendation: 'Približite dokument i snimite oštriju fotografiju.',
        ),
      );
    }

    if (blurScore < 45) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.blur,
          message: 'Fotografija je previše zamućena.',
          blocking: true,
          recommendation:
              'Držite uređaj mirno i fokusirajte tekst prije snimanja.',
        ),
      );
    }

    if (brightnessMean < 45) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.tooDark,
          message: 'Fotografija je pretamna za pouzdan OCR.',
          blocking: true,
          recommendation:
              'Pojačajte osvjetljenje i izbjegnite sjene preko dokumenta.',
        ),
      );
    }

    if (glareRatio > 0.2) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.glare,
          message: 'Fotografija ima prejaki odsjaj.',
          blocking: true,
          recommendation:
              'Promijenite kut snimanja i izbjegnite refleksiju svjetla.',
        ),
      );
    }

    if (brightnessMean > 220) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.overexposed,
          message: 'Fotografija je presvijetla za pouzdan OCR.',
          blocking: true,
          recommendation: 'Smanjite ekspoziciju i izbjegnite direktno svjetlo.',
        ),
      );
    }

    if (skewAngleDegrees.abs() > 15) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.skewed,
          message: 'Dokument je previše nakošen u kadru.',
          blocking: true,
          recommendation:
              'Poravnajte dokument s rubovima kamere i pokušajte ponovno.',
        ),
      );
    }

    if (contrastStdDev < 25) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.lowContrast,
          message: 'Kontrast je slab pa je tekst teško čitljiv.',
          blocking: false,
          recommendation:
              'Snimite na ravnoj podlozi s boljim kontrastom pozadine.',
        ),
      );
    }

    if (documentCoverage < 0.18) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.documentCutOff,
          message: 'Dokument nije dovoljno obuhvaćen na fotografiji.',
          blocking: true,
          recommendation:
              'Snimite cijeli dokument unutar kadra, bez rezanja rubova.',
        ),
      );
    } else if (documentCoverage < 0.28) {
      issues.add(
        const DocumentScanQualityIssue(
          code: DocumentScanQualityIssueCodes.documentFar,
          message: 'Dokument je premalen u kadru.',
          blocking: false,
          recommendation: 'Približite dokument kameri da tekst bude veći.',
        ),
      );
    }

    return DocumentScanQualityReport(
      width: width,
      height: height,
      blurScore: blurScore,
      brightnessMean: brightnessMean,
      contrastStdDev: contrastStdDev,
      glareRatio: glareRatio,
      documentCoverage: documentCoverage,
      issues: issues,
    );
  }

  double _computeBrightnessMean(img.Image image, int step) {
    var sum = 0.0;
    var count = 0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        sum += _luminance(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        count += 1;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  double _computeContrastStdDev(img.Image image, double mean, int step) {
    var varianceSum = 0.0;
    var count = 0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final lum = _luminance(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        final delta = lum - mean;
        varianceSum += delta * delta;
        count += 1;
      }
    }
    if (count == 0) return 0;
    return math.sqrt(varianceSum / count);
  }

  double _computeLaplacianVariance(img.Image image, int step) {
    final width = image.width;
    final height = image.height;
    if (width < 3 || height < 3) return 0;

    var sum = 0.0;
    var sumSquares = 0.0;
    var count = 0;

    for (var y = 1; y < height - 1; y += step) {
      for (var x = 1; x < width - 1; x += step) {
        final c = image.getPixel(x, y);
        final l = image.getPixel(x - 1, y);
        final r = image.getPixel(x + 1, y);
        final u = image.getPixel(x, y - 1);
        final d = image.getPixel(x, y + 1);

        final cLum = _luminance(c.r.toDouble(), c.g.toDouble(), c.b.toDouble());
        final lLum = _luminance(l.r.toDouble(), l.g.toDouble(), l.b.toDouble());
        final rLum = _luminance(r.r.toDouble(), r.g.toDouble(), r.b.toDouble());
        final uLum = _luminance(u.r.toDouble(), u.g.toDouble(), u.b.toDouble());
        final dLum = _luminance(d.r.toDouble(), d.g.toDouble(), d.b.toDouble());

        final lap = (4 * cLum) - lLum - rLum - uLum - dLum;
        sum += lap;
        sumSquares += lap * lap;
        count += 1;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    return (sumSquares / count) - (mean * mean);
  }

  double _computeGlareRatio(img.Image image, int step) {
    var bright = 0;
    var count = 0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final lum = _luminance(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        if (lum > 245) bright += 1;
        count += 1;
      }
    }
    return count == 0 ? 0 : bright / count;
  }

  double _computeBorderMean(img.Image image, int step) {
    var sum = 0.0;
    var count = 0;
    for (var x = 0; x < image.width; x += step) {
      final top = image.getPixel(x, 0);
      final bottom = image.getPixel(x, image.height - 1);
      sum += _luminance(top.r.toDouble(), top.g.toDouble(), top.b.toDouble());
      sum += _luminance(
        bottom.r.toDouble(),
        bottom.g.toDouble(),
        bottom.b.toDouble(),
      );
      count += 2;
    }
    for (var y = 0; y < image.height; y += step) {
      final left = image.getPixel(0, y);
      final right = image.getPixel(image.width - 1, y);
      sum += _luminance(
        left.r.toDouble(),
        left.g.toDouble(),
        left.b.toDouble(),
      );
      sum += _luminance(
        right.r.toDouble(),
        right.g.toDouble(),
        right.b.toDouble(),
      );
      count += 2;
    }
    return count == 0 ? 127 : sum / count;
  }

  double _computeDocumentCoverage(
    img.Image image,
    double borderMean,
    int step,
  ) {
    var foreground = 0;
    var total = 0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final lum = _luminance(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        if ((lum - borderMean).abs() > 28) {
          foreground += 1;
        }
        total += 1;
      }
    }
    return total == 0 ? 0 : foreground / total;
  }

  double _computeSkewAngle(img.Image image, double borderMean, int step) {
    var total = 0;
    var sumX = 0.0;
    var sumY = 0.0;

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final lum = _luminance(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        if ((lum - borderMean).abs() > 28) {
          total += 1;
          sumX += x;
          sumY += y;
        }
      }
    }

    if (total < 40) {
      return 0;
    }

    final cx = sumX / total;
    final cy = sumY / total;
    var sxx = 0.0;
    var syy = 0.0;
    var sxy = 0.0;

    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final lum = _luminance(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        if ((lum - borderMean).abs() > 28) {
          final dx = x - cx;
          final dy = y - cy;
          sxx += dx * dx;
          syy += dy * dy;
          sxy += dx * dy;
        }
      }
    }

    if (sxx == 0 && syy == 0) {
      return 0;
    }

    final angle = 0.5 * math.atan2(2 * sxy, (sxx - syy));
    return angle * (180 / math.pi);
  }

  double _luminance(double r, double g, double b) {
    return (0.2126 * r) + (0.7152 * g) + (0.0722 * b);
  }
}
