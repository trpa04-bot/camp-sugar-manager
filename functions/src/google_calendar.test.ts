import assert from "node:assert/strict";
import test from "node:test";

import {__googleCalendarTest} from "./index.js";

test("adapts all-day event dates", () => {
	// Google Calendar koristi ekskluzivinog end.date
	// Ako je boravak od 10.07 do 12.07 (3 dana), Google Calendar će imati:
	// start.date: "2026-07-10", end.date: "2026-07-13" (13 je ekskluzivinog, dan NAKON zadnjeg dana)
	const range = __googleCalendarTest.adaptEventDates(
		{date: "2026-07-10"},
		{date: "2026-07-13"}
	);

	assert.equal(range.isAllDay, true);
	assert.equal(range.checkIn.getFullYear(), 2026);
	assert.equal(range.checkIn.getMonth(), 6);
	assert.equal(range.checkIn.getDate(), 10);
	// checkOut bi trebao biti 12.07 jer je 13.07 ekskluzivinog
	assert.equal(range.checkOut.getFullYear(), 2026);
	assert.equal(range.checkOut.getMonth(), 6);
	assert.equal(range.checkOut.getDate(), 12);
});

test("adapts datetime event in Europe/Zagreb offset", () => {
	const range = __googleCalendarTest.adaptEventDates(
		{dateTime: "2026-08-01T16:00:00+02:00"},
		{dateTime: "2026-08-04T10:00:00+02:00"}
	);

	assert.equal(range.checkIn.getFullYear(), 2026);
	assert.equal(range.checkIn.getMonth(), 7);
	assert.equal(range.checkIn.getDate(), 1);
	assert.equal(range.checkOut.getFullYear(), 2026);
	assert.equal(range.checkOut.getMonth(), 7);
	assert.equal(range.checkOut.getDate(), 4);
	assert.equal(range.isAllDay, false);
});

test("maps source and guest counters from mixed text", () => {
	const source = __googleCalendarTest.normalizeReservationSource(
		"Airbnb booking potvrda - 2 adults i 1 dijete"
	);
	const counts = __googleCalendarTest.parseGuestCount(
		"2 adults + 1 dijete, ukupno 3 guests"
	);

	assert.equal(source, "airbnb");
	assert.equal(counts.adults, 2);
	assert.equal(counts.children, 1);
	assert.equal(counts.guestCount, 3);
});

test("normalizes reservation title to guest name", () => {
	assert.equal(
		__googleCalendarTest.parseTitleName("Rezervacija Ana Horvat - Airbnb booking"),
		"Ana Horvat"
	);
	assert.equal(
		__googleCalendarTest.parseTitleName("Marko Markic / 4 guests"),
		"Marko Markic"
	);
});

test("marks cancelled events and keeps google ids", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_1",
			summary: "Ivan Ivić",
			description: "Booking direct",
			start: {date: "2026-09-10"},
			end: {date: "2026-09-12"},
			status: "cancelled",
			updated: "2026-01-01T12:00:00.000Z",
		},
		"primary"
	);

	assert.equal(doc.googleEventId, "evt_1");
	assert.equal(doc.calendarId, "primary");
	assert.equal(doc.importStatus, "cancelled");
});

// ── removeUndefinedDeep ────────────────────────────────────────────────────

test("removeUndefinedDeep: undefined at top level becomes null", () => {
	assert.equal(__googleCalendarTest.removeUndefinedDeep(undefined), null);
});

test("removeUndefinedDeep: undefined field removed from object", () => {
	const result = __googleCalendarTest.removeUndefinedDeep({
		adults: undefined,
		children: 2,
	}) as Record<string, unknown>;

	assert.equal(Object.prototype.hasOwnProperty.call(result, "adults"), false);
	assert.equal(result.children, 2);
});

test("removeUndefinedDeep: null is preserved", () => {
	const result = __googleCalendarTest.removeUndefinedDeep({
		adults: null,
	}) as Record<string, unknown>;

	assert.equal(result.adults, null);
});

test("removeUndefinedDeep: false and 0 are preserved", () => {
	const result = __googleCalendarTest.removeUndefinedDeep({
		active: false,
		count: 0,
	}) as Record<string, unknown>;

	assert.equal(result.active, false);
	assert.equal(result.count, 0);
});

test("removeUndefinedDeep: empty string is preserved", () => {
	const result = __googleCalendarTest.removeUndefinedDeep({
		notes: "",
	}) as Record<string, unknown>;

	assert.equal(result.notes, "");
});

test("removeUndefinedDeep: nested undefined cleaned recursively", () => {
	const result = __googleCalendarTest.removeUndefinedDeep({
		parsedReservation: {
			adults: undefined,
			children: undefined,
			guestCount: null,
			source: "airbnb",
		},
	}) as {parsedReservation: Record<string, unknown>};

	const pr = result.parsedReservation;
	assert.equal(Object.prototype.hasOwnProperty.call(pr, "adults"), false);
	assert.equal(Object.prototype.hasOwnProperty.call(pr, "children"), false);
	assert.equal(pr.guestCount, null);
	assert.equal(pr.source, "airbnb");
});

test("removeUndefinedDeep: array items processed", () => {
	const result = __googleCalendarTest.removeUndefinedDeep([
		undefined,
		{a: undefined, b: 1},
		null,
	]) as unknown[];

	assert.equal(result[0], null);
	assert.equal((result[1] as Record<string, unknown>).b, 1);
	assert.equal(Object.prototype.hasOwnProperty.call(result[1], "a"), false);
	assert.equal(result[2], null);
});

// ── eventToImportDoc: no undefined in parsedReservation ───────────────────

test("eventToImportDoc: parsedReservation.adults is null when no guest info", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_no_guests",
			summary: "Ana Horvat",
			start: {date: "2026-09-10"},
			end: {date: "2026-09-12"},
		},
		"primary"
	);

	// adults must never be undefined
	const pr = doc.parsedReservation as Record<string, unknown>;
	assert.notEqual(pr.adults, undefined, "adults must not be undefined");
	assert.equal(pr.adults, null);
});

test("eventToImportDoc: parsedReservation.children is null when not parsed", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_no_children",
			summary: "Test event",
			start: {date: "2026-07-01"},
			end: {date: "2026-07-03"},
		},
		"primary"
	);

	const pr = doc.parsedReservation as Record<string, unknown>;
	assert.notEqual(pr.children, undefined, "children must not be undefined");
	assert.equal(pr.children, null);
});

test("eventToImportDoc: sourceReservationId is null not undefined", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_source",
			summary: "Test",
			start: {date: "2026-08-01"},
			end: {date: "2026-08-05"},
		},
		"primary"
	);

	const pr = doc.parsedReservation as Record<string, unknown>;
	assert.notEqual(pr.sourceReservationId, undefined);
	assert.equal(pr.sourceReservationId, null);
});

test("eventToImportDoc: event without guests becomes needsReview", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_needs_review",
			// no summary, no description
			start: {date: "2026-09-01"},
			end: {date: "2026-09-03"},
		},
		"primary"
	);

	const pr = doc.parsedReservation as Record<string, unknown>;
	assert.equal(pr.needsReview, true);
	assert.equal(doc.importStatus, "needsReview");
});

test("eventToImportDoc: htmlLink is null not undefined when missing", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_nohtmllink",
			summary: "Test",
			start: {date: "2026-10-01"},
			end: {date: "2026-10-03"},
		},
		"primary"
	);

	assert.notEqual(doc.htmlLink, undefined, "htmlLink must not be undefined");
	assert.equal(doc.htmlLink, null);
});

test("eventToImportDoc: updatedAtGoogle is null not undefined when missing", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_noupdated",
			summary: "Test",
			start: {date: "2026-10-01"},
			end: {date: "2026-10-03"},
		},
		"primary"
	);

	assert.notEqual(doc.updatedAtGoogle, undefined, "updatedAtGoogle must not be undefined");
	assert.equal(doc.updatedAtGoogle, null);
});

// ── extractGuestNameParts ─────────────────────────────────────────────────

test("extractGuestNameParts: two-word title with descriptor", () => {
	const r = __googleCalendarTest.extractGuestNameParts("Nadia Cusin kamper");
	assert.equal(r.firstName, "Nadia");
	assert.equal(r.lastName, "Cusin");
});

test("extractGuestNameParts: two-word plain name", () => {
	const r = __googleCalendarTest.extractGuestNameParts("Gabriela Senčakova");
	assert.equal(r.firstName, "Gabriela");
	assert.equal(r.lastName, "Senčakova");
});

test("extractGuestNameParts: title with campspace descriptor", () => {
	const r = __googleCalendarTest.extractGuestNameParts("Timothy White campspace");
	assert.equal(r.firstName, "Timothy");
	assert.equal(r.lastName, "White");
});

test("extractGuestNameParts: title with location suffix", () => {
	const r = __googleCalendarTest.extractGuestNameParts("Marina Stankovic Bg");
	assert.equal(r.firstName, "Marina");
	assert.equal(r.lastName, "Stankovic");
});

test("extractGuestNameParts: descriptor before last name", () => {
	const r = __googleCalendarTest.extractGuestNameParts("Alessio sa kamper");
	assert.equal(r.firstName, "Alessio");
	// 'sa' is a descriptor, 'kamper' is also a descriptor — no lastName
	assert.equal(r.lastName, null);
});

test("extractGuestNameParts: non-personal title returns nulls", () => {
	const r = __googleCalendarTest.extractGuestNameParts("poljaci 2 satora");
	assert.equal(r.firstName, null);
	assert.equal(r.lastName, null);
});

test("extractGuestNameParts: title with multiple suffix descriptors", () => {
	const r = __googleCalendarTest.extractGuestNameParts("Nina Kavsek booking dole kut rez");
	assert.equal(r.firstName, "Nina");
	assert.equal(r.lastName, "Kavsek");
});

test("extractGuestNameParts: empty title returns nulls", () => {
	const r = __googleCalendarTest.extractGuestNameParts("");
	assert.equal(r.firstName, null);
	assert.equal(r.lastName, null);
});

test("eventToImportDoc: firstName and lastName stored in parsedReservation", () => {
	const doc = __googleCalendarTest.eventToImportDoc(
		{
			id: "evt_nadia",
			summary: "Nadia Cusin kamper",
			start: {date: "2026-08-01"},
			end: {date: "2026-08-05"},
		},
		"primary"
	);

	const pr = doc.parsedReservation as Record<string, unknown>;
	assert.equal(pr.primaryGuestFirstName, "Nadia");
	assert.equal(pr.primaryGuestLastName, "Cusin");
});
