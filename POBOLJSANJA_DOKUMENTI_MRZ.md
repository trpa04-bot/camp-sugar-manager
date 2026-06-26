# Poboljšanja: Upload dokumenata i MRZ skeniranje

**Pripremio:** Manus &nbsp;•&nbsp; **Datum:** 26.06.2026.
**Predmet:** Dijagnoza zašto upload slika dokumenata i MRZ skeniranje nisu radili te maksimalno unapređenje tih funkcionalnosti.

---

## 1. Sažetak

Pronašao sam i otklonio glavne uzroke zbog kojih upload slika dokumenata i MRZ skeniranje nisu radili pouzdano, posebno u web pregledniku. Sve promjene su provjerene: **`flutter analyze` bez ijedne greške** i **svih 186 testova prolazi** (7 novih testova za nove module).

Najvažnije za vas: kad sad nešto pođe po zlu, aplikacija će vam reći **točan razlog** umjesto generičke poruke, pa je problem moguće riješiti u sekundama umjesto nagađanjem.

---

## 2. Što nije radilo i zašto

| # | Problem | Uzrok | Status |
|---|---------|-------|--------|
| 1 | Generičke poruke o greškama | Svi različiti uzroci (auth, format, mreža, backend) sažimali su se u "OCR nije uspio." / "Datoteka se ne može pročitati." | **Riješeno** |
| 2 | Tihi kvar kod HEIC/HEIF slika | Web kod je kod neuspjele konverzije u JPEG **tiho** slao sirove (nedekodive) bajtove dalje, pa je upload "prošao" a kvaliteta/OCR pao bez jasnog razloga | **Riješeno** |
| 3 | MRZ ne radi na webu | `mrz_scanner_service.dart` koristio `dart:io` (`File`, temp direktorij), a `mrz_scanner_sheet.dart` native kameru — ništa od toga ne postoji u pregledniku | **Riješeno (web-safe put)** |
| 4 | Slab MRZ parser | Lokalni parser je tražio gotovo savršene MRZ linije i lako "pao" na realnom OCR tekstu (razmaci, okolni tekst, OCR zamjene znakova) | **Riješeno (robusni finder + parser)** |

---

## 3. Konkretne izmjene

### 3.1. Robusni MRZ pronalazak — `MrzLineFinder` (novo)
Nova datoteka `lib/features/document_scan/mrz/mrz_line_finder.dart` izvlači MRZ iz **bilo kojeg** OCR teksta:
- prepoznaje i čisti MRZ retke usred ljudski čitljivog teksta (npr. "REPUBLIKA HRVATSKA … PASSPORT"),
- uklanja razmake i mala slova, zadržava samo dopuštene znakove (A–Z, 0–9, `<`),
- automatski **poravnava** retke na točnu duljinu (TD1=30, TD2=36, TD3=44), uključujući blago skraćene OCR retke.

Pokriveno s **5 jediničnih testova**.

### 3.2. Web-sigurno MRZ skeniranje — `MrzScannerService` (refaktorirano)
`lib/features/reservations/services/mrz_scanner_service.dart` sada:
- koristi `MrzLineFinder` + postojeći jaki `MrzParser` (puna ICAO 9303 validacija kontrolnih znamenki i ispravak OCR zamjena O↔0, I↔1, B↔8…),
- ima novu metodu **`scanRecognizedText(String)`** koja radi **bez `dart:io`** — dakle i u pregledniku — parsirajući OCR tekst (npr. onaj koji vraća backend Google Vision),
- ispravno konvertira datume u format aplikacije (`dd.MM.yyyy`) i razdvaja imena.

Pokriveno s **2 nova testa** (parsiranje TD3 putovnice iz "prljavog" OCR teksta + jasna greška kad MRZ ne postoji).

### 3.3. Precizne poruke o greškama — `DocumentOcrErrorResolver` (novo)
`lib/features/reservations/services/document_ocr_error_resolver.dart` prevodi tehničke greške u jasne hrvatske poruke. Primjeri:

| Uzrok (kod) | Što korisnik sada vidi |
|---|---|
| `unauthenticated` | "Niste prijavljeni za obradu dokumenta. Prijavite se ponovno…" |
| `not-found` | "Slika dokumenta nije pronađena na poslužitelju…" |
| `permission-denied` | "Nemate ovlasti…/putanja slike nije ispravna…" |
| `internal` (Vision) | "OCR obrada nije uspjela na poslužitelju (Google Vision). Provjerite jesu li Cloud Functions objavljene…" |
| HEIC/HEIF | "HEIC/HEIF format nije podržan u pregledniku. Odaberite JPG/PNG…" |
| Mrežni problem | "Problem s mrežom. Provjerite internetsku vezu…" |

### 3.4. Uklonjen tihi fallback na webu
`document_image_source_adapter_web.dart` više **ne** šalje nedekodive HEIC/HEIF bajtove dalje. Ako preglednik ne može pretvoriti HEIC u JPEG, korisnik odmah dobije jasnu, korisnu uputu (npr. kako na iPhoneu promijeniti format kamere).

### 3.5. Jasnija web MRZ poruka
Umjesto "MRZ kamera nije dostupna", korisnik sada vidi: *"U pregledniku se MRZ čita iz fotografije dokumenta. Učitajte ili slikajte donji dio dokumenta — podaci se prepoznaju automatski."*

---

## 4. Dokaz ispravnosti

| Provjera | Rezultat |
|---|---|
| `flutter analyze` (cijeli projekt) | **No issues found** |
| `flutter test` (cijeli projekt) | **186/186 prolazi** (prethodno 179) |
| Novi testovi | 7 (5 za `MrzLineFinder`, 2 za `MrzScannerService`) |
| `flutter build web --release` | **Uspješno** |

---

## 5. Važno: zašto je potreban Firebase backend

Upload i OCR ovise o Firebase infrastrukturi koju ja iz ovog okruženja ne mogu konfigurirati umjesto vas. Da bi sve radilo **na živo** (i u web preglednik linku), potrebno je:

1. **Cloud Functions objavljene** — funkcija `processDocumentOcrCallable` (regija `europe-west1`) mora biti deployana i imati pristup **Google Vision API**-ju. Bez toga OCR vraća `internal` grešku (sada s jasnom porukom).
2. **Autorizirana domena** — za prijavu i pozive iz web preglednika, domena mora biti u Firebase Console → Authentication → Settings → *Authorized domains*.
3. **Storage bucket** — aplikacija očekuje `camp-sugar-manager.firebasestorage.app`. Ako se razlikuje, upload javlja jasnu poruku o konfiguraciji.

Na mobilnoj (native) aplikaciji MRZ dodatno radi i izravno preko kamere + ML Kit, neovisno o backendu.

---

## 6. Popis novih/izmijenjenih datoteka

**Nove:**
- `lib/features/document_scan/mrz/mrz_line_finder.dart`
- `lib/features/reservations/services/document_ocr_error_resolver.dart`
- `test/features/document_scan/mrz/mrz_line_finder_test.dart`
- `test/features/reservations/services/mrz_scanner_service_test.dart`

**Izmijenjene:**
- `lib/features/reservations/services/mrz_scanner_service.dart` (robusno + web-safe)
- `lib/features/reservations/services/document_image_source_adapter_web.dart` (uklonjen tihi fallback)
- `lib/features/reservations/widgets/reservation_document_scan_sheet.dart` (precizne greške)
- `lib/features/reservations/widgets/reservation_details_sheet.dart` (jasnija web poruka)

---

*Sljedeći mogući korak: mogu vam pomoći objaviti Cloud Functions i ispravno konfigurirati Firebase domenu kako bi upload i OCR radili u potpunosti i na webu, ili dodatno poboljšati prepoznavanje (npr. automatsko popravljanje imena iz vizualnog dijela dokumenta — backend to već djelomično podržava).*
