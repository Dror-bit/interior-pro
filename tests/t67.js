// t67 - Escape gets him out of whatever he is in the middle of (2026-10-07).
//
// The user: "צריכה להיות אופציה שאם אני מסמן משהו למחיקה או כל פעולה אחרת בכל
// התוסף הזה ואני לוחץ אסקייפ זה יוצא לי אוטומטית מהפעולה שאני עושה."
// It is line 1 of the iron law in CLAUDE.md.
//
// What Escape did before, read from the code: it forgot a half-drawn dimension
// and what was picked, and LEFT HIM IN THE SAME TOOL. And it did not stop the
// eraser - a sweep already under way kept its list, and letting go of the mouse
// rubbed all of it out. Escape pressed to save the lines; the lines gone anyway.
//
// THE RULE: everything half done is dropped, never finished, and he is back on
// the select arrow. Pressed through the real keyboard handler the window
// registers - not by calling a function on the side.
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
const LISTEN = {};
global.window = { addEventListener(type, fn) { (LISTEN[type] = LISTEN[type] || []).push(fn); }, devicePixelRatio: 1 };
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
const YARD = [];
for (let n = 0; n < 9; n++) YARD.push({ type: "polyline", points: [[n * 10, 200], [n * 10, 260]], weight: 0.01 });
const fresh = () => { const s = JSON.parse(JSON.stringify(SHEET)); s.doc.canvases[0].layers.find(l => l.name === "SITE").shapes = JSON.parse(JSON.stringify(YARD)); s.state.site_count = 9;
  s.state.marks = [{ t: "dim", x1: 0, y1: 0, x2: 100, y2: 0, off: 10 }]; return s; };
const site = () => api.get("DOC").canvases[0].layers.find(l => l.name === "SITE");
const dropped = () => global.sent.filter(m => m.name === "drop_site_line");
const pushed = () => global.sent.filter(m => m.name === "set_state");

// the window wires its keys up when it has loaded - let it
let wired = null;
try { (LISTEN.load || []).forEach(fn => fn({})); } catch (e) { wired = e; }
ok("the window wires up its keyboard without throwing", !wired && (LISTEN.keydown || []).length >= 1, wired && String(wired));
const press = (key, target) => { let stopped = false;
  (LISTEN.keydown || []).forEach(fn => fn({ key, code: key, target: target || { tagName: "BODY", id: "" }, preventDefault() { stopped = true; }, stopPropagation() {} }));
  return stopped; };
const letGo = () => (LISTEN.mouseup || []).forEach(fn => fn({ clientX: 0, clientY: 0 }));

ok("the window has the switch, and it is on", safe("ESCEXITS") === true, safe("ESCEXITS"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby owns the switch and sends it with the sheet",
   /USE_ESCAPE_EXITS = true unless const_defined/.test(rb) && /escape_exits: USE_ESCAPE_EXITS/.test(rb));

// ----------------------------------------------------------- 1. HIS CASE: the eraser
api.call("loadSheet", fresh());
api.call("setMode", "erase");
api.set("ERASWEEP", [{ kind: "site", i: 1 }, { kind: "site", i: 4 }, { kind: "site", i: 6 }]);   // three lines lit up, mouse still down
global.sent.length = 0;
press("Escape");
letGo();                                             // he lets go of the mouse afterwards
ok("ESCAPE IN THE MIDDLE OF A SWEEP: NOTHING IS RUBBED OUT  <<< THE RULE",
   site().shapes.length === 9 && dropped().length === 0, [site().shapes.length, dropped().length]);
ok("and he is back on the select arrow, out of the eraser", api.get("MODE") === "hand", api.get("MODE"));
ok("nothing is left lit up", api.get("ERA") === null && api.get("ERASWEEP") === null);
ok("the select button is the one that looks pressed",
   /on/.test(document.getElementById("thand").className) && !/on/.test(document.getElementById("terase").className),
   [document.getElementById("thand").className, document.getElementById("terase").className]);

// the eraser doing nothing in particular: Escape still puts it down
api.call("setMode", "erase");
press("Escape");
ok("Escape with the eraser just in his hand puts the eraser down", api.get("MODE") === "hand");

// ------------------------------------------------------- 2. half a dimension, half a note
api.call("setMode", "dim");
api.set("PEND", [0, 0]); api.set("PEND2", [50, 0]);
const before = api.get("STATE").marks.length;
press("Escape");
ok("half a dimension: the clicks are forgotten, nothing is added", api.get("PEND") === null && api.get("PEND2") === null &&
   api.get("STATE").marks.length === before);
ok("and he is out of the dimension tool", api.get("MODE") === "hand", api.get("MODE"));

api.call("setMode", "note");
api.set("PEND", [0, 0]); api.set("PEND2", [20, 20]); api.set("PEND3", [40, 20]);
document.getElementById("notebar").className = "on";
press("Escape");
ok("a note with its box open: the box closes, no note is added, out of the tool",
   document.getElementById("notebar").className === "" && api.get("PEND") === null &&
   api.get("STATE").marks.length === before && api.get("MODE") === "hand");

// ---------------------------------------------------------- 3. something in the hand
api.call("setMode", "hand");
const m0 = JSON.parse(JSON.stringify(api.get("STATE").marks[0]));
api.set("SEL", 0);
api.set("CARRY", { i: 0, part: "all", at: [0, 0], snap: JSON.parse(JSON.stringify(m0)) });
api.get("STATE").marks[0].x1 = 500; api.get("STATE").marks[0].x2 = 600;          // carried a long way off
press("Escape");
ok("a dimension being carried goes back where it was picked up",
   JSON.stringify(api.get("STATE").marks[0]) === JSON.stringify(m0) && api.get("CARRY") === null, api.get("STATE").marks[0]);
ok("and nothing is left picked", api.get("SEL") === null && api.get("SELS").length === 0);

// ------------------------------------------------------------- 4. the plan being slid
api.get("STATE").origin_x = 10; api.get("STATE").origin_y = 20;
api.set("DRAG", { x: 0, y: 0, ox: 10, oy: 20, pan: false, sl: 0, st: 0 });
api.get("STATE").origin_x = 400; api.get("STATE").origin_y = -300;                 // dragged
global.sent.length = 0;
press("Escape");
letGo();
ok("the plan being slid across the sheet goes back where it was",
   api.get("STATE").origin_x === 10 && api.get("STATE").origin_y === 20 && api.get("DRAG") === null,
   [api.get("STATE").origin_x, api.get("STATE").origin_y]);
ok("and the abandoned slide is not saved", pushed().length === 0, pushed().length);

// a rubber band
api.set("BAND", { x0: 0, y0: 0, x1: 50, y1: 50, moved: true });
press("Escape"); letGo();
ok("a rubber band is dropped and picks nothing", api.get("BAND") === null && api.get("SELS").length === 0);

// --------------------------------------------------------------- 5. what must not change
api.call("setMode", "erase");
press("Escape", { tagName: "INPUT", id: "address" });
ok("typing in a box: Escape there does not throw his tool away", api.get("MODE") === "erase", api.get("MODE"));
ok("Escape is swallowed by the window when it acts - it does not fall through", press("Escape") === true);
api.call("setMode", "dim");
press(" ");
ok("the space bar still picks up the arrow, as it always did", api.get("MODE") === "hand");

// ------------------------------------------------------------------------ the switch
const off = fresh(); off.escape_exits = false;
api.call("loadSheet", off);
api.call("setMode", "dim");
api.set("PEND", [0, 0]);
press("Escape");
ok("switched off: Escape forgets the half-drawn thing but leaves him in the tool, as before",
   api.get("PEND") === null && api.get("MODE") === "dim", api.get("MODE"));

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
