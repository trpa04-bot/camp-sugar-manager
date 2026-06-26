import assert from "node:assert/strict";
import test from "node:test";

import {__test} from "./index.js";

test("parses German ID card multilingual labels correctly", () => {
	const rawText = [
		"BUNDESREPUBLIK DEUTSCHLAND",
		"Identity Card",
		"Name / Surname / Nom",
		"RAUH",
		"Geburtsname / Name at birth / Nom de naissance",
		"MEIER",
		"Vornamen / Given names / Prénoms",
		"HANS",
		"Geburtsdatum / Date of birth / Date de naissance",
		"26.05.1947",
		"Staatsangehörigkeit / Nationality / Nationalité",
		"DEUTSCH",
		"Ausstellungsdatum",
		"08.06.2021",
		"Gültig bis / Date of expiry / Date d'expiration",
		"07.06.2031",
		"Ausweisnummer",
		"L628C54X8",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.firstName, "HANS");
	assert.equal(parsed.lastName, "RAUH");
	assert.equal(parsed.dateOfBirth, "26.05.1947");
	assert.equal(parsed.nationality, "DEU");
	assert.equal(parsed.nationalityCode, "DEU");
	assert.equal(parsed.nationalityDisplayName, "Njemačka");
	assert.equal(parsed.documentType, "nationalIdCard");
	assert.equal(parsed.documentKind, "nationalIdCard");
	assert.equal(parsed.documentNumber, "L628C54X8");
	assert.equal(parsed.documentExpiryDate, "07.06.2031");
	assert.equal(parsed.issueDate, "08.06.2021");
});

test("does not treat labels as values and skips inline multilingual label text", () => {
	const lines = [
		"Vornamen / Given names / Prénoms",
		"Given names",
		"Prénoms",
		"HANS",
	];

	const value = __test.findValueAfterLabel(lines, [
		"Vornamen / Given names / Prénoms",
		"Given names",
		"Prénoms",
	]);

	assert.equal(value, "HANS");
});

test("does not use birth surname when main surname exists", () => {
	const rawText = [
		"Name / Surname / Nom",
		"RAUH",
		"Geburtsname / Name at birth / Nom de naissance",
		"SCHMIDT",
		"Vornamen / Given names / Prénoms",
		"HANS",
		"Staatsangehörigkeit / Nationality / Nationalité",
		"DEUTSCH",
		"Identity Card",
		"L628C54X8",
	].join("\n");

	const parsed = __test.parseDocument(rawText);
	assert.equal(parsed.lastName, "RAUH");
});

test("validates generic document number format", () => {
	assert.equal(__test.isValidDocumentNumber("L628C54X8"), true);
	assert.equal(__test.isValidDocumentNumber("AB1234567890"), true);
	assert.equal(__test.isValidDocumentNumber("PASSPORT"), false);
	assert.equal(__test.isValidDocumentNumber("07.06.2031"), false);
});

test("merges front and back side results into one guest record", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				dateOfBirth: "26.05.1947",
				nationality: "DEU",
				nationalityCode: "DEU",
				nationalityDisplayName: "Njemačka",
				documentType: "ID Card",
				documentNumber: "L628C54X8",
				documentExpiryDate: "07.06.2031",
				issueDate: "08.06.2021",
				confidence: 0.8,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				dateOfBirth: "26.05.1947",
				nationality: "DEU",
				nationalityCode: "DEU",
				nationalityDisplayName: "Njemačka",
				documentNumber: "L628C54X8",
				gender: "M",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.7,
			},
		},
	]);

	assert.equal(merged.parsed.firstName, "HANS");
	assert.equal(merged.parsed.lastName, "RAUH");
	assert.equal(merged.parsed.documentNumber, "L628C54X8");
	assert.equal(merged.parsed.nationalityCode, "DEU");
	assert.equal(merged.parsed.nationalityDisplayName, "Njemačka");
	assert.equal(merged.parsed.gender, "M");
});

test("prefers MRZ-backed value over weak fallback candidate", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				documentNumber: "A12345678",
				confidence: 0.35,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				documentNumber: "L628C54X8",
				mrzText:
					"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\\nL898902C36UTO7408122F1204159ZE184226B<<<<<10",
				confidence: 0.65,
			},
		},
	]);

	assert.equal(merged.parsed.documentNumber, "L628C54X8");
	assert.equal(merged.fields.documentNumber.sourceType, "mrz");
});

test("flags conflicts when front and MRZ provide different birth dates", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				dateOfBirth: "26.05.1947",
				confidence: 0.8,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				dateOfBirth: "27.05.1947",
				mrzText:
					"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\\nL898902C36UTO7408122F1204159ZE184226B<<<<<10",
				confidence: 0.7,
			},
		},
	]);

	assert.equal(merged.fields.dateOfBirth.needsReview, true);
	assert.equal(
		merged.conflicts.some((item: string) => item.includes("MRZ i prednja strana")),
		true
	);
});

test("keeps processing when back side is missing", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				documentNumber: "L628C54X8",
				confidence: 0.75,
			},
		},
	]);

	assert.equal(merged.parsed.firstName, "HANS");
	assert.equal(merged.parsed.lastName, "RAUH");
	assert.equal(merged.parsed.documentNumber, "L628C54X8");
});

test("supports multiple additional images without breaking merge", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				confidence: 0.8,
			},
		},
		{
			imageId: "add1",
			storagePath: "reservations/r1/documents/g1/add1.jpg",
			documentSide: "additional",
			rawText: "add1",
			parsed: {
				nationality: "DEU",
				confidence: 0.6,
			},
		},
		{
			imageId: "add2",
			storagePath: "reservations/r1/documents/g1/add2.jpg",
			documentSide: "additional",
			rawText: "add2",
			parsed: {
				documentExpiryDate: "07.06.2031",
				confidence: 0.6,
			},
		},
	]);

	assert.equal(merged.parsed.nationality, "DEU");
	assert.equal(merged.parsed.documentExpiryDate, "07.06.2031");
});

test("parses provided German ID TD1 MRZ sample correctly", () => {
	const rawText = [
		"IDD<<L628C54X89<<<<<<<<<<<<<<<",
		"4705266<3106073D<<<<<<<<<<<<<<8",
		"RAUH<<HANS<<<<<<<<<<<<<<<<<<<<",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.documentType, "nationalIdCard");
	assert.equal(parsed.documentCode, "ID");
	assert.equal(parsed.documentNumber, "L628C54X8");
	assert.equal(parsed.firstName, "HANS");
	assert.equal(parsed.lastName, "RAUH");
	assert.equal(parsed.dateOfBirth, "26.05.1947");
	assert.equal(parsed.documentExpiryDate, "07.06.2031");
	assert.equal(parsed.gender, undefined);
	assert.equal(parsed.issuingCountry, "DEU");
	assert.equal(parsed.nationality, "DEU");
	assert.equal(parsed.nationalityCode, "DEU");
	assert.equal(parsed.nationalityDisplayName, "Njemačka");
});

test("parses Romanian ID TD1 MRZ sample correctly", () => {
	const rawText = [
		"IDROUDJ104858751820416160012<<",
		"8204169M3602195ROU<<<<<<<<<<<4",
		"VAVURA<<ADI<DANIEL<<<<<<<<<<<<",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.documentType, "nationalIdCard");
	assert.equal(parsed.documentKind, "nationalIdCard");
	assert.equal(parsed.documentCode, "ID");
	assert.equal(parsed.issuingCountry, "ROU");
	assert.equal(parsed.documentNumber, "DJ1048587");
	assert.equal(parsed.firstName, "ADI");
	assert.equal(parsed.lastName, "VAVURA");
	assert.equal(parsed.dateOfBirth, "16.04.1982");
	assert.equal(parsed.documentExpiryDate, "19.02.2036");
	assert.equal(parsed.nationality, "ROU");
	assert.equal(parsed.nationalityCode, "ROU");
	assert.equal(parsed.nationalityDisplayName, "Rumunjska");
});

test("removed image before processing does not affect merge", () => {
	const images = [
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				confidence: 0.8,
			},
		},
		{
			imageId: "to-remove",
			storagePath: "reservations/r1/documents/g1/remove.jpg",
			documentSide: "additional",
			rawText: "remove",
			parsed: {
				firstName: "SHOULD_NOT_BE_USED",
				confidence: 0.1,
			},
		},
	];

	const merged = __test.mergeImageResults(images.slice(0, 1));
	assert.equal(merged.parsed.firstName, "HANS");
});

test("rejects nationality that looks like date", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				nationality: "26.05.1947",
				confidence: 0.8,
			},
		},
	]);

	assert.equal(merged.fields.nationality.needsReview, true);
});

test("implements MRZ checksum validation", () => {
	assert.equal(__test.validateMrzCheck("740812", "2"), true);
	assert.equal(__test.validateMrzCheck("120415", "9"), true);
	assert.equal(__test.validateMrzCheck("120415", "1"), false);
});

test("parses TD3 passport MRZ", () => {
	const rawText = [
		"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
		"L898902C36UTO7408122F1204159ZE184226B<<<<<10",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.documentType, "passport");
	assert.equal(parsed.documentCode, "P");
	assert.equal(parsed.lastName, "ERIKSSON");
	assert.equal(parsed.firstName, "ANNA");
	assert.equal(parsed.middleNames, "MARIA");
	assert.equal(parsed.documentNumber, "L898902C3");
	assert.equal(parsed.nationality, "UTO");
});

test("parses TD2 MRZ", () => {
	const rawText = [
		"I<UTODOE<<JOHN<<<<<<<<<<<<<<<<<<<<<<",
		"D231458907UTO7408122M1204159<<<<<<<",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.documentType, "nationalIdCard");
	assert.equal(parsed.documentCode, "I");
	assert.equal(parsed.lastName, "DOE");
	assert.equal(parsed.firstName, "JOHN");
	assert.equal(parsed.documentNumber, "D23145890");
	assert.equal(parsed.gender, "M");
});

test("parses MRV-A visa format", () => {
	const rawText = [
		"V<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
		"L898902C36UTO7408122F1204159ZE184226B<<<<<10",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.documentType, "residencePermit");
	assert.equal(parsed.documentCode, "V");
	assert.equal(parsed.lastName, "ERIKSSON");
	assert.equal(parsed.firstName, "ANNA");
});

test("parses MRV-B visa format", () => {
	const rawText = [
		"V<UTODOE<<JOHN<<<<<<<<<<<<<<<<<<<<<<",
		"D231458907UTO7408122M1204159<<<<<<<",
	].join("\n");

	const parsed = __test.parseDocument(rawText);

	assert.equal(parsed.documentType, "residencePermit");
	assert.equal(parsed.documentCode, "V");
	assert.equal(parsed.lastName, "DOE");
	assert.equal(parsed.firstName, "JOHN");
});

test("detects driving licence without MRZ", () => {
	const rawText = [
		"DRIVING LICENCE",
		"Surname",
		"O'CONNOR",
		"Given names",
		"SEAN",
	].join("\n");

	const parsed = __test.parseDocument(rawText);
	assert.equal(parsed.documentType, "drivingLicence");
	assert.equal(parsed.firstName, "SEAN");
	assert.equal(parsed.lastName, "O'CONNOR");
});

test("does not mark consistent first and last name as needsReview", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "ANNA",
				lastName: "ERIKSSON",
				mrzText:
					"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\\nL898902C36UTO7408122F1204159ZE184226B<<<<<10",
				confidence: 0.9,
			},
		},
	]);

	assert.equal(merged.fields.firstName.needsReview, false);
	assert.equal(merged.fields.lastName.needsReview, false);
});

test("treats missing gender as optional and does not require review", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "ANNA",
				lastName: "ERIKSSON",
				documentNumber: "L898902C3",
				gender: "<",
				confidence: 0.8,
			},
		},
	]);

	assert.equal(merged.parsed.gender, undefined);
	assert.equal(merged.fields.gender.needsReview, false);
});

test("does not flag first/last name conflict for MRZ formatting differences", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: " HANS ",
				lastName: "RAUH",
				documentNumber: "L628C54X8",
				confidence: 0.95,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "HANS<<",
				lastName: "  RAUH   ",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(
		merged.conflicts.some((item: string) => item.includes("različito ime")),
		false
	);
	assert.equal(
		merged.conflicts.some((item: string) => item.includes("različito prezime")),
		false
	);
	assert.equal(merged.fields.firstName.needsReview, false);
	assert.equal(merged.fields.lastName.needsReview, false);
});

test("rejects ODDHANS visual noise and keeps MRZ names without conflicts", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "Name / Surname / Nom\nVornamen / Given names / Prénoms",
			parsed: {
				firstName: "ODDHANS",
				lastName: "ODDHANS",
				confidence: 1.0,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(merged.parsed.firstName, "HANS");
	assert.equal(merged.parsed.lastName, "RAUH");
	assert.equal(merged.fields.firstName.needsReview, false);
	assert.equal(merged.fields.lastName.needsReview, false);
	assert.equal(
		merged.conflicts.some((item: string) => item.includes("različito ime")),
		false
	);
	assert.equal(
		merged.conflicts.some((item: string) => item.includes("različito prezime")),
		false
	);
	assert.equal(merged.debug?.firstName?.visualValid, false);
	assert.equal(merged.debug?.lastName?.visualValid, false);
});

test("same visual candidate for first and last is rejected", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				lastName: "HANS",
				confidence: 0.95,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(merged.debug?.firstName?.visualValid, false);
	assert.equal(merged.debug?.lastName?.visualValid, false);
	assert.equal(
		merged.debug?.firstName?.rejectionReason,
		"duplicateCandidateForFirstAndLastName"
	);
	assert.equal(
		merged.debug?.lastName?.rejectionReason,
		"duplicateCandidateForFirstAndLastName"
	);
});

test("labelMatch without strong spatial evidence is not trusted and not 100 percent", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "Vornamen / Given names / Prénoms",
			parsed: {
				firstName: "HANS",
				confidence: 1.0,
			},
		},
	]);

	assert.equal(merged.debug?.firstName?.visualSourceType, "labelMatch");
	assert.equal((merged.debug?.firstName?.visualConfidenceBeforeValidation || 0) <= 0.75, true);
	assert.equal(merged.debug?.firstName?.visualValid, false);
});

test("valid matching visual name does not create conflict", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				confidence: 0.9,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "HANS",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(
		merged.conflicts.some((item: string) => item.includes("različito ime")),
		false
	);
	assert.equal(merged.fields.firstName.needsReview, false);
});

test("valid differing visual name creates a real conflict", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANSEN",
				confidence: 0.9,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "HANS",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(
		merged.conflicts.some((item: string) => item.includes("različito ime")),
		true
	);
	assert.equal(merged.fields.firstName.needsReview, true);
});

test("normalizes nationality aliases D and D to DEU without review", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				nationality: "D",
				nationalityCode: "D",
				documentNumber: "L628C54X8",
				confidence: 0.9,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				nationality: "DEU",
				nationalityCode: "DEU",
				documentNumber: "L628C54X8",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(merged.parsed.nationalityCode, "DEU");
	assert.equal(merged.fields.nationalityCode.value, "DEU");
});

test("maps document type label ID Card to nationalIdCard without review", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "Identity Card",
			parsed: {
				firstName: "HANS",
				lastName: "RAUH",
				documentType: "ID Card",
				documentKind: "nationalIdCard",
				documentNumber: "L628C54X8",
				confidence: 0.83,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				documentType: "nationalIdCard",
				documentKind: "nationalIdCard",
				documentNumber: "L628C54X8",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(merged.parsed.documentType, "nationalIdCard");
	assert.equal(merged.fields.documentType.needsReview, false);
});

test("checksum fail on MRZ document number always requires manual review", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				documentNumber: "L628C54X8",
				confidence: 0.92,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				documentNumber: "L628C54X8",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<0",
				confidence: 0.99,
			},
		},
	]);

	assert.equal(merged.fields.documentNumber.needsReview, true);
});

test("keeps visual OCR diacritics when transliteration matches MRZ", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				firstName: "ŽELJKO",
				lastName: "ŠIMIĆ",
				confidence: 0.93,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				firstName: "ZELJKO",
				lastName: "SIMIC",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.95,
			},
		},
	]);

	assert.equal(merged.parsed.firstName, "ŽELJKO");
	assert.equal(merged.parsed.lastName, "ŠIMIĆ");
	assert.equal(merged.fields.firstName.needsReview, false);
	assert.equal(merged.fields.lastName.needsReview, false);
});

test("when MRZ is not found parser falls back to label extraction", () => {
	const parsed = __test.parseDocument([
		"Identity Card",
		"Name / Surname / Nom",
		"HORVAT",
		"Given names",
		"ANA",
		"Date of birth",
		"26.05.1947",
	].join("\n"));

	assert.equal(parsed.firstName, "ANA");
	assert.equal(parsed.lastName, "HORVAT");
	assert.equal(parsed.mrzText, undefined);
});

test("empty MRZ field never overwrites valid OCR value", () => {
	const merged = __test.mergeImageResults([
		{
			imageId: "front",
			storagePath: "reservations/r1/documents/g1/front.jpg",
			documentSide: "frontIdCard",
			rawText: "front",
			parsed: {
				documentNumber: "AA1122334",
				confidence: 0.88,
			},
		},
		{
			imageId: "back",
			storagePath: "reservations/r1/documents/g1/back.jpg",
			documentSide: "backIdCard",
			rawText: "back",
			parsed: {
				documentNumber: "",
				mrzText:
					"IDDEUL628C54X8<<<<<<<<<<<<<<<\\n4705264M3106076DEU<<<<<<<<<<<8",
				confidence: 0.9,
			},
		},
	]);

	assert.equal(merged.parsed.documentNumber, "AA1122334");
	assert.equal(merged.fields.documentNumber.value, "AA1122334");
});
