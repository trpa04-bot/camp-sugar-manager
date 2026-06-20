import 'package:cloud_functions/cloud_functions.dart';

import '../models/document_image.dart';
import '../models/document_ocr_result.dart';

class DocumentOcrCloudService {
  DocumentOcrCloudService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  final FirebaseFunctions _functions;

  Future<DocumentOcrResult> processDocument({
    required String storagePath,
  }) async {
    return processDocuments(
      reservationId: '',
      guestId: '',
      images: const <DocumentImage>[],
      legacyStoragePath: storagePath,
    );
  }

  Future<DocumentOcrResult> processDocuments({
    required String reservationId,
    required String guestId,
    required List<DocumentImage> images,
    String? legacyStoragePath,
  }) async {
    final callable = _functions.httpsCallable('processDocumentOcrCallable');
    final payload = <String, dynamic>{
      'reservationId': reservationId,
      'guestId': guestId,
      'images': images
          .map(
            (image) => <String, dynamic>{
              'imageId': image.id,
              'storagePath': image.storagePath,
              'documentSide': image.documentSide.apiValue,
            },
          )
          .toList(growable: false),
    };
    if (legacyStoragePath != null && legacyStoragePath.trim().isNotEmpty) {
      payload['storagePath'] = legacyStoragePath.trim();
    }

    final response = await callable.call(payload);

    final data = response.data;
    if (data is! Map) {
      throw StateError('OCR odgovor nije ispravnog formata.');
    }

    return DocumentOcrResult.fromMap(data.cast<String, dynamic>());
  }
}
