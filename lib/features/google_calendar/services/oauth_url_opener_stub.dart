import 'package:url_launcher/url_launcher.dart';

Future<void> openOAuthUrlImpl(Uri authorizationUrl) async {
  final launched = await launchUrl(
    authorizationUrl,
    mode: LaunchMode.platformDefault,
    webOnlyWindowName: '_self',
  );

  if (!launched) {
    throw StateError('Google OAuth URL nije moguće otvoriti.');
  }
}
