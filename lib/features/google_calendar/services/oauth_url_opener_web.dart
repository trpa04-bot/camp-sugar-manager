import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

Future<void> openOAuthUrlImpl(Uri authorizationUrl) async {
  if (authorizationUrl.scheme != 'https') {
    throw StateError('OAuth URL mora koristiti HTTPS.');
  }

  debugPrint('OAuth opener implementation: web');
  web.window.location.assign(authorizationUrl.toString());
}
