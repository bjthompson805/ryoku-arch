// Pure time/date formatting for the clock designs: split a Date into the fields
// each design draws, and resolve the accent choice to a colour. No QML here, so
// every design shares one formatting source instead of repeating it. Avoids
// Date.now()/Math.random() (both throw in the Quickshell JS engine); reading a
// passed-in Date is fine.

function pad2(n) { return (n < 10 ? "0" : "") + n; }

var WEEKDAY = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
var WEEKDAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
var MONTH = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
var MONTH_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// Clock fields. `hh` is zero-padded in 24h and un-padded in 12h, matching how the
// two formats read; raw `hours/minutes/seconds` (and fractional angles) drive the
// analog and ring designs.
function parts(date, is24) {
    var h = date.getHours();
    var m = date.getMinutes();
    var s = date.getSeconds();
    var h12 = h % 12;
    if (h12 === 0)
        h12 = 12;
    return {
        hours: h, minutes: m, seconds: s, h12: h12,
        ampm: h < 12 ? "AM" : "PM",
        hh: is24 ? pad2(h) : String(h12),
        mm: pad2(m),
        ss: pad2(s),
        // Smooth angles in degrees, 12 o'clock = 0, clockwise.
        hourAngle: (h % 12 + m / 60) * 30,
        minuteAngle: (m + s / 60) * 6,
        secondAngle: s * 6
    };
}

// Date fields for the date designs.
function dateParts(date) {
    var dow = date.getDay();
    var mon = date.getMonth();
    return {
        dow: dow, dom: date.getDate(), mon: mon, year: date.getFullYear(),
        weekday: WEEKDAY[dow], weekdayShort: WEEKDAY_SHORT[dow],
        month: MONTH[mon], monthShort: MONTH_SHORT[mon]
    };
}

// Resolve the accent choice (wallust | brand | mono) to one of the candidate
// colours the dispatcher already holds.
function pickAccent(choice, wallust, brand, mono) {
    if (choice === "brand") return brand;
    if (choice === "mono") return mono;
    return wallust;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { pad2, parts, dateParts, pickAccent, WEEKDAY, WEEKDAY_SHORT, MONTH, MONTH_SHORT };
}
