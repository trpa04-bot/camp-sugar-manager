import 'package:image_picker/image_picker.dart';

import 'document_image_source_adapter.dart';

class DocumentImageSourceAdapterStub implements DocumentImageSourceAdapter {
  DocumentImageSourceAdapterStub({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  @override
  bool get isWeb => false;

  @override
  bool get isMobileWeb => false;

  @override
  bool get supportsWebCamera => false;

  @override
  Future<XFile?> captureFromMobileCamera() {
    return _imagePicker.pickImage(source: ImageSource.camera);
  }

  @override
  Future<XFile?> captureFromWebCamera() async {
    return null;
  }

  @override
  Future<XFile?> pickFromGallery() {
    return _imagePicker.pickImage(source: ImageSource.gallery);
  }

  @override
  Future<XFile?> pickFromFile() {
    return _imagePicker.pickImage(source: ImageSource.gallery);
  }
}

DocumentImageSourceAdapter createDocumentImageSourceAdapterImpl() {
  return DocumentImageSourceAdapterStub();
}
