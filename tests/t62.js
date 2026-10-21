// t62 - a yard of loose lines is ONE element, and the strip waits (2026-10-07).
//
// 6 Bronco Ln. The user, after his house finally came onto the sheet as walls:
// "זה עבד טוב אבל זה זז לאט".
//
// Measured, not guessed - his own drawing loaded into a real browser:
//
//   15,394 elements in the sheet; every step of a drag and every click of the
//   wheel throws them all away and builds them again.
//     drag      286 ms a step     (140 with the page strip closed)
//     wheel     366 ms a click
//   Building the TEXT of the drawing took 16 ms of that. The rest was the
//   browser making fifteen thousand elements, twice - once for the sheet and
//   once more for the little copy of it in the page strip.
//
// So two things, and this suite pins both:
//   1. consecutive open lines of one weight are written as a single <path>.
//      Same points, same weight, same order - the picture is the same picture.
//   2. while the plan is being dragged or zoomed the page strip is left alone.
//
// And what must not move: walls, fills, closed outlines and writing are drawn
// exactly as before, and the switch puts every line back in its own element.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const src = fs.readFileSync(RB, 'utf8');
const js = src.match(/<script>([\s\S]*?)<\/script>/)[1];

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}

function el() {
  return {
    className: '', innerHTML: '', textContent: '', value: '', disabled: false,
    style: {}, id: '', onclick: null,
    appendChild() {}, querySelector() { return null; }, querySelectorAll() { return []; },
    focus() {}, select() {}, addEventListener() {}, removeAttribute() {},
    scrollIntoView() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; },
    clientWidth: 800, clientHeight: 600, firstChild: null, scrollLeft: 0, scrollTop: 0
  };
}
const nodes = {};
const sandbox = {
  console,
  document: {
    getElementById(id) { return nodes[id] || (nodes[id] = el()); },
    createElement() { return el(); }, createElementNS() { return el(); },
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

// ------------------------------------------------------------- his kind of sheet
const YARD = [];
for (let i = 0; i < 3000; i++) YARD.push({ type: 'polyline', points: [[i, 0], [i, 50 + (i % 7)]], closed: false, weight: 0.010 });
const PAGE = {
  name: 'FLOOR PLAN', sheet_number: 'A-101', width: 36, height: 24, kind: 'plan',
  views: [{ name: 'PLAN', x: 1, y: 2, w: 30, h: 20, canvas: 'MODEL', scale: '1/4"' }],
  layers: [{ name: 'TITLE', visible: true, shapes: [
    { type: 'text', text: 'A-101 FLOOR PLAN', x: 20, y: 1, h: 0.1, align: 'left' },
    { type: 'line', x1: 0.5, y1: 1.6, x2: 35.5, y2: 1.6, weight: 0.03 }
  ] }]
};
const WALLS = { name: 'WALLS', visible: true, shapes: [
  { type: 'polygon', points: [[0, 0], [240, 0], [240, 6], [0, 6]], closed: true, fill: [64, 64, 64] },
  { type: 'polyline', points: [[0, 0], [240, 0], [240, 180], [0, 180], [0, 0]], closed: true },
  { type: 'text', text: 'KITCHEN', x: 120, y: 90, h: 6, align: 'center' }
] };
const MIXED = { name: 'DOORS', visible: true, shapes: [
  { type: 'polyline', points: [[10, 10], [20, 10]], closed: false },
  { type: 'polyline', points: [[20, 10], [20, 30], [40, 30]], closed: false },            // a bent line
  { type: 'polygon', points: [[50, 50], [60, 50], [60, 60]], closed: true, fill: [0, 0, 0] }, // breaks the run
  { type: 'polyline', points: [[70, 10], [80, 10]], closed: false },
  { type: 'polyline', points: [[70, 20], [80, 20]], closed: false, weight: 0.5 }          // a heavier line
] };
sandbox.DOC = { pages: [PAGE], canvases: [{ name: 'MODEL', layers: [WALLS, MIXED, { name: 'SITE', visible: true, shapes: YARD }] }] };
sandbox.STATE = { scale: '1/4"', hidden: [], origin_x: 120, origin_y: 90, active: 0, marks: [] };
sandbox.SF = { '1/4"': 0.25 / 12 };
sandbox.URLS = {};
sandbox.PAGE = PAGE;

const count = (s, re) => (s.match(re) || []).length;
const numbers = d => (d.match(/-?[0-9]+\.[0-9]+/g) || []).map(Number);

ok('the window has the switch, and it is on', sandbox.FAST === true, sandbox.FAST);
ok('Ruby owns the switch and sends it with the sheet',
   /USE_FAST_SHEET = true unless const_defined/.test(src) && /fast: USE_FAST_SHEET/.test(src) &&
   /FAST = \(p\.fast!==false\)/.test(js));

// -------------------------------------------------------------------- 1. one element
vm.runInContext('FAST=true', sandbox);
const fast = sandbox.sheetSVG(PAGE, 20, true);
vm.runInContext('FAST=false', sandbox);
const slow = sandbox.sheetSVG(PAGE, 20, true);
vm.runInContext('FAST=true', sandbox);

const slowEls = count(slow, /<(polyline|polygon|line|path|text)[ >]/g);
const fastEls = count(fast, /<(polyline|polygon|line|path|text)[ >]/g);
ok('before: every loose line is an element of its own', slowEls > 3000, slowEls);
ok('3,000 LOOSE LINES ARE A HANDFUL OF ELEMENTS, NOT 3,000  <<< THE RULE', fastEls < 20, fastEls);

// the same picture: every point of every loose line, in the same order
const slowPts = (slow.match(/<polyline points="([^"]*)"/g) || []).map(m => numbers(m)).flat();
const fastPts = (fast.match(/<path d="([^"]*)"/g) || []).map(m => numbers(m)).flat();
ok('not one point is lost, moved or reordered',
   slowPts.length === fastPts.length && slowPts.length >= 3000 * 4 &&
   slowPts.every((v, i) => Math.abs(v - fastPts[i]) < 0.011),
   [slowPts.length, fastPts.length, slowPts.slice(0, 4), fastPts.slice(0, 4)]);
ok('every loose line starts its own stroke - none is joined to the next',
   count(fast, /M-?[0-9]/g) === 3000 + 4, count(fast, /M-?[0-9]/g));
ok('a bent line keeps its bend', /M[0-9.]+ [0-9.]+L[0-9.]+ [0-9.]+L[0-9.]+ [0-9.]+/.test(fast));
ok('the line weight is the same one', (() => {
  const a = [...new Set((slow.match(/<polyline[^>]*stroke-width="([^"]*)"/g) || []).map(m => m.match(/stroke-width="([^"]*)"/)[1]))].sort();
  const b = [...new Set((fast.match(/<path[^>]*stroke-width="([^"]*)"/g) || []).map(m => m.match(/stroke-width="([^"]*)"/)[1]))].sort();
  return a.length === b.length && a.every((v, i) => Number(v) === Number(b[i]));
})());
ok('a heavier line is not swallowed into the thin run - it gets a path of its own weight',
   count(fast, /<path /g) >= 3, count(fast, /<path /g));
ok('nothing is drawn as NaN', !/NaN/.test(fast));

// ---------------------------------------------------------- what must not move
const keep = s => (s.match(/<polygon[^>]*>|<text[^>]*>[^<]*<\/text>|<line [^>]*>|<rect[^>]*>|<clipPath[^>]*>/g) || []).join('\n');
ok('walls, fills, closed outlines, writing and the title block are drawn EXACTLY as before',
   keep(fast) === keep(slow) && keep(fast).length > 200, [keep(fast).length, keep(slow).length]);
ok('a filled shape between two lines still sits between them on the page',
   fast.indexOf('rgb(0,0,0)') > fast.indexOf('<path') && fast.lastIndexOf('<path') > fast.indexOf('rgb(0,0,0)'));
ok('the closed outline of a wall is still a closed outline', count(fast, /<polygon[^>]*fill="none"/g) === 1,
   count(fast, /<polygon[^>]*fill="none"/g));
ok('tags are balanced', count(fast, /<g[ >]/g) === count(fast, /<\/g>/g) && fast.endsWith('</svg>'));

// the thumbnail goes through the same routine
const thumb = sandbox.sheetSVG(PAGE, 520 / 36, false);
ok('the little sheet in the strip is drawn the same way', count(thumb, /<path /g) >= 1 && count(thumb, /<polyline /g) === 0,
   [count(thumb, /<path /g), count(thumb, /<polyline /g)]);

// ------------------------------------------------------------ 2. the strip waits
let strips = 0;
vm.runInContext('var __realStrip = paintStrip; paintStrip = function(){ __n = (typeof __n === "number" ? __n : 0) + 1; };', sandbox);
const stripCount = () => vm.runInContext('typeof __n === "number" ? __n : 0', sandbox);
nodes['strip'] = el(); nodes['strip'].className = 'on';
nodes['sheetWrap'] = el();
vm.runInContext('render()', sandbox);
ok('an ordinary redraw still draws the page strip', stripCount() === 1, stripCount());
vm.runInContext('setZoom(2)', sandbox);
ok('ZOOMING DOES NOT REDRAW THE PAGE STRIP', stripCount() === 1, stripCount());
ok('...and the sheet itself was redrawn at the new size', /width="/.test(nodes['sheetWrap'].innerHTML));
// Inspect the function the VM actually parsed; Ruby heredoc indentation is not behavior.
const onMove = sandbox.onMove.toString();
ok('DRAGGING THE PLAN DOES NOT REDRAW THE PAGE STRIP ON EVERY STEP',
   /STATE\.origin_y=DRAG\.oy\+\(e\.clientY-DRAG\.y\)\/k\/sf;\s*render\(true\);/.test(onMove));
ok('when the drag ends Ruby is told, and its answer redraws everything, strip included',
   /if\(moved\) push\(\);/.test(js) &&
   /function applyPages\(pages, marksLayer\)\{[\s\S]{0,300}render\(\);/.test(js));
vm.runInContext('FAST=false; setZoom(3)', sandbox);
ok('switched off: the strip is redrawn on every zoom, as before', stripCount() === 2, stripCount());
vm.runInContext('FAST=true', sandbox);

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
