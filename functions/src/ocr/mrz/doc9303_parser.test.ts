import assert from "node:assert/strict";
import test from "node:test";

import {parseMrzFromLines, validateMrzCheck} from "./doc9303_parser.js";

test("parses TD3 MRZ and validates checks", () => {
	const result = parseMrzFromLines([
		"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
		"L898902C36UTO7408122F1204159ZE184226B<<<<<10",
	]);

	assert.ok(result);
	assert.equal(result?.mrzType, "TD3");
	assert.equal(result?.parsed.documentCode, "P");
	assert.equal(result?.parsed.lastName, "ERIKSSON");
	assert.equal(result?.parsed.firstName, "ANNA");
	assert.equal(result?.parsed.middleNames, "MARIA");
	assert.equal(result?.parsed.documentNumber, "L898902C3");
	assert.equal(result?.parsed.nationality, "UTO");
	assert.equal(result?.allChecksPassed, true);
});

test("handles OCR confusions in numeric fields (O->0, I->1, S->5)", () => {
	const result = parseMrzFromLines([
		"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
		"L8989O2C36UTO74O8I22F12O4I59ZE184226B<<<<<10",
	]);

	assert.ok(result);
	assert.equal(result?.mrzType, "TD3");
	assert.equal(result?.parsed.documentNumber, "L8989O2C3");
	assert.equal(result?.checks.birthDate, true);
	assert.equal(result?.checks.expiryDate, true);
});

test("fails checksum validation on tampered check digit", () => {
	const result = parseMrzFromLines([
		"P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<",
		"L898902C36UTO7408122F1204151ZE184226B<<<<<10",
	]);

	assert.ok(result);
	assert.equal(result?.checks.expiryDate, false);
	assert.equal(result?.allChecksPassed, false);
	assert.equal(result?.errors.includes("expiryDateCheckFailed"), true);
});

test("supports TD1 MRZ sample", () => {
	const result = parseMrzFromLines([
		"IDROUDJ104858751820416160012<<",
		"8204169M3602195ROU<<<<<<<<<<<4",
		"VAVURA<<ADI<DANIEL<<<<<<<<<<<<",
	]);

	assert.ok(result);
	assert.equal(result?.mrzType, "TD1");
	assert.equal(result?.parsed.documentCode, "ID");
	assert.equal(result?.parsed.documentNumber, "DJ1048587");
	assert.equal(result?.parsed.lastName, "VAVURA");
	assert.equal(result?.parsed.firstName, "ADI");
});

test("supports TD2 MRZ sample", () => {
	const result = parseMrzFromLines([
		"I<UTODOE<<JOHN<<<<<<<<<<<<<<<<<<<<<<",
		"D231458907UTO7408122M1204159<<<<<<<",
	]);

	assert.ok(result);
	assert.equal(result?.mrzType, "TD2");
	assert.equal(result?.parsed.documentCode, "I");
	assert.equal(result?.parsed.documentNumber, "D23145890");
	assert.equal(result?.parsed.lastName, "DOE");
	assert.equal(result?.parsed.firstName, "JOHN");
});

test("returns null when MRZ is not found", () => {
	const result = parseMrzFromLines([
		"Identity Card",
		"Given names",
		"ANA",
		"Surname",
		"HORVAT",
	]);

	assert.equal(result, null);
});

test("validateMrzCheck follows ICAO weighting", () => {
	assert.equal(validateMrzCheck("740812", "2"), true);
	assert.equal(validateMrzCheck("120415", "9"), true);
	assert.equal(validateMrzCheck("120415", "1"), false);
});
