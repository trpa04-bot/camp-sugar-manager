import 'package:cloud_firestore/cloud_firestore.dart';

enum GuestVerificationStatus { verified, pendingReview, rejected }

enum GuestVerificationMethod { ocrAuto, ocrManual, manual }

enum DocumentRetentionPolicy {
  deleteImmediately,
  deleteAfterCheckout,
  retainManually,
}

enum GuestStayStatus {
  upcoming,
  awaitingCheckIn,
  currentlyStaying,
  departed,
  cancelled,
}

String maskDocumentNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.length <= 4) {
    return trimmed;
  }
  return '${'*' * (trimmed.length - 4)}${trimmed.substring(trimmed.length - 4)}';
}

GuestVerificationStatus guestVerificationStatusFromString(String value) {
  return GuestVerificationStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => GuestVerificationStatus.verified,
  );
}

GuestVerificationMethod guestVerificationMethodFromString(String value) {
  return GuestVerificationMethod.values.firstWhere(
    (item) => item.name == value,
    orElse: () => GuestVerificationMethod.ocrManual,
  );
}

DocumentRetentionPolicy documentRetentionPolicyFromString(String value) {
  return DocumentRetentionPolicy.values.firstWhere(
    (item) => item.name == value,
    orElse: () => DocumentRetentionPolicy.deleteImmediately,
  );
}

class ReservationGuest {
  const ReservationGuest({
    required this.id,
    this.reservationId = '',
    this.pitchId = '',
    this.pitchName = '',
    required this.firstName,
    required this.lastName,
    this.dateOfBirth,
    required this.nationality,
    this.nationalityCode = '',
    this.nationalityDisplayName = '',
    required this.documentType,
    required this.documentNumber,
    this.maskedDocumentNumber = '',
    this.documentExpiryDate,
    required this.gender,
    this.issuingCountry = '',
    this.checkInDate,
    this.checkOutDate,
    required this.isPrimaryGuest,
    this.verificationStatus = GuestVerificationStatus.verified,
    this.verificationMethod = GuestVerificationMethod.ocrManual,
    this.documentAcceptanceStatus = 'accepted',
    this.manualReviewCompleted = false,
    required this.documentImagePath,
    this.documentImagePaths = const <String>[],
    this.retentionPolicy = DocumentRetentionPolicy.deleteImmediately,
    this.deleteAfterDate,
    this.cleanupPending = false,
    required this.ocrStatus,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String reservationId;
  final String pitchId;
  final String pitchName;
  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String nationality;
  final String nationalityCode;
  final String nationalityDisplayName;
  final String documentType;
  final String documentNumber;
  final String maskedDocumentNumber;
  final DateTime? documentExpiryDate;
  final String gender;
  final String issuingCountry;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final bool isPrimaryGuest;
  final GuestVerificationStatus verificationStatus;
  final GuestVerificationMethod verificationMethod;
  final String documentAcceptanceStatus;
  final bool manualReviewCompleted;
  final String documentImagePath;
  final List<String> documentImagePaths;
  final DocumentRetentionPolicy retentionPolicy;
  final DateTime? deleteAfterDate;
  final bool cleanupPending;
  final String ocrStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayDocumentNumber => maskedDocumentNumber.isNotEmpty
      ? maskedDocumentNumber
      : maskDocumentNumber(documentNumber);

  GuestStayStatus stayStatus({
    required String reservationStatus,
    DateTime? now,
  }) {
    final today = (now ?? DateTime.now());
    final checkIn = checkInDate;
    final checkOut = checkOutDate;
    if (reservationStatus == 'cancelled') {
      return GuestStayStatus.cancelled;
    }
    if (checkIn == null || checkOut == null) {
      return GuestStayStatus.upcoming;
    }

    final start = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final end = DateTime(checkOut.year, checkOut.month, checkOut.day);
    final current = DateTime(today.year, today.month, today.day);

    if (reservationStatus == 'checkedOut' || current.isAfter(end)) {
      return GuestStayStatus.departed;
    }

    final inStayWindow =
        (current.isAtSameMomentAs(start) || current.isAfter(start)) &&
        (current.isBefore(end) || current.isAtSameMomentAs(end));

    if (reservationStatus == 'checkedIn' && inStayWindow) {
      return GuestStayStatus.currentlyStaying;
    }

    if ((reservationStatus == 'inquiry' || reservationStatus == 'confirmed') &&
        inStayWindow) {
      return GuestStayStatus.awaitingCheckIn;
    }

    if (current.isAfter(end)) {
      return GuestStayStatus.departed;
    }

    return GuestStayStatus.upcoming;
  }

  factory ReservationGuest.empty() {
    return const ReservationGuest(
      id: '',
      reservationId: '',
      pitchId: '',
      pitchName: '',
      firstName: '',
      lastName: '',
      dateOfBirth: null,
      nationality: '',
      nationalityCode: '',
      nationalityDisplayName: '',
      documentType: '',
      documentNumber: '',
      maskedDocumentNumber: '',
      documentExpiryDate: null,
      gender: '',
      issuingCountry: '',
      checkInDate: null,
      checkOutDate: null,
      isPrimaryGuest: false,
      verificationStatus: GuestVerificationStatus.pendingReview,
      verificationMethod: GuestVerificationMethod.manual,
      documentAcceptanceStatus: 'manualOnly',
      manualReviewCompleted: false,
      documentImagePath: '',
      documentImagePaths: <String>[],
      retentionPolicy: DocumentRetentionPolicy.deleteImmediately,
      deleteAfterDate: null,
      cleanupPending: false,
      ocrStatus: 'pending',
    );
  }

  factory ReservationGuest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ReservationGuest(
      id: (data['id'] as String?) ?? doc.id,
      reservationId: (data['reservationId'] as String?) ?? '',
      pitchId: (data['pitchId'] as String?) ?? '',
      pitchName: (data['pitchName'] as String?) ?? '',
      firstName: (data['firstName'] as String?) ?? '',
      lastName: (data['lastName'] as String?) ?? '',
      dateOfBirth: _readDate(data['dateOfBirth']),
      nationality: (data['nationality'] as String?) ?? '',
      nationalityCode: (data['nationalityCode'] as String?) ?? '',
      nationalityDisplayName: (data['nationalityDisplayName'] as String?) ?? '',
      documentType: (data['documentType'] as String?) ?? '',
      documentNumber: (data['documentNumber'] as String?) ?? '',
      maskedDocumentNumber:
          (data['maskedDocumentNumber'] as String?) ??
          maskDocumentNumber((data['documentNumber'] as String?) ?? ''),
      documentExpiryDate: _readDate(data['documentExpiryDate']),
      gender: (data['gender'] as String?) ?? '',
      issuingCountry: (data['issuingCountry'] as String?) ?? '',
      checkInDate: _readDate(data['checkInDate']),
      checkOutDate: _readDate(data['checkOutDate']),
      isPrimaryGuest: (data['isPrimaryGuest'] as bool?) ?? false,
      verificationStatus: guestVerificationStatusFromString(
        (data['verificationStatus'] as String?) ?? 'verified',
      ),
      verificationMethod: guestVerificationMethodFromString(
        (data['verificationMethod'] as String?) ?? 'ocrManual',
      ),
      documentAcceptanceStatus:
          (data['documentAcceptanceStatus'] as String?) ?? 'accepted',
      manualReviewCompleted: (data['manualReviewCompleted'] as bool?) ?? false,
      documentImagePath: (data['documentImagePath'] as String?) ?? '',
      documentImagePaths: ((data['documentImagePaths'] as List?) ?? const [])
          .whereType<String>()
          .toList(growable: false),
      retentionPolicy: documentRetentionPolicyFromString(
        (data['retentionPolicy'] as String?) ?? 'deleteImmediately',
      ),
      deleteAfterDate: _readDate(data['deleteAfterDate']),
      cleanupPending: (data['cleanupPending'] as bool?) ?? false,
      ocrStatus: (data['ocrStatus'] as String?) ?? 'pending',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'reservationId': reservationId,
      'pitchId': pitchId,
      'pitchName': pitchName,
      'firstName': firstName,
      'lastName': lastName,
      if (dateOfBirth != null) 'dateOfBirth': Timestamp.fromDate(dateOfBirth!),
      'nationality': nationality,
      'nationalityCode': nationalityCode,
      'nationalityDisplayName': nationalityDisplayName,
      'documentType': documentType,
      'documentNumber': documentNumber,
      'maskedDocumentNumber': maskedDocumentNumber.isNotEmpty
          ? maskedDocumentNumber
          : maskDocumentNumber(documentNumber),
      if (documentExpiryDate != null)
        'documentExpiryDate': Timestamp.fromDate(documentExpiryDate!),
      'gender': gender,
      'issuingCountry': issuingCountry,
      if (checkInDate != null) 'checkInDate': Timestamp.fromDate(checkInDate!),
      if (checkOutDate != null)
        'checkOutDate': Timestamp.fromDate(checkOutDate!),
      'isPrimaryGuest': isPrimaryGuest,
      'verificationStatus': verificationStatus.name,
      'verificationMethod': verificationMethod.name,
      'documentAcceptanceStatus': documentAcceptanceStatus,
      'manualReviewCompleted': manualReviewCompleted,
      'documentImagePath': documentImagePath,
      'documentImagePaths': documentImagePaths,
      'retentionPolicy': retentionPolicy.name,
      if (deleteAfterDate != null)
        'deleteAfterDate': Timestamp.fromDate(deleteAfterDate!),
      'cleanupPending': cleanupPending,
      'ocrStatus': ocrStatus,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  ReservationGuest copyWith({
    String? id,
    String? reservationId,
    String? pitchId,
    String? pitchName,
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    String? nationality,
    String? nationalityCode,
    String? nationalityDisplayName,
    String? documentType,
    String? documentNumber,
    String? maskedDocumentNumber,
    DateTime? documentExpiryDate,
    String? gender,
    String? issuingCountry,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    bool? isPrimaryGuest,
    GuestVerificationStatus? verificationStatus,
    GuestVerificationMethod? verificationMethod,
    String? documentAcceptanceStatus,
    bool? manualReviewCompleted,
    String? documentImagePath,
    List<String>? documentImagePaths,
    DocumentRetentionPolicy? retentionPolicy,
    DateTime? deleteAfterDate,
    bool? cleanupPending,
    String? ocrStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReservationGuest(
      id: id ?? this.id,
      reservationId: reservationId ?? this.reservationId,
      pitchId: pitchId ?? this.pitchId,
      pitchName: pitchName ?? this.pitchName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      nationality: nationality ?? this.nationality,
      nationalityCode: nationalityCode ?? this.nationalityCode,
      nationalityDisplayName:
          nationalityDisplayName ?? this.nationalityDisplayName,
      documentType: documentType ?? this.documentType,
      documentNumber: documentNumber ?? this.documentNumber,
      maskedDocumentNumber: maskedDocumentNumber ?? this.maskedDocumentNumber,
      documentExpiryDate: documentExpiryDate ?? this.documentExpiryDate,
      gender: gender ?? this.gender,
      issuingCountry: issuingCountry ?? this.issuingCountry,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      isPrimaryGuest: isPrimaryGuest ?? this.isPrimaryGuest,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verificationMethod: verificationMethod ?? this.verificationMethod,
      documentAcceptanceStatus:
          documentAcceptanceStatus ?? this.documentAcceptanceStatus,
      manualReviewCompleted:
          manualReviewCompleted ?? this.manualReviewCompleted,
      documentImagePath: documentImagePath ?? this.documentImagePath,
      documentImagePaths: documentImagePaths ?? this.documentImagePaths,
      retentionPolicy: retentionPolicy ?? this.retentionPolicy,
      deleteAfterDate: deleteAfterDate ?? this.deleteAfterDate,
      cleanupPending: cleanupPending ?? this.cleanupPending,
      ocrStatus: ocrStatus ?? this.ocrStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
