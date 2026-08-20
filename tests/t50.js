// t50 - moving a dimension's NUMBER out of the way (2026-08-19), window half.
//
// The user: "אני רוצה שיהיה לי אפשרות להזיז אותן ימינה ושמאלה ולמטה ולמעלה,
// תלוי איך אני מצייר אותן לאיזה כיוון" - and, right after: a select mode on
// the long key where he can pick what he has drawn and shove it.
//
// The window does not DRAW the number - Ruby does, for the preview and the
// paper alike, which is the rule this whole file set is built on. But the
// window has to know WHERE the number is, or it cannot let him grab it. So
// there are two copies of one formula, and two copies of one formula drift.
//
// dim_label_cases.json is what stops that. rt81 checks Ruby against it and
// this suite checks the window against the SAME file: neither implementation
// can move without one of the two going red. Do not inline these numbers.
//
// The other half of the suite is the shove itself: a drag is given in sheet
// x/y, and what gets STORED is along-the-line and across-it, so the number
// stays where he put it when the dimension is later moved. That is not a
// detail - it is the difference between setting it once and re-aiming it
// every time he touches the plan.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const js = fs.readFileSync(RB, 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
const CASES = JSON.parse(fs.readFileSync(path.join(__dirname, 'dim_label_cases.json'), 'utf8'));

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}
function close(a, b, tol) {
  tol = tol === undefined ? 1e-6 : tol;
  return typeof a === 'number' && typeof b === 'number' && Math.abs(a - b) < tol;
}

function el() {
  return {
    className: '', innerHTML: '', textContent: '', value: '', title: '',
    type: '', checked: false, disabled: false, style: {}, id: '', children: [],
    appendChild(c) { this.children.push(c); return c; },
    querySelector() { return null; },
    focus() {}, select() {}, addEventListener() {}, removeAttribute() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; },
    clientWidth: 800, clientHeight: 600, firstChild: null
  };
}
const nodes = {};
const sandbox = {
  console,
  document: {
    getElementById(id) { return nodes[id] || (nodes[id] = el()); },
    createElement() { return el(); },
    addEventListener() {}
  },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: () => () => {} }),
  Image: function () {}, FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

// ------------------------------------------------------------ the defaults

ok('the window has the label formula', typeof sandbox.dimLabelXY === 'function',
   typeof sandbox.dimLabelXY);
ok('and it can be moved', typeof sandbox.moveMark === 'function');
ok('the default text height starts at what the shared cases assume',
   close(sandbox.markTextH(), CASES._default_text_h),
   [sandbox.markTextH(), CASES._default_text_h]);
ok('and so does the default offset',
   close(sandbox.DIM_LABEL_OFF, CASES._default_off),
   [sandbox.DIM_LABEL_OFF, CASES._default_off]);

// ------------------------------------ the same answers Ruby gives, exactly

CASES.cases.forEach(function (c) {
  const got = sandbox.dimLabelXY(c.m);
  ok(c.why, close(got[0], c.xy[0]) && close(got[1], c.xy[1]), [got, c.xy]);
});

// --------------------------------------------------------------- the shove
//
// A horizontal dimension: sheet +x is ALONG it, sheet +y is ACROSS it.
function dim(extra) {
  return Object.assign({ t: 'dim', x1: 0, y1: 0, x2: 100, y2: 0 }, extra || {});
}

let m = dim();
sandbox.moveMark(m, 'text', 12, 0);
ok('dragging along the line writes oa and leaves across alone',
   close(m.oa, 12) && close(m.oc, sandbox.markTextH() * CASES._default_off),
   [m.oa, m.oc]);

m = dim();
sandbox.moveMark(m, 'text', 0, 6);
ok('dragging across the line writes oc and leaves along alone',
   close(m.oa, 0) && close(m.oc, sandbox.markTextH() * CASES._default_off + 6),
   [m.oa, m.oc]);

m = dim();
sandbox.moveMark(m, 'text', -5, -30);
ok('and it goes both ways at once',
   close(m.oa, -5) && close(m.oc, sandbox.markTextH() * CASES._default_off - 30),
   [m.oa, m.oc]);

m = dim();
sandbox.moveMark(m, 'text', 9, 4);
ok('the shove does NOT touch the dimension itself',
   m.x1 === 0 && m.y1 === 0 && m.x2 === 100 && m.y2 === 0,
   [m.x1, m.y1, m.x2, m.y2]);

// a VERTICAL dimension: now sheet +y is along it and sheet -x is across it
let v = { t: 'dim', x1: 0, y1: 0, x2: 0, y2: 100 };
sandbox.moveMark(v, 'text', 0, 12);
ok('on a vertical dimension, dragging UP slides it ALONG the line',
   close(v.oa, 12), [v.oa, v.oc]);
v = { t: 'dim', x1: 0, y1: 0, x2: 0, y2: 100 };
sandbox.moveMark(v, 'text', -7, 0);
ok('and dragging left pushes it ACROSS - the frame really does turn with the line',
   close(v.oc, sandbox.markTextH() * CASES._default_off + 7), [v.oa, v.oc]);

// a dimension drawn the other way round reverses both, which is the whole
// "תלוי איך אני מצייר אותן לאיזה כיוון"
let r = { t: 'dim', x1: 100, y1: 0, x2: 0, y2: 0 };
sandbox.moveMark(r, 'text', 12, 0);
ok('drawn right-to-left, dragging right stores a NEGATIVE along',
   close(r.oa, -12), r.oa);

// a stray double click has no direction - do not divide by zero
let z = { t: 'dim', x1: 5, y1: 5, x2: 5, y2: 5 };
sandbox.moveMark(z, 'text', 3, 3);
ok('a zero length dimension is left alone rather than blowing up',
   z.oa === undefined && z.oc === undefined, [z.oa, z.oc]);

// ------------------------------------------------ THE POINT OF THE FRAME
//
// Shove the number, then drag the whole dimension somewhere else. The number
// has to come with it, still exactly where he put it. This is what a plain
// sheet-x/sheet-y offset would NOT do.
m = dim();
sandbox.moveMark(m, 'text', 15, -22);
const before = sandbox.dimLabelXY(m);
sandbox.moveMark(m, 'all', 400, 250);
const after = sandbox.dimLabelXY(m);
ok('move the whole dimension and the number travels with it, exactly',
   close(after[0] - before[0], 400) && close(after[1] - before[1], 250),
   [before, after]);

// and stretching an END keeps it in the same place relative to the line
m = dim();
sandbox.moveMark(m, 'text', 0, 10);
const rel = m.oc;
sandbox.moveMark(m, 'b', 60, 0);
ok('stretching the dimension does not un-shove the number',
   close(m.oc, rel), [m.oc, rel]);
ok('and the number rides to the new middle',
   close(sandbox.dimLabelXY(m)[0], 80), sandbox.dimLabelXY(m)[0]);

// ---------------------------------------------- shoving is reversible
m = dim({ oa: 30, oc: -40 });
sandbox.moveMark(m, 'text', -30, 40 + sandbox.markTextH() * CASES._default_off);
ok('dragging it back lands on the numbers it started life with',
   close(m.oa, 0) && close(m.oc, sandbox.markTextH() * CASES._default_off),
   [m.oa, m.oc]);
ok('and that really is where an untouched dimension puts it',
   close(sandbox.dimLabelXY(m)[0], sandbox.dimLabelXY(dim())[0]) &&
   close(sandbox.dimLabelXY(m)[1], sandbox.dimLabelXY(dim())[1]),
   [sandbox.dimLabelXY(m), sandbox.dimLabelXY(dim())]);

// ------------------------------------------- the other parts still work
m = dim();
sandbox.moveMark(m, 'a', 5, 5);
ok('grabbing an end still moves that end only',
   m.x1 === 5 && m.y1 === 5 && m.x2 === 100 && m.y2 === 0, [m.x1, m.y1, m.x2, m.y2]);
ok('and grabbing an end does not invent an offset',
   m.oa === undefined && m.oc === undefined, [m.oa, m.oc]);

let note = { t: 'note', x: 0, y: 0, text: 'x', kx: 1, ky: 1 };
sandbox.moveMark(note, 'all', 10, 20);
ok('a note is untouched by any of this',
   note.x === 10 && note.y === 20 && note.kx === 11 && note.ky === 21,
   [note.x, note.y, note.kx, note.ky]);

// -------------------------------- standing the dimension off the object
//
// The user's blocker: "המידה יושבת על האובייקט". Dragging the LINE pulls the
// dimension away from the wall; the two clicked points never move, because
// they are the thing being measured.

ok('the window knows where the dimension line stands',
   typeof sandbox.dimLine === 'function', typeof sandbox.dimLine);

let d = dim();
ok('with no off, the line IS the two clicked points',
   sandbox.dimLine(d).slice(0, 4).join(',') === '0,0,100,0',
   sandbox.dimLine(d).slice(0, 4));
ok('off pushes it across',
   sandbox.dimLine(dim({ off: 12 })).slice(0, 4).join(',') === '0,12,100,12',
   sandbox.dimLine(dim({ off: 12 })).slice(0, 4));
ok('and the window agrees with Ruby about which side',
   sandbox.dimLine({ t: 'dim', x1: 100, y1: 0, x2: 0, y2: 0, off: 12 })
     .slice(0, 4).join(',') === '100,-12,0,-12');

d = dim();
sandbox.moveMark(d, 'off', 0, 30);
ok('dragging the line away from the wall writes off', close(d.off, 30), d.off);
ok('and the two measured points do NOT move',
   d.x1 === 0 && d.y1 === 0 && d.x2 === 100 && d.y2 === 0,
   [d.x1, d.y1, d.x2, d.y2]);

d = dim();
sandbox.moveMark(d, 'off', 40, 0);
ok('sliding ALONG the line changes nothing - there is nothing to slide',
   close(d.off, 0), d.off);

d = dim();
sandbox.moveMark(d, 'off', 40, 15);
ok('a diagonal drag takes only the sideways part of it', close(d.off, 15), d.off);

let dv = { t: 'dim', x1: 0, y1: 0, x2: 0, y2: 100 };
sandbox.moveMark(dv, 'off', -18, 0);
ok('on a vertical dimension, dragging sideways is what moves it',
   close(dv.off, 18), dv.off);

let dz = { t: 'dim', x1: 5, y1: 5, x2: 5, y2: 5 };
sandbox.moveMark(dz, 'off', 3, 3);
ok('a zero length dimension is left alone', dz.off === undefined, dz.off);

// off and the number are independent: shove the number, then pull the
// dimension off the wall, and the number keeps its place ON the dimension.
d = dim();
sandbox.moveMark(d, 'text', 8, 5);
const oaWas = d.oa, ocWas = d.oc;
sandbox.moveMark(d, 'off', 0, 25);
ok('pulling the dimension off the wall does not un-shove the number',
   close(d.oa, oaWas) && close(d.oc, ocWas), [d.oa, d.oc, oaWas, ocWas]);
ok('and the number travels the whole 25 with it',
   close(sandbox.dimLabelXY(d)[1] - sandbox.dimLabelXY(dim({ oa: oaWas, oc: ocWas }))[1], 25),
   sandbox.dimLabelXY(d));

// the default for the NEXT dimension
sandbox.STATE = { marks: [], dim_off: 18 };
sandbox.SEL = null;
ok('a remembered distance is what a new dimension is born with',
   sandbox.dimOff() === 18, sandbox.dimOff());
sandbox.STATE = { marks: [] };
ok('and with nothing remembered it is 0 - exactly how it always was',
   sandbox.dimOff() === 0, sandbox.dimOff());

console.log(fails === 0 ? 't50 ALL PASS' : 't50 ' + fails + ' FAILED');
process.exit(fails === 0 ? 0 : 1);
