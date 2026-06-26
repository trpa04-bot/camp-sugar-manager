import 'oauth_url_opener_stub.dart'
    if (dart.library.js_interop) 'oauth_url_opener_web.dart';

Future<void> openOAuthUrl(Uri authorizationUrl) {
  return openOAuthUrlImpl(authorizationUrl);
}
