# Camp Sugar Manager — Project Status

**Datum zadnje provjere:** 2026-06-21

---

## 1. PROJEKT

| Stavka               | Vrijednost                                                                 |
|----------------------|----------------------------------------------------------------------------|
| Naziv projekta       | Camp Sugar Manager                                                         |
| Puni path            | `/Users/trpimirsugar/Developer/FlutterProjects/Camp Sugar Manager`         |
| Firebase project ID  | `camp-sugar-manager`                                                       |
| GitHub remote        | `https://github.com/trpa04-bot/camp-sugar-manager.git`                    |
| Aktivni branch       | `main`                                                                     |
| Zadnji commit        | `c33723e` — "Stable Camp Sugar Manager core with OCR guests and check-in flow" |
| Necommitane izmjene  | **DA** — mnogo modificiranih i novih datoteka (Google Calendar modul, import flow itd.) |

---

## 2. FIREBASE

| Stavka               | Vrijednost                                                                 |
|----------------------|----------------------------------------------------------------------------|
| Firebase project ID  | `camp-sugar-manager`                                                       |
| Hosting URL          | `https://camp-sugar-manager.web.app`                                       |
| Hosting zadnji deploy | 2026-06-20 21:42:46                                                      |
| Functions region     | `europe-west1`                                                             |

---

## 3. GOOGLE CALENDAR INTEGRACIJA

### OAuth Callback URL (točan)
```
https://europe-west1-camp-sugar-manager.cloudfunctions.net/googleCalendarOAuthCallback
```
> Ovaj URL mora biti upisan kao Authorized Redirect URI u Google Cloud Console → OAuth Client.

### Firebase Functions (definirane u kodu, još nisu deployane):
- `getGoogleCalendarAuthorizationUrl`
- `googleCalendarOAuthCallback`
- `listGoogleCalendars`
- `syncGoogleCalendarEvents`
- `disconnectGoogleCalendar`
- `scheduledGoogleCalendarSync`

---

## 4. FIREBASE SECRETS STATUS

| Secret                        | Status                                                     |
|-------------------------------|------------------------------------------------------------|
| GOOGLE_CALENDAR_CLIENT_ID     | **KREIRAN, ali bez vrijednosti** (unos nije prošao)        |
| GOOGLE_CALENDAR_CLIENT_SECRET | **NE POSTOJI** — treba kreirati                            |
| GOOGLE_CALENDAR_REDIRECT_URI  | **NE POSTOJI** — treba kreirati                            |

---

## 5. GLAVNI MODULI

- **Auth** — Firebase Authentication
- **Reservations** — upravljanje rezervacijama
- **OCR / Import** — skeniranje gostiju putem kamere (google_mlkit_text_recognition)
- **Google Calendar** — integracija (u tijeku, nije deployano)
- **Check-in flow** — prijem gostiju

---

## 6. ŠTO JE DEPLOYANO

- Flutter web app na Firebase Hosting (`https://camp-sugar-manager.web.app`)
- Stabilan core (OCR, check-in, rezervacije)

## 7. ŠTO NIJE KONFIGURIRANO / DEPLOYANO

- Google Calendar Firebase Functions (kod postoji, secrets nedostaju, deploy nije napravljen)
- Firebase Secrets (CLIENT_ID bez vrijednosti, CLIENT_SECRET i REDIRECT_URI ne postoje)

---

## 8. SLJEDEĆI KORACI (redom)

### Korak 1 — Postavi GOOGLE_CALENDAR_CLIENT_ID
```bash
firebase functions:secrets:set GOOGLE_CALENDAR_CLIENT_ID
```
Vrijednost: pronađi u Google Cloud Console → Google Auth Platform → Clients → Camp Sugar Manager Web

### Korak 2 — Postavi GOOGLE_CALENDAR_CLIENT_SECRET
```bash
firebase functions:secrets:set GOOGLE_CALENDAR_CLIENT_SECRET
```
(Ne šalji u chat — upiši direktno u terminal)

### Korak 3 — Postavi GOOGLE_CALENDAR_REDIRECT_URI
```bash
firebase functions:secrets:set GOOGLE_CALENDAR_REDIRECT_URI
```
Vrijednost:
```
https://europe-west1-camp-sugar-manager.cloudfunctions.net/googleCalendarOAuthCallback
```

### Korak 4 — Provjeri Google Cloud Console
U Google Cloud Console → OAuth Client → Authorized redirect URIs dodaj:
```
https://europe-west1-camp-sugar-manager.cloudfunctions.net/googleCalendarOAuthCallback
```

### Korak 5 — Deploy Functions
```bash
cd "/Users/trpimirsugar/Developer/FlutterProjects/Camp Sugar Manager"
firebase deploy --only functions
```

---

## 9. KORISNE NAREDBE

### Pokretanje aplikacije lokalno
```bash
cd "/Users/trpimirsugar/Developer/FlutterProjects/Camp Sugar Manager"
flutter run -d chrome
```

### Build za web
```bash
flutter build web
```

### Deploy hosting
```bash
firebase deploy --only hosting
```

### Deploy sve
```bash
firebase deploy
```

### Provjera secretsa
```bash
firebase functions:secrets:get GOOGLE_CALENDAR_CLIENT_ID
```

---

## 10. NAPOMENE

- **Nikad ne upisuj tajne (Client Secret, tokeni) u Copilot chat** — upisuj ih direktno u terminal
- Sve necommitane izmjene su dio Google Calendar integracije i import flow-a
- Commitaj tek kad je Google Calendar integracija funkcionalna i testirana
