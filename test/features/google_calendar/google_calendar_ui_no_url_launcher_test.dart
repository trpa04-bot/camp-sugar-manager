import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google Calendar UI module does not call url_launcher directly', () {
    final settingsSource = File(
      'lib/features/google_calendar/google_calendar_settings_page.dart',
    ).readAsStringSync();
    final serviceSource = File(
      'lib/features/google_calendar/services/google_calendar_service.dart',
    ).readAsStringSync();

    const forbiddenSnippets = <String>[
      'import \'package:url_launcher/url_launcher.dart\'',
      'launchUrl(',
      'launch(',
      'UrlLauncherPlatform.instance.launchUrl',
      "MethodChannel('plugins.flutter.io/url_launcher')",
      'plugins.flutter.io/url_launcher',
    ];

    for (final snippet in forbiddenSnippets) {
      expect(settingsSource.contains(snippet), isFalse);
      expect(serviceSource.contains(snippet), isFalse);
    }

    expect(settingsSource.contains('await openOAuthUrl('), isTrue);
  });
}
