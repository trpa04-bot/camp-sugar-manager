/// Zajedničke pomoćne funkcije za rad s datumima i obračunom noćenja.
///
/// Ovaj modul centralizira logiku koja se prije ponavljala kroz desetke
/// datoteka (npr. `_formatDate`, "danas" izračun, broj noćenja). Time se
/// smanjuje rizik od nekonzistentnosti i grešaka te olakšava održavanje.
///
/// Ponašanje je namjerno usklađeno s postojećim implementacijama u aplikaciji:
/// - format datuma: `dd.MM.yyyy`
/// - "noćenja" se računaju kao razlika u danima, uz minimalnu vrijednost
///   ovisno o kontekstu (vidi pojedine metode).
library;

/// Vraća datum bez vremenske komponente (ponoć istog dana).
///
/// Zamjenjuje ponavljani obrazac:
/// `DateTime(value.year, value.month, value.day)`.
DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Vraća današnji datum bez vremenske komponente.
///
/// Opcionalni [now] omogućuje deterministicno testiranje.
DateTime today({DateTime? now}) {
  return dateOnly(now ?? DateTime.now());
}

/// Provjerava jesu li dva datuma isti kalendarski dan (ignorira vrijeme).
///
/// Zamjenjuje ponavljane `_isSameDate` / `_isSameDay` implementacije.
bool isSameDate(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

/// Formatira datum u oblik `dd.MM.yyyy` (npr. `05.07.2026`).
///
/// Usklađeno s postojećim `_formatDate` implementacijama u aplikaciji.
String formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

/// Formatira nullable datum; vraća [fallback] (zadano `-`) kada je vrijednost
/// `null`. Usklađeno s ponašanjem na ekranima gostiju i kalendara.
String formatDateOrDash(DateTime? value, {String fallback = '-'}) {
  if (value == null) {
    return fallback;
  }
  return formatDate(value);
}

/// Formatira raspon datuma kao `dd.MM.yyyy - dd.MM.yyyy`.
String formatDateRange(DateTime start, DateTime end) {
  return '${formatDate(start)} - ${formatDate(end)}';
}

/// Broj kalendarskih noćenja između dva datuma (ignorira vrijeme).
///
/// [minimum] postavlja donju granicu rezultata. Različiti dijelovi aplikacije
/// koriste različite minimume:
/// - obračun cijene za potvrđenu rezervaciju koristi `minimum: 1`
///   (uvijek se naplaćuje barem jedna noć),
/// - prikaz proteklih noćenja gosta koristi `minimum: 0`.
int nightsBetween(DateTime checkIn, DateTime checkOut, {int minimum = 0}) {
  final start = dateOnly(checkIn);
  final end = dateOnly(checkOut);
  final nights = end.difference(start).inDays;
  return nights < minimum ? minimum : nights;
}
