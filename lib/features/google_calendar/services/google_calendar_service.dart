import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/google_calendar_connection.dart';
import '../models/google_calendar_import_event.dart';

class GoogleCalendarOption {
  const GoogleCalendarOption({
    required this.id,
    required this.name,
    required this.primary,
  });

  final String id;
  final String name;
  final bool primary;

  factory GoogleCalendarOption.fromMap(Map<String, dynamic> map) {
    return GoogleCalendarOption(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      primary: (map['primary'] as bool?) ?? false,
    );
  }
}

class GoogleCalendarSyncResponse {
  const GoogleCalendarSyncResponse({
    required this.newEvents,
    required this.updatedEvents,
    required this.cancelledEvents,
    required this.needsReview,
    required this.invalidSyncTokenRecovered,
  });

  final int newEvents;
  final int updatedEvents;
  final int cancelledEvents;
  final int needsReview;
  final bool invalidSyncTokenRecovered;

  factory GoogleCalendarSyncResponse.fromMap(Map<String, dynamic> map) {
    int readInt(String key) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return GoogleCalendarSyncResponse(
      newEvents: readInt('newEvents'),
      updatedEvents: readInt('updatedEvents'),
      cancelledEvents: readInt('cancelledEvents'),
      needsReview: readInt('needsReview'),
      invalidSyncTokenRecovered:
          (map['invalidSyncTokenRecovered'] as bool?) ?? false,
    );
  }
}

class AuthDiagnostics {
  const AuthDiagnostics({
    required this.userExists,
    required this.uid,
    required this.email,
    required this.emailVerified,
    required this.adminClaimPresent,
    required this.adminClaimValue,
  });

  final bool userExists;
  final String uid;
  final String email;
  final bool emailVerified;
  final bool adminClaimPresent;
  final bool adminClaimValue;
}

class GoogleCalendarService {
  static const String _functionsRegion = 'europe-west1';

  GoogleCalendarService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: _functionsRegion),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    _logDebug('Functions region: $_functionsRegion');
  }

  final FirebaseFunctions _functions;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  void _logDebug(String message) {
    debugPrint('[GoogleCalendarService] $message');
  }

  void _logError(String source, Object error) {
    if (error is FirebaseFunctionsException) {
      _logDebug(
        '$source error code=${error.code} message=${error.message ?? ''}',
      );
      return;
    }
    if (error is FirebaseException) {
      _logDebug(
        '$source error code=${error.code} message=${error.message ?? ''}',
      );
      return;
    }
    _logDebug('$source error message=$error');
  }

  String _requireUid() {
    final hasCurrentUser = _auth.currentUser != null;
    final hasUid = ((_auth.currentUser?.uid ?? '').isNotEmpty);
    _logDebug('currentUser exists: $hasCurrentUser');
    _logDebug('uid exists: $hasUid');

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Korisnik nije prijavljen.');
    }
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _connectionDoc(String uid) {
    return _firestore.collection('googleCalendarConnections').doc(uid);
  }

  CollectionReference<Map<String, dynamic>> _eventsCollection(String uid) {
    return _connectionDoc(uid).collection('importEvents');
  }

  Stream<GoogleCalendarConnection> watchConnection() {
    final controller = StreamController<GoogleCalendarConnection>();
    StreamSubscription<GoogleCalendarConnection>? liveSubscription;

    controller.onCancel = () async {
      await liveSubscription?.cancel();
    };

    Future<void>(() async {
      try {
        final uid = _requireUid();
        _logDebug('Firestore read status: start');

        final initialDoc = await _connectionDoc(uid).get().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'deadline-exceeded',
              message:
                  'Ucitavanje statusa Google kalendara je isteklo nakon 15 sekundi.',
            );
          },
        );

        _logDebug('connection document exists: ${initialDoc.exists}');
        _logDebug('Firestore read status: success');

        if (!initialDoc.exists) {
          controller.add(GoogleCalendarConnection.empty(uid));
        } else {
          controller.add(GoogleCalendarConnection.fromMap(initialDoc.data()!));
        }

        liveSubscription = _connectionDoc(uid)
            .snapshots()
            .map((doc) {
              _logDebug('connection document exists: ${doc.exists}');
              _logDebug('Firestore read status: success');
              if (!doc.exists) {
                return GoogleCalendarConnection.empty(uid);
              }
              return GoogleCalendarConnection.fromMap(doc.data()!);
            })
            .listen(
              controller.add,
              onError: (error) {
                _logDebug('Firestore read status: error');
                _logError('watchConnection', error);
                controller.addError(error);
              },
              onDone: controller.close,
            );
      } catch (error) {
        _logDebug('Firestore read status: error');
        _logError('watchConnection', error);
        controller.addError(error);
      }
    });

    return controller.stream;
  }

  Stream<List<GoogleCalendarImportEvent>> watchImportEvents() {
    final uid = _requireUid();
    return _eventsCollection(uid)
        .orderBy('startDate', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => GoogleCalendarImportEvent.fromMap(doc.id, doc.data()),
              )
              .toList(growable: false),
        );
  }

  Future<Uri> getAuthorizationUrl() async {
    _logDebug('callable function start: getGoogleCalendarAuthorizationUrl');
    final callable = _functions.httpsCallable(
      'getGoogleCalendarAuthorizationUrl',
    );
    try {
      final result = await callable.call(<String, dynamic>{});
      _logDebug('callable function success: getGoogleCalendarAuthorizationUrl');
      final data = Map<String, dynamic>.from(result.data as Map);
      final rawUrl = (data['authorizationUrl'] as String?)?.trim() ?? '';
      _logDebug('authorization payload keys: ${data.keys.join(',')}');
      _logDebug('authorization url length: ${rawUrl.length}');

      final uri = Uri.tryParse(rawUrl);
      final hasValidScheme =
          uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
      if (!hasValidScheme) {
        throw StateError('Neispravan Google OAuth URL.');
      }
      return uri;
    } catch (error) {
      _logError('getGoogleCalendarAuthorizationUrl', error);
      rethrow;
    }
  }

  Future<void> handleOAuthCallback({
    required String code,
    required String state,
  }) async {
    _logDebug('callable function start: handleGoogleCalendarOAuthCallback');
    final callable = _functions.httpsCallable(
      'handleGoogleCalendarOAuthCallback',
    );
    try {
      await callable.call(<String, dynamic>{'code': code, 'state': state});
      _logDebug('callable function success: handleGoogleCalendarOAuthCallback');
    } catch (error) {
      _logError('handleGoogleCalendarOAuthCallback', error);
      rethrow;
    }
  }

  Future<List<GoogleCalendarOption>> listCalendars() async {
    _logDebug('callable function start: listGoogleCalendars');
    final callable = _functions.httpsCallable('listGoogleCalendars');
    try {
      final result = await callable.call(<String, dynamic>{});
      _logDebug('callable function success: listGoogleCalendars');
      final data = Map<String, dynamic>.from(result.data as Map);
      final calendars = (data['calendars'] as List?) ?? const [];
      return calendars
          .whereType<Map>()
          .map(
            (item) =>
                GoogleCalendarOption.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } catch (error) {
      _logError('listGoogleCalendars', error);
      rethrow;
    }
  }

  Future<GoogleCalendarSyncResponse> syncNow({
    String? selectedCalendarId,
    bool forceFull = false,
  }) async {
    _logDebug('callable function start: syncGoogleCalendarEvents');
    final callable = _functions.httpsCallable('syncGoogleCalendarEvents');
    try {
      final result = await callable.call(<String, dynamic>{
        if (selectedCalendarId != null && selectedCalendarId.trim().isNotEmpty)
          'selectedCalendarId': selectedCalendarId.trim(),
        'forceFull': forceFull,
      });
      _logDebug('callable function success: syncGoogleCalendarEvents');
      return GoogleCalendarSyncResponse.fromMap(
        Map<String, dynamic>.from(result.data as Map),
      );
    } catch (error) {
      _logError('syncGoogleCalendarEvents', error);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _logDebug('callable function start: disconnectGoogleCalendar');
    final callable = _functions.httpsCallable('disconnectGoogleCalendar');
    try {
      await callable.call(<String, dynamic>{});
      _logDebug('callable function success: disconnectGoogleCalendar');
    } catch (error) {
      _logError('disconnectGoogleCalendar', error);
      rethrow;
    }
  }

  Future<void> setAutoSyncEnabled(bool enabled) async {
    final uid = _requireUid();
    await _connectionDoc(uid).set({
      'uid': uid,
      'autoSyncEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> selectCalendar(GoogleCalendarOption calendar) async {
    final uid = _requireUid();
    await _connectionDoc(uid).set({
      'uid': uid,
      'selectedCalendarId': calendar.id,
      'selectedCalendarName': calendar.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> ignoreImportEvent(String eventId) async {
    final uid = _requireUid();
    await _eventsCollection(uid).doc(eventId).set({
      'importStatus': GoogleCalendarImportStatus.ignored.name,
      'ignoredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> markImported({
    required String eventId,
    String? reservationId,
  }) async {
    final uid = _requireUid();
    await _eventsCollection(uid).doc(eventId).set({
      'importStatus': GoogleCalendarImportStatus.imported.name,
      if (reservationId != null && reservationId.trim().isNotEmpty)
        'linkedReservationId': reservationId.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<AuthDiagnostics> getAuthDiagnostics({
    bool forceRefreshToken = true,
  }) async {
    final user = _auth.currentUser;
    final userExists = user != null;
    final uid = user?.uid ?? '';
    final email = user?.email ?? '';
    final emailVerified = user?.emailVerified ?? false;

    _logDebug('currentUser exists: $userExists');
    _logDebug('uid exists: ${uid.isNotEmpty}');
    if (uid.isNotEmpty) {
      _logDebug('uid: $uid');
    }
    if (email.isNotEmpty) {
      _logDebug('email: $email');
    }
    _logDebug('emailVerified: $emailVerified');

    if (!userExists) {
      _logDebug('admin claim present: false');
      _logDebug('admin claim value: false');
      return const AuthDiagnostics(
        userExists: false,
        uid: '',
        email: '',
        emailVerified: false,
        adminClaimPresent: false,
        adminClaimValue: false,
      );
    }

    if (forceRefreshToken) {
      await user.getIdToken(true);
    }
    final tokenResult = await user.getIdTokenResult(true);
    final claims = tokenResult.claims ?? const <String, dynamic>{};
    final adminClaimPresent = claims.containsKey('admin');
    final adminClaimValue = claims['admin'] == true;

    _logDebug('admin claim present: $adminClaimPresent');
    _logDebug('admin claim value: $adminClaimValue');

    return AuthDiagnostics(
      userExists: true,
      uid: uid,
      email: email,
      emailVerified: emailVerified,
      adminClaimPresent: adminClaimPresent,
      adminClaimValue: adminClaimValue,
    );
  }
}
