import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../models/document_image.dart';
import '../models/document_upload_diagnostics.dart';
import '../models/reservation_document_scan_context.dart';

class DocumentScanUploadResult {
  const DocumentScanUploadResult({
    required this.bytes,
    required this.fileName,
    required this.downloadUrl,
    required this.storagePath,
  });

  final Uint8List bytes;
  final String fileName;
  final String downloadUrl;
  final String storagePath;
}

class DocumentScanService {
  DocumentScanService({ImagePicker? imagePicker, FirebaseStorage? storage})
    : _imagePicker = imagePicker ?? ImagePicker(),
      _storage = storage ?? FirebaseStorage.instance;

  static const String _expectedBucket =
      'camp-sugar-manager.firebasestorage.app';

  final ImagePicker _imagePicker;
  final FirebaseStorage _storage;

  Future<XFile?> pickGalleryImage() {
    return _imagePicker.pickImage(source: ImageSource.gallery);
  }

  Future<XFile?> pickCameraImage() {
    return _imagePicker.pickImage(source: ImageSource.camera);
  }

  bool isSupportedImageFile(XFile file) {
    final lowerName = file.name.toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png');
  }

  DocumentUploadDiagnostics buildDiagnostics({
    required ReservationDocumentScanContext reservation,
    required String guestId,
    required XFile file,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final app = Firebase.app();
    final bucket = app.options.storageBucket;
    final fileName = p.basename(file.name).trim();

    return DocumentUploadDiagnostics(
      authenticated: currentUser != null,
      uidPresent: currentUser?.uid.trim().isNotEmpty ?? false,
      storageBucket: bucket == null || bucket.trim().isEmpty
          ? '(null)'
          : bucket,
      reservationIdPresent: reservation.reservationId.trim().isNotEmpty,
      guestIdPresent: guestId.trim().isNotEmpty,
      sanitizedPath: fileName.isEmpty
          ? 'reservations/[reservationId]/documents/[guestId]/[fileName]'
          : 'reservations/[reservationId]/documents/[guestId]/[fileName]',
    );
  }

  Future<DocumentScanUploadResult> uploadDocumentImage({
    required ReservationDocumentScanContext reservation,
    required String guestId,
    required String documentImageId,
    required DocumentSide documentSide,
    required XFile file,
    required Uint8List bytes,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError(
        'Korisnik nije prijavljen. Prijavi se ponovno i pokušaj opet.',
      );
    }

    final reservationId = reservation.reservationId.trim();
    final sanitizedGuestId = guestId.trim();
    final fileName = p.basename(file.name).trim();

    if (reservationId.isEmpty) {
      throw StateError('reservationId je prazan.');
    }
    if (sanitizedGuestId.isEmpty) {
      throw StateError('guestId je prazan.');
    }
    if (documentImageId.trim().isEmpty) {
      throw StateError('documentImageId je prazan.');
    }

    final storageBucket = _storage.app.options.storageBucket;
    if (storageBucket != _expectedBucket) {
      throw StateError('Firebase Storage bucket nije ispravan: $storageBucket');
    }

    await currentUser.getIdToken(true);

    final extension = _extensionFor(fileName);
    final generatedFileName = '$documentImageId.$extension';
    final storagePath =
        'reservations/$reservationId/documents/$sanitizedGuestId/$generatedFileName';
    debugPrint(
      'Uploading document to reservations/[reservationId]/documents/[guestId]/[fileName]',
    );

    final ref = _storage.ref().child(storagePath);
    final contentType = extension == 'png' ? 'image/png' : 'image/jpeg';

    final metadata = SettableMetadata(
      contentType: contentType,
      customMetadata: {
        'reservationId': reservationId,
        'guestId': sanitizedGuestId,
        'documentSide': documentSide.apiValue,
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    final uploadTask = ref.putData(bytes, metadata);
    await uploadTask;
    final downloadUrl = await ref.getDownloadURL();
    return DocumentScanUploadResult(
      bytes: bytes,
      fileName: generatedFileName,
      downloadUrl: downloadUrl,
      storagePath: storagePath,
    );
  }

  Future<void> deleteDocumentImage(String storagePath) {
    return _storage.ref().child(storagePath).delete();
  }

  String _extensionFor(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'png';
    }
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'jpg';
    }
    throw StateError('Podržani su samo JPG, JPEG i PNG.');
  }
}
