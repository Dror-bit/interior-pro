// t66 - a rubbed-out line leaves the sheet at once (2026-10-07).
//
// The user: "לוקח לו קצת זמן עד שהוא מוחק וצריך שזה יהיה יותר מהיר".
//
// The window used to send the numbers to Ruby and WAIT - for the whole model to
// be read again, 15,000 lines to be written into a new document, a megabyte and
// a half to come back, and all of it to be drawn from nothing. The line he had
// just rubbed out sat there on the sheet until that was over.
//
// THE RULE, on the window side (rt266 pins Ruby): the lines come off the sheet
// HERE, in the same breath as the mouse is let go, and Ruby is told which ones
// went and how many there were. The numbers are the ones Ruby holds - shape i
// is line i on both sides - and stay in step after the lines are gone.
const fs = require("fs");

let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? "PASS  " : "FAIL  ") + name + (cond ? "" : "   << " + JSON.stringify(extra)));
  if (!cond) fails++;
}

// ---------------------------------------------------------------- a DOM
// Enough of one for the window to load and draw. Not a browser: the sheet is
// built as an SVG STRING, so innerHTML stays a string and firstChild is a
// stand-in that remembers what was hung on it.
const els = {};
function mkEl(id) {
  const el = {
    id, value: '', innerHTML: '', textContent: '', className: '', style: {},
    checked: false, disabled: false, children: [], options: [],
    clientWidth: 900, clientHeight: 700,
    appendChild(c) { this.children.push(c); return c; },
    removeChild(c) { this.children = this.children.filter(x => x !== c); },
    insertBefore(c) { this.children.push(c); return c; },
    setAttribute(k, v) { this[k] = v; }, removeAttribute() {},
    getAttribute(k) { return this[k]; },
    focus() {}, blur() {}, select() {},
    querySelector(sel) {
      const want = String(sel).replace('#', '');
      return this.children.find(c => c.id === want) || null;
    },
    querySelectorAll() { return []; },
    addEventListener() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 900, height: 700 }; },
  };
  // the SVG the window draws into
  Object.defineProperty(el, 'firstChild', {
    get() { return el.innerHTML ? (el.__svg || (el.__svg = mkEl(id + '-svg'))) : null; }
  });
  return el;
}
global.document = {
  getElementById(id) { return els[id] || (els[id] = mkEl(id)); },
  createElement(t) { return mkEl('new-' + t); },
  createElementNS(_ns, t) { return mkEl('ns-' + t); },
  createTextNode(t) { return { nodeValue: String(t), textContent: String(t) }; },
  querySelectorAll() { return []; },
  addEventListener() {},
  body: mkEl('body'),
};
global.window = { addEventListener() {}, devicePixelRatio: 1 };
global.sent = [];
global.sketchup = new Proxy({}, {
  get: (_, name) => (...args) => global.sent.push({ name, args })
});

// ------------------------------------------------- (a) does it even parse?
const src = fs.readFileSync('sheet.js', 'utf8');
let api = null, boom = null;
try {
  api = (new Function(src +
    '\n; return { get:(n)=>eval(n), call:(n,...a)=>eval(n)(...a), set:(n,v)=>eval(n+" = v") };'))();
} catch (e) { boom = e; }
ok('THE SHEET WINDOW SCRIPT PARSES AND RUNS  <<< a broken one kills everything',
   !boom, boom && String(boom));
if (boom) { console.log('\n*** ' + fails + ' FAILED ***'); process.exit(1); }

// the pieces the label picker is built from
['loadSheet', 'hitText', 'eachText', 'textBox', 'openTextBar', 'closeTextBar',
 'paintTextPick', 'sendTextMark', 'hitSite', 'paintErase', 'showTextScale',
 'sendTextScale', 'render', 'sheetSVG', 'setMode'].forEach(function (fn) {
  ok('it defines ' + fn, typeof api.get(fn) === 'function', typeof api.get(fn));
});

// ------------------------------------------------- a sheet with real labels
// Shaped exactly like what push_all sends: a MODEL canvas seen through a view
// on the page, and the labels carrying the keys Ruby stamped on them.
const SHEET = {
  doc: {
    job_address: '15723 E La Belle St',
    canvases: [{
      name: 'MODEL',
      layers: [
        { name: 'ROOMS', visible: true, shapes: [
          { type: 'text', text: 'ROOM 2', x: 0, y: 0, h: 7, h0: 7, key: 'ROOMS|ROOM 2|1' },
          { type: 'text', text: '42 SF', x: 0, y: -12, h: 4.5, h0: 4.5, key: 'ROOMS|42 SF|1' } ] },
        { name: 'WINDOWS', visible: true, shapes: [
          { type: 'text', text: 'W101', x: 120, y: 60, h: 4.2, h0: 4.2, key: 'WINDOWS|W101|1' } ] },
        { name: 'SITE', visible: true, shapes: [
          { type: 'polyline', points: [[0, 200], [240, 200]], weight: 0.01 } ] },
        { name: 'WALLS', visible: true, shapes: [
          { type: 'line', x1: -200, y1: -200, x2: 200, y2: 200, weight: 0.02 } ] }
      ]
    }],
    pages: [{
      name: 'PLAN', width: 36, height: 24, kind: 'plan', sheet_number: 'A-101',
      views: [{ name: 'v', x: 1, y: 1, w: 30, h: 22, canvas: 'MODEL',
                scale: '1/4"', origin_x: 0, origin_y: 0, frame: [0.5, 0.5, 35, 23] }],
      layers: [{ name: 'TITLE', visible: true, shapes: [
        { type: 'text', text: 'A-101  FLOOR PLAN', x: 20, y: 0.7, h: 0.12, h0: 0.12,
          key: 'TITLE|A-101  FLOOR PLAN|1' } ] }]
    }]
  },
  state: {
    size: 'ARCH D', orientation: 'landscape', scale: '1/4"', hidden: [],
    origin_x: 0, origin_y: 0, active: 0, marks: [], images: [], open: {},
    sheet_number: 'A-101', sheet_title: 'FLOOR PLAN', site_count: 1,
    site_dropped: 0, tables_own_page: true,
    text_scale: { dims: 100, rooms: 100, tags: 100, tables: 100 },
    text_marks: {}
  },
  page_sizes: ['ARCH D'], scales: ['1/4"'], images: [], logo: null,
  bounds: [-200, -200, 240, 200]
};

const safe = n => { try { return api.get(n); } catch (e) { return undefined; } };
// his kind of sheet: a yard of loose lines, numbered so each can be told apart
const YARD = [];
for (let n = 0; n < 9; n++) YARD.push({ type: "polyline", points: [[n * 10, 200], [n * 10, 260]], weight: 0.01 });
const fresh = () => { const s = JSON.parse(JSON.stringify(SHEET)); s.doc.canvases[0].layers.find(l => l.name === "SITE").shapes = JSON.parse(JSON.stringify(YARD)); s.state.site_count = 9; return s; };
const site = () => api.get("DOC").canvases[0].layers.find(l => l.name === "SITE");
const firsts = () => site().shapes.map(s => s.points[0][0]);
const dropped = () => global.sent.filter(m => m.name === "drop_site_line").map(m => JSON.parse(m.args[0]));

ok("the window has the switch, and it is on", safe("FASTERASE") === true, safe("FASTERASE"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby owns the switch and sends it with the sheet",
   /USE_FAST_ERASE = true unless const_defined/.test(rb) && /fast_erase: USE_FAST_ERASE/.test(rb));

api.call("loadSheet", fresh());
api.call("setMode", "erase");
ok("nine lines on the sheet to start with", firsts().length === 9, firsts());

// ------------------------------------------------------------------ his sweep
global.sent.length = 0;
document.getElementById("sheetWrap").innerHTML = "";
api.call("eraseSweep", [{ kind: "site", i: 1 }, { kind: "site", i: 6 }, { kind: "site", i: 4 }, { kind: "site", i: 6 }]);
ok("THE LINES ARE OFF THE SHEET BEFORE RUBY HAS SAID A WORD  <<< THE RULE",
   JSON.stringify(firsts()) === JSON.stringify([0, 20, 30, 50, 70, 80]), firsts());
ok("and the sheet was drawn again without them, there and then",
   document.getElementById("sheetWrap").innerHTML.startsWith("<svg "));
const msg = dropped();
ok("Ruby is told once, for the whole sweep", msg.length === 1, msg.length);
ok("which lines went - each one once", JSON.stringify(msg[0].is.slice().sort()) === JSON.stringify([1, 4, 6]), msg[0].is);
ok("that the window has already taken them off", msg[0].quiet === true, msg[0]);
ok("and how many there were, so Ruby can tell if the two are out of step", msg[0].n === 9, msg[0].n);
ok("the count beside the button is right at once", api.get("STATE").site_count === 6, api.get("STATE").site_count);
ok("he is still holding the eraser", api.get("MODE") === "erase");
ok("nothing is left lit up from the line that went", api.get("ERA") === null && api.get("ERASWEEP") === null);

// the next sweep counts on the shortened sheet, like Ruby does
global.sent.length = 0;
api.call("eraseSweep", [{ kind: "site", i: 0 }]);
ok("a second sweep reads the shortened sheet", JSON.stringify(firsts()) === JSON.stringify([20, 30, 50, 70, 80]) &&
   dropped()[0].n === 6 && dropped()[0].is[0] === 0, [firsts(), dropped()[0]]);

// a number that is not on the sheet takes nothing with it
global.sent.length = 0;
api.call("eraseSweep", [{ kind: "site", i: 99 }]);
ok("a number that is not on the sheet takes nothing", firsts().length === 5, firsts());

// Ruby answering with a whole sheet (out of step) still puts everything right
api.call("loadSheet", fresh());
ok("if Ruby does send the whole sheet, the window takes it as the truth", firsts().length === 9);

// ------------------------------------------------------------------ the switch
const off = fresh(); off.fast_erase = false;
api.call("loadSheet", off);
global.sent.length = 0;
api.call("eraseSweep", [{ kind: "site", i: 2 }]);
ok("switched off: the window waits for Ruby, as before - the line is still there",
   firsts().length === 9 && dropped().length === 1 && dropped()[0].quiet === undefined, [firsts().length, dropped()[0]]);

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
