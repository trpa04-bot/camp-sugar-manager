import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation_import_result.dart';
import 'package:camp_sugar_manager/features/google_calendar/services/google_calendar_title_parser.dart';

enum GoogleCalendarImportStatus {
  newEvent,
  needsReview,
  imported,
  ignored,
  duplicate,
  cancelled,
  updatedAfterImport,
}

GoogleCalendarImportStatus googleCalendarImportStatusFromString(String value) {
  return GoogleCalendarImportStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => GoogleCalendarImportStatus.newEvent,
  );
}

class GoogleCalendarImportEvent {
  const GoogleCalendarImportEvent({
    required this.id,
    required this.googleEventId,
    required this.calendarId,
    required this.title,
    required this.description,
    required this.location,
    required this.startDate,
    required this.endDate,
    required this.isAllDay,
    required this.eventStatus,
    this.updatedAtGoogle,
    this.htmlLink,
    required this.rawSource,
    required this.parsedReservation,
    required this.parseWarnings,
    required this.confidence,
    required this.importStatus,
    this.linkedReservationId,
    this.ignoredAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String googleEventId;
  final String calendarId;
  final String title;
  final String description;
  final String location;
  final DateTime startDate;
  final DateTime endDate;
  final bool isAllDay;
  final String eventStatus;
  final DateTime? updatedAtGoogle;
  final String? htmlLink;
  final String rawSource;
  final ReservationImportResult parsedReservation;
  final List<String> parseWarnings;
  final double confidence;
  final GoogleCalendarImportStatus importStatus;
  final String? linkedReservationId;
  final DateTime? ignoredAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static DateTime _readRequiredDate(dynamic value, DateTime fallback) {
    return _readDate(value) ?? fallback;
  }

  static double _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return 0;
  }

  factory GoogleCalendarImportEvent.fromMap(
    String id,
    Map<String, dynamic> map,
  ) {
    final parsed = map['parsedReservation'];
    final parsedMap = parsed is Map
        ? Map<String, dynamic>.from(parsed)
        : <String, dynamic>{};

    return GoogleCalendarImportEvent(
      id: id,
      googleEventId: (map['googleEventId'] as String?) ?? '',
      calendarId: (map['calendarId'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      description: (map['description'] as String?) ?? '',
      location: (map['location'] as String?) ?? '',
      startDate: _readRequiredDate(map['startDate'], DateTime.now()),
      endDate: _readRequiredDate(
        map['endDate'],
        DateTime.now().add(const Duration(days: 1)),
      ),
      isAllDay: (map['isAllDay'] as bool?) ?? false,
      eventStatus: (map['eventStatus'] as String?) ?? 'confirmed',
      updatedAtGoogle: _readDate(map['updatedAtGoogle']),
      htmlLink: (map['htmlLink'] as String?),
      rawSource: (map['rawSource'] as String?) ?? 'googleCalendar',
      parsedReservation: ReservationImportResult(
        primaryGuestFirstName: _resolveFirstName(parsedMap, map),
        primaryGuestLastName: _resolveLastName(parsedMap, map),
        primaryGuestFullName: _resolveFullName(parsedMap, map),
        checkInDate: _readDate(parsedMap['checkInDate']),
        checkOutDate: _readDate(parsedMap['checkOutDate']),
        adults: parsedMap['adults'] as int?,
        children: parsedMap['children'] as int?,
        infants: parsedMap['infants'] as int?,
        guestCount: parsedMap['guestCount'] as int?,
        pitchCount: (parsedMap['pitchCount'] as int?) ?? 1,
        sourceReservationId: parsedMap['sourceReservationId'] as String?,
        source: null,
        phone: parsedMap['phone'] as String?,
        email: parsedMap['email'] as String?,
        totalPrice: _readDouble(parsedMap['totalPrice']),
        currency: parsedMap['currency'] as String?,
        notes: parsedMap['notes'] as String?,
        rawImportedText: parsedMap['rawImportedText'] as String?,
        confidence: _readDouble(parsedMap['confidence']),
        needsReview: (parsedMap['needsReview'] as bool?) ?? true,
        fieldConfidences: const <String, double>{},
        warnings: const <String>[],
      ),
      parseWarnings:
          (map['parseWarnings'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      confidence: _readDouble(map['confidence']),
      importStatus: googleCalendarImportStatusFromString(
        (map['importStatus'] as String?) ?? 'newEvent',
      ),
      linkedReservationId: map['linkedReservationId'] as String?,
      ignoredAt: _readDate(map['ignoredAt']),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'googleEventId': googleEventId,
      'calendarId': calendarId,
      'title': title,
      'description': description,
      'location': location,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'isAllDay': isAllDay,
      'eventStatus': eventStatus,
      if (updatedAtGoogle != null)
        'updatedAtGoogle': Timestamp.fromDate(updatedAtGoogle!),
      'htmlLink': htmlLink,
      'rawSource': rawSource,
      'parsedReservation': parsedReservation.toMap(),
      'parseWarnings': parseWarnings,
      'confidence': confidence,
      'importStatus': importStatus.name,
      'linkedReservationId': linkedReservationId,
      if (ignoredAt != null) 'ignoredAt': Timestamp.fromDate(ignoredAt!),
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  // ── fallback name resolution (backward compatible) ────────────────────────

  static String? _resolveFirstName(
    Map<String, dynamic> parsedMap,
    Map<String, dynamic> eventMap,
  ) {
    final stored = parsedMap['primaryGuestFirstName'] as String?;
    if (stored != null && stored.isNotEmpty) return stored;

    final parts = GoogleCalendarTitleParser.extractNameParts(
      _sourceTitle(parsedMap, eventMap),
    );
    return parts.firstName;
  }

  static String? _resolveLastName(
    Map<String, dynamic> parsedMap,
    Map<String, dynamic> eventMap,
  ) {
    final stored = parsedMap['primaryGuestLastName'] as String?;
    if (stored != null && stored.isNotEmpty) return stored;

    final parts = GoogleCalendarTitleParser.extractNameParts(
      _sourceTitle(parsedMap, eventMap),
    );
    return parts.lastName;
  }

  static String? _resolveFullName(
    Map<String, dynamic> parsedMap,
    Map<String, dynamic> eventMap,
  ) {
    final stored = parsedMap['primaryGuestFullName'] as String?;
    if (stored != null && stored.isNotEmpty) return stored;

    return _sourceTitle(parsedMap, eventMap);
  }

  static String? _sourceTitle(
    Map<String, dynamic> parsedMap,
    Map<String, dynamic> eventMap,
  ) {
    final fromParsed = parsedMap['primaryGuestFullName'] as String?;
    if (fromParsed != null && fromParsed.isNotEmpty) return fromParsed;

    final fromTitle = eventMap['title'] as String?;
    if (fromTitle != null && fromTitle.isNotEmpty) return fromTitle;

    return null;
  }

  GoogleCalendarImportEvent copyWith({
    String? id,
    String? googleEventId,
    String? calendarId,
    String? title,
    String? description,
    String? location,
    DateTime? startDate,
    DateTime? endDate,
    bool? isAllDay,
    String? eventStatus,
    DateTime? updatedAtGoogle,
    String? htmlLink,
    String? rawSource,
    ReservationImportResult? parsedReservation,
    List<String>? parseWarnings,
    double? confidence,
    GoogleCalendarImportStatus? importStatus,
    String? linkedReservationId,
    DateTime? ignoredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GoogleCalendarImportEvent(
      id: id ?? this.id,
      googleEventId: googleEventId ?? this.googleEventId,
      calendarId: calendarId ?? this.calendarId,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isAllDay: isAllDay ?? this.isAllDay,
      eventStatus: eventStatus ?? this.eventStatus,
      updatedAtGoogle: updatedAtGoogle ?? this.updatedAtGoogle,
      htmlLink: htmlLink ?? this.htmlLink,
      rawSource: rawSource ?? this.rawSource,
      parsedReservation: parsedReservation ?? this.parsedReservation,
      parseWarnings: parseWarnings ?? this.parseWarnings,
      confidence: confidence ?? this.confidence,
      importStatus: importStatus ?? this.importStatus,
      linkedReservationId: linkedReservationId ?? this.linkedReservationId,
      ignoredAt: ignoredAt ?? this.ignoredAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
