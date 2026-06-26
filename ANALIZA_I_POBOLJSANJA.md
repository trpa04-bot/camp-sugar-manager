# Camp Sugar Manager — Analiza projekta i prijedlozi poboljšanja

**Pripremio:** Manus &nbsp;•&nbsp; **Datum:** 26.06.2026.
**Predmet:** Pregled postojećeg Flutter projekta, ocjena kvalitete koda i konkretni, dokazani prijedlozi unapređenja.

---

## 1. Sažetak

Camp Sugar Manager je **ozbiljna, dobro strukturirana Flutter aplikacija** za upravljanje kampom. Riječ je o znatno naprednijem projektu nego što je tipično za rad uz pomoć ChatGPT-a i Copilota — vidljivo je da postoji promišljena arhitektura, podjela po značajkama (*feature-first*), te — što je najvažnije — **opsežan skup testova (179 testova)**.

Ono što sam napravio u ovom pregledu:

1. Pročitao i analizirao cijeli projekt (74 Dart datoteke, ~23.800 linija).
2. Identificirao konkretne, mjerljive prilike za poboljšanje.
3. **Stvarno implementirao jedno poboljšanje** kao dokaz pristupa (zajednička biblioteka za datume) i **dokazao da radi**: `flutter analyze` bez ijedne greške, svih **179 testova prolazi**.

> Ključna poruka: kod je u dobrom stanju. Najveća vrijednost koju mogu donijeti nije "popravljanje", nego **smanjivanje ponavljanja, razbijanje velikih datoteka i uvođenje jasnog sloja podataka** kako bi projekt ostao održiv kako raste.

---

## 2. Pregled projekta

| Stavka | Vrijednost |
|---|---|
| Tip | Flutter aplikacija (Android, iOS, Web, Desktop) |
| Broj Dart datoteka | 74 |
| Ukupno linija koda (lib) | ~23.800 |
| Broj testova | 179 (svi prolaze) |
| Backend | Firebase: Auth, Firestore, Storage, Cloud Functions |
| Napredne značajke | OCR skeniranje dokumenata (ML Kit + MRZ parser), Google Calendar sinkronizacija, Cloud Vision |
| State management | Ugrađeni Flutter (`StatefulWidget` + `setState` + `StreamBuilder`) |

**Glavni moduli:** rezervacije, gosti, parcele (pitch-evi), plaćanja, dashboard, skeniranje dokumenata, Google Calendar.

---

## 3. Što je već jako dobro

Važno je istaknuti jake strane jer one znače da projekt ima zdrave temelje:

- **Feature-first organizacija** — svaki modul ima vlastite `models/`, `services/`, `widgets/`, `pages/`. Ovo je preporučena struktura za rast aplikacije.
- **Odvojen sloj servisa** — Firestore pozivi su uglavnom izdvojeni u `*_service.dart` klase, a ne razbacani po widgetima.
- **Dependency injection kroz konstruktore** — servisi primaju `FirebaseFirestore? firestore`, što omogućuje testiranje s `fake_cloud_firestore`. Ovo je znak zrelog pristupa.
- **Robusna deserijalizacija** — model `Reservation` koristi sigurne pomoćne metode (`_readInt`, `_readDouble`, `_readDate`) s `null`-fallbackovima, pa neispravni podaci iz baze ne ruše aplikaciju.
- **Sigurnosna pravila postoje** — `firestore.rules` i `storage.rules` su definirana, s admin-only zaštitom za Google Calendar tokene i tajne. Ovo je često zanemareno, a ovdje je dobro odrađeno.
- **Graciozno rukovanje greškama pri pokretanju** — `main.dart` ima zaseban prikaz ako Firebase ne uspije krenuti.
- **Bez `print()` poziva** — koristi se `debugPrint` (27 mjesta), što je ispravno.

---

## 4. Glavne prilike za poboljšanje

Poredano po omjeru koristi i truda.

### 4.1. Ponavljanje koda za datume i obračun (VISOK prioritet) — *RIJEŠENO u demu*

Ista logika ponavlja se kroz cijeli projekt:

| Obrazac | Broj pojavljivanja |
|---|---|
| `_formatDate` (ista metoda kopirana) | 11 definicija u 11 datoteka |
| "danas" izračun `DateTime(now.year, now.month, now.day)` | 38+ mjesta |
| Izračun noćenja `difference(...).inDays` | 8 mjesta |
| `_isSameDate` / `_isSameDay` | više kopija |

**Zašto je to problem:** ako se ikad promijeni format datuma ili pravilo obračuna noćenja, morate ručno mijenjati 10+ mjesta — i lako je promašiti neko, što stvara suptilne greške.

**Što sam napravio:** uveo sam `lib/core/utils/date_utils.dart` s jasnim, testiranim funkcijama (`formatDate`, `dateOnly`, `today`, `isSameDate`, `nightsBetween`, `formatDateRange`, `formatDateOrDash`) i napisao **13 jediničnih testova**. Zatim sam refaktorirao tri datoteke da koriste novu biblioteku kao primjer. **Sve provjereno: 0 grešaka u analizi, svih 179 testova prolazi.**

### 4.2. Vrlo velike datoteke (VISOK prioritet)

Nekoliko datoteka je preraslo zdravu granicu (preporuka: < 400 linija po datoteci):

| Datoteka | Linije |
|---|---|
| `reservation_form_dialog.dart` | 1.810 |
| `reservation_service.dart` | 1.503 |
| `reservations_page.dart` | 1.399 |
| `reservation_document_scan_sheet.dart` | 1.372 |
| `document_guest_verification_dialog.dart` | 1.316 |
| `parcels_page.dart` | 1.210 |
| `reservation_import_parser.dart` | 1.089 |

**Preporuka:** `reservation_service.dart` trenutno miješa rezervacije, goste, dokumente, stanje parcela i plaćanja u jednoj klasi. Predlažem podjelu na: `ReservationRepository`, `GuestRepository`, `PaymentReconciler`, `PitchOccupancyUpdater`. Slično, `reservation_form_dialog.dart` može se razdvojiti na manje pod-widgete (sekcija gosta, sekcija plaćanja, sekcija parcele) i izdvojiti poslovnu logiku cijene u zaseban "controller".

### 4.3. State management (SREDNJI prioritet)

Aplikacija koristi `setState` intenzivno — u jednoj datoteci čak **27 poziva**, u drugoj 25. To radi, ali kako aplikacija raste postaje teško pratiti tok podataka i lako dolazi do nepotrebnih ponovnih iscrtavanja.

**Preporuka:** postupno uvođenje lakog rješenja poput **Riverpod** (ili `provider`). Ne treba prepisivati sve odjednom — može se krenuti od jednog modula (npr. dashboard) i širiti. Korist: čišće odvajanje UI-a od logike, lakše testiranje, manje `setState` "vodoinstalaterstva".

### 4.4. Izravno instanciranje servisa (SREDNJI prioritet)

Servisi se na više mjesta stvaraju izravno (`ReservationService()`, `PitchService()` itd.) unutar widgeta. Iako konstruktori podržavaju injekciju, widgeti je ne koriste, pa su čvrsto vezani uz konkretnu implementaciju.

**Preporuka:** centralizirati pružanje servisa (kroz Riverpod provider ili jednostavan DI), čime se olakšava testiranje i zamjena implementacija.

### 4.5. Sigurnosna pravila Firestorea (SREDNJI–VISOK prioritet)

Trenutna pravila dopuštaju **svakom prijavljenom korisniku čitanje i pisanje gotovo svih kolekcija**:

```
match /{collection}/{docId} {
  allow read, write: if signedIn() && !collection.matches('googleCalendar.*');
}
```

Za internu aplikaciju s povjerljivim osobljem to može biti prihvatljivo, ali ako ikada bude više korisnika/uloga, ovo je preširoko. **Preporuka:** uvesti uloge (npr. `admin`, `osoblje`) i ograničiti pisanje na potrebne kolekcije, te validirati oblik podataka pri pisanju (kao što je već lijepo napravljeno za Google Calendar).

### 4.6. Lokalizacija i prikaz (NIZAK prioritet)

UI tekstovi su tvrdo kodirani na hrvatskom (npr. "Nije placeno" bez dijakritike na nekim mjestima). Ako se planira višejezičnost ili dosljedna dijakritika, vrijedi uvesti `flutter_localizations` + ARB datoteke. Niskog je prioriteta ako je aplikacija namijenjena samo domaćem tržištu.

### 4.7. Format datuma kroz `intl` (NIZAK prioritet)

Ručno formatiranje (`padLeft`) radi, ali paket `intl` daje lokalizirane formate, nazive mjeseci i robusnije parsiranje ako zatreba.

---

## 5. Dokaz: što je konkretno napravljeno u ovom pregledu

| Akcija | Rezultat |
|---|---|
| Nova datoteka `lib/core/utils/date_utils.dart` | 7 zajedničkih, dokumentiranih funkcija |
| Novi testovi `test/core/utils/date_utils_test.dart` | 13 jediničnih testova |
| Refaktorirano `dashboard_stats_service.dart` | Koristi `nightsBetween(...)` |
| Refaktorirano `guests_page.dart` | Koristi `formatDateOrDash`, `formatDateRange` |
| Refaktorirano `reservation_details_sheet.dart` | Koristi `formatDate` |
| `flutter analyze` (cijeli projekt) | **No issues found** |
| `flutter test` (cijeli projekt) | **All tests passed — 179/179** |

Ponašanje aplikacije je **nepromijenjeno** — radi se o čistom refaktoriranju koje smanjuje buduće greške. Ovo je samo demonstracija; istu biblioteku možete dalje primijeniti na preostalih ~7 datoteka koje još imaju kopirani kod.

---

## 6. Predloženi plan rada (ako želite nastaviti zajedno)

Predlažem postupni pristup u kojem **vi zadržavate potpunu kontrolu** i nastavljate raditi u Flutteru/VS Code, a ja preuzimam veće, dosadne ili rizične refaktore uz testove kao zaštitnu mrežu:

1. **Faza 1 — Čišćenje (nizak rizik):** Dovršiti primjenu `date_utils` na sve datoteke; izdvojiti još zajedničkih util-a (formatiranje novca, statusi). *Zaštita: postojeći testovi.*
2. **Faza 2 — Razbijanje velikih datoteka:** Podijeliti `reservation_service.dart` i `reservation_form_dialog.dart` na manje, jasne dijelove. *Uz nove testove.*
3. **Faza 3 — State management:** Uvesti Riverpod na jednom modulu kao pilot, pa proširiti.
4. **Faza 4 — Sigurnost i uloge:** Pooštriti Firestore pravila i dodati uloge ako je potrebno.
5. **Faza 5 — Nove značajke:** Što god vi želite (npr. izvještaji/PDF, statistika prihoda, push obavijesti, izvoz podataka).

---

## 7. Kako koristiti isporučeni projekt

U priloženom ZIP-u nalazi se vaš **cijeli projekt s primijenjenim poboljšanjima**. Možete ga otvoriti u VS Code-u i nastaviti raditi kao i dosad:

```bash
flutter pub get
flutter analyze      # očekivano: No issues found
flutter test         # očekivano: All tests passed (179)
flutter run          # pokretanje aplikacije
```

Sve nove i izmijenjene datoteke navedene su u poglavlju 5. Ništa od vaše originalne logike nije uklonjeno — samo je centralizirano.

---

*Recite mi koji vas smjer najviše zanima (npr. razbijanje `reservation_service.dart`, uvođenje Riverpoda, ili neka nova značajka) pa krećemo na konkretno.*
