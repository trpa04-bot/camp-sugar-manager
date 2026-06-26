import 'package:camp_sugar_manager/features/google_calendar/models/google_calendar_import_event.dart';
import 'package:camp_sugar_manager/features/parcels/models/pitch.dart';
import 'package:camp_sugar_manager/features/reservations/models/reservation.dart';
import 'package:camp_sugar_manager/features/reservations/services/reservation_import_parser.dart';

class GoogleEventDateRange {
  const GoogleEventDateRange({
    required this.checkInDate,
    required this.checkOutDate,
    required this.isAllDay,
  });

  final DateTime checkInDate;
  final DateTime checkOutDate;
  final bool isAllDay;
}

class GoogleCalendarRawEvent {
  const GoogleCalendarRawEvent({
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
  });

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
}

String buildGoogleCalendarImportText({
  required String title,
  required String description,
  required String location,
}) {
  return [
    title.trim(),
    description.trim(),
    location.trim(),
  ].where((part) => part.isNotEmpty).join('\n');
}

GoogleEventDateRange adaptGoogleEventDates({
  required DateTime start,
  required DateTime end,
  required bool isAllDay,
}) {
  final normalizedStart = DateTime(start.year, start.month, start.day);
  final normalizedEnd = DateTime(end.year, end.month, end.day);

  if (!isAllDay) {
    return GoogleEventDateRange(
      checkInDate: normalizedStart,
      checkOutDate: normalizedEnd.isAfter(normalizedStart)
          ? normalizedEnd
          : normalizedStart.add(const Duration(days: 1)),
      isAllDay: false,
    );
  }

  // Google all-day events use exclusive end date; reservation model stores checkout date.
  return GoogleEventDateRange(
    checkInDate: normalizedStart,
    checkOutDate: normalizedEnd,
    isAllDay: true,
  );
}

String _normalizeToken(String value) {
  final lower = value.toLowerCase().trim();
  final map = {
    'č': 'c',
    'ć': 'c',
    'đ': 'd',
    'š': 's',
    'ž': 'z',
    'ä': 'a',
    'ö': 'o',
    'ü': 'u',
    'ß': 'ss',
  };

  var normalized = lower;
  map.forEach((key, replacement) {
    normalized = normalized.replaceAll(key, replacement);
  });
  return normalized.replaceAll(RegExp(r'\s+'), ' ');
}

Pitch? detectPitchFromText({
  required String text,
  required List<Pitch> pitches,
}) {
  final normalizedText = _normalizeToken(text);

  Pitch? best;
  var bestLength = 0;
  for (final pitch in pitches) {
    final candidate = _normalizeToken(pitch.name);
    if (candidate.isEmpty) {
      continue;
    }
    final exactContains = RegExp(
      '(^|[^a-z0-9])${RegExp.escape(candidate)}([^a-z0-9]|\$)',
    ).hasMatch(normalizedText);
    if (exactContains && candidate.length > bestLength) {
      best = pitch;
      bestLength = candidate.length;
    }
  }
  return best;
}

Future<GoogleCalendarImportEvent> toImportEvent({
  required GoogleCalendarRawEvent rawEvent,
  required ReservationSource sourceHint,
}) async {
  final importText = buildGoogleCalendarImportText(
    title: rawEvent.title,
    description: rawEvent.description,
    location: rawEvent.location,
  );

  final parsed = await ReservationImportParser.parseText(
    importText,
    sourceHint: sourceHint,
  );

  final adaptedDates = adaptGoogleEventDates(
    start: rawEvent.startDate,
    end: rawEvent.endDate,
    isAllDay: rawEvent.isAllDay,
  );

  final mergedParsed = parsed.copyWith(
    checkInDate: adaptedDates.checkInDate,
    checkOutDate: adaptedDates.checkOutDate,
  );

  return GoogleCalendarImportEvent(
    id: rawEvent.googleEventId,
    googleEventId: rawEvent.googleEventId,
    calendarId: rawEvent.calendarId,
    title: rawEvent.title,
    description: rawEvent.description,
    location: rawEvent.location,
    startDate: rawEvent.startDate,
    endDate: rawEvent.endDate,
    isAllDay: rawEvent.isAllDay,
    eventStatus: rawEvent.eventStatus,
    updatedAtGoogle: rawEvent.updatedAtGoogle,
    htmlLink: rawEvent.htmlLink,
    rawSource: 'googleCalendar',
    parsedReservation: mergedParsed,
    parseWarnings: mergedParsed.warnings,
    confidence: mergedParsed.confidence,
    importStatus: mergedParsed.needsReview
        ? GoogleCalendarImportStatus.needsReview
        : GoogleCalendarImportStatus.newEvent,
  );
}
