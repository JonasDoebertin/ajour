import assert from "node:assert/strict";
import { test } from "node:test";
import { formatMenuBarClock } from "../site/clock.js";

test("formats the date and time like the macOS menu bar", () => {
  assert.equal(formatMenuBarClock(new Date(2026, 10, 6, 12, 33)), "Fri 6 Nov  12:33");
});

test("pads hours and minutes to two digits", () => {
  assert.equal(formatMenuBarClock(new Date(2026, 0, 4, 9, 5)), "Sun 4 Jan  09:05");
});

test("shows midnight as 00:00", () => {
  assert.equal(formatMenuBarClock(new Date(2026, 11, 31, 0, 0)), "Thu 31 Dec  00:00");
});
