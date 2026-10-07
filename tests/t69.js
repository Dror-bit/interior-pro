// t69 - loose lines can be picked, several at once, and deleted together
// (2026-10-07).
//
// The user: "בחירה של קווים גם עם שיפט ואז יכולת מחיקה של כולם ביחד."
//
// Until now the only thing that could touch a loose line was the eraser, and a
// sweep of the eraser is a commitment - what it crosses is gone. Picking is
// the other way: gather, look at what is lit up, then Delete.
//
// THE RULE:
//   click a line                 it is picked, the rest are let go
//   Shift+click                  it joins what is picked, or leaves it
//   rubber band, left to right   every line wholly inside
//   rubber band, right to left   every line the box touches (SketchUp's rule)
//   Delete                       all of them at once - one message to Ruby, one Ctrl+Z
//   Escape                       lets go
// Every one of these is done here with the mouse and the keyboard the window
// really listens to: the handlers hookDrag hangs on the sheet and the ones the
// window registers when it loads.
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
// nine upright lines, 100 inches apart, numbered 0..8 left to right
const YARD = [];
for (let n = 0; n < 9; n++) YARD.push({ type: "polyline", points: [[-400 + n * 100, -100], [-400 + n * 100, 100]], weight: 0.01 });
const DIM = { t: "dim", x1: -400, y1: 250, x2: -300, y2: 250, off: 20 };
const fresh = () => { const s = JSON.parse(JSON.stringify(SHEET)); s.doc.canvases[0].layers.find(l => l.name === "SITE").shapes = JSON.parse(JSON.stringify(YARD)); s.state.site_count = 9;
  s.state.marks = [JSON.parse(JSON.stringify(DIM))]; s.bounds = [-500, -300, 500, 300]; return s; };
const site = () => api.get("DOC").canvases[0].layers.find(l => l.name === "SITE");
const xs = () => site().shapes.map(s => s.points[0][0]);
const msgs = name => global.sent.filter(m => m.name === name).map(m => JSON.parse(m.args[0]));
const picked = () => api.get("SSEL").slice().sort((a, b) => a - b);

let wired = null;
try { (LISTEN.load || []).forEach(fn => fn({})); } catch (e) { wired = e; }
ok("the window wires itself up without throwing", !wired && (LISTEN.keydown || []).length >= 1, wired && String(wired));

// ---- a mouse and a keyboard, going through the window's own handlers
const svg = () => document.getElementById("sheetWrap").firstChild;
const ev = (x, y, m) => Object.assign({ clientX: x, clientY: y, button: 0, shiftKey: false, altKey: false, ctrlKey: false,
  target: { tagName: "svg", id: "" }, preventDefault() {}, stopPropagation() {} }, m || {});
const down = (x, y, m) => svg().onmousedown(ev(x, y, m));
const move = (x, y, m) => (LISTEN.mousemove || []).forEach(fn => fn(ev(x, y, m)));
const up   = (x, y, m) => (LISTEN.mouseup || []).forEach(fn => fn(ev(x, y, m)));
const click = (x, y, m) => { down(x, y, m); up(x, y, m); };
const drag  = (x0, y0, x1, y1, m) => { down(x0, y0, m); move((x0 + x1) / 2, (y0 + y1) / 2, m); move(x1, y1, m); up(x1, y1, m); };
const key = (k, m) => (LISTEN.keydown || []).forEach(fn => fn(Object.assign({ key: k, code: k, target: { tagName: "BODY", id: "" }, preventDefault() {}, stopPropagation() {} }, m || {})));
const at = (n, yy) => api.call("screenOf", -400 + n * 100, yy === undefined ? 0 : yy);     // on line n

ok("the window has the switch, and it is on", safe("LINEPICK") === true, safe("LINEPICK"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby owns the switch and sends it with the sheet",
   /USE_LINE_PICK = true unless const_defined/.test(rb) && /line_pick: USE_LINE_PICK/.test(rb));

api.call("loadSheet", fresh());
api.call("setMode", "hand");
ok("the nine lines are far enough apart on the screen to tell apart", at(1)[0] - at(0)[0] > 30, at(1)[0] - at(0)[0]);

// ------------------------------------------------------------------ 1. a click
click(...at(3));
ok("A CLICK ON A LINE PICKS IT  <<< THE RULE", JSON.stringify(picked()) === "[3]", picked());
ok("and it is drawn in blue over itself", /id="sitepick"[^>]*stroke="#1f6feb"/.test(document.getElementById("sheetWrap").innerHTML));
ok("the line under the window tells him what he can do now", /קו נבחר/.test(document.getElementById("markinfo").textContent),
   document.getElementById("markinfo").textContent);
click(...at(6));
ok("a click on another line picks that one instead", JSON.stringify(picked()) === "[6]", picked());

// ---------------------------------------------------------------- 2. Shift+click
click(...at(3), { shiftKey: true });
ok("SHIFT+CLICK ADDS A LINE TO WHAT IS PICKED", JSON.stringify(picked()) === "[3,6]", picked());
click(...at(8), { shiftKey: true });
ok("and another", JSON.stringify(picked()) === "[3,6,8]", picked());
click(...at(6), { shiftKey: true });
ok("Shift+click on a picked line lets go of just that one", JSON.stringify(picked()) === "[3,8]", picked());
ok("the count says so", /2 קווים נבחרו/.test(document.getElementById("markinfo").textContent), document.getElementById("markinfo").textContent);

// Shift+DRAG is still the way to slide the view, and picks nothing
const stage = document.getElementById("stage");
stage.scrollLeft = 100; stage.scrollTop = 100;
const p3 = at(3);
drag(p3[0], p3[1], p3[0] - 60, p3[1] - 40, { shiftKey: true });
ok("Shift+DRAG still slides the view, as it always did", stage.scrollLeft === 160 && stage.scrollTop === 140, [stage.scrollLeft, stage.scrollTop]);
ok("and a drag is not a click - what was picked is untouched", JSON.stringify(picked()) === "[3,8]", picked());

// ------------------------------------------------------------- 3. empty paper, Escape
const empty = api.call("screenOf", -450, 0);
click(empty[0], empty[1]);
ok("a click on empty paper lets go of everything", picked().length === 0, picked());
click(...at(2)); click(...at(4), { shiftKey: true });
key("Escape");
ok("Escape lets go of everything", picked().length === 0 && api.get("MODE") === "hand", picked());

// ------------------------------------------------------------------ 4. the rubber band
let a = api.call("screenOf", -350, 150), b = api.call("screenOf", -50, -150);     // round lines 1, 2, 3 completely
drag(a[0], a[1], b[0], b[1]);
ok("A RUBBER BAND, LEFT TO RIGHT, PICKS THE LINES WHOLLY INSIDE IT", JSON.stringify(picked()) === "[1,2,3]", picked());
a = api.call("screenOf", 150, 30); b = api.call("screenOf", 350, -30);              // a low box across lines 6 and 7
drag(a[0], a[1], b[0], b[1]);
ok("left to right, a box that only CROSSES lines picks none of them", picked().length === 0, picked());
drag(b[0], b[1], a[0], a[1]);
ok("RIGHT TO LEFT, THE SAME BOX PICKS EVERY LINE IT TOUCHES - SketchUp's rule", JSON.stringify(picked()) === "[6,7]", picked());
a = api.call("screenOf", -450, 300); b = api.call("screenOf", -250, -150);         // lines 0, 1 and the dimension above them
drag(a[0], a[1], b[0], b[1]);
ok("a band over lines AND a dimension picks both kinds", JSON.stringify(picked()) === "[0,1]" && api.get("SELS").length === 1,
   [picked(), api.get("SELS")]);

// ------------------------------------------------------------------------ 5. Delete
global.sent.length = 0;
key("Delete");
ok("DELETE TAKES EVERYTHING PICKED AT ONCE - the two lines", JSON.stringify(xs()) === JSON.stringify([-200, -100, 0, 100, 200, 300, 400]), xs());
ok("...and the dimension that was picked with them", api.get("STATE").marks.length === 0, api.get("STATE").marks.length);
const d = msgs("drop_site_line");
ok("Ruby is told once, the quick way, with both numbers",
   d.length === 1 && d[0].quiet === true && d[0].n === 9 && JSON.stringify(d[0].is.slice().sort()) === "[0,1]", d);
ok("nothing is left picked", picked().length === 0 && api.get("SELS").length === 0 && api.get("SEL") === null);

key("z", { code: "KeyZ", ctrlKey: true });
ok("ONE CTRL+Z BRINGS ALL OF IT BACK - both lines and the dimension",
   xs().length === 9 && xs()[0] === -400 && xs()[1] === -300 && api.get("STATE").marks.length === 1, [xs(), api.get("STATE").marks.length]);

// a dimension on its own is still deleted the way it always was
api.call("setMode", "hand");
api.set("SEL", 0); api.set("SELS", []);
key("Delete");
ok("Delete on a picked dimension alone still works", api.get("STATE").marks.length === 0);
key("z", { code: "KeyZ", ctrlKey: true });

// ------------------------------------------------- 6. the numbers never go stale
click(...at(5));
api.call("setMode", "erase");
ok("picking up another tool lets go of the lines", picked().length === 0);
api.call("setMode", "hand");
click(...at(5));
api.call("loadSheet", fresh());
ok("a new sheet from Ruby lets go of them - the numbers belonged to the old one", picked().length === 0);
click(...at(5));
api.call("eraseSweep", [{ kind: "site", i: 0 }]);
ok("a rub-out lets go of them - every number after it has moved", picked().length === 0);

// a click on a dimension picks the dimension, not a line under it
api.call("loadSheet", fresh());
api.call("setMode", "hand");
click(...at(5));               // (not line 4: the room name sits on it, and a click there picks the name)
ok("a line is picked, ready for the next check", JSON.stringify(picked()) === "[5]", picked());
const dl = api.call("dimLine", api.get("STATE").marks[0]);
const dm = api.call("screenOf", (dl[0] + dl[2]) / 2, (dl[1] + dl[3]) / 2);
down(dm[0], dm[1]); up(dm[0], dm[1]);
ok("a click on a dimension picks the dimension and lets go of the lines", picked().length === 0 && api.get("SEL") === 0, [picked(), api.get("SEL")]);

// ------------------------------------------------------------------------ the switch
const off = fresh(); off.line_pick = false;
api.call("loadSheet", off);
api.call("setMode", "hand");
click(...at(3));
ok("switched off: a click on a line picks nothing, as before", picked().length === 0, picked());
a = api.call("screenOf", -350, 150); b = api.call("screenOf", -50, -150);
drag(a[0], a[1], b[0], b[1]);
ok("switched off: nor does a rubber band", picked().length === 0, picked());

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
