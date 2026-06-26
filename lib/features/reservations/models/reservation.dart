import 'package:cloud_firestore/cloud_firestore.dart';

enum ReservationSource {
  booking,
  airbnb,
  campspace,
  whatsapp,
  phone,
  email,
  direct,
  other,
}

enum ReservationStatus { inquiry, confirmed, checkedIn, checkedOut, cancelled }

enum PaymentStatus { unpaid, partiallyPaid, paid, refunded }

ReservationSource reservationSourceFromString(String value) {
  return ReservationSource.values.firstWhere(
    (source) => source.name == value,
    orElse: () => ReservationSource.other,
  );
}

ReservationStatus reservationStatusFromString(String value) {
  return ReservationStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ReservationStatus.inquiry,
  );
}

PaymentStatus paymentStatusFromString(String value) {
  return PaymentStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => PaymentStatus.unpaid,
  );
}

extension ReservationSourceX on ReservationSource {
  String get displayLabel {
    switch (this) {
      case ReservationSource.booking:
        return 'Booking.com';
      case ReservationSource.airbnb:
        return 'Airbnb';
      case ReservationSource.campspace:
        return 'Campspace';
      case ReservationSource.whatsapp:
        return 'WhatsApp';
      case ReservationSource.phone:
        return 'Telefon';
      case ReservationSource.email:
        return 'Email';
      case ReservationSource.direct:
        return 'Direktno';
      case ReservationSource.other:
        return 'Drugo';
    }
  }
}

extension ReservationStatusX on ReservationStatus {
  String get displayLabel {
    switch (this) {
      case ReservationStatus.inquiry:
        return 'Upit';
      case ReservationStatus.confirmed:
        return 'Potvrđeno';
      case ReservationStatus.checkedIn:
        return 'Prijavljen';
      case ReservationStatus.checkedOut:
        return 'Odjavljen';
      case ReservationStatus.cancelled:
        return 'Otkazano';
    }
  }
}

extension PaymentStatusX on PaymentStatus {
  String get displayLabel {
    switch (this) {
      case PaymentStatus.unpaid:
        return 'Nije placeno';
      case PaymentStatus.partiallyPaid:
        return 'Djelomicno placeno';
      case PaymentStatus.paid:
        return 'Placeno';
      case PaymentStatus.refunded:
        return 'Refundirano';
    }
  }
}

PaymentStatus derivePaymentStatus({
  required double totalPrice,
  required double amountPaid,
  PaymentStatus? currentStatus,
}) {
  // Preserve explicit refunded status.
  if (currentStatus == PaymentStatus.refunded) {
    return PaymentStatus.refunded;
  }

  // When total price is not set yet, respect explicit manual "paid" selection.
  if (currentStatus == PaymentStatus.paid && totalPrice <= 0.01) {
    return PaymentStatus.paid;
  }

  if (totalPrice > 0 && amountPaid >= (totalPrice - 0.01)) {
    return PaymentStatus.paid;
  }
  if (amountPaid > 0.01) {
    return PaymentStatus.partiallyPaid;
  }
  return PaymentStatus.unpaid;
}

class Reservation {
  const Reservation({
    required this.id,
    required this.bookingReference,
    required this.source,
    required this.primaryGuestName,
    required this.primaryGuestId,
    required this.primaryGuestPhone,
    required this.primaryGuestEmail,
    required this.pitchId,
    required this.pitchName,
    required this.checkInDate,
    required this.checkOutDate,
    required this.adults,
    required this.children,
    required this.pets,
    required this.vehicles,
    this.vehicleDescription = '',
    this.vehicleImageUrl = '',
    this.vehicleImagePath = '',
    this.vehicleImageSizeBytes = 0,
    required this.accommodationType,
    required this.status,
    required this.totalPrice,
    required this.depositPaid,
    required this.amountPaid,
    this.pricePerNight = 0.0,
    required this.paymentStatus,
    required this.notes,
    required this.registeredGuestCount,
    required this.currentGuests,
    this.actualCheckInAt,
    this.actualCheckOutAt,
    this.checkedInByUid,
    this.checkedOutByUid,
    this.createdAt,
    this.updatedAt,
    this.pitchIds = const <String>[],
    this.primaryGuestFirstName = '',
    this.primaryGuestLastName = '',
    this.infants = 0,
    this.guestCount = 0,
    this.pitchCount = 1,
    this.sourceReservationId = '',
    this.country = '',
    this.language = '',
    this.currency = 'EUR',
    this.prepaidAmount = 0.0,
    this.balanceDue = 0.0,
    this.importMethod = '',
    this.importConfidence = 0.0,
    this.importNeedsReview = false,
    this.departureDateUnknown = false,
    this.externalSource = '',
    this.googleCalendarEventId = '',
    this.googleCalendarId = '',
    this.googleCalendarLastUpdatedAt,
    this.importedFromGoogleCalendar = false,
  });

  final String id;
  final String bookingReference;
  final ReservationSource source;
  final String primaryGuestName;
  final String primaryGuestId;
  final String primaryGuestPhone;
  final String primaryGuestEmail;
  final String pitchId;
  final String pitchName;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final int adults;
  final int children;
  final int pets;
  final int vehicles;
  final String vehicleDescription;
  final String vehicleImageUrl;
  final String vehicleImagePath;
  final int vehicleImageSizeBytes;
  final String accommodationType;
  final ReservationStatus status;
  final double totalPrice;
  final double depositPaid;
  final double amountPaid;
  final double pricePerNight;
  final PaymentStatus paymentStatus;
  final String notes;
  final int registeredGuestCount;
  final int currentGuests;
  final DateTime? actualCheckInAt;
  final DateTime? actualCheckOutAt;
  final String? checkedInByUid;
  final String? checkedOutByUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> pitchIds;
  final String primaryGuestFirstName;
  final String primaryGuestLastName;
  final int infants;
  final int guestCount;
  final int pitchCount;
  final String sourceReservationId;
  final String country;
  final String language;
  final String currency;
  final double prepaidAmount;
  final double balanceDue;
  final String importMethod;
  final double importConfidence;
  final bool importNeedsReview;
  final bool departureDateUnknown;
  final String externalSource;
  final String googleCalendarEventId;
  final String googleCalendarId;
  final DateTime? googleCalendarLastUpdatedAt;
  final bool importedFromGoogleCalendar;

  factory Reservation.empty() {
    final now = DateTime.now();
    return Reservation(
      id: '',
      bookingReference: '',
      source: ReservationSource.direct,
      primaryGuestName: '',
      primaryGuestId: '',
      primaryGuestPhone: '',
      primaryGuestEmail: '',
      pitchId: '',
      pitchName: '',
      checkInDate: DateTime(now.year, now.month, now.day),
      checkOutDate: DateTime(now.year, now.month, now.day + 1),
      adults: 2,
      children: 0,
      pets: 0,
      vehicles: 1,
      accommodationType: '',
      status: ReservationStatus.inquiry,
      totalPrice: 0,
      depositPaid: 0,
      amountPaid: 0,
      pricePerNight: 0.0,
      paymentStatus: PaymentStatus.unpaid,
      notes: '',
      registeredGuestCount: 0,
      currentGuests: 0,
    );
  }

  factory Reservation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Reservation(
      id: (data['id'] as String?) ?? doc.id,
      bookingReference: (data['bookingReference'] as String?) ?? '',
      source: reservationSourceFromString(
        (data['source'] as String?) ?? 'other',
      ),
      primaryGuestName: (data['primaryGuestName'] as String?) ?? '',
      primaryGuestId: (data['primaryGuestId'] as String?) ?? '',
      primaryGuestPhone: (data['primaryGuestPhone'] as String?) ?? '',
      primaryGuestEmail: (data['primaryGuestEmail'] as String?) ?? '',
      pitchId: (data['pitchId'] as String?) ?? '',
      pitchName: (data['pitchName'] as String?) ?? '',
      checkInDate: _readDate(data['checkInDate']) ?? DateTime.now(),
      checkOutDate:
          _readDate(data['checkOutDate']) ??
          DateTime.now().add(const Duration(days: 1)),
      adults: _readInt(data['adults']) ?? 0,
      children: _readInt(data['children']) ?? 0,
      pets: _readInt(data['pets']) ?? 0,
      vehicles: _readInt(data['vehicles']) ?? 0,
      vehicleDescription: (data['vehicleDescription'] as String?) ?? '',
      vehicleImageUrl: (data['vehicleImageUrl'] as String?) ?? '',
      vehicleImagePath: (data['vehicleImagePath'] as String?) ?? '',
      vehicleImageSizeBytes: _readInt(data['vehicleImageSizeBytes']) ?? 0,
      accommodationType: (data['accommodationType'] as String?) ?? '',
      status: reservationStatusFromString(
        (data['status'] as String?) ?? 'inquiry',
      ),
      totalPrice: _readDouble(data['totalPrice']) ?? 0,
      depositPaid: _readDouble(data['depositPaid']) ?? 0,
      amountPaid: _readDouble(data['amountPaid']) ?? 0,
      pricePerNight: _readDouble(data['pricePerNight']) ?? 0,
      paymentStatus: paymentStatusFromString(
        (data['paymentStatus'] as String?) ?? 'unpaid',
      ),
      notes: (data['notes'] as String?) ?? '',
      registeredGuestCount: _readInt(data['registeredGuestCount']) ?? 0,
      currentGuests: _readInt(data['currentGuests']) ?? 0,
      actualCheckInAt: _readDate(data['actualCheckInAt']),
      actualCheckOutAt: _readDate(data['actualCheckOutAt']),
      checkedInByUid: (data['checkedInByUid'] as String?)?.trim(),
      checkedOutByUid: (data['checkedOutByUid'] as String?)?.trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      pitchIds: _readList(data['pitchIds']),
      primaryGuestFirstName: (data['primaryGuestFirstName'] as String?) ?? '',
      primaryGuestLastName: (data['primaryGuestLastName'] as String?) ?? '',
      infants: _readInt(data['infants']) ?? 0,
      guestCount: _readInt(data['guestCount']) ?? 0,
      pitchCount: _readInt(data['pitchCount']) ?? 1,
      sourceReservationId: (data['sourceReservationId'] as String?) ?? '',
      country: (data['country'] as String?) ?? '',
      language: (data['language'] as String?) ?? '',
      currency: (data['currency'] as String?) ?? 'EUR',
      prepaidAmount: _readDouble(data['prepaidAmount']) ?? 0.0,
      balanceDue: _readDouble(data['balanceDue']) ?? 0.0,
      importMethod: (data['importMethod'] as String?) ?? '',
      importConfidence: _readDouble(data['importConfidence']) ?? 0.0,
      importNeedsReview: (data['importNeedsReview'] as bool?) ?? false,
      departureDateUnknown: (data['departureDateUnknown'] as bool?) ?? false,
      externalSource: (data['externalSource'] as String?) ?? '',
      googleCalendarEventId: (data['googleCalendarEventId'] as String?) ?? '',
      googleCalendarId: (data['googleCalendarId'] as String?) ?? '',
      googleCalendarLastUpdatedAt: _readDate(
        data['googleCalendarLastUpdatedAt'],
      ),
      importedFromGoogleCalendar:
          (data['importedFromGoogleCalendar'] as bool?) ?? false,
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

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static List<String> _readList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const <String>[];
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'bookingReference': bookingReference,
      'source': source.name,
      'primaryGuestName': primaryGuestName,
      'primaryGuestId': primaryGuestId,
      'primaryGuestPhone': primaryGuestPhone,
      'primaryGuestEmail': primaryGuestEmail,
      'pitchId': pitchId,
      'pitchName': pitchName,
      'checkInDate': Timestamp.fromDate(checkInDate),
      'checkOutDate': Timestamp.fromDate(checkOutDate),
      'adults': adults,
      'children': children,
      'pets': pets,
      'vehicles': vehicles,
      'vehicleDescription': vehicleDescription,
      'vehicleImageUrl': vehicleImageUrl,
      'vehicleImagePath': vehicleImagePath,
      'vehicleImageSizeBytes': vehicleImageSizeBytes,
      'accommodationType': accommodationType,
      'status': status.name,
      'totalPrice': totalPrice,
      'depositPaid': depositPaid,
      'amountPaid': amountPaid,
      'pricePerNight': pricePerNight,
      'paymentStatus': paymentStatus.name,
      'notes': notes,
      'registeredGuestCount': registeredGuestCount,
      'currentGuests': currentGuests,
      if (actualCheckInAt != null)
        'actualCheckInAt': Timestamp.fromDate(actualCheckInAt!),
      if (actualCheckOutAt != null)
        'actualCheckOutAt': Timestamp.fromDate(actualCheckOutAt!),
      if ((checkedInByUid ?? '').trim().isNotEmpty)
        'checkedInByUid': checkedInByUid,
      if ((checkedOutByUid ?? '').trim().isNotEmpty)
        'checkedOutByUid': checkedOutByUid,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      'pitchIds': pitchIds,
      'primaryGuestFirstName': primaryGuestFirstName,
      'primaryGuestLastName': primaryGuestLastName,
      'infants': infants,
      'guestCount': guestCount,
      'pitchCount': pitchCount,
      'sourceReservationId': sourceReservationId,
      'country': country,
      'language': language,
      'currency': currency,
      'prepaidAmount': prepaidAmount,
      'balanceDue': balanceDue,
      'importMethod': importMethod,
      'importConfidence': importConfidence,
      'importNeedsReview': importNeedsReview,
      'departureDateUnknown': departureDateUnknown,
      'externalSource': externalSource,
      'googleCalendarEventId': googleCalendarEventId,
      'googleCalendarId': googleCalendarId,
      if (googleCalendarLastUpdatedAt != null)
        'googleCalendarLastUpdatedAt': Timestamp.fromDate(
          googleCalendarLastUpdatedAt!,
        ),
      'importedFromGoogleCalendar': importedFromGoogleCalendar,
    };
  }

  Reservation copyWith({
    String? id,
    String? bookingReference,
    ReservationSource? source,
    String? primaryGuestName,
    String? primaryGuestId,
    String? primaryGuestPhone,
    String? primaryGuestEmail,
    String? pitchId,
    String? pitchName,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    int? adults,
    int? children,
    int? pets,
    int? vehicles,
    String? vehicleDescription,
    String? vehicleImageUrl,
    String? vehicleImagePath,
    int? vehicleImageSizeBytes,
    String? accommodationType,
    ReservationStatus? status,
    double? totalPrice,
    double? depositPaid,
    double? amountPaid,
    double? pricePerNight,
    PaymentStatus? paymentStatus,
    String? notes,
    int? registeredGuestCount,
    int? currentGuests,
    DateTime? actualCheckInAt,
    DateTime? actualCheckOutAt,
    String? checkedInByUid,
    String? checkedOutByUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? pitchIds,
    String? primaryGuestFirstName,
    String? primaryGuestLastName,
    int? infants,
    int? guestCount,
    int? pitchCount,
    String? sourceReservationId,
    String? country,
    String? language,
    String? currency,
    double? prepaidAmount,
    double? balanceDue,
    String? importMethod,
    double? importConfidence,
    bool? importNeedsReview,
    bool? departureDateUnknown,
    String? externalSource,
    String? googleCalendarEventId,
    String? googleCalendarId,
    DateTime? googleCalendarLastUpdatedAt,
    bool? importedFromGoogleCalendar,
  }) {
    return Reservation(
      id: id ?? this.id,
      bookingReference: bookingReference ?? this.bookingReference,
      source: source ?? this.source,
      primaryGuestName: primaryGuestName ?? this.primaryGuestName,
      primaryGuestId: primaryGuestId ?? this.primaryGuestId,
      primaryGuestPhone: primaryGuestPhone ?? this.primaryGuestPhone,
      primaryGuestEmail: primaryGuestEmail ?? this.primaryGuestEmail,
      pitchId: pitchId ?? this.pitchId,
      pitchName: pitchName ?? this.pitchName,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      adults: adults ?? this.adults,
      children: children ?? this.children,
      pets: pets ?? this.pets,
      vehicles: vehicles ?? this.vehicles,
      vehicleDescription: vehicleDescription ?? this.vehicleDescription,
      vehicleImageUrl: vehicleImageUrl ?? this.vehicleImageUrl,
      vehicleImagePath: vehicleImagePath ?? this.vehicleImagePath,
      vehicleImageSizeBytes:
          vehicleImageSizeBytes ?? this.vehicleImageSizeBytes,
      accommodationType: accommodationType ?? this.accommodationType,
      status: status ?? this.status,
      totalPrice: totalPrice ?? this.totalPrice,
      depositPaid: depositPaid ?? this.depositPaid,
      amountPaid: amountPaid ?? this.amountPaid,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      notes: notes ?? this.notes,
      registeredGuestCount: registeredGuestCount ?? this.registeredGuestCount,
      currentGuests: currentGuests ?? this.currentGuests,
      actualCheckInAt: actualCheckInAt ?? this.actualCheckInAt,
      actualCheckOutAt: actualCheckOutAt ?? this.actualCheckOutAt,
      checkedInByUid: checkedInByUid ?? this.checkedInByUid,
      checkedOutByUid: checkedOutByUid ?? this.checkedOutByUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pitchIds: pitchIds ?? this.pitchIds,
      primaryGuestFirstName:
          primaryGuestFirstName ?? this.primaryGuestFirstName,
      primaryGuestLastName: primaryGuestLastName ?? this.primaryGuestLastName,
      infants: infants ?? this.infants,
      guestCount: guestCount ?? this.guestCount,
      pitchCount: pitchCount ?? this.pitchCount,
      sourceReservationId: sourceReservationId ?? this.sourceReservationId,
      country: country ?? this.country,
      language: language ?? this.language,
      currency: currency ?? this.currency,
      prepaidAmount: prepaidAmount ?? this.prepaidAmount,
      balanceDue: balanceDue ?? this.balanceDue,
      importMethod: importMethod ?? this.importMethod,
      importConfidence: importConfidence ?? this.importConfidence,
      importNeedsReview: importNeedsReview ?? this.importNeedsReview,
      departureDateUnknown: departureDateUnknown ?? this.departureDateUnknown,
      externalSource: externalSource ?? this.externalSource,
      googleCalendarEventId:
          googleCalendarEventId ?? this.googleCalendarEventId,
      googleCalendarId: googleCalendarId ?? this.googleCalendarId,
      googleCalendarLastUpdatedAt:
          googleCalendarLastUpdatedAt ?? this.googleCalendarLastUpdatedAt,
      importedFromGoogleCalendar:
          importedFromGoogleCalendar ?? this.importedFromGoogleCalendar,
    );
  }
}

extension ReservationPaymentStateX on Reservation {
  PaymentStatus get effectivePaymentStatus => derivePaymentStatus(
    totalPrice: totalPrice,
    amountPaid: amountPaid,
    currentStatus: paymentStatus,
  );
}
