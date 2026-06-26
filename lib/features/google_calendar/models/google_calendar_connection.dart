import 'package:cloud_firestore/cloud_firestore.dart';

enum GoogleCalendarSyncStatus { idle, syncing, success, error }

GoogleCalendarSyncStatus googleCalendarSyncStatusFromString(String value) {
  return GoogleCalendarSyncStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => GoogleCalendarSyncStatus.idle,
  );
}

class GoogleCalendarConnection {
  const GoogleCalendarConnection({
    required this.uid,
    required this.connected,
    required this.googleAccountEmail,
    required this.selectedCalendarId,
    required this.selectedCalendarName,
    this.lastSyncAt,
    required this.nextSyncToken,
    required this.autoSyncEnabled,
    required this.syncStatus,
    required this.lastError,
    this.createdAt,
    this.updatedAt,
    this.newEventsCount = 0,
    this.needsReviewCount = 0,
  });

  final String uid;
  final bool connected;
  final String googleAccountEmail;
  final String selectedCalendarId;
  final String selectedCalendarName;
  final DateTime? lastSyncAt;
  final String nextSyncToken;
  final bool autoSyncEnabled;
  final GoogleCalendarSyncStatus syncStatus;
  final String lastError;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int newEventsCount;
  final int needsReviewCount;

  factory GoogleCalendarConnection.empty(String uid) {
    return GoogleCalendarConnection(
      uid: uid,
      connected: false,
      googleAccountEmail: '',
      selectedCalendarId: '',
      selectedCalendarName: '',
      nextSyncToken: '',
      autoSyncEnabled: false,
      syncStatus: GoogleCalendarSyncStatus.idle,
      lastError: '',
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

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  factory GoogleCalendarConnection.fromMap(Map<String, dynamic> data) {
    return GoogleCalendarConnection(
      uid: (data['uid'] as String?) ?? '',
      connected: (data['connected'] as bool?) ?? false,
      googleAccountEmail: (data['googleAccountEmail'] as String?) ?? '',
      selectedCalendarId: (data['selectedCalendarId'] as String?) ?? '',
      selectedCalendarName: (data['selectedCalendarName'] as String?) ?? '',
      lastSyncAt: _readDate(data['lastSyncAt']),
      nextSyncToken: (data['nextSyncToken'] as String?) ?? '',
      autoSyncEnabled: (data['autoSyncEnabled'] as bool?) ?? false,
      syncStatus: googleCalendarSyncStatusFromString(
        (data['syncStatus'] as String?) ?? 'idle',
      ),
      lastError: (data['lastError'] as String?) ?? '',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      newEventsCount: _readInt(data['newEventsCount']),
      needsReviewCount: _readInt(data['needsReviewCount']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'connected': connected,
      'googleAccountEmail': googleAccountEmail,
      'selectedCalendarId': selectedCalendarId,
      'selectedCalendarName': selectedCalendarName,
      'lastSyncAt': lastSyncAt == null ? null : Timestamp.fromDate(lastSyncAt!),
      'nextSyncToken': nextSyncToken,
      'autoSyncEnabled': autoSyncEnabled,
      'syncStatus': syncStatus.name,
      'lastError': lastError,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'newEventsCount': newEventsCount,
      'needsReviewCount': needsReviewCount,
    };
  }

  GoogleCalendarConnection copyWith({
    String? uid,
    bool? connected,
    String? googleAccountEmail,
    String? selectedCalendarId,
    String? selectedCalendarName,
    DateTime? lastSyncAt,
    String? nextSyncToken,
    bool? autoSyncEnabled,
    GoogleCalendarSyncStatus? syncStatus,
    String? lastError,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? newEventsCount,
    int? needsReviewCount,
  }) {
    return GoogleCalendarConnection(
      uid: uid ?? this.uid,
      connected: connected ?? this.connected,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      selectedCalendarId: selectedCalendarId ?? this.selectedCalendarId,
      selectedCalendarName: selectedCalendarName ?? this.selectedCalendarName,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      nextSyncToken: nextSyncToken ?? this.nextSyncToken,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      syncStatus: syncStatus ?? this.syncStatus,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      newEventsCount: newEventsCount ?? this.newEventsCount,
      needsReviewCount: needsReviewCount ?? this.needsReviewCount,
    );
  }
}
