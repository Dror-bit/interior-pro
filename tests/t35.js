// t35 - the sheet window zooms towards the mouse (2026-08-14).
//
// The user: "when I zoom with the wheel it only comes closer to one place, and
// I want it to zoom to wherever I put the mouse."
//
// He was right, and the reason is arithmetic, not taste. Zooming only made the
// sheet bigger; the scroll box stayed where it was, so whatever sat at the top
// left stayed put and everything he was looking at slid off the screen.
//
// The fix: note which spot on the SHEET is under the mouse, redraw, then scroll
// so that spot is back under the mouse. This file re-implements just enough of
// the browser to prove that spot really does not move - and, at the end, that
// the old way really did run away, so the test is measuring something.

const fs = require('fs');
const path = require('path');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const src = fs.readFileSync(RB, 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

// ---------------------------------------------------- the wiring is really there
ok('the wheel zooms towards the mouse, not towards a corner',
   /addEventListener\('wheel'[\s\S]{0,200}zoomAt\(e\.clientX, e\.clientY/.test(src),
   'the wheel handler no longer passes the mouse position to zoomAt');
// The - / fit / + bar used to sit pinned over the bottom corner of the sheet.
// The user asked for it gone - it covered the drawing and the wheel already
// does the job, now that the wheel zooms where he is pointing.
ok('the zoom bar is gone from the corner of the sheet',
   !src.includes("$('zin')") && !src.includes("$('zout')") &&
   !src.includes("$('zfit')") && !src.includes('zoomMiddle'),
   'something is still wired to the old zoom bar');
ok('and the wheel is the only thing that zooms',
   (src.match(/zoomAt\(/g) || []).length === 2,   // the definition and the wheel
   (src.match(/zoomAt\([^)]*/g) || []));

// --------------------------------------------- a scroll box and a sheet inside it
const STAGE = { w: 800, h: 600 };
let state;

function reset(k) {
  state = { k: k || 1, scrollLeft: 0, scrollTop: 0, sheetW: 1000, sheetH: 700 };
}

// What the browser would report for the sheet: centred while it fits, and
// pushed about by the scroll position once it does not.
function rect() {
  const w = state.sheetW * state.k, h = state.sheetH * state.k;
  return {
    left: (w <= STAGE.w ? (STAGE.w - w) / 2 : 0) - state.scrollLeft,
    top: (h <= STAGE.h ? (STAGE.h - h) / 2 : 0) - state.scrollTop,
    width: w, height: h
  };
}

// The routine under test, written the same way as in the window.
function zoomAt(cx, cy, z) {
  z = Math.min(Math.max(z, 0.2), 14);
  const r = rect();
  if (!r.width || !r.height) { state.k = z; return; }
  const fx = Math.max(0, Math.min(1, (cx - r.left) / r.width));
  const fy = Math.max(0, Math.min(1, (cy - r.top) / r.height));
  state.k = z;
  const r2 = rect();
  state.scrollLeft += (r2.left + fx * r2.width) - cx;
  state.scrollTop += (r2.top + fy * r2.height) - cy;
}

// where a given spot on the sheet currently is, in screen pixels
function screenOf(fx, fy) {
  const r = rect();
  return [r.left + fx * r.width, r.top + fy * r.height];
}

function holds(target, z) {
  const before = screenOf(target[0], target[1]);
  zoomAt(before[0], before[1], z);
  const after = screenOf(target[0], target[1]);
  return { before, after,
           moved: Math.hypot(after[0] - before[0], after[1] - before[1]) };
}

// ------------------------------------------------------- it does not run away
reset(1);
let r1 = holds([0.8, 0.25], 4);
ok('a corner of the plan stays under the mouse when zooming in',
   r1.moved < 0.01, r1);

let r2 = holds([0.8, 0.25], 1.5);
ok('and when zooming back out', r2.moved < 0.01, r2);

reset(1);
let r3 = holds([0.5, 0.5], 6);
ok('the middle of the sheet works too', r3.moved < 0.01, r3);

reset(2);
let r4 = holds([0.05, 0.95], 9);
ok('so does the far bottom left', r4.moved < 0.01, r4);

// eight small steps, the way a wheel actually arrives
reset(1);
const spot = [0.72, 0.31];
let worst = 0;
for (let i = 0; i < 8; i++) {
  worst = Math.max(worst, holds(spot, state.k * 1.15).moved);
}
ok('eight wheel clicks in a row do not drift', worst < 0.01, worst);

// ------------------------------------------------ and the old way really was wrong
reset(1);
const was = screenOf(0.8, 0.25);
state.k = 4;                       // what setZoom used to do, on its own
const now = screenOf(0.8, 0.25);
ok('without the correction the spot ran right off - that was the complaint',
   Math.hypot(now[0] - was[0], now[1] - was[1]) > 100, { was, now });

// ----------------------------------------------------------------- awkward cases
reset(4);
const r0 = rect();
zoomAt(r0.left - 500, r0.top - 500, 5);
ok('a wheel out in the grey does not send the page to infinity',
   Number.isFinite(state.scrollLeft) && Number.isFinite(state.scrollTop), state);

reset(1);
zoomAt(400, 300, 999);
ok('zoom stops at 14', state.k === 14, state.k);
zoomAt(400, 300, 0.00001);
ok('and never goes below 0.2', state.k === 0.2, state.k);

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
