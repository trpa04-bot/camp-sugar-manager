import 'document_ocr_service_stub.dart'
    if (dart.library.io) 'document_ocr_service_io.dart'
    as impl;
import 'package:image_picker/image_picker.dart';

String? _normalizeOcrText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Future<String?> recognizeDocumentText(XFile file) => impl
    .recognizeDocumentText(file)
    .then((value) => _normalizeOcrText(value ?? ''));
