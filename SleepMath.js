.pragma library

// The arithmetic sleepcalculator.com does, and nothing else.
//
// Its own scripts/common.js builds each row as an offset in hours applied to
// a base time:
//
//   bedtime: formatTime(wakeTime, (6 - i) * -1.5 - .25)
//   wake-up: formatTime(now,      (6 - i) *  1.5 + .25)
//
// for i in 0..5. So a row is `cycles` 90-minute cycles plus the quarter hour
// the site allows for falling asleep, subtracted from the time you want to be
// up, or added to the time you are going to bed. Six rows, from six cycles
// down to one, and the site marks the first two — six and five cycles — as
// the ones to aim for ("a good night's sleep consists of 5-6 complete sleep
// cycles").
//
// The one place this file deliberately parts company with the site is the
// wrap. Its formatTime() works in a 12-hour space of 720 minutes and flips
// AM/PM at most once, which breaks at 12 o'clock in two ways: it reads a
// picked "12:30" as 750 minutes rather than 30, so every row for a 12 o'clock
// wake time comes out twelve hours wrong, and its `> 720` test misses the flip
// for a wake-up that lands exactly on 12:00. Minutes-of-day arithmetic mod
// 1440 has neither problem. Compared row for row across every minute of the
// clock — 17,280 rows — this file agrees with the site on all 16,548 it gets
// right and differs only on the 732 it does not.
var CYCLE_MINUTES = 90
var FALL_ASLEEP_MINUTES = 15
var CYCLE_COUNTS = [6, 5, 4, 3, 2, 1]
var RECOMMENDED_CYCLES = 5   // five or more cycles is a row worth aiming for

function normalize(minutes) {
  return ((Math.round(minutes) % 1440) + 1440) % 1440
}

// Minutes between lights-out and being awake: the cycles themselves, plus the
// time the site allows for actually falling asleep.
function offsetFor(cycles) {
  return cycles * CYCLE_MINUTES + FALL_ASLEEP_MINUTES
}

function minutesFromClock(hour12, minute, meridiem) {
  var h = ((Math.round(hour12) % 12) + 12) % 12
  if (String(meridiem).toUpperCase() === "PM") h += 12
  return normalize(h * 60 + Math.round(minute))
}

function hour12Of(minutes) {
  var h = Math.floor(normalize(minutes) / 60) % 12
  return h === 0 ? 12 : h
}

function minuteOf(minutes) {
  return normalize(minutes) % 60
}

function meridiemOf(minutes) {
  return Math.floor(normalize(minutes) / 60) < 12 ? "AM" : "PM"
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// "9:15 PM" — the site's own format: no leading zero on the hour, two digits
// on the minute.
function formatClock(minutes) {
  return hour12Of(minutes) + ":" + pad2(minuteOf(minutes)) + " " + meridiemOf(minutes)
}

// 24-hour "HH:MM", which is what gets written to shell.json so the stored
// wake time reads the same way a clock does when edited by hand.
function formatIso(minutes) {
  var m = normalize(minutes)
  return pad2(Math.floor(m / 60)) + ":" + pad2(m % 60)
}

function parseIso(text, fallback) {
  var match = /^\s*(\d{1,2})\s*:\s*(\d{1,2})\s*$/.exec(String(text || ""))
  if (!match) return fallback
  var h = parseInt(match[1], 10)
  var m = parseInt(match[2], 10)
  if (!isFinite(h) || !isFinite(m) || h > 23 || m > 59) return fallback
  return normalize(h * 60 + m)
}

// Time asleep, which is the cycles alone — the quarter hour before them is
// spent falling asleep, not sleeping.
function formatSleepLength(cycles) {
  var total = cycles * CYCLE_MINUTES
  var h = Math.floor(total / 60)
  var m = total % 60
  return m === 0 ? h + "h" : h + "h " + pad2(m) + "m"
}

function buildRow(cycles, minutes) {
  return {
    cycles: cycles,
    minutes: minutes,
    time: formatClock(minutes),
    sleep: formatSleepLength(cycles),
    recommended: cycles >= RECOMMENDED_CYCLES
  }
}

// Times to fall asleep in order to be up at `wakeMinutes`, longest night first.
function bedtimes(wakeMinutes) {
  var rows = []
  for (var i = 0; i < CYCLE_COUNTS.length; i++) {
    var cycles = CYCLE_COUNTS[i]
    rows.push(buildRow(cycles, normalize(wakeMinutes - offsetFor(cycles))))
  }
  return rows
}

// Times to wake if you go to bed at `bedMinutes` now, longest night first.
function wakeTimes(bedMinutes) {
  var rows = []
  for (var i = 0; i < CYCLE_COUNTS.length; i++) {
    var cycles = CYCLE_COUNTS[i]
    rows.push(buildRow(cycles, normalize(bedMinutes + offsetFor(cycles))))
  }
  return rows
}
