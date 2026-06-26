import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

class VehicleImageUploadResult {
  const VehicleImageUploadResult({
    required this.bytes,
    required this.downloadUrl,
    required this.storagePath,
  });

  final Uint8List bytes;
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
    final mimeType = (file.mimeType ?? '').toLowerCase();
    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.heic') ||
        lowerName.endsWith('.heif') ||
        mimeType == 'image/jpeg' ||
        mimeType == 'image/jpg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/heic' ||
        mimeType == 'image/heif';
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

    final extension = _extensionFor(fileName, file.mimeType);
    final generatedFileName = '$documentImageId.$extension';
    final storagePath =
        'reservations/$reservationId/documents/$sanitizedGuestId/$generatedFileName';
    debugPrint(
      'Uploading document to reservations/[reservationId]/documents/[guestId]/[fileName]',
    );

    final ref = _storage.ref().child(storagePath);
    final contentType = switch (extension) {
      'png' => 'image/png',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };

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

  Future<VehicleImageUploadResult> uploadVehicleImage({
    required String reservationId,
    required XFile file,
    int maxBytes = 100 * 1024,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw StateError(
        'Korisnik nije prijavljen. Prijavi se ponovno i pokušaj opet.',
      );
    }

    final trimmedReservationId = reservationId.trim();
    if (trimmedReservationId.isEmpty) {
      throw StateError('reservationId je prazan.');
    }

    if (!isSupportedImageFile(file)) {
      throw StateError('Podržani su samo JPG, JPEG i PNG.');
    }

    final rawBytes = await file.readAsBytes();
    final compressedBytes = _compressVehicleImage(rawBytes, maxBytes: maxBytes);

    final storagePath =
        'reservations/$trimmedReservationId/vehicle/current.jpg';
    final ref = _storage.ref().child(storagePath);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {
        'reservationId': trimmedReservationId,
        'imageType': 'vehicle',
        'uploadedAt': DateTime.now().toUtc().toIso8601String(),
      },
    );

    await ref.putData(compressedBytes, metadata);
    final downloadUrl = await ref.getDownloadURL();

    return VehicleImageUploadResult(
      bytes: compressedBytes,
      downloadUrl: downloadUrl,
      storagePath: storagePath,
    );
  }

  Uint8List _compressVehicleImage(Uint8List bytes, {required int maxBytes}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Ne mogu obraditi sliku vozila.');
    }

    var working = decoded;
    final longestSide = working.width > working.height
        ? working.width
        : working.height;
    if (longestSide > 1600) {
      final ratio = 1600 / longestSide;
      final width = (working.width * ratio).round();
      final height = (working.height * ratio).round();
      working = img.copyResize(working, width: width, height: height);
    }

    var quality = 88;
    var output = Uint8List.fromList(img.encodeJpg(working, quality: quality));

    while (output.lengthInBytes > maxBytes && quality > 25) {
      quality -= 7;
      output = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }

    while (output.lengthInBytes > maxBytes &&
        (working.width > 360 || working.height > 360)) {
      final width = (working.width * 0.9).round();
      final height = (working.height * 0.9).round();
      working = img.copyResize(
        working,
        width: width < 320 ? 320 : width,
        height: height < 320 ? 320 : height,
      );
      output = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    }

    if (output.lengthInBytes > maxBytes) {
      throw StateError(
        'Slika je prevelika i nakon kompresije. Pokušaj s manjom slikom.',
      );
    }

    return output;
  }

  String _extensionFor(String fileName, String? mimeType) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'png';
    }
    if (lowerName.endsWith('.heic')) {
      return 'heic';
    }
    if (lowerName.endsWith('.heif')) {
      return 'heif';
    }
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'jpg';
    }
    final normalizedMime = (mimeType ?? '').toLowerCase();
    if (normalizedMime == 'image/png') {
      return 'png';
    }
    if (normalizedMime == 'image/heic') {
      return 'heic';
    }
    if (normalizedMime == 'image/heif') {
      return 'heif';
    }
    if (normalizedMime == 'image/jpeg' || normalizedMime == 'image/jpg') {
      return 'jpg';
    }
    throw StateError('Podržani su JPG, JPEG, PNG, HEIC i HEIF.');
  }
}
