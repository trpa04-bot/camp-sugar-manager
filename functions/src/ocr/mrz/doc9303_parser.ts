export type MrzType = "TD1" | "TD2" | "TD3";

export interface MrzFieldChecks {
	documentNumber: boolean;
	birthDate: boolean;
	expiryDate: boolean;
	composite: boolean;
}

export interface MrzParsedData {
	documentCode?: string;
	issuingCountry?: string;
	documentNumber?: string;
	nationality?: string;
	dateOfBirth?: string;
	dateOfExpiry?: string;
	sex?: string;
	optionalData?: string;
	personalNumber?: string;
	lastName?: string;
	firstName?: string;
	middleNames?: string;
}

export interface MrzParseResult {
	mrzType: MrzType;
	rawLines: string[];
	cleanedLines: string[];
	parsed: MrzParsedData;
	checks: MrzFieldChecks;
	errors: string[];
	allChecksPassed: boolean;
	correctedCharacterCount: number;
	confidence: number;
}

interface NormalizedValue {
	value: string;
	corrections: number;
}

export function parseMrzFromLines(lines: string[]): MrzParseResult | null {
	const candidates = lines
		.map((line) => normalizeMrzLine(line))
		.filter((line) => line.length >= 25 && /^[A-Z0-9<]+$/.test(line));

	for (let i = 0; i < candidates.length - 1; i++) {
		const l1 = padToLength(candidates[i], 44);
		const l2 = padToLength(candidates[i + 1], 44);
		if (l1.startsWith("P<") && l1.includes("<<")) {
			const parsed = parseTd3(l1, l2);
			if (parsed) {
				return parsed;
			}
		}
	}

	for (let i = 0; i < candidates.length - 1; i++) {
		const l1 = padToLength(candidates[i], 36);
		const l2 = padToLength(candidates[i + 1], 36);
		if (/^[ACI]</.test(l1) && l1.includes("<<")) {
			const parsed = parseTd2(l1, l2);
			if (parsed) {
				return parsed;
			}
		}
	}

	for (let i = 0; i < candidates.length - 2; i++) {
		const l1 = padToLength(candidates[i], 30);
		const l2 = padToLength(candidates[i + 1], 30);
		const l3 = padToLength(candidates[i + 2], 30);
		if (/^[ACI]/.test(l1) && l3.includes("<<")) {
			const parsed = parseTd1(l1, l2, l3);
			if (parsed) {
				return parsed;
			}
		}
	}

	return null;
}

export function validateMrzCheck(value: string, checkDigit: string): boolean {
	if (!value || !checkDigit) {
		return false;
	}
	let sum = 0;
	for (let i = 0; i < value.length; i++) {
		sum += mrzCharValue(value[i]) * [7, 3, 1][i % 3];
	}
	return String(sum % 10) === checkDigit;
}

function parseTd3(line1Raw: string, line2Raw: string): MrzParseResult | null {
	if (line1Raw.length !== 44 || line2Raw.length !== 44) {
		return null;
	}

	const line1 = normalizeAlphaNum(line1Raw);
	const line2 = normalizeAlphaNum(line2Raw);
	const doc = normalizeAlphaNum(line2.value.substring(0, 9));
	const birth = normalizeNumeric(line2.value.substring(13, 19));
	const expiry = normalizeNumeric(line2.value.substring(21, 27));
	const nationality = normalizeAlpha(line2.value.substring(10, 13));
	const issuing = normalizeAlpha(line1.value.substring(2, 5));

	const docCheck = normalizeNumeric(line2.value.substring(9, 10)).value;
	const birthCheck = normalizeNumeric(line2.value.substring(19, 20)).value;
	const expiryCheck = normalizeNumeric(line2.value.substring(27, 28)).value;
	const compositeCheck = normalizeNumeric(line2.value.substring(43, 44)).value;

	const checks: MrzFieldChecks = {
		documentNumber: validateMrzCheck(doc.value, docCheck),
		birthDate: validateMrzCheck(birth.value, birthCheck),
		expiryDate: validateMrzCheck(expiry.value, expiryCheck),
		composite: validateMrzCheck(
			line2.value.substring(0, 10) + line2.value.substring(13, 20) + line2.value.substring(21, 43),
			compositeCheck
		),
	};

	const parsedNames = parseNames(line1.value.substring(5));
	const errors = buildCheckErrors(checks);
	const correctionCount =
		line1.corrections +
		line2.corrections +
		doc.corrections +
		birth.corrections +
		expiry.corrections +
		nationality.corrections +
		issuing.corrections;

	return {
		mrzType: "TD3",
		rawLines: [line1Raw, line2Raw],
		cleanedLines: [line1.value, line2.value],
		parsed: {
			documentCode: normalizeDocCode(line1.value.substring(0, 2)),
			issuingCountry: normalizeField(issuing.value),
			documentNumber: normalizeField(doc.value),
			nationality: normalizeField(nationality.value),
			dateOfBirth: parseMrzDate(birth.value, "birth"),
			dateOfExpiry: parseMrzDate(expiry.value, "expiry", parseMrzDate(birth.value, "birth")),
			sex: parseSex(line2.value.substring(20, 21)),
			optionalData: normalizeField(line2.value.substring(28, 42)),
			personalNumber: normalizeField(line2.value.substring(28, 42)),
			lastName: parsedNames.lastName,
			firstName: parsedNames.firstName,
			middleNames: parsedNames.middleNames,
		},
		checks,
		errors,
		allChecksPassed: checks.documentNumber && checks.birthDate && checks.expiryDate && checks.composite,
		correctedCharacterCount: correctionCount,
		confidence: calculateConfidence(checks, correctionCount),
	};
}

function parseTd2(line1Raw: string, line2Raw: string): MrzParseResult | null {
	if (line1Raw.length !== 36 || line2Raw.length !== 36) {
		return null;
	}

	const line1 = normalizeAlphaNum(line1Raw);
	const line2 = normalizeAlphaNum(line2Raw);
	const doc = normalizeAlphaNum(line2.value.substring(0, 9));
	const birth = normalizeNumeric(line2.value.substring(13, 19));
	const expiry = normalizeNumeric(line2.value.substring(21, 27));
	const nationality = normalizeAlpha(line2.value.substring(10, 13));
	const issuing = normalizeAlpha(line1.value.substring(2, 5));

	const docCheck = normalizeNumeric(line2.value.substring(9, 10)).value;
	const birthCheck = normalizeNumeric(line2.value.substring(19, 20)).value;
	const expiryCheck = normalizeNumeric(line2.value.substring(27, 28)).value;
	const compositeCheck = normalizeNumeric(line2.value.substring(35, 36)).value;

	const checks: MrzFieldChecks = {
		documentNumber: validateMrzCheck(doc.value, docCheck),
		birthDate: validateMrzCheck(birth.value, birthCheck),
		expiryDate: validateMrzCheck(expiry.value, expiryCheck),
		composite: validateMrzCheck(
			line2.value.substring(0, 10) + line2.value.substring(13, 20) + line2.value.substring(21, 35),
			compositeCheck
		),
	};

	const parsedNames = parseNames(line1.value.substring(5));
	const errors = buildCheckErrors(checks);
	const correctionCount =
		line1.corrections +
		line2.corrections +
		doc.corrections +
		birth.corrections +
		expiry.corrections +
		nationality.corrections +
		issuing.corrections;

	return {
		mrzType: "TD2",
		rawLines: [line1Raw, line2Raw],
		cleanedLines: [line1.value, line2.value],
		parsed: {
			documentCode: normalizeDocCode(line1.value.substring(0, 2)),
			issuingCountry: normalizeField(issuing.value),
			documentNumber: normalizeField(doc.value),
			nationality: normalizeField(nationality.value),
			dateOfBirth: parseMrzDate(birth.value, "birth"),
			dateOfExpiry: parseMrzDate(expiry.value, "expiry", parseMrzDate(birth.value, "birth")),
			sex: parseSex(line2.value.substring(20, 21)),
			optionalData: normalizeField(line2.value.substring(28, 35)),
			personalNumber: normalizeField(line2.value.substring(28, 35)),
			lastName: parsedNames.lastName,
			firstName: parsedNames.firstName,
			middleNames: parsedNames.middleNames,
		},
		checks,
		errors,
		allChecksPassed: checks.documentNumber && checks.birthDate && checks.expiryDate && checks.composite,
		correctedCharacterCount: correctionCount,
		confidence: calculateConfidence(checks, correctionCount),
	};
}

function parseTd1(line1Raw: string, line2Raw: string, line3Raw: string): MrzParseResult | null {
	if (line1Raw.length !== 30 || line2Raw.length !== 30 || line3Raw.length !== 30) {
		return null;
	}

	const line1 = normalizeAlphaNum(line1Raw);
	const line2 = normalizeAlphaNum(line2Raw);
	const line3 = normalizeAlphaNum(line3Raw);
	const doc = normalizeAlphaNum(line1.value.substring(5, 14));
	const birth = normalizeNumeric(line2.value.substring(0, 6));
	const expiry = normalizeNumeric(line2.value.substring(8, 14));
	const nationality = normalizeAlpha(line2.value.substring(15, 18));
	const issuing = normalizeAlpha(line1.value.substring(2, 5));

	const docCheck = normalizeNumeric(line1.value.substring(14, 15)).value;
	const birthCheck = normalizeNumeric(line2.value.substring(6, 7)).value;
	const expiryCheck = normalizeNumeric(line2.value.substring(14, 15)).value;
	const compositeCheck = normalizeNumeric(line2.value.substring(29, 30)).value;

	const checks: MrzFieldChecks = {
		documentNumber: validateMrzCheck(doc.value, docCheck),
		birthDate: validateMrzCheck(birth.value, birthCheck),
		expiryDate: validateMrzCheck(expiry.value, expiryCheck),
		composite: validateMrzCheck(
			line1.value.substring(5, 30) + line2.value.substring(0, 7) + line2.value.substring(8, 15) + line2.value.substring(18, 29),
			compositeCheck
		),
	};

	const parsedNames = parseNames(line3.value);
	const errors = buildCheckErrors(checks);
	const correctionCount =
		line1.corrections +
		line2.corrections +
		line3.corrections +
		doc.corrections +
		birth.corrections +
		expiry.corrections +
		nationality.corrections +
		issuing.corrections;

	return {
		mrzType: "TD1",
		rawLines: [line1Raw, line2Raw, line3Raw],
		cleanedLines: [line1.value, line2.value, line3.value],
		parsed: {
			documentCode: normalizeDocCode(line1.value.substring(0, 2)),
			issuingCountry: normalizeField(issuing.value),
			documentNumber: normalizeField(doc.value),
			nationality: normalizeField(nationality.value),
			dateOfBirth: parseMrzDate(birth.value, "birth"),
			dateOfExpiry: parseMrzDate(expiry.value, "expiry", parseMrzDate(birth.value, "birth")),
			sex: parseSex(line2.value.substring(7, 8)),
			optionalData: normalizeField(line1.value.substring(15, 30)),
			personalNumber: normalizeField(line2.value.substring(18, 29)),
			lastName: parsedNames.lastName,
			firstName: parsedNames.firstName,
			middleNames: parsedNames.middleNames,
		},
		checks,
		errors,
		allChecksPassed: checks.documentNumber && checks.birthDate && checks.expiryDate && checks.composite,
		correctedCharacterCount: correctionCount,
		confidence: calculateConfidence(checks, correctionCount),
	};
}

function normalizeMrzLine(value: string): string {
	return value.trim().toUpperCase().replace(/\s+/g, "").replace(/[^A-Z0-9<]/g, "");
}

function padToLength(value: string, length: number): string {
	if (value.length >= length) {
		return value.substring(0, length);
	}
	return value.padEnd(length, "<");
}

function normalizeNumeric(value: string): NormalizedValue {
	let corrections = 0;
	let result = "";
	for (const char of value) {
		let next = char;
		switch (char) {
			case "O":
			case "D":
			case "Q":
				next = "0";
				break;
			case "I":
			case "L":
				next = "1";
				break;
			case "Z":
				next = "2";
				break;
			case "S":
				next = "5";
				break;
			case "G":
				next = "6";
				break;
			case "B":
				next = "8";
				break;
			default:
				break;
		}
		if (next !== char) {
			corrections += 1;
		}
		result += next;
	}
	return {value: result, corrections};
}

function normalizeAlpha(value: string): NormalizedValue {
	let corrections = 0;
	let result = "";
	for (const char of value) {
		let next = char;
		switch (char) {
			case "0":
				next = "O";
				break;
			case "1":
				next = "I";
				break;
			case "2":
				next = "Z";
				break;
			case "5":
				next = "S";
				break;
			case "6":
				next = "G";
				break;
			case "8":
				next = "B";
				break;
			default:
				break;
		}
		if (next !== char) {
			corrections += 1;
		}
		result += next;
	}
	return {value: result, corrections};
}

function normalizeAlphaNum(value: string): NormalizedValue {
	return {value, corrections: 0};
}

function parseNames(value: string): {lastName?: string; firstName?: string; middleNames?: string} {
	const parts = value.split("<<");
	const lastName = normalizeField(parts[0]);
	const given = normalizeField(parts.slice(1).join(" "));
	if (!given) {
		return {lastName};
	}
	const tokens = given.split(" ").filter((token) => token.length > 0);
	return {
		lastName,
		firstName: tokens[0],
		middleNames: tokens.slice(1).join(" ") || undefined,
	};
}

function normalizeDocCode(value: string): string | undefined {
	const clean = value.replace(/</g, "").trim().toUpperCase();
	return clean || undefined;
}

function normalizeField(value: string): string | undefined {
	const clean = value.replace(/</g, " ").replace(/\s+/g, " ").trim().toUpperCase();
	return clean || undefined;
}

function parseSex(value: string): string | undefined {
	const clean = value.trim().toUpperCase();
	if (clean === "M" || clean === "F" || clean === "X") {
		return clean;
	}
	return undefined;
}

function parseMrzDate(value: string, kind: "birth" | "expiry", birthDateHint?: string): string | undefined {
	if (!/^\d{6}$/.test(value)) {
		return undefined;
	}
	const yy = Number(value.substring(0, 2));
	const mm = Number(value.substring(2, 4));
	const dd = Number(value.substring(4, 6));
	if (mm < 1 || mm > 12 || dd < 1 || dd > 31) {
		return undefined;
	}

	const now = new Date();
	const c1900 = new Date(Date.UTC(1900 + yy, mm - 1, dd));
	const c2000 = new Date(Date.UTC(2000 + yy, mm - 1, dd));

	if (kind === "birth") {
		if (c2000.getTime() <= now.getTime() && ageInYears(c2000, now) <= 120) {
			return formatDate(c2000);
		}
		return formatDate(c1900);
	}

	const birth = parseDisplayDate(birthDateHint);
	if (birth && c2000.getTime() > birth.getTime()) {
		return formatDate(c2000);
	}
	if (birth && c1900.getTime() > birth.getTime()) {
		return formatDate(c1900);
	}
	return formatDate(c2000);
}

function formatDate(date: Date): string {
	const day = String(date.getUTCDate()).padStart(2, "0");
	const month = String(date.getUTCMonth() + 1).padStart(2, "0");
	const year = String(date.getUTCFullYear());
	return `${day}.${month}.${year}`;
}

function parseDisplayDate(value?: string): Date | null {
	if (!value) {
		return null;
	}
	const m = value.match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
	if (!m) {
		return null;
	}
	return new Date(Date.UTC(Number(m[3]), Number(m[2]) - 1, Number(m[1])));
}

function ageInYears(from: Date, to: Date): number {
	let years = to.getUTCFullYear() - from.getUTCFullYear();
	if (
		to.getUTCMonth() < from.getUTCMonth() ||
		(to.getUTCMonth() === from.getUTCMonth() && to.getUTCDate() < from.getUTCDate())
	) {
		years -= 1;
	}
	return years;
}

function buildCheckErrors(checks: MrzFieldChecks): string[] {
	const errors: string[] = [];
	if (!checks.documentNumber) {
		errors.push("documentNumberCheckFailed");
	}
	if (!checks.birthDate) {
		errors.push("birthDateCheckFailed");
	}
	if (!checks.expiryDate) {
		errors.push("expiryDateCheckFailed");
	}
	if (!checks.composite) {
		errors.push("compositeCheckFailed");
	}
	return errors;
}

function calculateConfidence(checks: MrzFieldChecks, correctedCharacterCount: number): number {
	const passCount = [checks.documentNumber, checks.birthDate, checks.expiryDate, checks.composite].filter(Boolean)
		.length;
	let confidence = 0.55 + passCount * 0.1;
	confidence -= Math.min(0.2, correctedCharacterCount * 0.01);
	if (confidence < 0) {
		return 0;
	}
	if (confidence > 0.99) {
		return 0.99;
	}
	return Math.round(confidence * 1000) / 1000;
}

function mrzCharValue(char: string): number {
	if (char >= "0" && char <= "9") {
		return Number(char);
	}
	if (char >= "A" && char <= "Z") {
		return char.charCodeAt(0) - 55;
	}
	if (char === "<") {
		return 0;
	}
	return 0;
}
