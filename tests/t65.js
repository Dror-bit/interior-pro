// t65 - he can get closer, and the lines stay lines (2026-10-07).
//
// The user: "אני רוצה לעשות יותר זום אין."
//
// The wheel stopped at 14 times. On a whole lot at 3/32" that is four pixels
// to the inch of yard. Measured on his drawing up to 200 times: no slower, and
// the spot under the mouse holds.
//
// The catch, also measured: a line has a paper thickness and was drawn that
// thickness TIMES THE ZOOM. At 50 times a hairline was 20 pixels wide and the
// treads of his stairs were one black smear - closer showed him less. He was
// shown both pictures side by side (zoom_options.png) and told to start.
//
// THE RULE: the drawing keeps growing; past KSTROKE pixels to the paper inch a
// line is drawn as if the zoom had stopped there. All weights stop at the same
// point, so heavy stays heavier than light. Below it nothing changes at all.

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
  return { className: '', innerHTML: '', textContent: '', value: '', disabled: false, style: {}, id: '',
           appendChild() {}, querySelector() { return null; }, querySelectorAll() { return []; },
           focus() {}, select() {}, addEventListener() {}, removeAttribute() {}, scrollIntoView() {},
           getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; },
           clientWidth: 800, clientHeight: 600, firstChild: null, scrollLeft: 0, scrollTop: 0 };
}
const nodes = {};
const sandbox = {
  console,
  document: { getElementById(id) { return nodes[id] || (nodes[id] = el()); }, createElement() { return el(); },
              createElementNS() { return el(); }, addEventListener() {} },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: () => () => {} }),
  Image: function () {}, FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout, Infinity
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);
const get = n => { try { return vm.runInContext(n, sandbox); } catch (e) { return undefined; } };

const PAGE = { name: 'FLOOR PLAN', sheet_number: 'A-101', width: 36, height: 24, kind: 'plan',
               views: [{ name: 'PLAN', x: 1, y: 2, w: 34, h: 21, canvas: 'MODEL', scale: '1/4"' }],
               layers: [{ name: 'TITLE', visible: true, shapes: [{ type: 'line', x1: 0.5, y1: 1.6, x2: 35.5, y2: 1.6, weight: 0.03 }] }] };
sandbox.DOC = { pages: [PAGE], canvases: [{ name: 'MODEL', layers: [
  { name: 'SITE', visible: true, shapes: [
    { type: 'polyline', points: [[0, 0], [10, 0]], closed: false, weight: 0.010 },      // a yard line
    { type: 'polyline', points: [[0, 5], [10, 5]], closed: false, weight: 0.010 } ] },
  { name: 'WALLS', visible: true, shapes: [
    { type: 'polyline', points: [[0, 9], [10, 9], [10, 19], [0, 9]], closed: true, weight: 0.020 },   // a heavier outline
    { type: 'polygon', points: [[0, 20], [10, 20], [10, 26], [0, 26]], closed: true, fill: [64, 64, 64] },
    { type: 'text', text: 'KITCHEN', x: 5, y: 30, h: 6 } ] } ] }] };
sandbox.STATE = { scale: '1/4"', hidden: [], origin_x: 5, origin_y: 10, active: 0, marks: [] };
sandbox.SF = { '1/4"': 0.25 / 12 };
sandbox.URLS = {};
sandbox.PAGE = PAGE;

const widths = svg => (svg.match(/stroke-width="([0-9.]+)"/g) || []).map(m => Number(m.match(/"([0-9.]+)"/)[1]));
const widthOf = (svg, tag) => Number((svg.match(new RegExp('<' + tag + '[^>]*stroke="#000"[^>]*stroke-width="([0-9.]+)"')) || [])[1]);
const draw = k => sandbox.sheetSVG(PAGE, k, false);

ok('the window knows how close and how fat', get('ZMAX') === 200 && get('KSTROKE') === 160, [get('ZMAX'), get('KSTROKE')]);
ok('Ruby owns the switch and sends it with the sheet',
   /USE_DEEP_ZOOM = true unless const_defined/.test(src) && /deep_zoom: USE_DEEP_ZOOM/.test(src) &&
   /if\(p\.deep_zoom===false\)\{ ZMAX=14; KSTROKE=Infinity; \}/.test(js));

// ------------------------------------------------------------- 1. closer
ok('the wheel is no longer stopped at 14 times', /z = Math\.min\(Math\.max\(z, 0\.2\), ZMAX\);/.test(js) &&
   !/Math\.max\(z, 0\.2\), 14\)/.test(js));

// ------------------------------------------------- 2. the lines stay lines
const far = draw(40), edge = draw(160), near = draw(2000), nearer = draw(7900);     // 7900 = 200 times on his screen
ok('a yard line at 50 times is a line, not a 20 pixel bar  <<< THE RULE', widthOf(near, 'path') === 1.6, widthOf(near, 'path'));
ok('and at 200 times it is still the same line', widthOf(nearer, 'path') === 1.6, widthOf(nearer, 'path'));
ok('a heavier line stays heavier - twice the weight is twice the line',
   Math.abs(widthOf(near, 'polygon') / widthOf(near, 'path') - 2) < 0.01, [widthOf(near, 'polygon'), widthOf(near, 'path')]);
ok('the title block line (three times the weight) is three times the line',
   Math.abs(widthOf(near, 'line') / widthOf(near, 'path') - 3) < 0.01, [widthOf(near, 'line'), widthOf(near, 'path')]);
ok('the DRAWING still grows: the same line is fifty times longer at fifty times the zoom', (() => {
  const len = s => { const m = s.match(/<path d="M([0-9.-]+) ([0-9.-]+)L([0-9.-]+) ([0-9.-]+)/); return Math.hypot(m[3] - m[1], m[4] - m[2]); };
  return Math.abs(len(near) / len(far) - 50) < 0.5;
})());
ok('writing still grows with the zoom - it is the lines that stop', (() => {
  const fs = s => Number((s.match(/font-size="([0-9.]+)"/) || [])[1]);
  return fs(near) > fs(edge) * 10;
})());
ok('a filled wall is still filled', near.includes('rgb(64,64,64)'));

// -------------------------------------------------- 3. what must not change
vm.runInContext('KSTROKE=Infinity', sandbox);
const farOld = draw(40), edgeOld = draw(160), thumbOld = draw(520 / 36), nearOld = draw(2000);
vm.runInContext('KSTROKE=160', sandbox);
ok('THE WHOLE SHEET IN THE WINDOW IS DRAWN EXACTLY AS BEFORE', far === farOld);
ok('so is the little sheet in the page strip', draw(520 / 36) === thumbOld);
ok('so is everything up to the point where the lines stop', edge === edgeOld);
ok('and before this change that yard line really was 20 pixels wide at 50 times',
   widthOf(nearOld, 'path') === 20, widthOf(nearOld, 'path'));
ok('nothing is drawn as NaN', !/NaN/.test(near + nearer));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
