// t63 - the wheel zooms to the spot under the mouse, wherever the mouse is
// (2026-10-07).
//
// The user asked for this once already (2026-08-14, t35) and had to ask again:
// "שאני עושה זום זה רק למקום אחד, ואני רוצה שאיפה ששם את העכבר ועושה זום זה
// יהיה לשם."
//
// Measured on his drawing in a real browser, mouse on the LEFT of the sheet,
// six clicks of the wheel: the spot under the mouse went from x = -462 to
// x = 81 - forty-five feet - and the same way every time. Mouse on the right:
// it held. So the old suite was green and the window was wrong, for a plain
// reason: t35 carries its own copy of zoomAt and its own idea of a scroll box
// that never runs out. The real one does. It cannot scroll below zero, it has
// nothing to scroll while the sheet still fits, and the window kept a sheet
// bigger than itself CENTRED - half the overhang off the left edge, where no
// scroll bar goes.
//
// THIS suite runs the zoomAt that ships, against a stage that behaves like a
// stage: scroll clamps at both ends, a sheet that fits has no scroll at all,
// margins push it about, and auto margins centre it only while it fits.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const src = fs.readFileSync(RB, 'utf8');
const js = src.match(/<script>([\s\S]*?)<\/script>/)[1];
const css = src.match(/<style>([\s\S]*?)<\/style>/)[1];

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

// ------------------------------------------------------------ a stage that is one
const PAD = 20;
const CENTRED = /#stage \{[^}]*justify-content:center/.test(css);   // the old layout
const stage = {
  left: 238, top: 0, clientWidth: 1480, clientHeight: 1200, _sl: 0, _st: 0,
  className: '', style: {}, addEventListener() {},
  getBoundingClientRect() { return { left: this.left, top: this.top, width: this.clientWidth, height: this.clientHeight }; },
  get scrollLeft() { return this._sl; },
  set scrollLeft(v) { this._sl = Math.max(0, Math.min(Math.max(0, extent('x') - this.clientWidth), v)); },
  get scrollTop() { return this._st; },
  set scrollTop(v) { this._st = Math.max(0, Math.min(Math.max(0, extent('y') - this.clientHeight), v)); }
};
const wrap = { style: {}, className: '', innerHTML: '', get firstChild() { return svg; } };
let sandbox;
function size() {
  const k = vm.runInContext('fitK()*(ZOOM||1)', sandbox);
  return { w: 36 * k, h: 24 * k };
}
function px(v) { return v === undefined || v === '' ? null : parseFloat(v); }
// where the sheet's corner sits inside the scrolled content, the way a flex box
// with these margins puts it
function corner(axis) {
  const s = size(), len = axis === 'x' ? s.w : s.h;
  const inner = (axis === 'x' ? stage.clientWidth : stage.clientHeight) - 2 * PAD;
  const m0 = px(axis === 'x' ? wrap.style.marginLeft : wrap.style.marginTop);
  const m1 = px(axis === 'x' ? wrap.style.marginRight : wrap.style.marginBottom);
  if (m0 === null) {                                  // margin:auto
    if (len <= inner) return PAD + (inner - len) / 2;         // fits: centred
    // too big: the old layout centred the OVERHANG too (justify-content:center)
    return axis === 'x' && CENTRED ? PAD + (inner - len) / 2 : PAD;
  }
  const free = inner - (m0 + len + m1);
  return PAD + m0 + (free < 0 && axis === 'x' && CENTRED ? free / 2 : 0);
}
function extent(axis) {
  const s = size(), len = axis === 'x' ? s.w : s.h;
  const m1 = px(axis === 'x' ? wrap.style.marginRight : wrap.style.marginBottom) || 0;
  return Math.max(axis === 'x' ? stage.clientWidth : stage.clientHeight, corner(axis) + len + m1 + PAD);
}
const svg = {
  style: {}, querySelector() { return null; },
  getBoundingClientRect() {
    const s = size();
    return { left: stage.left + corner('x') - stage.scrollLeft, top: stage.top + corner('y') - stage.scrollTop, width: s.w, height: s.h,
             right: stage.left + corner('x') - stage.scrollLeft + s.w, bottom: stage.top + corner('y') - stage.scrollTop + s.h };
  }
};
function el() {
  return { className: '', innerHTML: '', textContent: '', value: '', style: {}, appendChild() {}, querySelector() { return null; },
           querySelectorAll() { return []; }, addEventListener() {}, focus() {}, scrollIntoView() {},
           getBoundingClientRect() { return { left: 0, top: 0, width: 10, height: 10 }; }, clientWidth: 10, clientHeight: 10 };
}
const nodes = { stage, sheetWrap: wrap };
sandbox = {
  console,
  document: { getElementById(id) { return nodes[id] || (nodes[id] = el()); }, createElement() { return el(); }, createElementNS() { return el(); }, addEventListener() {} },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: () => () => {} }),
  Image: function () {}, FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

const PAGE = { name: 'FLOOR PLAN', sheet_number: 'A-101', width: 36, height: 24, kind: 'plan',
               views: [{ name: 'PLAN', x: 1, y: 2, w: 34, h: 21, canvas: 'MODEL', scale: '1/4"' }], layers: [] };
sandbox.DOC = { pages: [PAGE], canvases: [{ name: 'MODEL', layers: [] }] };
sandbox.STATE = { scale: '1/4"', hidden: [], origin_x: 0, origin_y: 0, active: 0, marks: [] };
sandbox.SF = { '1/4"': 0.25 / 12 };
sandbox.URLS = {};
sandbox.PAGE = PAGE;

function reset() {
  wrap.style = {};
  stage._sl = 0; stage._st = 0;
  vm.runInContext('ZOOM=null; STATE.zoom=null;', sandbox);
}
// which spot of the sheet (0..1 across, 0..1 down) is under a point on the screen
function spot(x, y) {
  const r = svg.getBoundingClientRect();
  return [(x - r.left) / r.width, (y - r.top) / r.height];
}
function wheel(x, y, clicks) {
  for (let i = 0; i < Math.abs(clicks); i++) {
    const z = vm.runInContext('(ZOOM||1)', sandbox) * (clicks > 0 ? 1.15 : 1 / 1.15);
    sandbox.zoomAt(x, y, z);
  }
}
function drift(x, y, clicks) {
  reset();
  const a = spot(x, y);
  wheel(x, y, clicks);
  const b = spot(x, y);
  const r = svg.getBoundingClientRect();
  return Math.max(Math.abs(a[0] - b[0]) * r.width, Math.abs(a[1] - b[1]) * r.height);   // screen pixels
}

ok('the stage in this suite really is his: the sheet fits and sits in the middle to start with', (() => {
  reset(); const r = svg.getBoundingClientRect();
  return r.width < stage.clientWidth && Math.abs((r.left - stage.left) - (stage.left + stage.clientWidth - r.right)) < 0.01;
})());
ok('the window has the switch, and it is on', sandbox.ZHOLD === true, sandbox.ZHOLD);
ok('Ruby owns the switch and sends it with the sheet',
   /USE_ZOOM_TO_MOUSE = true unless const_defined/.test(src) && /zoom_hold: USE_ZOOM_TO_MOUSE/.test(src) &&
   /ZHOLD = \(p\.zoom_hold!==false\)/.test(js));

// ------------------------------------------------------------------- THE RULE
const R0 = (() => { reset(); return svg.getBoundingClientRect(); })();
const at = (fx, fy) => [R0.left + fx * R0.width, R0.top + fy * R0.height];
const PLACES = { 'the left of the sheet': at(0.12, 0.5), 'the top left': at(0.1, 0.12), 'the right': at(0.9, 0.5),
                 'the bottom right': at(0.92, 0.9), 'the bottom left': at(0.08, 0.9), 'the middle': at(0.5, 0.5) };
Object.keys(PLACES).forEach(name => {
  const [x, y] = PLACES[name];
  const d1 = drift(x, y, 1), d6 = drift(x, y, 6), d14 = drift(x, y, 14);
  ok(`zooming IN at ${name}: the spot under the mouse stays under the mouse`,
     d1 < 0.2 && d6 < 0.2 && d14 < 0.2, [d1, d6, d14].map(v => +v.toFixed(2)));
});
Object.keys(PLACES).forEach(name => {
  const [x, y] = PLACES[name];
  reset(); wheel(x, y, 8);
  const a = spot(x, y); wheel(x, y, -14); const b = spot(x, y); const r = svg.getBoundingClientRect();
  const d = Math.max(Math.abs(a[0] - b[0]) * r.width, Math.abs(a[1] - b[1]) * r.height);
  ok(`in and back OUT past "fits" at ${name}: still under the mouse`, d < 0.2, +d.toFixed(2));
});

// every part of a zoomed sheet can be reached - nothing is lost off the left
reset(); wheel(...PLACES['the right'], 8);
stage.scrollLeft = 0; stage.scrollTop = 0;
ok('zoomed in, scrolling all the way back shows the LEFT edge of the sheet - none of it is cut off',
   svg.getBoundingClientRect().left >= stage.left - 0.01, svg.getBoundingClientRect().left);
ok('the layout no longer centres a sheet that is bigger than the window', !CENTRED &&
   /#stage \{[^}]*justify-content:flex-start/.test(css));
ok('...and a sheet that fits is still centred, by its own margins', /#sheetWrap \{[^}]*margin:auto/.test(css));

// off the sheet: hold the nearest edge where it is, do not fling the sheet at the mouse
reset();
const before = svg.getBoundingClientRect();
sandbox.zoomAt(before.left - 150, before.top + before.height / 2, 1.15);
const after = svg.getBoundingClientRect();
ok('mouse to the LEFT of the sheet: its left edge stays where it was', Math.abs(after.left - before.left) < 0.2,
   [before.left, after.left]);

// the limits the old code had are still there
reset(); sandbox.zoomAt(600, 400, 999);
ok('it will not zoom in without end - but it goes well past the old 14 times', vm.runInContext('ZOOM', sandbox) === 200, vm.runInContext('ZOOM', sandbox));
reset(); sandbox.zoomAt(600, 400, 0.00001);
ok('nor out past "fits" - the sheet is never smaller than the window (2026-10-07)', vm.runInContext('ZOOM', sandbox) >= 1, vm.runInContext('ZOOM', sandbox));

// ------------------------------------------------------------------ the switch
// Zooming OUT at a corner: the sheet fits the window, so there is nothing to
// scroll, and the old arithmetic can only watch it shrink towards the middle.
// (since 2026-10-07 the wheel stops at "fits", so the sheet is first zoomed in)
reset(); wheel(...PLACES['the top left'], 6);
const held = drift(...PLACES['the top left'], -4);
ok('zooming OUT at a corner: the sheet shrinks towards the mouse', held < 0.2, +held.toFixed(2));
reset(); wheel(...PLACES['the top left'], -6);
ok('and out past "fits" nothing happens: ZOOM holds at 1 and the sheet stays where it was', vm.runInContext('ZOOM', sandbox) === 1);

// ------------------------------------------------- all the way out = the whole sheet, in the middle (2026-10-08)
// His picture: zoomed in at one spot, wheel out at another - the sheet stopped
// at "fits" with its top off the window and nothing to scroll. "כשאני עושה
// זום אווט עד הסוף הוא יחזור למרכז את הדף באמצע."
function centred() {
  const r = svg.getBoundingClientRect();
  const dx = (r.left + r.width / 2) - (stage.left + stage.clientWidth / 2);
  const dy = (r.top + r.height / 2) - (stage.top + stage.clientHeight / 2);
  return { dx: +dx.toFixed(2), dy: +dy.toFixed(2), whole: r.top >= stage.top - 0.01 && r.bottom <= stage.top + stage.clientHeight + 0.01 && r.left >= stage.left - 0.01 && r.right <= stage.left + stage.clientWidth + 0.01 };
}
ok('the window has the switch, and it is on', sandbox.FITCENTRE === true, sandbox.FITCENTRE);
ok('Ruby owns the switch and sends it with the sheet', /fit_centre: USE_FIT_CENTRE/.test(src) && /USE_FIT_CENTRE = true unless/.test(src));
reset(); wheel(...PLACES['the top left'], 8);
const mid = [stage.left + stage.clientWidth - 100, stage.top + stage.clientHeight - 100];   // the wheel at another spot, bottom right
wheel(mid[0], mid[1], 7);
ok('(zoomed in at the top left, then in again at the bottom right: the sheet is not centred now)', !centred().whole || Math.abs(centred().dx) > 1, centred());
wheel(mid[0], mid[1], -15);
ok('ZOOM is back at "fits"', vm.runInContext('ZOOM', sandbox) === 1, vm.runInContext('ZOOM', sandbox));
ok('ALL THE WAY OUT: THE WHOLE SHEET IS IN THE WINDOW, IN THE MIDDLE - top and all', centred().whole && Math.abs(centred().dx) < 0.5 && Math.abs(centred().dy) < 0.5, centred());
ok('the place it was given is taken back (the layout centres it, the way it opens)', !px(wrap.style.marginLeft) && !px(wrap.style.marginTop) && stage.scrollLeft === 0 && stage.scrollTop === 0, [wrap.style, stage.scrollLeft, stage.scrollTop]);
// one more click out changes nothing
wheel(mid[0], mid[1], -1);
ok('and one more click out: still whole, still in the middle', centred().whole && Math.abs(centred().dy) < 0.5, centred());
// 1.15 in and 1.15 out is "fits" exactly, not a hair over it
reset(); wheel(...PLACES['the top left'], 1); wheel(...PLACES['the top left'], -1);
ok('one click in and one out is "fits" exactly - so it centres', vm.runInContext('ZOOM', sandbox) === 1 && centred().whole && Math.abs(centred().dy) < 0.5, [vm.runInContext('ZOOM', sandbox), centred()]);
// zooming in again from "fits" still goes to the mouse
reset(); const d1 = drift(...PLACES['the right'], 1);
ok('zooming in from "fits" still goes to the spot under the mouse', d1 < 0.2, d1);
// the switch
sandbox.FITCENTRE = false;
reset(); wheel(...PLACES['the top left'], 8); wheel(mid[0], mid[1], -8);
ok('SWITCHED OFF: the sheet shrinks towards the mouse down to "fits" and stays where that leaves it, as before', vm.runInContext('ZOOM', sandbox) === 1 && (!centred().whole || Math.abs(centred().dy) > 1), centred());
sandbox.FITCENTRE = true;

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
