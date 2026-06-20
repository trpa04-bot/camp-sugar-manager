import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {setGlobalOptions} from "firebase-functions/v2";
import * as functionsV1 from "firebase-functions/v1";
import {ImageAnnotatorClient} from "@google-cloud/vision";

admin.initializeApp();
setGlobalOptions({maxInstances: 10, region: "europe-west1"});

type DocumentKind =
	| "passport"
	| "nationalIdCard"
	| "residencePermit"
	| "drivingLicence"
	| "unknownIdentityDocument";

type MrzFormat = "TD1" | "TD2" | "TD3" | "MRV-A" | "MRV-B";

interface ParsedData {
	documentType?: string;
	documentKind?: DocumentKind;
	documentCode?: string;
	firstName?: string;
	middleNames?: string;
	lastName?: string;
	dateOfBirth?: string;
	nationality?: string;
	nationalityCode?: string;
	nationalityDisplayName?: string;
	documentNumber?: string;
	documentExpiryDate?: string;
	issueDate?: string;
	gender?: string;
	issuingCountry?: string;
	optionalData?: string;
	personalNumber?: string;
	mrzText?: string;
	confidence?: number;
}

interface OcrImageRequest {
	imageId?: string;
	storagePath: string;
	documentSide?: string;
}

interface OcrElement {
	text: string;
	boundingBox: Array<{x: number; y: number}>;
	confidence?: number;
	pageImageId: string;
	detectedLanguage?: string;
}

interface OcrImageResult {
	imageId: string;
	storagePath: string;
	documentSide: string;
	rawText: string;
	elements?: OcrElement[];
	detectedLanguages?: string[];
	parsed: ParsedData;
}

interface MergedField {
	value?: string;
	confidence: number;
	sourceImageId?: string;
	sourceType: "mrz" | "labelMatch" | "spatialMatch" | "fallback" | "manual";
	needsReview: boolean;
}

interface MergedResult {
	parsed: ParsedData;
	fields: Record<string, MergedField>;
	conflicts: string[];
	debug?: {
		firstName?: NameFieldDebugInfo;
		lastName?: NameFieldDebugInfo;
	};
}

interface NameFieldDebugInfo {
	mrzNormalizedValue?: string;
	rawVisualCandidate?: string;
	visualNormalizedValue?: string;
	visualValid?: boolean;
	rejectionReason?: string;
	visualConfidence?: number;
	visualConfidenceBeforeValidation?: number;
	visualConfidenceAfterValidation?: number;
	visualSourceType?: MergedField["sourceType"];
}

interface NameCandidate {
	value: string;
	canonicalValue: string;
	score: number;
	scoreBeforeValidation: number;
	scoreAfterValidation: number;
	sourceImageId: string;
	sourceType: MergedField["sourceType"];
	rejectionReason?: string;
}

interface NameFieldResolution {
	field: MergedField;
	debug: NameFieldDebugInfo;
	mrzCandidate?: NameCandidate;
	visualCandidate?: NameCandidate;
}

const ENABLE_NAME_CANDIDATE_DEBUG = true;

interface OcrOutput {
	rawText: string;
	parsed: ParsedData;
	images: OcrImageResult[];
	merged: MergedResult;
}

interface VisionTextAnnotation {
	description?: string | null;
	locale?: string | null;
	confidence?: number | null;
	boundingPoly?: {
		vertices?: Array<{x?: number | null; y?: number | null}> | null;
	} | null;
}

interface DocumentContext {
	lines: string[];
	detectedLanguages: string[];
	mrzFormat?: MrzFormat;
	documentCode?: string;
	issuingCountry?: string;
}

interface DocumentCountryAdapter {
	name: string;
	supports(context: DocumentContext): boolean;
	extractFields(context: DocumentContext): Partial<ParsedData>;
	normalizeDocumentNumber(value?: string): string | undefined;
	normalizeNationality(value?: string): string | undefined;
	extractIssueDate(context: DocumentContext): string | undefined;
	detectSpecialFields(context: DocumentContext): Partial<ParsedData>;
}

const visionClient = new ImageAnnotatorClient();
const STORAGE_PATH_REGEX = /^reservations\/([^/]+)\/documents\/([^/]+)\/[^/]+$/;

export const processDocumentOcr = onCall(async (request): Promise<OcrOutput> => {
	if (!request.auth?.uid) {
		throw new HttpsError("unauthenticated", "Korisnik nije autentificiran.");
	}

	try {
		const images = parseImageRequests(request.data);
		return await processOcrRequest(images);
	} catch (error) {
		handleOcrError(error, false);
		throw new HttpsError("internal", "OCR obrada nije uspjela.");
	}
});

export const processDocumentOcrCallable = functionsV1
	.region("europe-west1")
	.runWith({maxInstances: 10, memory: "256MB", timeoutSeconds: 60})
	.https.onCall(async (data, context): Promise<OcrOutput> => {
		if (!context.auth?.uid) {
			throw new functionsV1.https.HttpsError(
				"unauthenticated",
				"Korisnik nije autentificiran."
			);
		}

		try {
			const images = parseImageRequests(data);
			return await processOcrRequest(images);
		} catch (error) {
			handleOcrError(error, true);
			throw new functionsV1.https.HttpsError("internal", "OCR obrada nije uspjela.");
		}
	});

function parseImageRequests(data: unknown): OcrImageRequest[] {
	if (!data || typeof data !== "object") {
		throw new HttpsError("invalid-argument", "Podaci zahtjeva nedostaju.");
	}

	const payload = data as Record<string, unknown>;
	const storagePath = ((payload.storagePath as string) || "").trim();
	const payloadReservationId = ((payload.reservationId as string) || "").trim();
	const payloadGuestId = ((payload.guestId as string) || "").trim();
	const imagesRaw = Array.isArray(payload.images) ? payload.images : [];

	const images: OcrImageRequest[] = [];
	for (const entry of imagesRaw) {
		if (!entry || typeof entry !== "object") continue;
		const mapped = entry as Record<string, unknown>;
		const path = ((mapped.storagePath as string) || "").trim();
		if (!path) continue;
		images.push({
			imageId: ((mapped.imageId as string) || "").trim() || undefined,
			storagePath: path,
			documentSide: ((mapped.documentSide as string) || "additional").trim(),
		});
	}

	if (images.length === 0 && storagePath) {
		images.push({imageId: "single", storagePath, documentSide: "additional"});
	}
	if (images.length === 0) {
		throw new HttpsError("invalid-argument", "Potrebna je barem jedna slika.");
	}
	if (images.length > 5) {
		throw new HttpsError("invalid-argument", "Maksimalno je 5 slika po zahtjevu.");
	}

	const firstMatch = STORAGE_PATH_REGEX.exec(images[0].storagePath);
	if (!firstMatch) {
		throw new HttpsError("permission-denied", "Neispravna putanja dokumenta.");
	}
	const reservationId = firstMatch[1];
	const guestId = firstMatch[2];

	if (payloadReservationId && payloadReservationId !== reservationId) {
		throw new HttpsError("permission-denied", "reservationId ne odgovara storage putanjama.");
	}
	if (payloadGuestId && payloadGuestId !== guestId) {
		throw new HttpsError("permission-denied", "guestId ne odgovara storage putanjama.");
	}

	for (const image of images) {
		const match = STORAGE_PATH_REGEX.exec(image.storagePath);
		if (!match || match[1] !== reservationId || match[2] !== guestId) {
			throw new HttpsError(
				"permission-denied",
				"Sve slike moraju pripadati istoj rezervaciji i gostu."
			);
		}
	}

	return images;
}

async function processOcrRequest(images: OcrImageRequest[]): Promise<OcrOutput> {
	const bucket = admin.storage().bucket();
	const imageResults: OcrImageResult[] = [];

	for (let i = 0; i < images.length; i++) {
		const item = images[i];
		const imageId = item.imageId || `img-${i + 1}`;
		const file = bucket.file(item.storagePath);
		const [exists] = await file.exists();
		if (!exists) {
			throw new HttpsError("not-found", "Slika dokumenta nije pronađena.");
		}

		const [bytes] = await file.download();
		const [visionResult] = await visionClient.documentTextDetection({image: {content: bytes}});
		const rawText = (visionResult.fullTextAnnotation?.text || "").trim();
		const confidence = computeConfidence(visionResult);
		const annotations = visionResult.textAnnotations as VisionTextAnnotation[] | undefined;
		const elements = extractOcrElements(annotations, imageId);
		const detectedLanguages = Array.from(
			new Set(
				elements
					.map((element) => (element.detectedLanguage || "").trim().toLowerCase())
					.filter((value) => value.length > 0)
			)
		);
		const parsed = parseDocument(rawText, confidence, annotations, detectedLanguages);

		imageResults.push({
			imageId,
			storagePath: item.storagePath,
			documentSide: (item.documentSide || "additional").trim() || "additional",
			rawText,
			elements,
			detectedLanguages,
			parsed,
		});
	}

	const merged = mergeImageResults(imageResults);
	logger.info("OCR processed", {imageCount: imageResults.length});
	return {
		rawText: imageResults[0]?.rawText || "",
		parsed: merged.parsed,
		images: imageResults,
		merged,
	};
}

function handleOcrError(error: unknown, isV1: boolean): never {
	if (error instanceof HttpsError) {
		if (isV1) {
			throw new functionsV1.https.HttpsError(error.code, error.message);
		}
		throw error;
	}
	if (error instanceof functionsV1.https.HttpsError) {
		throw error;
	}
	const message = error instanceof Error ? error.message : String(error);
	logger.error("OCR processing failed", {isV1, message});
	if (isV1) {
		throw new functionsV1.https.HttpsError("internal", "OCR obrada nije uspjela.");
	}
	throw new HttpsError("internal", "OCR obrada nije uspjela.");
}

function parseDocument(
	rawText: string,
	confidence?: number,
	textAnnotations?: VisionTextAnnotation[],
	detectedLanguages: string[] = []
): ParsedData {
	const lines = normalizeLines(rawText);
	const spatialLines = extractSpatiallyOrderedLines(textAnnotations);
	const parserLines = spatialLines.length > 0 ? spatialLines : lines;
	const parsed: ParsedData = {confidence};

	const mrz = extractMrz(lines);
	if (mrz) {
		Object.assign(parsed, mrz.parsed);
		parsed.mrzText = mrz.lines.join("\n");
	}

	mergeMissing(parsed, parseWithLabels(parserLines, lines, detectedLanguages));

	const context: DocumentContext = {
		lines: parserLines,
		detectedLanguages,
		mrzFormat: mrz?.format,
		documentCode: parsed.documentCode,
		issuingCountry: parsed.issuingCountry,
	};
	applyCountryAdapters(parsed, context);

	const kind = detectDocumentKind({
		lines: parserLines,
		documentCode: parsed.documentCode,
		mrzFormat: mrz?.format,
		hasMrz: Boolean(mrz),
	});
	parsed.documentKind = kind;
	parsed.documentType = kind;

	return parsed;
}

function normalizeLines(rawText: string): string[] {
	return rawText
		.split(/\r?\n/)
		.map((line) => line.trim())
		.filter((line) => line.length > 0);
}

function extractMrz(lines: string[]): {lines: string[]; format: MrzFormat; parsed: ParsedData} | null {
	const mrzLike = lines
		.map((line) => line.replace(/\s+/g, ""))
		.filter((line) => /^[A-Z0-9<]{25,}$/.test(line));

	for (let i = 0; i < mrzLike.length - 2; i++) {
		const l1 = padMrz(mrzLike[i], 30);
		const l2 = padMrz(mrzLike[i + 1], 30);
		const l3 = padMrz(mrzLike[i + 2], 30);
		if (l1 && l2 && l3) {
			return {lines: [l1, l2, l3], format: "TD1", parsed: parseTd1([l1, l2, l3])};
		}
	}

	for (let i = 0; i < mrzLike.length - 1; i++) {
		const l1_44 = padMrz(mrzLike[i], 44);
		const l2_44 = padMrz(mrzLike[i + 1], 44);
		if (l1_44 && l2_44) {
			const code = normalizeMrzCode(l1_44.substring(0, 2));
			const format: MrzFormat = code.startsWith("V") ? "MRV-A" : "TD3";
			return {
				lines: [l1_44, l2_44],
				format,
				parsed: format === "MRV-A" ? parseVisaLike([l1_44, l2_44], 44) : parseTd3([l1_44, l2_44]),
			};
		}

		const l1_36 = padMrz(mrzLike[i], 36);
		const l2_36 = padMrz(mrzLike[i + 1], 36);
		if (l1_36 && l2_36) {
			const code = normalizeMrzCode(l1_36.substring(0, 2));
			const format: MrzFormat = code.startsWith("V") ? "MRV-B" : "TD2";
			return {
				lines: [l1_36, l2_36],
				format,
				parsed: format === "MRV-B" ? parseVisaLike([l1_36, l2_36], 36) : parseTd2([l1_36, l2_36]),
			};
		}
	}

	return null;
}

function padMrz(line: string, target: number): string {
	const cleaned = line.replace(/[^A-Z0-9<]/g, "");
	if (cleaned.length < target - 2) return "";
	if (cleaned.length < target) return cleaned.padEnd(target, "<");
	return cleaned.substring(0, target);
}

function parseTd1(lines: string[]): ParsedData {
	const [line1, line2, line3] = lines;
	const names = parseMrzNames(line3);
	const documentCode = normalizeMrzCode(line1.substring(0, 2));
	const issuingCountry = normalizeCountryCode(line1.substring(2, 5));
	const nationality = normalizeCountryCode(line2.substring(15, 18));
	const meta = mapNationality(nationality);
	const birth = parseMrzDateWithContext(line2.substring(0, 6), "birth");
	const expiry = parseMrzDateWithContext(line2.substring(8, 14), "expiry", birth);

	return {
		documentCode,
		documentKind: mapDocumentCodeToKind(documentCode),
		documentType: mapDocumentCodeToKind(documentCode),
		...names,
		issuingCountry,
		documentNumber: normalizeMrzField(line1.substring(5, 14)),
		dateOfBirth: birth,
		documentExpiryDate: expiry,
		nationality: meta.code,
		nationalityCode: meta.code,
		nationalityDisplayName: meta.displayName,
		gender: parseSex(line2.substring(7, 8)),
		optionalData: normalizeMrzField(line1.substring(15, 30)),
		personalNumber: normalizeMrzField(line2.substring(18, 29)),
	};
}

function parseTd2(lines: string[]): ParsedData {
	const [line1, line2] = lines;
	const names = parseMrzNames(line1.substring(5));
	const documentCode = normalizeMrzCode(line1.substring(0, 2));
	const issuingCountry = normalizeCountryCode(line1.substring(2, 5));
	const nationality = normalizeCountryCode(line2.substring(10, 13));
	const meta = mapNationality(nationality);
	const birth = parseMrzDateWithContext(line2.substring(13, 19), "birth");
	const expiry = parseMrzDateWithContext(line2.substring(21, 27), "expiry", birth);
	const optionalData = normalizeMrzField(line2.substring(28, 35));

	return {
		documentCode,
		documentKind: mapDocumentCodeToKind(documentCode),
		documentType: mapDocumentCodeToKind(documentCode),
		...names,
		issuingCountry,
		documentNumber: normalizeMrzField(line2.substring(0, 9)),
		dateOfBirth: birth,
		documentExpiryDate: expiry,
		nationality: meta.code,
		nationalityCode: meta.code,
		nationalityDisplayName: meta.displayName,
		gender: parseSex(line2.substring(20, 21)),
		optionalData,
		personalNumber: optionalData,
	};
}

function parseTd3(lines: string[]): ParsedData {
	const [line1, line2] = lines;
	const names = parseMrzNames(line1.substring(5));
	const documentCode = normalizeMrzCode(line1.substring(0, 2));
	const issuingCountry = normalizeCountryCode(line1.substring(2, 5));
	const nationality = normalizeCountryCode(line2.substring(10, 13));
	const meta = mapNationality(nationality);
	const birth = parseMrzDateWithContext(line2.substring(13, 19), "birth");
	const expiry = parseMrzDateWithContext(line2.substring(21, 27), "expiry", birth);
	const optionalData = normalizeMrzField(line2.substring(28, 42));

	return {
		documentCode,
		documentKind: "passport",
		documentType: "passport",
		...names,
		issuingCountry,
		documentNumber: normalizeMrzField(line2.substring(0, 9)),
		dateOfBirth: birth,
		documentExpiryDate: expiry,
		nationality: meta.code,
		nationalityCode: meta.code,
		nationalityDisplayName: meta.displayName,
		gender: parseSex(line2.substring(20, 21)),
		optionalData,
		personalNumber: optionalData,
	};
}

function parseVisaLike(lines: string[], width: 44 | 36): ParsedData {
	const [line1, line2] = lines;
	const names = parseMrzNames(line1.substring(5));
	const documentCode = normalizeMrzCode(line1.substring(0, 2));
	const issuingCountry = normalizeCountryCode(line1.substring(2, 5));
	const nationality = normalizeCountryCode(line2.substring(10, 13));
	const meta = mapNationality(nationality);
	const birth = parseMrzDateWithContext(line2.substring(13, 19), "birth");
	const expiry = parseMrzDateWithContext(line2.substring(21, 27), "expiry", birth);
	const optionalData = normalizeMrzField(line2.substring(28, width === 44 ? 43 : 35));

	return {
		documentCode,
		documentKind: "residencePermit",
		documentType: "residencePermit",
		...names,
		issuingCountry,
		documentNumber: normalizeMrzField(line2.substring(0, 9)),
		dateOfBirth: birth,
		documentExpiryDate: expiry,
		nationality: meta.code,
		nationalityCode: meta.code,
		nationalityDisplayName: meta.displayName,
		gender: parseSex(line2.substring(20, 21)),
		optionalData,
		personalNumber: optionalData,
	};
}

function normalizeMrzCode(value: string): string {
	return value.replace(/</g, "").trim().toUpperCase();
}

function normalizeMrzField(value: string): string | undefined {
	const cleaned = value.replace(/</g, "").trim().toUpperCase();
	return cleaned || undefined;
}

function normalizeMrzText(text: string): string {
	return text.replace(/</g, " ").replace(/\s+/g, " ").trim();
}

function parseMrzNames(value: string): {firstName?: string; middleNames?: string; lastName?: string} {
	const split = value.split("<<");
	const lastName = normalizeMrzText(split[0]) || undefined;
	const given = normalizeMrzText(split.slice(1).join(" "));
	const parts = given.split(" ").filter(Boolean);
	return {
		firstName: parts[0] || undefined,
		middleNames: parts.slice(1).join(" ") || undefined,
		lastName,
	};
}

function parseMrzDateWithContext(
	value: string,
	kind: "birth" | "expiry",
	birthDateHint?: string
): string | undefined {
	if (!/^\d{6}$/.test(value)) return undefined;
	const yy = Number(value.substring(0, 2));
	const mm = Number(value.substring(2, 4));
	const dd = Number(value.substring(4, 6));
	if (mm < 1 || mm > 12 || dd < 1 || dd > 31) return undefined;

	const candidate1900 = new Date(Date.UTC(1900 + yy, mm - 1, dd));
	const candidate2000 = new Date(Date.UTC(2000 + yy, mm - 1, dd));
	const now = new Date();

	if (kind === "birth") {
		const age1900 = yearsBetween(candidate1900, now);
		const age2000 = yearsBetween(candidate2000, now);
		if (candidate2000.getTime() <= now.getTime() && age2000 >= 0 && age2000 <= 120) {
			return formatDate(candidate2000);
		}
		if (candidate1900.getTime() <= now.getTime() && age1900 >= 0 && age1900 <= 120) {
			return formatDate(candidate1900);
		}
		return undefined;
	}

	const birthDate = parseDateToUtc(birthDateHint);
	if (birthDate && candidate2000.getTime() > birthDate.getTime()) {
		return formatDate(candidate2000);
	}
	if (birthDate && candidate1900.getTime() > birthDate.getTime()) {
		return formatDate(candidate1900);
	}
	return formatDate(candidate2000);
}

function yearsBetween(start: Date, end: Date): number {
	let years = end.getUTCFullYear() - start.getUTCFullYear();
	if (
		end.getUTCMonth() < start.getUTCMonth() ||
		(end.getUTCMonth() === start.getUTCMonth() && end.getUTCDate() < start.getUTCDate())
	) {
		years -= 1;
	}
	return years;
}

function formatDate(date: Date): string {
	const dd = String(date.getUTCDate()).padStart(2, "0");
	const mm = String(date.getUTCMonth() + 1).padStart(2, "0");
	const yyyy = String(date.getUTCFullYear());
	return `${dd}.${mm}.${yyyy}`;
}

function parseSex(value: string): string | undefined {
	const normalized = value.trim().toUpperCase();
	if (normalized === "M" || normalized === "F" || normalized === "X") return normalized;
	return undefined;
}

function extractOcrElements(
	annotations: VisionTextAnnotation[] | undefined,
	pageImageId: string
): OcrElement[] {
	if (!annotations || annotations.length < 2) return [];
	const result: OcrElement[] = [];
	for (const annotation of annotations.slice(1)) {
		const text = (annotation.description || "").trim();
		if (!text) continue;
		const vertices = annotation.boundingPoly?.vertices || [];
		const boundingBox = vertices.map((vertex) => ({
			x: typeof vertex?.x === "number" ? vertex.x : 0,
			y: typeof vertex?.y === "number" ? vertex.y : 0,
		}));
		if (boundingBox.length === 0) continue;
		result.push({
			text,
			boundingBox,
			confidence: typeof annotation.confidence === "number" ? annotation.confidence : undefined,
			pageImageId,
			detectedLanguage: (annotation.locale || "").trim().toLowerCase() || undefined,
		});
	}
	return result;
}

function extractSpatiallyOrderedLines(annotations?: VisionTextAnnotation[]): string[] {
	if (!annotations || annotations.length < 2) return [];
	const words = annotations
		.slice(1)
		.map((annotation) => {
			const text = (annotation.description || "").trim();
			const vertices = annotation.boundingPoly?.vertices || [];
			const xs = vertices
				.map((vertex) => vertex?.x)
				.filter((x): x is number => typeof x === "number");
			const ys = vertices
				.map((vertex) => vertex?.y)
				.filter((y): y is number => typeof y === "number");
			if (!text || xs.length === 0 || ys.length === 0) return null;
			return {
				text,
				x: xs.reduce((sum, item) => sum + item, 0) / xs.length,
				y: ys.reduce((sum, item) => sum + item, 0) / ys.length,
			};
		})
		.filter((value): value is {text: string; x: number; y: number} => value !== null);

	if (words.length === 0) return [];

	words.sort((a, b) => a.y - b.y || a.x - b.x);
	const grouped: Array<Array<{text: string; x: number; y: number}>> = [];
	for (const word of words) {
		const current = grouped[grouped.length - 1];
		if (!current) {
			grouped.push([word]);
			continue;
		}
		const avgY = current.reduce((sum, item) => sum + item.y, 0) / current.length;
		if (Math.abs(word.y - avgY) <= 20) {
			current.push(word);
		} else {
			grouped.push([word]);
		}
	}

	return grouped
		.map((group) =>
			group
				.sort((a, b) => a.x - b.x)
				.map((item) => item.text)
				.join(" ")
				.trim()
		)
		.filter((line) => line.length > 0);
}

const LABEL_DICTIONARY: Record<string, string[]> = {
	firstName: ["Ime", "Vornamen", "Given names", "Given name", "Prénoms", "Prenoms", "Nome"],
	lastName: ["Prezime", "Name", "Surname", "Familienname", "Nom", "Cognome"],
	dateOfBirth: [
		"Datum rođenja",
		"Geburtsdatum",
		"Date of birth",
		"Date de naissance",
		"Data di nascita",
	],
	nationality: [
		"Državljanstvo",
		"Staatsangehörigkeit",
		"Staatsangehorigkeit",
		"Nationality",
		"Nationalité",
	],
	documentNumber: ["Broj dokumenta", "Ausweisnummer", "Document No", "Document number", "Personal ID"],
	documentExpiryDate: ["Vrijedi do", "Gültig bis", "Date of expiry", "Date d'expiration"],
	issueDate: ["Datum izdavanja", "Ausstellungsdatum", "Ausgestellt am", "Date of issue", "Issued on"],
	gender: ["Spol", "Geschlecht", "Sex", "Gender"],
	issuingCountry: ["Država izdavanja", "Issuing country", "Ausstellender Staat"],
};

const COMMON_LABEL_LINES = [
	"name",
	"surname",
	"given names",
	"prenoms",
	"date of birth",
	"nationality",
	"document number",
	"sex",
	"gender",
];

const IGNORED_VALUE_PHRASES = [
	"given names",
	"prenoms",
	"surname",
	"nationality",
	"date of birth",
	"date of expiry",
	"identity card",
	"passport",
	"driving licence",
];

interface FindValueOptions {
	validator?: (value: string) => boolean;
	regexBonus?: RegExp;
	forbiddenSameLineTerms?: string[];
}

interface Candidate {
	value: string;
	score: number;
}

function parseWithLabels(
	lines: string[],
	rawLines: string[],
	_detectedLanguages: string[] = []
): ParsedData {
	const parsed: ParsedData = {};
	const mainLastName = findValueAfterLabel(lines, LABEL_DICTIONARY.lastName, {
		forbiddenSameLineTerms: ["geburtsname", "birth", "naissance"],
	});
	const birthLastName = findValueAfterLabel(lines, [
		"Geburtsname / Name at birth / Nom de naissance",
		"Geburtsname",
		"Name at birth",
		"Nom de naissance",
	]);
	parsed.lastName = sanitizeName(mainLastName) || sanitizeName(birthLastName);
	parsed.firstName = sanitizeName(findValueAfterLabel(lines, LABEL_DICTIONARY.firstName));
	parsed.dateOfBirth = normalizeDateValue(
		findValueAfterLabel(lines, LABEL_DICTIONARY.dateOfBirth, {
			regexBonus: /(\d{2}[.\-/ ]\d{2}[.\-/ ]\d{4}|\d{4}[.\-/ ]\d{2}[.\-/ ]\d{2})/,
		})
	);
	parsed.documentExpiryDate = normalizeDateValue(
		findValueAfterLabel(lines, LABEL_DICTIONARY.documentExpiryDate, {
			regexBonus: /(\d{2}[.\-/ ]\d{2}[.\-/ ]\d{4}|\d{4}[.\-/ ]\d{2}[.\-/ ]\d{2})/,
		})
	);
	parsed.issueDate = normalizeDateValue(
		findValueAfterLabel(lines, LABEL_DICTIONARY.issueDate, {
			regexBonus: /(\d{2}[.\-/ ]\d{2}[.\-/ ]\d{4}|\d{4}[.\-/ ]\d{2}[.\-/ ]\d{2})/,
		})
	);
	parsed.nationality = normalizeNationality(findValueAfterLabel(lines, LABEL_DICTIONARY.nationality));
	const nat = mapNationality(parsed.nationality);
	parsed.nationalityCode = nat.code;
	parsed.nationalityDisplayName = nat.displayName;
	parsed.issuingCountry = normalizeCountryCode(findValueAfterLabel(lines, LABEL_DICTIONARY.issuingCountry));
	parsed.documentNumber = findDocumentNumber(lines, rawLines);
	parsed.gender = findGender(lines);
	return parsed;
}

function findValueAfterLabel(
	lines: string[],
	labels: string[],
	options: FindValueOptions = {}
): string | undefined {
	const normalizedLabels = labels.map(normalizeForMatch);
	const candidates: Candidate[] = [];

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i].trim();
		if (!line) continue;
		const normalizedLine = normalizeForMatch(line);

		let matchedLabel: string | undefined;
		for (let j = 0; j < normalizedLabels.length; j++) {
			if (normalizedLine.includes(normalizedLabels[j])) {
				matchedLabel = labels[j];
				break;
			}
		}
		if (!matchedLabel) continue;

		const inline = extractInlineCandidate(line, matchedLabel);
		if (inline) addCandidate(candidates, inline, 70, options);

		for (let offset = 1; offset <= 4 && i + offset < lines.length; offset++) {
			const next = lines[i + offset].trim();
			if (!next) continue;
			if (isLikelyLabelLine(next) || isIgnoredValue(next)) continue;
			if (containsAny(normalizeForMatch(next), options.forbiddenSameLineTerms)) continue;
			addCandidate(candidates, next, 100 - (offset - 1) * 15, options);
			break;
		}
	}

	if (candidates.length === 0) return undefined;
	candidates.sort((a, b) => b.score - a.score);
	return candidates[0].value;
}

function addCandidate(
	candidates: Candidate[],
	rawValue: string,
	baseScore: number,
	options: FindValueOptions
): void {
	const clean = cleanupCandidate(rawValue);
	if (!clean || isLikelyLabelLine(clean) || isIgnoredValue(clean)) return;
	if (options.validator && !options.validator(clean)) return;
	let score = baseScore;
	if (options.regexBonus?.test(clean)) score += 20;
	candidates.push({value: clean, score});
}

function extractInlineCandidate(line: string, label: string): string | undefined {
	const normalizedLabel = normalizeForMatch(label);
	const lineTokens = normalizeForMatch(line).split(" ");
	const labelTokens = normalizedLabel.split(" ").filter(Boolean);
	let startToken = 0;
	while (
		startToken + labelTokens.length <= lineTokens.length &&
		lineTokens.slice(startToken, startToken + labelTokens.length).join(" ") !== normalizedLabel
	) {
		startToken++;
	}
	if (startToken + labelTokens.length > lineTokens.length) return undefined;

	const originalParts = line.split(/\s+/);
	const after = originalParts.slice(startToken + labelTokens.length).join(" ");
	const candidate = cleanupCandidate(after.replace(/^[:\-\/\s]+/, ""));
	if (!candidate || isLikelyLabelLine(candidate) || isIgnoredValue(candidate)) return undefined;
	return candidate;
}

function findDocumentNumber(lines: string[], rawLines: string[]): string | undefined {
	const byLabel = findValueAfterLabel(lines, LABEL_DICTIONARY.documentNumber, {
		validator: isValidDocumentNumber,
		regexBonus: /^[A-Z0-9<]{5,20}$/,
	});
	if (byLabel) return normalizeDocumentNumberGeneral(byLabel);

	for (const line of [...lines, ...rawLines]) {
		const tokens = line.toUpperCase().match(/[A-Z0-9<]{5,20}/g) || [];
		for (const token of tokens) {
			if (isValidDocumentNumber(token)) {
				return normalizeDocumentNumberGeneral(token);
			}
		}
	}

	return undefined;
}

function normalizeDocumentNumberGeneral(value?: string): string | undefined {
	if (!value) return undefined;
	const candidate = value.trim().toUpperCase().replace(/\s+/g, "");
	return candidate || undefined;
}

function isValidDocumentNumber(value: string): boolean {
	const candidate = (normalizeDocumentNumberGeneral(value) || "").replace(/</g, "");
	if (!/^[A-Z0-9]{5,20}$/.test(candidate)) return false;
	if (!/\d/.test(candidate)) return false;
	if (["IDENTITYCARD", "PASSPORT", "DRIVINGLICENCE", "DRIVERSLICENSE"].includes(candidate)) return false;
	if (normalizeDateValue(candidate)) return false;
	return true;
}

function normalizeDateValue(value?: string): string | undefined {
	if (!value) return undefined;
	const text = value.trim();
	const eu = text.match(/(\d{2})[.\-/ ](\d{2})[.\-/ ](\d{4})/);
	if (eu) return `${eu[1]}.${eu[2]}.${eu[3]}`;
	const iso = text.match(/(\d{4})[.\-/ ](\d{2})[.\-/ ](\d{2})/);
	if (iso) return `${iso[3]}.${iso[2]}.${iso[1]}`;
	return undefined;
}

function normalizeNationality(value?: string): string | undefined {
	if (!value) return undefined;
	const cleaned = cleanupCandidate(value).toUpperCase();
	if (!cleaned || looksLikeDate(cleaned)) return undefined;
	return normalizeCountryCode(cleaned) || cleaned;
}

function mapNationality(value?: string): {code?: string; displayName?: string} {
	const code = normalizeCountryCode(value);
	if (!code) return {};
	return {
		code,
		displayName: ISO_3166_ALPHA3_TO_DISPLAY[code] || code,
	};
}

const ISO_3166_ALPHA3_TO_DISPLAY: Record<string, string> = {
	HRV: "Hrvatska",
	DEU: "Njemačka",
	ITA: "Italija",
	AUT: "Austrija",
	SVN: "Slovenija",
	POL: "Poljska",
	CZE: "Češka",
	SVK: "Slovačka",
	HUN: "Mađarska",
	FRA: "Francuska",
	NLD: "Nizozemska",
	BEL: "Belgija",
	ESP: "Španjolska",
	PRT: "Portugal",
	CHE: "Švicarska",
	GBR: "Ujedinjeno Kraljevstvo",
	USA: "Sjedinjene Američke Države",
	CAN: "Kanada",
	AUS: "Australija",
};

const COUNTRY_CODE_ALIASES: Record<string, string> = {
	D: "DEU",
	DE: "DEU",
	DEUTSCH: "DEU",
	GERMAN: "DEU",
	GERMANY: "DEU",
	HR: "HRV",
	CROATIA: "HRV",
	IT: "ITA",
	SI: "SVN",
	AT: "AUT",
	PL: "POL",
	CZ: "CZE",
	SK: "SVK",
	HU: "HUN",
	FR: "FRA",
	NL: "NLD",
	BE: "BEL",
	ES: "ESP",
	PT: "PRT",
	CH: "CHE",
	GB: "GBR",
	UK: "GBR",
	US: "USA",
	CA: "CAN",
	AU: "AUS",
};

function normalizeCountryCode(value?: string): string | undefined {
	if (!value) return undefined;
	const cleaned = cleanupCandidate(value)
		.replace(/</g, "")
		.replace(/[^\p{L}0-9]/gu, "")
		.toUpperCase();
	if (!cleaned) return undefined;
	if (COUNTRY_CODE_ALIASES[cleaned]) return COUNTRY_CODE_ALIASES[cleaned];
	if (cleaned.length === 3 && ISO_3166_ALPHA3_TO_DISPLAY[cleaned]) return cleaned;
	if (cleaned.length <= 3) return cleaned;
	return undefined;
}

function sanitizeName(value?: string): string | undefined {
	if (!value) return undefined;
	const cleaned = cleanupCandidate(value).replace(/[^\p{L}\s\-']/gu, "").trim();
	if (!cleaned || isIgnoredValue(cleaned) || isLikelyLabelLine(cleaned)) return undefined;
	return cleaned.toUpperCase();
}

function findGender(lines: string[]): string | undefined {
	const byLabel = findValueAfterLabel(lines, LABEL_DICTIONARY.gender);
	if (byLabel) {
		const normalized = normalizeGender(byLabel);
		if (normalized) return normalized;
	}
	for (const line of lines) {
		const normalized = normalizeGender(line);
		if (normalized) return normalized;
	}
	return undefined;
}

function normalizeGender(value: string): string | undefined {
	const normalized = normalizeForMatch(value);
	if (/(^|\s)m(\s|$)|mannlich|masculin|masculino/.test(normalized)) return "M";
	if (/(^|\s)f(\s|$)|weiblich|feminin|feminino/.test(normalized)) return "F";
	if (/(^|\s)x(\s|$)|divers|other/.test(normalized)) return "X";
	return undefined;
}

function cleanupCandidate(value: string): string {
	return value
		.replace(/^[\s:;,.\-\/|]+/, "")
		.replace(/[\s:;,.\-\/|]+$/, "")
		.replace(/\s+/g, " ")
		.trim();
}

function normalizeForMatch(value: string): string {
	return value
		.normalize("NFD")
		.replace(/[\u0300-\u036f]/g, "")
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, " ")
		.replace(/\s+/g, " ")
		.trim();
}

function containsAny(value: string, terms?: string[]): boolean {
	if (!terms || terms.length === 0) return false;
	return terms.some((term) => value.includes(normalizeForMatch(term)));
}

function isIgnoredValue(value: string): boolean {
	const normalized = normalizeForMatch(value);
	return IGNORED_VALUE_PHRASES.some((phrase) => normalized.includes(normalizeForMatch(phrase)));
}

function isLikelyLabelLine(value: string): boolean {
	const normalized = normalizeForMatch(value);
	if (!normalized) return true;
	if (COMMON_LABEL_LINES.some((label) => normalized.includes(normalizeForMatch(label)))) {
		const words = normalized.split(" ").filter(Boolean);
		const labelWords = COMMON_LABEL_LINES.flatMap((label) => normalizeForMatch(label).split(" "));
		const nonLabelWords = words.filter((word) => !labelWords.includes(word));
		if (nonLabelWords.length <= 1) return true;
	}
	return false;
}

function mapDocumentCodeToKind(code?: string): DocumentKind {
	const normalized = (code || "").toUpperCase();
	if (normalized.startsWith("P")) return "passport";
	if (normalized.startsWith("I")) return "nationalIdCard";
	if (normalized.startsWith("A") || normalized.startsWith("C") || normalized.startsWith("V")) {
		return "residencePermit";
	}
	return "unknownIdentityDocument";
}

function detectDocumentKind(input: {
	lines: string[];
	documentCode?: string;
	mrzFormat?: MrzFormat;
	hasMrz: boolean;
}): DocumentKind {
	const byCode = mapDocumentCodeToKind(input.documentCode);
	if (byCode !== "unknownIdentityDocument") return byCode;
	const joined = input.lines.join(" ").toLowerCase();
	if (
		joined.includes("driving licence") ||
		joined.includes("driver license") ||
		joined.includes("vozačka dozvola") ||
		joined.includes("führerschein") ||
		joined.includes("fuhrerschein")
	) {
		return "drivingLicence";
	}
	if (joined.includes("passport") || joined.includes("reisepass") || joined.includes("putovnica")) {
		return "passport";
	}
	if (joined.includes("residence permit") || joined.includes("boravišna") || joined.includes("permesso di soggiorno")) {
		return "residencePermit";
	}
	if (joined.includes("identity card") || joined.includes("osobna iskaznica") || joined.includes("personalausweis")) {
		return "nationalIdCard";
	}
	if (input.mrzFormat === "TD3") return "passport";
	if (input.mrzFormat === "MRV-A" || input.mrzFormat === "MRV-B") return "residencePermit";
	if (input.mrzFormat === "TD1" || input.mrzFormat === "TD2") return "nationalIdCard";
	return input.hasMrz ? "unknownIdentityDocument" : "unknownIdentityDocument";
}

const COUNTRY_ADAPTERS: DocumentCountryAdapter[] = [
	createCountryAdapter("Croatia", ["HRV"]),
	createCountryAdapter("Germany", ["DEU"]),
	createCountryAdapter("Italy", ["ITA"]),
	createCountryAdapter("Slovenia", ["SVN"]),
	createCountryAdapter("Austria", ["AUT"]),
	createCountryAdapter("Poland", ["POL"]),
	createCountryAdapter("CzechRepublic", ["CZE"]),
	createCountryAdapter("Slovakia", ["SVK"]),
	createCountryAdapter("Hungary", ["HUN"]),
];

function createCountryAdapter(name: string, countryCodes: string[]): DocumentCountryAdapter {
	return {
		name,
		supports(context: DocumentContext): boolean {
			return countryCodes.includes((context.issuingCountry || "").toUpperCase());
		},
		extractFields(_context: DocumentContext): Partial<ParsedData> {
			return {};
		},
		normalizeDocumentNumber(value?: string): string | undefined {
			return normalizeDocumentNumberGeneral(value);
		},
		normalizeNationality(value?: string): string | undefined {
			return normalizeCountryCode(value);
		},
		extractIssueDate(context: DocumentContext): string | undefined {
			return normalizeDateValue(findValueAfterLabel(context.lines, LABEL_DICTIONARY.issueDate));
		},
		detectSpecialFields(_context: DocumentContext): Partial<ParsedData> {
			return {};
		},
	};
}

function applyCountryAdapters(parsed: ParsedData, context: DocumentContext): void {
	for (const adapter of COUNTRY_ADAPTERS) {
		if (!adapter.supports(context)) continue;
		mergeMissing(parsed, adapter.extractFields(context));
		const normalizedDocumentNumber = adapter.normalizeDocumentNumber(parsed.documentNumber);
		if (normalizedDocumentNumber) parsed.documentNumber = normalizedDocumentNumber;
		const normalizedNationality = adapter.normalizeNationality(parsed.nationalityCode || parsed.nationality);
		if (normalizedNationality) {
			const meta = mapNationality(normalizedNationality);
			parsed.nationality = meta.code;
			parsed.nationalityCode = meta.code;
			parsed.nationalityDisplayName = meta.displayName;
		}
		if (!parsed.issueDate) parsed.issueDate = adapter.extractIssueDate(context);
		mergeMissing(parsed, adapter.detectSpecialFields(context));
	}
}

function mergeImageResults(images: OcrImageResult[]): MergedResult {
	const fields: Record<string, MergedField> = {};
	const parsed: ParsedData = {};
	const conflicts: string[] = [];
	let firstNameResolution = resolveNameField(images, "firstName");
	let lastNameResolution = resolveNameField(images, "lastName");

	({first: firstNameResolution, last: lastNameResolution} =
		applyDuplicateVisualNameCandidateRule(
			firstNameResolution,
			lastNameResolution,
			images
		));

	fields.firstName = firstNameResolution.field;
	fields.middleNames = resolveField(images, "middleNames", isValidName);
	fields.lastName = lastNameResolution.field;
	fields.documentCode = resolveField(images, "documentCode", (value) => /^[A-Z]{1,2}$/.test(value));
	fields.documentKind = resolveField(images, "documentKind", (value) => value.length > 0);
	fields.dateOfBirth = resolveField(images, "dateOfBirth", isValidDate);
	fields.documentExpiryDate = resolveField(images, "documentExpiryDate", isValidDate);
	fields.issueDate = resolveField(images, "issueDate", isValidDate, {optional: true});
	fields.nationality = resolveField(
		images,
		"nationality",
		(value) => !looksLikeDate(value) && !isValidDocumentNumber(value)
	);
	fields.nationalityCode = resolveField(images, "nationalityCode", (value) => /^[A-Z]{1,3}$/.test(value));
	fields.nationalityDisplayName = resolveField(images, "nationalityDisplayName", (value) => value.length > 0);
	fields.documentNumber = resolveField(images, "documentNumber", isValidDocumentNumber);
	fields.gender = resolveField(
		images,
		"gender",
		(value) => /^(M|F|X)$/i.test(value),
		{optional: true}
	);
	fields.issuingCountry = resolveField(images, "issuingCountry", (value) => value.length > 0);
	fields.optionalData = resolveField(images, "optionalData", (value) => value.length > 0, {
		optional: true,
	});
	fields.personalNumber = resolveField(images, "personalNumber", (value) => value.length > 0, {
		optional: true,
	});
	fields.documentType = resolveField(images, "documentType", (value) => value.length > 0);

	parsed.firstName = fields.firstName.value;
	parsed.middleNames = fields.middleNames.value;
	parsed.lastName = fields.lastName.value;
	parsed.documentCode = fields.documentCode.value;
	parsed.documentKind = fields.documentKind.value as DocumentKind | undefined;
	parsed.dateOfBirth = fields.dateOfBirth.value;
	parsed.documentExpiryDate = fields.documentExpiryDate.value;
	parsed.issueDate = fields.issueDate.value;
	parsed.nationality = fields.nationality.value;
	parsed.nationalityCode = fields.nationalityCode.value;
	parsed.nationalityDisplayName = fields.nationalityDisplayName.value;
	parsed.documentNumber = fields.documentNumber.value;
	parsed.gender = fields.gender.value;
	parsed.issuingCountry = fields.issuingCountry.value;
	parsed.optionalData = fields.optionalData.value;
	parsed.personalNumber = fields.personalNumber.value;
	parsed.documentType = (parsed.documentKind || fields.documentType.value) as string | undefined;
	parsed.mrzText = images
		.map((image) => image.parsed.mrzText)
		.find((value) => ((value || "").trim().length > 0));
	parsed.confidence = computeMergedConfidence(fields);

	if (
		normalizeNameComparisonValue(parsed.firstName) ===
			normalizeNameComparisonValue(parsed.lastName) &&
		(parsed.firstName || "").trim().length > 0
	) {
		conflicts.push("Ime i prezime su jednaki. Potrebna ručna provjera.");
		markNeedsReview(fields, ["firstName", "lastName"]);
	}
	if (parsed.nationality && looksLikeDate(parsed.nationality)) {
		conflicts.push("Nacionalnost izgleda kao datum. Potrebna ručna provjera.");
		markNeedsReview(fields, ["nationality"]);
	}
	if (parsed.documentNumber && isLikelyCountryText(parsed.documentNumber)) {
		conflicts.push("Broj dokumenta izgleda kao naziv države.");
		markNeedsReview(fields, ["documentNumber"]);
	}
	if (
		parsed.dateOfBirth &&
		parsed.documentExpiryDate &&
		parsed.dateOfBirth === parsed.documentExpiryDate
	) {
		conflicts.push("Datum rođenja i datum isteka su isti.");
		markNeedsReview(fields, ["dateOfBirth", "documentExpiryDate"]);
	}
	if (uniqueFieldValues(images, "documentNumber").length > 1) {
		conflicts.push("Različite fotografije daju različite brojeve dokumenta.");
		markNeedsReview(fields, ["documentNumber"]);
	}

	const mrzBirth = findMrzFieldValues(images, "dateOfBirth");
	const labelBirth = findNonMrzFieldValues(images, "dateOfBirth");
	if (mrzBirth.length > 0 && labelBirth.length > 0 && !mrzBirth.some((value) => labelBirth.includes(value))) {
		conflicts.push("MRZ i prednja strana daju različit datum rođenja.");
		markNeedsReview(fields, ["dateOfBirth"]);
	}

	if (
		firstNameResolution.debug.mrzNormalizedValue &&
		firstNameResolution.debug.visualNormalizedValue &&
		firstNameResolution.debug.mrzNormalizedValue !== firstNameResolution.debug.visualNormalizedValue
	) {
		conflicts.push("MRZ i prednja strana daju različito ime.");
		markNeedsReview(fields, ["firstName"]);
	}

	if (
		lastNameResolution.debug.mrzNormalizedValue &&
		lastNameResolution.debug.visualNormalizedValue &&
		lastNameResolution.debug.mrzNormalizedValue !== lastNameResolution.debug.visualNormalizedValue
	) {
		conflicts.push("MRZ i prednja strana daju različito prezime.");
		markNeedsReview(fields, ["lastName"]);
	}

	validateDateConsistency(parsed, fields, conflicts);
	return {
		parsed,
		fields,
		conflicts,
		debug: ENABLE_NAME_CANDIDATE_DEBUG
			? {
					firstName: firstNameResolution.debug,
					lastName: lastNameResolution.debug,
				}
			: undefined,
	};
}

function resolveNameField(images: OcrImageResult[], field: "firstName" | "lastName"): NameFieldResolution {
	const candidates = images
		.map((image) => {
			const valueRaw = (image.parsed[field] as string | undefined) || "";
			const value = valueRaw.trim();
			if (!value) return null;
			const sourceType = inferSourceType(image, field, value);
			const scoreBeforeValidation = adjustNameCandidateScore({
				image,
				field,
				sourceType,
				baseConfidence: image.parsed.confidence || 0.5,
			});
			const validation = validateVisualNameCandidate({
				field,
				value,
				image,
				sourceType,
				scoreBeforeValidation,
			});
			if (!validation.valid) {
				return {
					value,
					canonicalValue: normalizeNameComparisonValue(value),
					score: scoreBeforeValidation,
					scoreBeforeValidation,
					scoreAfterValidation: 0,
					sourceImageId: image.imageId,
					sourceType,
					rejectionReason: validation.reason,
				};
			}
			const canonicalValue = normalizeNameComparisonValue(value);
			if (!canonicalValue) return null;
			return {
				value,
				canonicalValue,
				score: scoreBeforeValidation,
				scoreBeforeValidation,
				scoreAfterValidation: scoreBeforeValidation,
				sourceImageId: image.imageId,
				sourceType,
			};
		})
		.filter(
			(
				candidate
			): candidate is NameCandidate => candidate !== null
		);

	const mrzCandidates = candidates.filter((candidate) => candidate.sourceType === "mrz");
	const visualCandidates = candidates.filter(
		(candidate) => candidate.sourceType !== "mrz" && !candidate.rejectionReason
	);
	const rejectedVisualCandidates = candidates.filter(
		(candidate) => candidate.sourceType !== "mrz" && !!candidate.rejectionReason
	);
	const bestRejectedVisual = rejectedVisualCandidates.sort(
		(a, b) => b.scoreBeforeValidation - a.scoreBeforeValidation
	)[0];

	if (mrzCandidates.length === 0 && visualCandidates.length === 0) {
		return {
			field: {
				confidence: 0,
				sourceType: "manual",
				needsReview: true,
			},
			debug: {
				rawVisualCandidate: bestRejectedVisual?.value,
				visualNormalizedValue: bestRejectedVisual?.canonicalValue,
				visualValid: false,
				rejectionReason: bestRejectedVisual?.rejectionReason,
				visualSourceType: bestRejectedVisual?.sourceType,
				visualConfidence: bestRejectedVisual?.scoreAfterValidation,
				visualConfidenceBeforeValidation:
					bestRejectedVisual?.scoreBeforeValidation,
				visualConfidenceAfterValidation: bestRejectedVisual?.scoreAfterValidation,
			},
		};
	}

	const grouped = new Map<string, number>();
	for (const candidate of [...mrzCandidates, ...visualCandidates]) {
		grouped.set(candidate.canonicalValue, (grouped.get(candidate.canonicalValue) || 0) + 1);
	}

	const validCandidates = [...mrzCandidates, ...visualCandidates];
	validCandidates.sort((a, b) => {
		const freqA = grouped.get(a.canonicalValue) || 0;
		const freqB = grouped.get(b.canonicalValue) || 0;
		if (freqA !== freqB) return freqB - freqA;
		return b.score - a.score;
	});

	const best = validCandidates[0];
	const bestVisual = visualCandidates[0];
	const bestMrz = mrzCandidates[0];
	const hasConflictCandidate =
		bestMrz != null &&
		visualCandidates.some(
			(candidate) =>
				candidate.score >= 0.75 &&
				candidate.sourceType !== "fallback" &&
				candidate.canonicalValue !== bestMrz.canonicalValue
		);

	let bestImage: OcrImageResult | undefined;
	for (const image of images) {
		if (image.imageId == best.sourceImageId) {
			bestImage = image;
			break;
		}
	}
	const fromValidMrz =
		best.sourceType === "mrz" &&
		bestImage != null &&
		isMrzChecksumValid(bestImage.parsed.mrzText);

	const needsReview = hasConflictCandidate || (!fromValidMrz && best.score < 0.75);

	return {
		field: {
			value: best.value,
			confidence: roundConfidence(best.score),
			sourceImageId: best.sourceImageId,
			sourceType: best.sourceType,
			needsReview,
		},
		debug: {
			mrzNormalizedValue: bestMrz?.canonicalValue,
			rawVisualCandidate: bestVisual?.value ?? bestRejectedVisual?.value,
			visualNormalizedValue: bestVisual?.canonicalValue,
			visualValid: bestVisual != null,
			rejectionReason: bestVisual == null ? bestRejectedVisual?.rejectionReason : undefined,
			visualConfidence: bestVisual ? roundConfidence(bestVisual.score) : undefined,
			visualConfidenceBeforeValidation: bestVisual?.scoreBeforeValidation,
			visualConfidenceAfterValidation: bestVisual?.scoreAfterValidation,
			visualSourceType: bestVisual?.sourceType,
		},
		mrzCandidate: bestMrz,
		visualCandidate: bestVisual,
	};
}

function applyDuplicateVisualNameCandidateRule(
	first: NameFieldResolution,
	last: NameFieldResolution,
	images: OcrImageResult[]
): {first: NameFieldResolution; last: NameFieldResolution} {
	const firstVisual = first.visualCandidate;
	const lastVisual = last.visualCandidate;
	if (
		firstVisual == null ||
		lastVisual == null ||
		firstVisual.canonicalValue != lastVisual.canonicalValue
	) {
		return {first, last};
	}

	if (hasDistinctVisualEvidence(firstVisual, lastVisual, images)) {
		return {first, last};
	}

	const reason = "duplicateCandidateForFirstAndLastName";
	first.debug = {
		...first.debug,
		visualValid: false,
		rejectionReason: first.debug.rejectionReason ?? reason,
		visualConfidenceAfterValidation: 0,
		visualConfidence: 0,
		visualNormalizedValue: undefined,
	};
	last.debug = {
		...last.debug,
		visualValid: false,
		rejectionReason: last.debug.rejectionReason ?? reason,
		visualConfidenceAfterValidation: 0,
		visualConfidence: 0,
		visualNormalizedValue: undefined,
	};
	first.visualCandidate = undefined;
	last.visualCandidate = undefined;

	if (first.mrzCandidate && first.mrzCandidate.sourceType === "mrz") {
		first.field = {
			value: first.mrzCandidate.value,
			confidence: roundConfidence(first.mrzCandidate.score),
			sourceImageId: first.mrzCandidate.sourceImageId,
			sourceType: "mrz",
			needsReview: false,
		};
	}
	if (last.mrzCandidate && last.mrzCandidate.sourceType === "mrz") {
		last.field = {
			value: last.mrzCandidate.value,
			confidence: roundConfidence(last.mrzCandidate.score),
			sourceImageId: last.mrzCandidate.sourceImageId,
			sourceType: "mrz",
			needsReview: false,
		};
	}

	return {first, last};
}

function resolveField(
	images: OcrImageResult[],
	field: keyof ParsedData,
	validator: (value: string) => boolean,
	options: {optional?: boolean} = {}
): MergedField {
	const candidates = images
		.map((image) => {
			const valueRaw = (image.parsed[field] as string | undefined) || "";
			const value = normalizeMergeFieldValueForField(field, valueRaw.trim());
			if (!value || !validator(value)) return null;
			const canonicalValue = normalizeFieldForComparison(field, value);
			if (!canonicalValue) return null;

			const sourceType = inferSourceType(image, field, value);
			let score = image.parsed.confidence || 0.5;
			if (sourceType === "mrz") score += isMrzChecksumValid(image.parsed.mrzText) ? 0.45 : 0.15;
			if (sourceType === "labelMatch") score += 0.2;
			if (sourceType === "fallback") score -= 0.1;

			return {value, canonicalValue, score, sourceImageId: image.imageId, sourceType};
		})
		.filter(
			(
				candidate
			): candidate is {
				value: string;
				canonicalValue: string;
				score: number;
				sourceImageId: string;
				sourceType: MergedField["sourceType"];
			} => candidate !== null
		);

	if (candidates.length === 0) {
		return {
			confidence: 0,
			sourceType: "manual",
			needsReview: !(options.optional ?? false),
		};
	}

	const grouped = new Map<string, number>();
	for (const candidate of candidates) {
		grouped.set(candidate.canonicalValue, (grouped.get(candidate.canonicalValue) || 0) + 1);
	}

	candidates.sort((a, b) => {
		const freqA = grouped.get(a.canonicalValue) || 0;
		const freqB = grouped.get(b.canonicalValue) || 0;
		if (freqA !== freqB) return freqB - freqA;
		return b.score - a.score;
	});

	const best = candidates[0];
	const hasConflictCandidate = candidates.some(
		(candidate) => candidate.canonicalValue !== best.canonicalValue && candidate.score > 0.75
	);

	let bestImage: OcrImageResult | undefined;
	for (const image of images) {
		if (image.imageId == best.sourceImageId) {
			bestImage = image;
			break;
		}
	}
	const fromValidMrz =
		best.sourceType === "mrz" &&
		bestImage != null &&
		isMrzChecksumValid(bestImage.parsed.mrzText);

	const needsReview = hasConflictCandidate || (!fromValidMrz && best.score < 0.75);

	return {
		value: best.value,
		confidence: roundConfidence(best.score),
		sourceImageId: best.sourceImageId,
		sourceType: best.sourceType,
		needsReview,
	};
}

function normalizeMergeFieldValueForField(
	field: keyof ParsedData,
	value: string
): string {
	if (!value) return "";

	if (field === "nationality" || field === "nationalityCode" || field === "issuingCountry") {
		return normalizeCountryCode(value) || value.trim().toUpperCase();
	}

	if (field === "documentType" || field === "documentKind") {
		return normalizeDocumentKindValue(value);
	}

	return value;
}

function normalizeDocumentKindValue(value: string): string {
	const normalized = normalizeForMatch(value);
	if (!normalized) return value.trim();
	if (
		normalized.includes("identity card") ||
		normalized.includes("personalausweis") ||
		normalized.includes("osobna iskaznica") ||
		normalized === "id card" ||
		normalized === "id"
	) {
		return "nationalIdCard";
	}
	if (normalized.includes("passport") || normalized.includes("reisepass") || normalized.includes("putovnica")) {
		return "passport";
	}
	if (
		normalized.includes("residence permit") ||
		normalized.includes("boravisna") ||
		normalized.includes("permesso di soggiorno")
	) {
		return "residencePermit";
	}
	if (
		normalized.includes("driving licence") ||
		normalized.includes("driver license") ||
		normalized.includes("vozacka")
	) {
		return "drivingLicence";
	}
	return value.trim();
}

function inferSourceType(
	image: OcrImageResult,
	field: keyof ParsedData,
	value: string
): MergedField["sourceType"] {
	const mrzFields: Array<keyof ParsedData> = [
		"documentCode",
		"firstName",
		"middleNames",
		"lastName",
		"documentNumber",
		"nationality",
		"nationalityCode",
		"dateOfBirth",
		"gender",
		"documentExpiryDate",
		"issuingCountry",
		"optionalData",
		"personalNumber",
	];
	const mrzText = (image.parsed.mrzText || "").replace(/\s+/g, "").toUpperCase();
	if (
		mrzText &&
		(mrzFields.includes(field) || mrzText.includes(value.replace(/\s+/g, "").toUpperCase()))
	) {
		return "mrz";
	}
	if (field === "firstName" || field === "lastName" || field === "middleNames") {
		const rawText = normalizeForMatch(image.rawText || "");
		const labels =
			LABEL_DICTIONARY[
				field === "lastName" ? "lastName" : "firstName"
			] || [];
		if (rawText && labels.some((label) => rawText.includes(normalizeForMatch(label)))) {
			return "labelMatch";
		}
		if (image.documentSide === "frontIdCard") {
			return "spatialMatch";
		}
	}
	if (field === "documentNumber" && image.documentSide === "frontIdCard") return "spatialMatch";
	if (field === "documentNumber" || field === "dateOfBirth" || field === "documentExpiryDate") {
		return "labelMatch";
	}
	return "fallback";
}

function computeMergedConfidence(fields: Record<string, MergedField>): number {
	const values = Object.values(fields)
		.map((field) => field.confidence)
		.filter((value) => value > 0);
	if (values.length === 0) return 0;
	return roundConfidence(values.reduce((sum, value) => sum + value, 0) / values.length);
}

function uniqueFieldValues(images: OcrImageResult[], field: keyof ParsedData): string[] {
	return Array.from(
		new Set(
			images
				.map((image) => ((image.parsed[field] as string | undefined) || "").trim())
				.map((value) => normalizeFieldForComparison(field, value))
				.filter((value) => value.length > 0)
		)
	);
}

function findMrzFieldValues(images: OcrImageResult[], field: keyof ParsedData): string[] {
	return Array.from(
		new Set(
			images
				.filter((image) => ((image.parsed.mrzText || "").trim().length > 0))
				.map((image) => ((image.parsed[field] as string | undefined) || "").trim())
				.map((value) => normalizeFieldForComparison(field, value))
				.filter((value) => value.length > 0)
		)
	);
}

function findNonMrzFieldValues(images: OcrImageResult[], field: keyof ParsedData): string[] {
	return Array.from(
		new Set(
			images
				.filter((image) => !((image.parsed.mrzText || "").trim().length > 0))
				.map((image) => ((image.parsed[field] as string | undefined) || "").trim())
				.map((value) => normalizeFieldForComparison(field, value))
				.filter((value) => value.length > 0)
		)
	);
}

function normalizeFieldForComparison(field: keyof ParsedData, value: string): string {
	const normalized = normalizeMergeComparisonValue(value);
	if (
		field === "documentNumber" ||
		field === "nationality" ||
		field === "nationalityCode" ||
		field === "issuingCountry" ||
		field === "documentCode"
	) {
		return normalized.replace(/\s+/g, "");
	}
	return normalized;
}

function normalizeNameComparisonValue(value?: string): string {
	if (!value) return "";
	return value
		.normalize("NFD")
		.replace(/[\u0300-\u036f]/g, "")
		.toUpperCase()
		.replace(/</g, " ")
		.replace(/[^\p{L}\s'\-]+/gu, " ")
		.replace(/\s+/g, " ")
		.trim();
}

function normalizeMergeComparisonValue(value?: string): string {
	if (!value) return "";
	return value
		.normalize("NFD")
		.replace(/[\u0300-\u036f]/g, "")
		.toUpperCase()
		.replace(/</g, " ")
		.replace(/\s+/g, " ")
		.trim();
}

function adjustNameCandidateScore(input: {
	image: OcrImageResult;
	field: "firstName" | "lastName";
	sourceType: MergedField["sourceType"];
	baseConfidence: number;
}): number {
	const {image, sourceType, baseConfidence} = input;
	let score = baseConfidence;

	if (sourceType === "mrz") {
		score = isMrzChecksumValid(image.parsed.mrzText)
			? Math.max(score, 0.95)
			: Math.max(score, 0.7);
		return roundConfidence(Math.min(score, 1));
	}

	if (sourceType === "spatialMatch") {
		return roundConfidence(Math.min(Math.max(score, 0.8), 0.95));
	}
	if (sourceType === "labelMatch") {
		return roundConfidence(Math.min(Math.max(score, 0.6), 0.75));
	}
	if (sourceType === "fallback") {
		return roundConfidence(Math.min(Math.max(score, 0.5), 0.65));
	}

	return roundConfidence(Math.min(Math.max(score, 0.5), 0.9));
}

function validateVisualNameCandidate(input: {
	field: "firstName" | "lastName";
	value: string;
	image: OcrImageResult;
	sourceType: MergedField["sourceType"];
	scoreBeforeValidation: number;
}): {valid: boolean; reason?: string} {
	const {field, value, image, sourceType, scoreBeforeValidation} = input;
	const normalized = normalizeNameComparisonValue(value);
	if (!normalized) return {valid: false, reason: "emptyCandidate"};
	if (normalized.length < 2 || normalized.length > 40) {
		return {valid: false, reason: "invalidLength"};
	}
	if (!/^[\p{L}\s'\-]+$/u.test(normalized)) {
		return {valid: false, reason: "invalidCharacters"};
	}
	if (looksLikeDate(value)) return {valid: false, reason: "looksLikeDate"};
	if (isValidDocumentNumber(value)) return {valid: false, reason: "looksLikeDocumentNumber"};
	if (isLikelyCountryText(value)) return {valid: false, reason: "looksLikeCountry"};
	if (containsNameLabelText(field, value)) return {valid: false, reason: "containsLabelText"};
	if (hasSuspiciousOcrPrefix(normalized)) return {valid: false, reason: "ocrNoisePrefix"};
	if (looksLikeMergedOcrNoise(normalized)) return {valid: false, reason: "ocrNoise"};

	if (image.elements != null && image.elements.length > 0) {
		if (!existsAsStandaloneOcrElement(image, normalized)) {
			return {valid: false, reason: "notStandaloneOcrElement"};
		}
	}

	if (sourceType === "labelMatch" && !hasStrongNameSpatialEvidence(image, field, normalized)) {
		return {valid: false, reason: "missingSpatialEvidence"};
	}

	if (sourceType === "fallback" && scoreBeforeValidation > 0.65) {
		return {valid: false, reason: "fallbackTooConfident"};
	}

	return {valid: true};
}

function containsNameLabelText(field: "firstName" | "lastName", value: string): boolean {
	const normalized = normalizeForMatch(value);
	const labels =
		field === "firstName"
			? ["vornamen", "given names", "prenoms", "first name", "forename", "ime"]
			: [
					"name",
					"surname",
					"nom",
					"family name",
					"last name",
					"prezime",
					"familienname",
					"geburtsname",
					"name at birth",
				];
	return labels.some((label) => normalized.includes(normalizeForMatch(label)));
}

function hasSuspiciousOcrPrefix(normalized: string): boolean {
	return /^(ODD|IDD|0DD)/.test(normalized.replace(/\s+/g, ""));
}

function looksLikeMergedOcrNoise(normalized: string): boolean {
	const compact = normalized.replace(/\s+/g, "");
	if (compact.length > 20) return true;
	if (/([A-Z])\1{3,}/.test(compact)) return true;
	return false;
}

function existsAsStandaloneOcrElement(image: OcrImageResult, normalized: string): boolean {
	const elements = image.elements || [];
	if (elements.length === 0) return true;
	return elements.some((element) => {
		const text = normalizeNameComparisonValue(element.text || "");
		return text === normalized;
	});
}

function hasStrongNameSpatialEvidence(
	image: OcrImageResult,
	field: "firstName" | "lastName",
	normalizedValue: string
): boolean {
	const elements = image.elements || [];
	if (elements.length === 0) return false;

	const labels = LABEL_DICTIONARY[field];
	const labelElements = elements.filter((element) =>
		labels.some((label) => normalizeForMatch(element.text).includes(normalizeForMatch(label)))
	);
	if (labelElements.length === 0) return false;

	const valueElements = elements.filter(
		(element) => normalizeNameComparisonValue(element.text) === normalizedValue
	);
	if (valueElements.length === 0) return false;

	for (const labelElement of labelElements) {
		const labelCenter = elementCenter(labelElement);
		for (const valueElement of valueElements) {
			const valueCenter = elementCenter(valueElement);
			const dy = valueCenter.y - labelCenter.y;
			const dx = Math.abs(valueCenter.x - labelCenter.x);
			if (dy >= 6 && dy <= 180 && dx <= 260) {
				return true;
			}
		}
	}

	return false;
}

function hasDistinctVisualEvidence(
	firstCandidate: NameCandidate,
	lastCandidate: NameCandidate,
	images: OcrImageResult[]
): boolean {
	if (firstCandidate.sourceImageId !== lastCandidate.sourceImageId) {
		return true;
	}
	const image = images.find((item) => item.imageId === firstCandidate.sourceImageId);
	if (!image || !image.elements || image.elements.length === 0) {
		return false;
	}

	const firstElements = image.elements.filter(
		(item) => normalizeNameComparisonValue(item.text) === firstCandidate.canonicalValue
	);
	const lastElements = image.elements.filter(
		(item) => normalizeNameComparisonValue(item.text) === lastCandidate.canonicalValue
	);
	if (firstElements.length < 2 || lastElements.length < 2) {
		return false;
	}

	const centers = [...firstElements, ...lastElements].map(elementCenter);
	const uniqueY = new Set(centers.map((center) => Math.round(center.y / 8)));
	return uniqueY.size >= 2;
}

function elementCenter(element: OcrElement): {x: number; y: number} {
	const points = element.boundingBox || [];
	if (points.length === 0) {
		return {x: 0, y: 0};
	}
	const x = points.reduce((sum, point) => sum + point.x, 0) / points.length;
	const y = points.reduce((sum, point) => sum + point.y, 0) / points.length;
	return {x, y};
}

function validateDateConsistency(
	parsed: ParsedData,
	fields: Record<string, MergedField>,
	conflicts: string[]
): void {
	const birth = parseDateToUtc(parsed.dateOfBirth);
	const expiry = parseDateToUtc(parsed.documentExpiryDate);
	if (!birth || !expiry) return;

	if (expiry.getTime() <= birth.getTime()) {
		conflicts.push("Datum isteka mora biti nakon datuma rođenja.");
		markNeedsReview(fields, ["dateOfBirth", "documentExpiryDate"]);
	}

	if (expiry.getTime() < Date.now()) {
		conflicts.push("Dokument je istekao. Potrebna ručna potvrda.");
		markNeedsReview(fields, ["documentExpiryDate"]);
	}
}

function parseDateToUtc(value?: string): Date | null {
	if (!value) return null;
	const eu = value.match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
	if (eu) return new Date(Date.UTC(Number(eu[3]), Number(eu[2]) - 1, Number(eu[1])));
	const iso = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
	if (iso) return new Date(Date.UTC(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3])));
	return null;
}

function markNeedsReview(fields: Record<string, MergedField>, names: string[]): void {
	for (const name of names) {
		if (fields[name]) fields[name].needsReview = true;
	}
}

function roundConfidence(value: number): number {
	if (value < 0) return 0;
	if (value > 1) return 1;
	return Math.round(value * 1000) / 1000;
}

function looksLikeDate(value: string): boolean {
	return /\d{2}[.\/-]\d{2}[.\/-]\d{4}|\d{4}[.\/-]\d{2}[.\/-]\d{2}/.test(value);
}

function isLikelyCountryText(value: string): boolean {
	const normalized = normalizeForMatch(value);
	return Object.values(ISO_3166_ALPHA3_TO_DISPLAY)
		.map((name) => normalizeForMatch(name))
		.some((name) => normalized.includes(name));
}

function isValidName(value: string): boolean {
	if (!value.trim()) return false;
	if (looksLikeDate(value) || isValidDocumentNumber(value)) return false;
	if (isLikelyLabelLine(value) || isIgnoredValue(value)) return false;
	return /^[\p{L}\s\-']+$/u.test(value);
}

function isValidDate(value: string): boolean {
	return parseDateToUtc(value) !== null;
}

function isMrzChecksumValid(mrzText?: string): boolean {
	if (!mrzText) return false;
	const lines = mrzText
		.split(/\r?\n/)
		.map((line) => line.replace(/\s+/g, ""))
		.filter((line) => line.length > 0);

	if (lines.length >= 3 && lines[0].length >= 30 && lines[1].length >= 30 && lines[2].length >= 30) {
		const second = lines[1];
		return validateMrzCheck(second.substring(0, 6), second[6]) && validateMrzCheck(second.substring(8, 14), second[14]);
	}
	if (lines.length >= 2 && lines[0].length >= 44 && lines[1].length >= 44) {
		const second = lines[1];
		return validateMrzCheck(second.substring(13, 19), second[19]) && validateMrzCheck(second.substring(21, 27), second[27]);
	}
	if (lines.length >= 2 && lines[0].length >= 36 && lines[1].length >= 36) {
		const second = lines[1];
		return validateMrzCheck(second.substring(13, 19), second[19]) && validateMrzCheck(second.substring(21, 27), second[27]);
	}
	return false;
}

function validateMrzCheck(value: string, checkDigit: string): boolean {
	if (!value || !checkDigit) return false;
	const weights = [7, 3, 1];
	let sum = 0;
	for (let i = 0; i < value.length; i++) {
		sum += mrzCharValue(value[i]) * weights[i % 3];
	}
	return String(sum % 10) === checkDigit;
}

function mrzCharValue(char: string): number {
	if (char >= "0" && char <= "9") return Number(char);
	if (char >= "A" && char <= "Z") return char.charCodeAt(0) - 55;
	if (char === "<") return 0;
	return 0;
}

function computeConfidence(result: {
	fullTextAnnotation?: {
		pages?: Array<{confidence?: number | null; blocks?: Array<{confidence?: number | null}> | null}> | null;
	} | null;
}): number | undefined {
	const values: number[] = [];
	const pages = result.fullTextAnnotation?.pages || [];
	for (const page of pages) {
		if (typeof page.confidence === "number") values.push(page.confidence);
		for (const block of page.blocks || []) {
			if (typeof block.confidence === "number") values.push(block.confidence);
		}
	}
	if (values.length === 0) return undefined;
	const avg = values.reduce((sum, value) => sum + value, 0) / values.length;
	return Math.round(avg * 1000) / 1000;
}

function mergeMissing(target: ParsedData, source: ParsedData): void {
	if (!target.documentType && source.documentType) target.documentType = source.documentType;
	if (!target.documentKind && source.documentKind) target.documentKind = source.documentKind;
	if (!target.documentCode && source.documentCode) target.documentCode = source.documentCode;
	if (!target.firstName && source.firstName) target.firstName = source.firstName;
	if (!target.middleNames && source.middleNames) target.middleNames = source.middleNames;
	if (!target.lastName && source.lastName) target.lastName = source.lastName;
	if (!target.dateOfBirth && source.dateOfBirth) target.dateOfBirth = source.dateOfBirth;
	if (!target.nationality && source.nationality) target.nationality = source.nationality;
	if (!target.nationalityCode && source.nationalityCode) target.nationalityCode = source.nationalityCode;
	if (!target.nationalityDisplayName && source.nationalityDisplayName) {
		target.nationalityDisplayName = source.nationalityDisplayName;
	}
	if (!target.documentNumber && source.documentNumber) target.documentNumber = source.documentNumber;
	if (!target.documentExpiryDate && source.documentExpiryDate) target.documentExpiryDate = source.documentExpiryDate;
	if (!target.issueDate && source.issueDate) target.issueDate = source.issueDate;
	if (!target.gender && source.gender) target.gender = source.gender;
	if (!target.issuingCountry && source.issuingCountry) target.issuingCountry = source.issuingCountry;
	if (!target.optionalData && source.optionalData) target.optionalData = source.optionalData;
	if (!target.personalNumber && source.personalNumber) target.personalNumber = source.personalNumber;
}

export const __test = {
	parseDocument,
	findValueAfterLabel,
	parseWithLabels,
	normalizeDateValue,
	isValidDocumentNumber,
	mergeImageResults,
	isMrzChecksumValid,
	resolveField,
	validateMrzCheck,
};
