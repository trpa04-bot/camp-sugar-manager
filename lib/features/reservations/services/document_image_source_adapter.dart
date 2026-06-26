import 'package:image_picker/image_picker.dart';

import 'document_image_source_adapter_stub.dart'
    if (dart.library.html) 'document_image_source_adapter_web.dart';

enum DocumentImageSourceKind { scan, gallery, file }

abstract class DocumentImageSourceAdapter {
  bool get isWeb;

  bool get isMobileWeb;

  bool get supportsWebCamera;

  Future<XFile?> captureFromMobileCamera();

  Future<XFile?> captureFromWebCamera();

  Future<XFile?> pickFromGallery();

  Future<XFile?> pickFromFile();
}

DocumentImageSourceAdapter createDocumentImageSourceAdapter() {
  return createDocumentImageSourceAdapterImpl();
}
