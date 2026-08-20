// t52 - a note's leader is DRAWN, not guessed (2026-08-19).
//
// The user, on how Rayon does it:
//   "בכפתור הזה קודם לחיצה אחת זה מותח קו אחד, ואז עוד לחיצה מותח קו שני,
//    ורק אז כותבים בריבוע מה שרוצים."
//
// Ours took ONE click and then chose the other two points for him - always up
// and to the right, whatever was there - and he dragged them where he actually
// wanted them afterwards. Two jobs for one note. It is the same complaint he
// made about the dimension tool an hour earlier, and the same rule in
// CLAUDE.md it breaks: fewer clicks, always.
//
// Now:
//   1  what the note is about   -> the arrow tip, and it snaps to a corner
//   2  where the leader bends   -> the knee
//   3  the end of the shoulder  -> and the words sit there
//   4  type
//
// The Rayon screenshot he sent settles the shape: a diagonal from the arrow to
// a knee, then a LEVEL shoulder whose length he chooses, then the box. The
// first version of this had the shoulder a fixed length; the picture showed a
// long one. He chooses it.
//
// This suite runs the window's own noteMark(), which is what saveNote calls.
// A copy of the arithmetic here would go on passing on the day the window
// stopped using it.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const js = fs.readFileSync(RB, 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

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
    getElementById(id) { if (!nodes[id]) { nodes[id] = el(); nodes[id].id = id; } return nodes[id]; },
    createElement() { return el(); }, createElementNS() { return el(); },
    addEventListener() {}
  },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: () => () => {} }),
  Image: function () {}, FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout,
  encodeURIComponent
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

ok('the window builds a note from the three points he clicked',
   typeof sandbox.noteMark === 'function', typeof sandbox.noteMark);
ok('and it really takes three of them', sandbox.noteMark.length >= 3,
   sandbox.noteMark.length);

// 1/8" scale: one paper inch is 96 model inches, so the 0.7" gap is 67.2"
const SF = 1 / 96;
// x/y is the MIDDLE of the words, so clearing the end of the line takes half
// the words plus a pad. A flat nudge would let a long note run back over the
// shoulder - and in his picture the box STARTS after the line ends.
const H = sandbox.markTextH();
function gapFor(t) { return String(t).length * H * 0.6 / 2 + (0.7 / SF) * 0.12; }

const TIP = [100, 100];
const KNEE = [400, 300];
const END = [900, 260];        // the mouse was NOT level - that must not matter
let n = sandbox.noteMark(TIP, KNEE, END, 'קירות פנים', true, SF);

ok('the FIRST click is where the arrow points',
   close(n.lx, 100) && close(n.ly, 100), [n.lx, n.ly]);
ok('the SECOND click is where the leader bends - not a place we chose for him',
   close(n.kx, 400) && close(n.ky, 300), [n.kx, n.ky]);
ok('THE THIRD click sets how long the shoulder is - it is not a fixed stub',
   n.x > 890, n.x);
ok('the words sit level with the knee, so the shoulder is flat...',
   close(n.y, n.ky), [n.y, n.ky]);
ok('...even though the mouse was 40" below it on the third click',
   close(n.y, 300), n.y);
ok('and past the end by HALF THE WORDS plus a pad, so the box starts after ' +
   'the line instead of sitting on it',
   close(n.x, 900 + gapFor('קירות פנים')), [n.x, 900 + gapFor('קירות פנים')]);
ok('a LONGER note is pushed further out, or its left half would run back ' +
   'over the shoulder',
   sandbox.noteMark(TIP, KNEE, END, 'a very much longer note indeed', true, SF).x >
     sandbox.noteMark(TIP, KNEE, END, 'ab', true, SF).x,
   [sandbox.noteMark(TIP, KNEE, END, 'a very much longer note indeed', true, SF).x,
    sandbox.noteMark(TIP, KNEE, END, 'ab', true, SF).x]);
ok('and its left edge really does clear the end of the line',
   (function(){
     var t='a very much longer note indeed';
     var q=sandbox.noteMark(TIP, KNEE, END, t, true, SF);
     return q.x - String(t).length*H*0.6/2 > END[0];
   })());
ok('the words are his', n.text === 'קירות פנים', n.text);
ok('and it is a note', n.t === 'note', n.t);
ok('the arrow head is carried through', n.arrow === true, n.arrow);
n = sandbox.noteMark(TIP, KNEE, END, 'x', false, SF);
ok('and so is asking for no head', n.arrow === false, n.arrow);

// pointing the other way: the shoulder must come out on the other side, or the
// words would sit ON TOP of the leader
n = sandbox.noteMark([900, 100], [400, 300], [50, 260], 'x', true, SF);
ok('a shoulder running right-to-left puts the words on its LEFT end',
   close(n.x, 50 - gapFor('x')), [n.x, 50 - gapFor('x')]);
ok('and still level with the knee', close(n.y, 300), n.y);

// straight up: no sideways component at all, and it must still pick a side
n = sandbox.noteMark([400, 100], [400, 300], [400, 300], 'x', true, SF);
ok('a shoulder of no length still puts the words off the point, not on it',
   Math.abs(n.x - 400) > 1, n.x);

// The clearance is two parts and they scale differently ON PURPOSE:
//   half the words - model inches, because the writing itself is model inches
//                    and shrinks with the drawing
//   the pad        - PAPER inches, so the breathing space beside the words
//                    looks the same on a 1/8" sheet and a 1/2" one
const halfX = String('x').length * H * 0.6 / 2;
const eighth = sandbox.noteMark(TIP, KNEE, END, 'x', true, 1 / 96);
const half = sandbox.noteMark(TIP, KNEE, END, 'x', true, 1 / 24);
const pad96 = (eighth.x - END[0]) - halfX;
const pad24 = (half.x - END[0]) - halfX;
ok('at 1/2" scale the PAD is a quarter of the model inches it is at 1/8"',
   close(pad24 * 4, pad96), [pad24, pad96]);
ok('...which is the SAME breathing space on paper',
   close(pad24 * (1 / 24), pad96 * (1 / 96)), [pad24 / 24, pad96 / 96]);
ok('and half the words does NOT change with the scale - the writing is model '
   + 'inches, so it shrinks with the drawing like everything else',
   close(half.x - END[0] - pad24, eighth.x - END[0] - pad96),
   [half.x - END[0] - pad24, eighth.x - END[0] - pad96]);

// the three points are all different, so all three can be dragged apart
ok('tip, knee and words are three separate places',
   !(close(n.lx, n.kx) && close(n.ly, n.ky)) &&
   !(close(n.x, n.kx) && close(n.y, n.ky)),
   [[n.lx, n.ly], [n.kx, n.ky], [n.x, n.y]]);

// and moveMark still knows all three parts - dragging the words takes the
// shoulder with them, which is the behaviour that was already there
const m = sandbox.noteMark(TIP, KNEE, END, 'x', true, SF);
const kxWas = m.kx, xWas = m.x;
sandbox.moveMark(m, 'all', 10, 20);
ok('dragging the words takes the knee with them',
   close(m.kx, kxWas + 10) && close(m.x, xWas + 10), [m.kx, m.x]);
sandbox.moveMark(m, 'tip', 5, 5);
ok('and the tip moves on its own', close(m.lx, 105) && close(m.ly, 105),
   [m.lx, m.ly]);

console.log(fails === 0 ? 't52 ALL PASS' : 't52 ' + fails + ' FAILED');
process.exit(fails === 0 ? 0 : 1);
