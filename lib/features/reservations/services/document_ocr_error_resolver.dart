import 'package:cloud_functions/cloud_functions.dart';

/// Translates low-level upload/OCR errors into clear, actionable Croatian
/// messages for the end user.
///
/// Previously every failure collapsed into a single generic string
/// ("OCR nije uspio." / "Datoteka se ne može pročitati."), which made it
/// impossible to tell whether the problem was authentication, a missing file,
/// an unsupported format, or a backend outage. This resolver inspects the error
/// type and Firebase Functions error code to surface the real cause.
class DocumentOcrErrorResolver {
  const DocumentOcrErrorResolver();

  String resolve(Object error) {
    if (error is FirebaseFunctionsException) {
      return _resolveFunctions(error);
    }

    final message = error.toString().toLowerCase();

    if (message.contains('heic') || message.contains('heif')) {
      return 'HEIC/HEIF format nije podržan u pregledniku. Odaberite JPG ili PNG '
          'fotografiju, ili na iPhoneu postavite format kamere na '
          '"Najkompatibilnije".';
    }
    if (message.contains('prazn') || message.contains('empty')) {
      return 'Slika je prazna. Odaberite drugu fotografiju.';
    }
    if (message.contains('bucket')) {
      return 'Pohrana datoteka (Firebase Storage) nije ispravno konfigurirana. '
          'Provjerite Firebase postavke aplikacije.';
    }
    if (message.contains('prijav') ||
        message.contains('unauth') ||
        message.contains('token')) {
      return 'Niste prijavljeni ili je sesija istekla. Prijavite se ponovno i '
          'pokušajte opet.';
    }
    if (message.contains('podrž') || message.contains('format')) {
      return 'Nepodržan format datoteke. Podržani su JPG, JPEG i PNG.';
    }
    if (message.contains('quality') || message.contains('kvalitet')) {
      return 'Provjera kvalitete slike nije uspjela. Slikajte dokument oštrije, '
          'bez odsjaja i u boljem svjetlu.';
    }
    if (message.contains('network') ||
        message.contains('mreža') ||
        message.contains('socket') ||
        message.contains('timeout')) {
      return 'Problem s mrežom. Provjerite internetsku vezu i pokušajte opet.';
    }
    if (message.contains('upload')) {
      return 'Upload slike nije uspio. Provjerite vezu i pokušajte ponovno.';
    }

    return 'Obrada dokumenta nije uspjela. Pokušajte ponovno ili odaberite '
        'drugu fotografiju.';
  }

  String _resolveFunctions(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Niste prijavljeni za obradu dokumenta. Prijavite se ponovno i '
            'pokušajte opet.';
      case 'permission-denied':
        return 'Nemate ovlasti za obradu ovog dokumenta, ili putanja slike nije '
            'ispravna. ${_detail(error)}';
      case 'not-found':
        return 'Slika dokumenta nije pronađena na poslužitelju. Pokušajte '
            'ponovno učitati fotografiju.';
      case 'invalid-argument':
        return 'Zahtjev za obradu nije ispravan. ${_detail(error)}';
      case 'resource-exhausted':
        return 'Previše zahtjeva u kratkom vremenu. Pričekajte trenutak pa '
            'pokušajte ponovno.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'Usluga za obradu dokumenata trenutno nije dostupna. Pokušajte '
            'ponovno za nekoliko trenutaka.';
      case 'internal':
      default:
        return 'OCR obrada nije uspjela na poslužitelju (Google Vision). '
            'Provjerite jesu li Cloud Functions objavljene i pokušajte ponovno.';
    }
  }

  String _detail(FirebaseFunctionsException error) {
    final message = error.message?.trim();
    if (message == null || message.isEmpty) {
      return '';
    }
    return message;
  }
}
