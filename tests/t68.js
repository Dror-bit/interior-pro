// t68 - Ctrl+Z brings back what was rubbed out (2026-10-07).
//
// The user: "אם מחקתי משהו ואני לוחץ קונטרול Z הוא צריך לחזור." Line 2 of the
// iron law in CLAUDE.md.
//
// The sheet window had no undo. A line rubbed out by mistake came back only
// with the button that puts back EVERYTHING ever rubbed out - and at the end of
// the list, so every number after it meant a different line.
//
// THE RULE, on the window side (rt267 pins Ruby):
//   One press takes back one thing he did - one sweep of the eraser, whatever
//   it crossed - and puts each line back at the number it had. Press again and
//   the sweep before that comes back. The same key takes back a change to the
//   hand-drawn dimensions and notes, because they all leave by one door.
// Pressed through the keyboard handler the window really registers.
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
const DIM = { t: "dim", x1: 0, y1: 0, x2: 100, y2: 0, off: 10 };
const NOTE = { t: "note", x: 50, y: 50, text: "pool", kx: 60, ky: 60, lx: 70, ly: 70 };
const fresh = () => { const s = JSON.parse(JSON.stringify(SHEET)); s.doc.canvases[0].layers.find(l => l.name === "SITE").shapes = JSON.parse(JSON.stringify(YARD)); s.state.site_count = 9;
  s.state.marks = [JSON.parse(JSON.stringify(DIM)), JSON.parse(JSON.stringify(NOTE))]; return s; };
const site = () => api.get("DOC").canvases[0].layers.find(l => l.name === "SITE");
const firsts = () => site().shapes.map(s => s.points[0][0]);
const msgs = name => global.sent.filter(m => m.name === name).map(m => JSON.parse(m.args[0]));

let wired = null;
try { (LISTEN.load || []).forEach(fn => fn({})); } catch (e) { wired = e; }
ok("the window wires up its keyboard without throwing", !wired && (LISTEN.keydown || []).length >= 1, wired && String(wired));
const press = (ev, target) => { let stopped = false;
  (LISTEN.keydown || []).forEach(fn => fn(Object.assign({ target: target || { tagName: "BODY", id: "" }, preventDefault() { stopped = true; }, stopPropagation() {} }, ev)));
  return stopped; };
const ctrlZ = () => press({ key: "z", code: "KeyZ", ctrlKey: true });

ok("the window has the switch, and it is on", safe("UNDOON") === true, safe("UNDOON"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby owns the switch and sends it with the sheet",
   /USE_SHEET_UNDO = true unless const_defined/.test(rb) && /undo: USE_SHEET_UNDO/.test(rb));

// ----------------------------------------------------------------- 1. HIS CASE
api.call("loadSheet", fresh());
api.call("setMode", "erase");
api.call("eraseSweep", [{ kind: "site", i: 1 }, { kind: "site", i: 6 }, { kind: "site", i: 4 }]);
ok("three lines rubbed out", JSON.stringify(firsts()) === JSON.stringify([0, 20, 30, 50, 70, 80]), firsts());
api.call("eraseSweep", [{ kind: "site", i: 0 }]);
ok("and then one more", JSON.stringify(firsts()) === JSON.stringify([20, 30, 50, 70, 80]), firsts());

global.sent.length = 0;
document.getElementById("sheetWrap").innerHTML = "";
ok("Ctrl+Z is taken by the window", ctrlZ() === true);
ok("CTRL+Z BRINGS BACK THE LAST LINE RUBBED OUT - AND ONLY THAT ONE  <<< THE RULE",
   JSON.stringify(firsts()) === JSON.stringify([0, 20, 30, 50, 70, 80]), firsts());
ok("it is back on the sheet he is looking at, there and then",
   document.getElementById("sheetWrap").innerHTML.startsWith("<svg "));
let u = msgs("undo_site_drop");
ok("Ruby is told which line, where it goes, and how many there were",
   u.length === 1 && u[0].items.length === 1 && u[0].items[0].i === 0 && u[0].n === 5 &&
   JSON.stringify(u[0].items[0].p) === JSON.stringify([[0, 200], [0, 260]]), u);

global.sent.length = 0;
ctrlZ();
ok("A SECOND CTRL+Z BRINGS BACK THE SWEEP BEFORE IT - ALL THREE, EACH IN ITS PLACE",
   JSON.stringify(firsts()) === JSON.stringify([0, 10, 20, 30, 40, 50, 60, 70, 80]), firsts());
u = msgs("undo_site_drop");
ok("as one message, with the three numbers they had",
   u.length === 1 && JSON.stringify(u[0].items.map(x => x.i)) === JSON.stringify([1, 4, 6]) && u[0].n === 6, u);
ok("he is still holding the eraser", api.get("MODE") === "erase");
ok("the count beside the button is right", api.get("STATE").site_count === 9);

global.sent.length = 0;
ctrlZ();
ok("a third Ctrl+Z, with nothing left to take back, changes nothing", firsts().length === 9 && msgs("undo_site_drop").length === 0);

// with the keyboard in Hebrew that key types a zayin
api.call("eraseSweep", [{ kind: "site", i: 3 }]);
press({ key: "\u05d6", code: "KeyZ", ctrlKey: true });
ok("with the keyboard in Hebrew the same key still undoes", firsts().length === 9, firsts());

// ------------------------------------------------- 2. the hand-drawn dimensions and notes
api.call("loadSheet", fresh());
api.call("setMode", "erase");
api.call("eraseSweep", [{ kind: "mark", i: 0 }]);
ok("a dimension rubbed out is gone", api.get("STATE").marks.length === 1 && api.get("STATE").marks[0].t === "note");
global.sent.length = 0;
ctrlZ();
ok("CTRL+Z BRINGS THE DIMENSION BACK, in its place in the list",
   api.get("STATE").marks.length === 2 && JSON.stringify(api.get("STATE").marks[0]) === JSON.stringify(DIM), api.get("STATE").marks);
ok("and Ruby is given the marks again, so the paper has it too", msgs("set_state").length === 1 &&
   msgs("set_state")[0].marks.length === 2);

// one sweep across a dimension AND two lines is one movement of the hand
api.call("eraseSweep", [{ kind: "mark", i: 1 }, { kind: "site", i: 2 }, { kind: "site", i: 7 }]);
ok("a sweep took a note and two lines", api.get("STATE").marks.length === 1 && firsts().length === 7);
ctrlZ();
ok("ONE Ctrl+Z brings back all of that sweep - the note and both lines",
   api.get("STATE").marks.length === 2 && JSON.stringify(firsts()) === JSON.stringify([0, 10, 20, 30, 40, 50, 60, 70, 80]),
   [api.get("STATE").marks.length, firsts()]);

// Delete on a picked dimension, and a dimension just drawn
api.call("setMode", "hand");
api.set("SEL", 0); api.call("dropMark");
ok("Delete took the picked dimension", api.get("STATE").marks.length === 1);
ctrlZ();
ok("Ctrl+Z brings back what Delete took", api.get("STATE").marks.length === 2);
api.get("STATE").marks.push({ t: "dim", x1: 5, y1: 5, x2: 50, y2: 5, off: 8 }); api.call("push");
ctrlZ();
ok("Ctrl+Z takes back a dimension he just drew", api.get("STATE").marks.length === 2, api.get("STATE").marks.length);
api.get("STATE").marks[0].off = 44; api.call("push");
ctrlZ();
ok("and puts a dimension he pulled back where it was", api.get("STATE").marks[0].off === 10, api.get("STATE").marks[0].off);

// ----------------------------------------------------------- 3. what must not happen
api.call("loadSheet", fresh());
api.call("setMode", "erase");
api.call("eraseSweep", [{ kind: "site", i: 2 }]);
press({ key: "z", code: "KeyZ", ctrlKey: true }, { tagName: "INPUT", id: "address" });
ok("typing in a box: Ctrl+Z there is the box's own undo, not the sheet's", firsts().length === 8, firsts().length);
press({ key: "z", code: "KeyZ" });
ok("z on its own does nothing", firsts().length === 8);
press({ key: "z", code: "KeyZ", ctrlKey: true, shiftKey: true });
ok("Ctrl+Shift+Z is left alone", firsts().length === 8);

// the list was read again behind the undo list (add what is selected, clear): the old numbers are not trusted
const reread = fresh(); reread.doc.canvases[0].layers.find(l => l.name === "SITE").shapes.length = 5;
api.call("loadSheet", reread);
global.sent.length = 0;
ctrlZ();
ok("after the lines are read again, an old rub-out is NOT put back on top of the wrong lines",
   firsts().length === 5 && msgs("undo_site_drop").length === 0, [firsts().length, msgs("undo_site_drop").length]);

// a plain refresh with the count we expect keeps the steps
api.call("loadSheet", fresh());
api.call("eraseSweep", [{ kind: "site", i: 2 }]);
const same = fresh(); same.doc.canvases[0].layers.find(l => l.name === "SITE").shapes.splice(2, 1);
api.call("loadSheet", same);                       // Ruby refreshing for some other reason
ctrlZ();
ok("a refresh that agrees with the window keeps the undo list", firsts().length === 9, firsts().length);

// ------------------------------------------------------------------------ the switch
const off = fresh(); off.undo = false;
api.call("loadSheet", off);
api.call("eraseSweep", [{ kind: "site", i: 2 }]);
ctrlZ();
ok("switched off: Ctrl+Z does nothing, as before", firsts().length === 8, firsts().length);

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
