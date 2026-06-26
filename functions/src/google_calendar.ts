import * as admin from "firebase-admin";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {defineSecret} from "firebase-functions/params";
import {google, calendar_v3} from "googleapis";
import {randomBytes} from "crypto";

const GOOGLE_CLIENT_ID = defineSecret("GOOGLE_CALENDAR_CLIENT_ID");
const GOOGLE_CLIENT_SECRET = defineSecret("GOOGLE_CALENDAR_CLIENT_SECRET");
const GOOGLE_REDIRECT_URI = defineSecret("GOOGLE_CALENDAR_REDIRECT_URI");

const CALENDAR_READONLY_SCOPE = "https://www.googleapis.com/auth/calendar.readonly";
const CONNECTIONS_COLLECTION = "googleCalendarConnections";
const IMPORT_EVENTS_SUBCOLLECTION = "importEvents";
const SECRET_COLLECTION = "googleCalendarSecrets";
const OAUTH_STATE_COLLECTION = "googleCalendarOAuthStates";
const SYNC_LOG_COLLECTION = "googleCalendarSyncLogs";
const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;
const WEB_APP_BASE_URL = "https://camp-sugar-manager.web.app";
const EXPECTED_REDIRECT_URI =
  "https://europe-west1-camp-sugar-manager.cloudfunctions.net/googleCalendarOAuthCallback";

interface SyncStats {
  newEvents: number;
  updatedEvents: number;
  cancelledEvents: number;
  needsReview: number;
  invalidSyncTokenRecovered: boolean;
  skippedCount: number;
  errorCount: number;
}

interface CalendarEventDoc {
  googleEventId: string;
  calendarId: string;
  title: string;
  description: string;
  location: string;
  startDate: admin.firestore.Timestamp;
  endDate: admin.firestore.Timestamp;
  isAllDay: boolean;
  eventStatus: string;
  updatedAtGoogle: admin.firestore.Timestamp | null;
  htmlLink: string | null;
  rawSource: "googleCalendar";
  parsedReservation: Record<string, unknown>;
  parseWarnings: string[];
  confidence: number;
  importStatus:
    | "newEvent"
    | "needsReview"
    | "imported"
    | "ignored"
    | "duplicate"
    | "cancelled"
    | "updatedAfterImport";
  linkedReservationId?: string;
  ignoredAt?: admin.firestore.Timestamp;
  createdAt?: admin.firestore.Timestamp;
  updatedAt?: admin.firestore.Timestamp;
}

function ensureAdmin(
  auth?: {uid?: string; token?: Record<string, unknown>} | null
): string {
  const uid = auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Korisnik nije autentificiran.");
  }
  const isAdmin = auth?.token?.admin === true;
  if (!isAdmin) {
    throw new HttpsError("permission-denied", "Samo admin može koristiti Google Calendar integraciju.");
  }
  return uid;
}

function sanitizeErrorMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  return raw
    .replace(/code=[^\s&]+/gi, "code=[redacted]")
    .replace(/state=[^\s&]+/gi, "state=[redacted]")
    .replace(/token=[^\s&]+/gi, "token=[redacted]")
    .replace(/client_secret=[^\s&]+/gi, "client_secret=[redacted]")
    .slice(0, 400);
}

function extractProviderOAuthError(error: unknown): {code?: string; description?: string} {
  const candidate = error as {
    response?: {data?: {error?: unknown; error_description?: unknown}};
  };

  const providerCode = candidate?.response?.data?.error;
  const providerDescription = candidate?.response?.data?.error_description;

  return {
    code: typeof providerCode === "string" && providerCode.trim() ? providerCode.trim() : undefined,
    description:
      typeof providerDescription === "string" && providerDescription.trim()
        ? providerDescription.trim().slice(0, 200)
        : undefined,
  };
}

function safeErrorCode(error: unknown): string {
  if (error instanceof HttpsError) {
    return error.code;
  }

  const providerError = extractProviderOAuthError(error);
  if (providerError.code) {
    return providerError.code;
  }

  const candidate = (error as {code?: string | number; status?: number}) || {};
  if (typeof candidate.code === "string" && candidate.code.trim()) {
    return candidate.code.trim();
  }
  if (typeof candidate.code === "number") {
    return String(candidate.code);
  }
  if (typeof candidate.status === "number") {
    return String(candidate.status);
  }
  return "unknown_error";
}

function renderCallbackErrorPage(errorCode: string): string {
  return `
<!doctype html>
<html lang="hr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Povezivanje nije dovršeno</title>
  </head>
  <body style="font-family: sans-serif; padding: 24px;">
    <h2>Povezivanje nije dovršeno</h2>
    <p>Kod greške: ${errorCode}</p>
    <p><a href="${WEB_APP_BASE_URL}/more">Povratak u Camp Sugar Manager</a></p>
  </body>
</html>`;
}

function readOAuthConfig() {
  const clientId = GOOGLE_CLIENT_ID.value().trim();
  const clientSecret = GOOGLE_CLIENT_SECRET.value().trim();
  const redirectUri = GOOGLE_REDIRECT_URI.value().trim();

  logger.info("oauth config checked", {
    clientIdPresent: clientId.length > 0,
    clientSecretPresent: clientSecret.length > 0,
    clientSecretLengthPositive: clientSecret.length > 0,
    redirectUriMatchesExpected: redirectUri === EXPECTED_REDIRECT_URI,
  });

  return {clientId, clientSecret, redirectUri};
}

function oauthClient() {
  const {clientId, clientSecret, redirectUri} = readOAuthConfig();
  return new google.auth.OAuth2(
    clientId,
    clientSecret,
    redirectUri
  );
}

function generateOAuthState(): string {
  return randomBytes(24).toString("base64url");
}

function normalizeReservationSource(text: string): string {
  const lower = text.toLowerCase();
  if (lower.includes("airbnb")) return "airbnb";
  if (lower.includes("campspace")) return "campspace";
  if (lower.includes("booking")) return "booking";
  if (lower.includes("whatsapp")) return "whatsapp";
  if (lower.includes("email") || lower.includes("poštovani")) return "email";
  return "other";
}

function parseDateOnly(value: string): Date {
  const [yearRaw, monthRaw, dayRaw] = value.split("-");
  const year = Number.parseInt(yearRaw, 10);
  const month = Number.parseInt(monthRaw, 10);
  const day = Number.parseInt(dayRaw, 10);

  if (
    Number.isNaN(year) ||
    Number.isNaN(month) ||
    Number.isNaN(day) ||
    year <= 0 ||
    month <= 0 ||
    day <= 0
  ) {
    return new Date(value);
  }

  return new Date(year, month - 1, day);
}

function parseGuestCount(text: string): {guestCount?: number; adults?: number; children?: number} {
  const normalized = text.toLowerCase();
  const adultMatch = normalized.match(/(\d+)\s*(adult|adults|odrasl|osob)/i);
  const childMatch = normalized.match(/(\d+)\s*(children|child|djec|dijete)/i);
  const guestsMatch = normalized.match(/(\d+)\s*(guests|guest|gosta|gosti|osobe|osoba)/i);

  const adults = adultMatch ? Number.parseInt(adultMatch[1], 10) : undefined;
  const children = childMatch ? Number.parseInt(childMatch[1], 10) : undefined;
  const guestCount = guestsMatch ? Number.parseInt(guestsMatch[1], 10) : undefined;

  if (guestCount !== undefined && adults === undefined && children === undefined) {
    return {guestCount, adults: guestCount};
  }

  return {guestCount, adults, children};
}

/**
 * Recursively removes all `undefined` values from a plain object or array.
 * Preserves: null, false, 0, "", Timestamp, Date, DocumentReference, GeoPoint.
 */
function removeUndefinedDeep(value: unknown): unknown {
  if (value === undefined) {
    return null;
  }
  if (value === null || typeof value !== "object") {
    return value;
  }
  // Preserve Firestore and built-in special types verbatim.
  if (
    value instanceof Date ||
    value instanceof admin.firestore.Timestamp ||
    value instanceof admin.firestore.DocumentReference ||
    value instanceof admin.firestore.GeoPoint ||
    (typeof (value as {_methodName?: unknown})._methodName === "string") // FieldValue sentinel
  ) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(removeUndefinedDeep);
  }
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (v !== undefined) {
      out[k] = removeUndefinedDeep(v);
    }
  }
  return out;
}

function parseTitleName(title: string): string {
  const cleaned = title
    .replace(/\s*[-\/|]\s*(booking|airbnb|campspace|\d+\s*(gost|gosta|guests?|osobe?)).*/i, "")
    .replace(/rezervacija\s+/i, "")
    .trim();

  if (!cleaned) {
    return title.trim();
  }
  return cleaned;
}

// Descriptor tokens that should not be treated as a last name.
const BOOKING_DESCRIPTOR_TOKENS = new Set([
  "kamper", "camper", "campspace", "booking", "airbnb", "whatsapp", "motor",
  "motori", "sator", "šator", "caravan", "kamp", "rez", "parcela", "pitch",
  "bg", "sa", "dole", "kut", "gornji", "donji", "lijevi", "desni", "gore",
]);

const PERSONAL_NAME_PATTERN = /^[\p{Lu}][\p{Ll}]+$/u;

/**
 * Attempts to extract firstName and lastName from a calendar event title.
 * Returns null values when the title does not look like a personal name.
 */
function extractGuestNameParts(title: string): {
  firstName: string | null;
  lastName: string | null;
  rawTitleSuffix: string | null;
} {
  const cleaned = title
    .replace(/\s*[-\/|]\s*.*/i, "")
    .replace(/\d+/g, "")
    .trim();

  const tokens = cleaned.split(/\s+/).filter((t) => t.length > 0);

  if (tokens.length === 0) {
    return {firstName: null, lastName: null, rawTitleSuffix: null};
  }

  const firstToken = tokens[0];

  // First token must look like a personal name (starts uppercase, rest lowercase)
  if (!PERSONAL_NAME_PATTERN.test(firstToken)) {
    return {firstName: null, lastName: null, rawTitleSuffix: null};
  }

  const firstName = firstToken;

  // Find the first subsequent token that is NOT a descriptor and looks like a name
  let lastName: string | null = null;
  let suffixStart = 1;
  for (let i = 1; i < tokens.length; i++) {
    const token = tokens[i];
    if (!BOOKING_DESCRIPTOR_TOKENS.has(token.toLowerCase())) {
      if (PERSONAL_NAME_PATTERN.test(token)) {
        lastName = token;
        suffixStart = i + 1;
      }
      // Stop at first non-descriptor token regardless
      break;
    }
  }

  const suffixTokens = tokens.slice(suffixStart).join(" ").trim();
  const rawTitleSuffix = suffixTokens.length > 0 ? suffixTokens : null;

  return {firstName, lastName, rawTitleSuffix};
}

function adaptEventDates(
  start: calendar_v3.Schema$EventDateTime | undefined,
  end: calendar_v3.Schema$EventDateTime | undefined
): {checkIn: Date; checkOut: Date; isAllDay: boolean} {
  const startDate = start?.date ? parseDateOnly(start.date) : new Date(start?.dateTime || Date.now());
  let endDate = end?.date ? parseDateOnly(end.date) : new Date(end?.dateTime || Date.now() + 86400000);
  const isAllDay = Boolean(start?.date && end?.date);

  // Za all-day događaje, end.date je ekskluzivinog (dan NAKON zadnjeg dana)
  // Trebam oduzeti 1 dan da bih dobio pravi zadnji dan boravka
  if (isAllDay && end?.date) {
    endDate = new Date(endDate.getTime() - 86400000);
  }

  const checkIn = new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate());
  const checkOut = new Date(endDate.getFullYear(), endDate.getMonth(), endDate.getDate());

  if (checkOut <= checkIn) {
    return {
      checkIn,
      checkOut: new Date(checkIn.getTime() + 86400000),
      isAllDay,
    };
  }

  return {checkIn, checkOut, isAllDay};
}

function eventToImportDoc(event: calendar_v3.Schema$Event, calendarId: string): CalendarEventDoc {
  const title = (event.summary || "").trim();
  const description = (event.description || "").trim();
  const location = (event.location || "").trim();
  const composedText = [title, description, location].filter((item) => item).join("\n");
  const {checkIn, checkOut, isAllDay} = adaptEventDates(event.start, event.end);
  const counts = parseGuestCount(composedText);
  const source = normalizeReservationSource(composedText);

  const parseWarnings: string[] = [];
  if (!title) parseWarnings.push("Događaj nema naslov");
  if (!event.start || !event.end) parseWarnings.push("Događaj nema potpune datume");

  const needsReview = parseWarnings.length > 0;

  const nameParts = extractGuestNameParts(title);
  const fullName = parseTitleName(title) || null;

  const parsedReservation: Record<string, unknown> = {
    primaryGuestFullName: fullName,
    primaryGuestFirstName: nameParts.firstName,
    primaryGuestLastName: nameParts.lastName,
    rawTitleSuffix: nameParts.rawTitleSuffix,
    checkInDate: admin.firestore.Timestamp.fromDate(checkIn),
    checkOutDate: admin.firestore.Timestamp.fromDate(checkOut),
    adults: counts.adults ?? null,
    children: counts.children ?? null,
    guestCount: counts.guestCount ?? null,
    source,
    sourceReservationId: null,
    rawImportedText: composedText,
    confidence: needsReview ? 0.6 : 0.82,
    needsReview,
  };

  return {
    googleEventId: (event.id || "").trim(),
    calendarId,
    title,
    description,
    location,
    startDate: admin.firestore.Timestamp.fromDate(checkIn),
    endDate: admin.firestore.Timestamp.fromDate(checkOut),
    isAllDay,
    eventStatus: (event.status || "confirmed").trim(),
    updatedAtGoogle: event.updated ? admin.firestore.Timestamp.fromDate(new Date(event.updated)) : null,
    htmlLink: (event.htmlLink || "").trim() || null,
    rawSource: "googleCalendar",
    parsedReservation,
    parseWarnings,
    confidence: needsReview ? 0.6 : 0.82,
    importStatus: event.status === "cancelled" ? "cancelled" : (needsReview ? "needsReview" : "newEvent"),
  };
}

async function getRefreshToken(uid: string): Promise<string> {
  const doc = await admin.firestore().collection(SECRET_COLLECTION).doc(uid).get();
  const token = (doc.data()?.refreshToken as string | undefined) || "";
  if (!token) {
    throw new HttpsError("failed-precondition", "Google račun nije povezan.");
  }
  return token;
}

async function saveConnection(uid: string, data: Record<string, unknown>) {
  await admin.firestore().collection(CONNECTIONS_COLLECTION).doc(uid).set(
    {
      uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...data,
    },
    {merge: true}
  );
}

async function validateOAuthState(state: string, expectedUid?: string): Promise<{uid: string; stateRef: FirebaseFirestore.DocumentReference}> {
  const stateRef = admin.firestore().collection(OAUTH_STATE_COLLECTION).doc(state);
  const stateSnap = await stateRef.get();
  const uid = (stateSnap.data()?.uid as string | undefined) || "";
  const createdAt = stateSnap.data()?.createdAt as admin.firestore.Timestamp | undefined;
  const expiresAt = stateSnap.data()?.expiresAt as admin.firestore.Timestamp | undefined;
  const used = stateSnap.data()?.used === true;

  if (!stateSnap.exists || !uid) {
    throw new HttpsError("permission-denied", "Neispravan OAuth state.");
  }

  if (used) {
    throw new HttpsError("permission-denied", "OAuth state je već iskorišten.");
  }

  if (expectedUid && uid !== expectedUid) {
    throw new HttpsError("permission-denied", "OAuth state ne pripada aktivnom korisniku.");
  }

  const expiresAtMs = expiresAt?.toMillis() || 0;
  if (expiresAtMs && Date.now() > expiresAtMs) {
    throw new HttpsError("permission-denied", "OAuth state je istekao.");
  }

  const createdAtMs = createdAt?.toMillis() || 0;
  if (!createdAtMs || Date.now() - createdAtMs > OAUTH_STATE_TTL_MS) {
    throw new HttpsError("permission-denied", "OAuth state je istekao.");
  }

  return {uid, stateRef};
}

async function completeOAuthForUid(uid: string, code: string) {
  const client = oauthClient();
  logger.info("token exchange", {phase: "start"});
  const tokenResponse = await client.getToken(code);
  logger.info("token exchange", {phase: "success"});
  const newRefreshToken = (tokenResponse.tokens.refresh_token || "").trim();
  const accessToken = tokenResponse.tokens.access_token || "";

  let effectiveRefreshToken = newRefreshToken;
  if (!effectiveRefreshToken) {
    const existingSecret = await admin.firestore().collection(SECRET_COLLECTION).doc(uid).get();
    effectiveRefreshToken = ((existingSecret.data()?.refreshToken as string | undefined) || "").trim();
  }

  logger.info("refresh token status", {
    refreshTokenPresent: effectiveRefreshToken.length > 0,
    receivedNewRefreshToken: newRefreshToken.length > 0,
  });

  if (!effectiveRefreshToken) {
    throw new HttpsError("failed-precondition", "Nedostaje refresh token.");
  }

  logger.info("firestore save", {phase: "start", target: "googleCalendarSecrets"});

  await admin.firestore().collection(SECRET_COLLECTION).doc(uid).set({
    uid,
    refreshToken: effectiveRefreshToken,
    tokenType: tokenResponse.tokens.token_type || "Bearer",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  logger.info("firestore save", {phase: "success", target: "googleCalendarSecrets"});

  client.setCredentials({refresh_token: effectiveRefreshToken, access_token: accessToken});
  const calendar = google.calendar({version: "v3", auth: client});
  const calendarList = await calendar.calendarList.list({maxResults: 20});
  const primary = (calendarList.data.items || []).find((item) => item.primary) ||
    (calendarList.data.items || [])[0];

  const googleAccountEmail = (primary?.id || "").trim();

  logger.info("firestore save", {phase: "start", target: "googleCalendarConnections"});
  await saveConnection(uid, {
    connected: true,
    googleAccountEmail,
    selectedCalendarId: primary?.id || "primary",
    selectedCalendarName: primary?.summary || "Primary",
    syncStatus: "idle",
    lastError: "",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    nextSyncToken: "",
  });
  logger.info("firestore save", {phase: "success", target: "googleCalendarConnections"});

  return {
    connected: true,
    googleAccountEmail,
    selectedCalendarId: primary?.id || "primary",
    selectedCalendarName: primary?.summary || "Primary",
  };
}

async function runSyncForUid(uid: string, opts?: {selectedCalendarId?: string; forceFull?: boolean}): Promise<SyncStats> {
  const stats: SyncStats = {
    newEvents: 0,
    updatedEvents: 0,
    cancelledEvents: 0,
    needsReview: 0,
    invalidSyncTokenRecovered: false,
    skippedCount: 0,
    errorCount: 0,
  };

  const connectionRef = admin.firestore().collection(CONNECTIONS_COLLECTION).doc(uid);
  const connectionSnap = await connectionRef.get();
  const connectionData = connectionSnap.data() || {};
  const selectedCalendarId = (opts?.selectedCalendarId || (connectionData.selectedCalendarId as string) || "primary").trim();
  const nextSyncToken = (connectionData.nextSyncToken as string | undefined) || "";

  const refreshToken = await getRefreshToken(uid);
  const client = oauthClient();
  client.setCredentials({refresh_token: refreshToken});

  const calendar = google.calendar({version: "v3", auth: client});

  const now = new Date();
  const rangeStart = new Date(now);
  rangeStart.setDate(rangeStart.getDate() - 30);
  const rangeEnd = new Date(now);
  rangeEnd.setMonth(rangeEnd.getMonth() + 18);

  const eventsRef = connectionRef.collection(IMPORT_EVENTS_SUBCOLLECTION);

  const processListResponse = async (resp: calendar_v3.Schema$Events): Promise<void> => {
    const items = resp.items || [];
    for (const item of items) {
      const eventId = (item.id || "").trim();
      if (!eventId) {
        stats.skippedCount += 1;
        continue;
      }

      try {
        const incoming = eventToImportDoc(item, selectedCalendarId);
        const sanitized = removeUndefinedDeep(incoming) as CalendarEventDoc;
        const eventRef = eventsRef.doc(eventId);
        const existingSnap = await eventRef.get();
        const existing = existingSnap.data() as CalendarEventDoc | undefined;

        if (sanitized.importStatus === "cancelled") {
          stats.cancelledEvents += 1;
        }
        if (sanitized.importStatus === "needsReview") {
          stats.needsReview += 1;
        }

        if (!existingSnap.exists) {
          stats.newEvents += 1;
          await eventRef.set({
            ...sanitized,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }

        const existingUpdated = existing?.updatedAtGoogle?.toDate().getTime() || 0;
        const incomingUpdated = sanitized.updatedAtGoogle?.toDate().getTime() || 0;
        const importedAlready = existing?.importStatus === "imported";

        let nextStatus = sanitized.importStatus;
        if (importedAlready && incomingUpdated > existingUpdated) {
          nextStatus = "updatedAfterImport";
        }

        stats.updatedEvents += 1;
        await eventRef.set(
          {
            ...sanitized,
            importStatus: nextStatus,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
      } catch (eventError) {
        stats.errorCount += 1;
        const shortId = eventId.slice(0, 12);
        logger.error("sync event error", {
          eventIdPrefix: shortId,
          error: eventError instanceof Error ? eventError.message.slice(0, 200) : String(eventError).slice(0, 200),
        });
      }
    }

    if (resp.nextSyncToken) {
      await saveConnection(uid, {
        selectedCalendarId,
        nextSyncToken: resp.nextSyncToken,
      });
    }
  };

  const runFullSync = async () => {
    let pageToken: string | undefined;
    do {
      const response = await calendar.events.list({
        calendarId: selectedCalendarId,
        singleEvents: true,
        showDeleted: true,
        pageToken,
        timeMin: rangeStart.toISOString(),
        timeMax: rangeEnd.toISOString(),
      });
      await processListResponse(response.data);
      pageToken = response.data.nextPageToken || undefined;
    } while (pageToken);
  };

  if (!opts?.forceFull && nextSyncToken) {
    try {
      const response = await calendar.events.list({
        calendarId: selectedCalendarId,
        singleEvents: true,
        showDeleted: true,
        syncToken: nextSyncToken,
      });
      await processListResponse(response.data);
    } catch (error) {
      const errorCode = (error as {code?: number}).code;
      if (errorCode === 410) {
        stats.invalidSyncTokenRecovered = true;
        await saveConnection(uid, {nextSyncToken: ""});
        await runFullSync();
      } else {
        throw error;
      }
    }
  } else {
    await runFullSync();
  }

  await saveConnection(uid, {
    connected: true,
    selectedCalendarId,
    lastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
    syncStatus: "success",
    lastError: "",
    newEventsCount: stats.newEvents,
    needsReviewCount: stats.needsReview,
  });

  return stats;
}

export const getGoogleCalendarAuthorizationUrl = onCall(
  {region: "europe-west1", secrets: [GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI]},
  async (request) => {
    const uid = ensureAdmin(request.auth);
    const client = oauthClient();
    const secretSnap = await admin.firestore().collection(SECRET_COLLECTION).doc(uid).get();
    const hasRefreshToken = Boolean((secretSnap.data()?.refreshToken as string | undefined)?.trim());

    const stateNonce = generateOAuthState();
    await admin.firestore().collection(OAUTH_STATE_COLLECTION).doc(stateNonce).set({
      uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + OAUTH_STATE_TTL_MS),
      used: false,
    });

    const authorizationUrl = client.generateAuthUrl({
      access_type: "offline",
      ...(hasRefreshToken ? {} : {prompt: "consent"}),
      include_granted_scopes: true,
      scope: [CALENDAR_READONLY_SCOPE],
      state: stateNonce,
    });

    return {authorizationUrl};
  }
);

export const handleGoogleCalendarOAuthCallback = onCall(
  {region: "europe-west1", secrets: [GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI]},
  async (request) => {
    const uid = ensureAdmin(request.auth);
    const code = ((request.data?.code as string) || "").trim();
    const state = ((request.data?.state as string) || "").trim();

    if (!code || !state) {
      throw new HttpsError("invalid-argument", "Nedostaju code ili state parametri.");
    }

    const validated = await validateOAuthState(state, uid);

    const response = await completeOAuthForUid(uid, code);

    await validated.stateRef.delete();

    return response;
  }
);

export const googleCalendarOAuthCallback = onRequest(
  {region: "europe-west1", secrets: [GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI]},
  async (request, response) => {
    const googleError = ((request.query.error as string) || "").trim();
    const code = ((request.query.code as string) || "").trim();
    const state = ((request.query.state as string) || "").trim();

    logger.info("callback received", {
      googleErrorPresent: googleError.length > 0,
      codePresent: code.length > 0,
      statePresent: state.length > 0,
    });

    if (googleError) {
      logger.error("oauth google error", {
        errorName: "google_oauth_error",
        errorCode: googleError,
      });
      response
        .status(400)
        .set("Content-Type", "text/html; charset=utf-8")
        .send(renderCallbackErrorPage("google_oauth_error"));
      return;
    }

    if (!code || !state) {
      response
        .status(400)
        .set("Content-Type", "text/html; charset=utf-8")
        .send(renderCallbackErrorPage("missing_code_or_state"));
      return;
    }

    try {
      logger.info("state validation", {phase: "start"});
      const validated = await validateOAuthState(state);
      logger.info("state validation", {phase: "success"});
      const uid = validated.uid;
      logger.info("uid recovered", {present: uid.length > 0});

      await completeOAuthForUid(uid, code);
      await validated.stateRef.set({used: true}, {merge: true});

      logger.info("final redirect", {phase: "success"});
      response.redirect(302, `${WEB_APP_BASE_URL}/?googleCalendar=connected`);
    } catch (error) {
      const message = sanitizeErrorMessage(error);
      const errorCode = safeErrorCode(error);
      const providerError = extractProviderOAuthError(error);
      const errorName = error instanceof Error ? error.name : "unknown";
      const httpStatus = (error as {status?: number; response?: {status?: number}})?.status ||
        (error as {response?: {status?: number}})?.response?.status ||
        undefined;

      logger.error("Google OAuth callback failed", {
        errorName,
        errorCode,
        providerErrorCode: providerError.code,
        providerErrorDescription: providerError.description,
        message,
        httpStatus,
      });

      logger.info("state validation", {phase: "failure"});
      logger.info("token exchange", {phase: "failure"});
      logger.info("firestore save", {phase: "failure"});
      logger.info("final redirect", {phase: "failure"});

      response
        .status(500)
        .set("Content-Type", "text/html; charset=utf-8")
        .send(renderCallbackErrorPage(errorCode));
    }
  }
);

export const listGoogleCalendars = onCall(
  {region: "europe-west1", secrets: [GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI]},
  async (request) => {
    const uid = ensureAdmin(request.auth);
    const refreshToken = await getRefreshToken(uid);
    const client = oauthClient();
    client.setCredentials({refresh_token: refreshToken});

    const calendar = google.calendar({version: "v3", auth: client});
    const response = await calendar.calendarList.list({maxResults: 100});
    const calendars = (response.data.items || []).map((item) => ({
      id: item.id || "",
      name: item.summary || "(Bez naziva)",
      primary: item.primary === true,
    }));

    return {calendars};
  }
);

export const syncGoogleCalendarEvents = onCall(
  {region: "europe-west1", secrets: [GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI]},
  async (request) => {
    const uid = ensureAdmin(request.auth);
    const selectedCalendarId = ((request.data?.selectedCalendarId as string) || "").trim();
    const forceFull = Boolean(request.data?.forceFull);

    await saveConnection(uid, {syncStatus: "syncing", lastError: ""});

    try {
      const stats = await runSyncForUid(uid, {
        selectedCalendarId: selectedCalendarId || undefined,
        forceFull,
      });

      return stats;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await saveConnection(uid, {syncStatus: "error", lastError: message});
      throw error;
    }
  }
);

export const disconnectGoogleCalendar = onCall(
  {region: "europe-west1"},
  async (request) => {
    const uid = ensureAdmin(request.auth);

    await admin.firestore().collection(SECRET_COLLECTION).doc(uid).delete();
    await admin.firestore().collection(CONNECTIONS_COLLECTION).doc(uid).set(
      {
        uid,
        connected: false,
        googleAccountEmail: "",
        selectedCalendarId: "",
        selectedCalendarName: "",
        nextSyncToken: "",
        autoSyncEnabled: false,
        syncStatus: "idle",
        lastError: "",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {disconnected: true};
  }
);

export const scheduledGoogleCalendarSync = onSchedule(
  {
    region: "europe-west1",
    schedule: "every 60 minutes",
    timeZone: "Europe/Zagreb",
    secrets: [GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI],
  },
  async () => {
    const startedAt = Date.now();
    const snapshot = await admin
      .firestore()
      .collection(CONNECTIONS_COLLECTION)
      .where("connected", "==", true)
      .where("autoSyncEnabled", "==", true)
      .get();

    for (const doc of snapshot.docs) {
      const uid = doc.id;
      let stats: SyncStats = {
        newEvents: 0,
        updatedEvents: 0,
        cancelledEvents: 0,
        needsReview: 0,
        invalidSyncTokenRecovered: false,
        skippedCount: 0,
        errorCount: 0,
      };
      let errorMessage = "";
      try {
        await saveConnection(uid, {syncStatus: "syncing", lastError: ""});
        stats = await runSyncForUid(uid);
      } catch (error) {
        errorMessage = error instanceof Error ? error.message : String(error);
        await saveConnection(uid, {syncStatus: "error", lastError: errorMessage});
      }

      await admin.firestore().collection(SYNC_LOG_COLLECTION).add({
        uid,
        startedAt: admin.firestore.Timestamp.fromMillis(startedAt),
        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
        newEvents: stats.newEvents,
        updatedEvents: stats.updatedEvents,
        cancelledEvents: stats.cancelledEvents,
        errors: errorMessage ? [errorMessage] : [],
      });

      if (errorMessage) {
        logger.error("Google Calendar scheduled sync failed", {uid, error: errorMessage});
      }
    }
  }
);

export const __calendarTest = {
  adaptEventDates,
  eventToImportDoc,
  normalizeReservationSource,
  parseGuestCount,
  parseTitleName,
  extractGuestNameParts,
  removeUndefinedDeep,
};
