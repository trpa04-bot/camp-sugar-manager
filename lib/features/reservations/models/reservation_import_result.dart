import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';

class ReservationImportResult {
  final String? primaryGuestFirstName;
  final String? primaryGuestLastName;
  final String? primaryGuestFullName;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final int? adults;
  final int? children;
  final int? infants;
  final int? guestCount;
  final int pitchCount;
  final String? accommodationType;
  final ReservationSource? source;
  final String? sourceReservationId;
  final String? phone;
  final String? email;
  final String? country;
  final String? language;
  final double? totalPrice;
  final String? currency;
  final double? prepaidAmount;
  final double? balanceDue;
  final String? notes;
  final String? rawImportedText;
  final double confidence;
  final bool needsReview;
  final Map<String, double> fieldConfidences;
  final List<String> warnings;

  const ReservationImportResult({
    this.primaryGuestFirstName,
    this.primaryGuestLastName,
    this.primaryGuestFullName,
    this.checkInDate,
    this.checkOutDate,
    this.adults,
    this.children,
    this.infants,
    this.guestCount,
    this.pitchCount = 1,
    this.accommodationType,
    this.source,
    this.sourceReservationId,
    this.phone,
    this.email,
    this.country,
    this.language,
    this.totalPrice,
    this.currency,
    this.prepaidAmount,
    this.balanceDue,
    this.notes,
    this.rawImportedText,
    this.confidence = 0.5,
    this.needsReview = true,
    this.fieldConfidences = const <String, double>{},
    this.warnings = const <String>[],
  });

  String get primaryGuestName {
    if (primaryGuestFullName != null && primaryGuestFullName!.isNotEmpty) {
      return primaryGuestFullName!;
    }
    final parts = <String>[];
    if (primaryGuestFirstName != null && primaryGuestFirstName!.isNotEmpty) {
      parts.add(primaryGuestFirstName!);
    }
    if (primaryGuestLastName != null && primaryGuestLastName!.isNotEmpty) {
      parts.add(primaryGuestLastName!);
    }
    return parts.join(' ').trim();
  }

  int get totalGuestCount {
    final count = (adults ?? 0) + (children ?? 0) + (infants ?? 0);
    return guestCount ?? (count > 0 ? count : 1);
  }

  ReservationImportResult copyWith({
    String? primaryGuestFirstName,
    String? primaryGuestLastName,
    String? primaryGuestFullName,
    DateTime? checkInDate,
    DateTime? checkOutDate,
    int? adults,
    int? children,
    int? infants,
    int? guestCount,
    int? pitchCount,
    String? accommodationType,
    ReservationSource? source,
    String? sourceReservationId,
    String? phone,
    String? email,
    String? country,
    String? language,
    double? totalPrice,
    String? currency,
    double? prepaidAmount,
    double? balanceDue,
    String? notes,
    String? rawImportedText,
    double? confidence,
    bool? needsReview,
    Map<String, double>? fieldConfidences,
    List<String>? warnings,
  }) {
    return ReservationImportResult(
      primaryGuestFirstName:
          primaryGuestFirstName ?? this.primaryGuestFirstName,
      primaryGuestLastName: primaryGuestLastName ?? this.primaryGuestLastName,
      primaryGuestFullName: primaryGuestFullName ?? this.primaryGuestFullName,
      checkInDate: checkInDate ?? this.checkInDate,
      checkOutDate: checkOutDate ?? this.checkOutDate,
      adults: adults ?? this.adults,
      children: children ?? this.children,
      infants: infants ?? this.infants,
      guestCount: guestCount ?? this.guestCount,
      pitchCount: pitchCount ?? this.pitchCount,
      accommodationType: accommodationType ?? this.accommodationType,
      source: source ?? this.source,
      sourceReservationId: sourceReservationId ?? this.sourceReservationId,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      country: country ?? this.country,
      language: language ?? this.language,
      totalPrice: totalPrice ?? this.totalPrice,
      currency: currency ?? this.currency,
      prepaidAmount: prepaidAmount ?? this.prepaidAmount,
      balanceDue: balanceDue ?? this.balanceDue,
      notes: notes ?? this.notes,
      rawImportedText: rawImportedText ?? this.rawImportedText,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      fieldConfidences: fieldConfidences ?? this.fieldConfidences,
      warnings: warnings ?? this.warnings,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'primaryGuestFirstName': primaryGuestFirstName,
      'primaryGuestLastName': primaryGuestLastName,
      'primaryGuestFullName': primaryGuestFullName,
      'checkInDate': checkInDate,
      'checkOutDate': checkOutDate,
      'adults': adults,
      'children': children,
      'infants': infants,
      'guestCount': guestCount,
      'pitchCount': pitchCount,
      'accommodationType': accommodationType,
      'source': source?.name,
      'sourceReservationId': sourceReservationId,
      'phone': phone,
      'email': email,
      'country': country,
      'language': language,
      'totalPrice': totalPrice,
      'currency': currency,
      'prepaidAmount': prepaidAmount,
      'balanceDue': balanceDue,
      'notes': notes,
      'rawImportedText': rawImportedText,
      'confidence': confidence,
      'needsReview': needsReview,
      'fieldConfidences': fieldConfidences,
    };
  }
}
