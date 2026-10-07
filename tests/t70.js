// t70 - loose lines can be DRAWN on the sheet (2026-10-07).
//
// The user: "הוספת קווים ע"י ציור". Asked which way - one line with two clicks,
// or a running line - he said: "תעשה את שני האופציות, 1 קו אחד עם שני קליקים
// ואחת עם קו מתמשך."
//
// THE RULE:
//   the line tool     click, click: one line. The next click starts a new one.
//   the chain tool    every click carries on from the one before. Escape ends
//                     the run; so does coming back to where it started.
//   a drawn line      is a loose line like any other: on the END of the SITE
//                     layer, one message to Ruby, and the select arrow, Delete
//                     and the eraser reach it with nothing written for them.
// and the iron law in CLAUDE.md:
//   it locks on corners and ends (green), middles (cyan), along a line
//   (magenta), shows which, and the click lands on the point it showed;
//   Escape drops the half-drawn line and gives the arrow back;
//   Ctrl+Z takes the last drawn line off, one a press;
//   after a click the zoom, the place and the tool are where they were.
// Everything here goes through the handlers the window really hangs on the
// sheet (mousemove, mousedown, click) and the keyboard it really listens to.
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

// one whole click of a tool, the way the browser delivers it
const tap = (x, y, m) => { svg().onmousemove(ev(x, y, m)); svg().onmousedown(ev(x, y, m)); up(x, y, m); svg().onclick(ev(x, y, m)); };
const hover = (x, y) => svg().onmousemove(ev(x, y));
const S = (mx, my) => api.call("screenOf", mx, my);
const tapM = (mx, my, dx, dy) => { const q = S(mx, my); tap(q[0] + (dx || 0), q[1] + (dy || 0)); };
const hoverM = (mx, my, dx, dy) => { const q = S(mx, my); hover(q[0] + (dx || 0), q[1] + (dy || 0)); };
const n = () => site().shapes.length;
const last = () => site().shapes[n() - 1];
const info = () => document.getElementById("markinfo").textContent;
const hi = () => svg().children.find(c => c.id === "drawhi") || null;
const ring = () => { const g = hi(); return g ? (g.children.find(c => c.id === "ns-circle") || null) : null; };
const rubber = () => { const g = hi(); return g ? (g.children.find(c => c.id === "ns-line") || null) : null; };
const PTS = s => JSON.stringify(s.points);

ok("the window has the switch, and it is on", safe("LINEDRAW") === true, safe("LINEDRAW"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby owns the switch and sends it with the sheet",
   /USE_LINE_DRAW = true unless const_defined/.test(rb) && /line_draw: USE_LINE_DRAW/.test(rb));
const page = fs.readFileSync("sheet.html", "utf8");
ok("the window has BOTH buttons - one line, and a running line", /id="tline"/.test(page) && /id="tchain"/.test(page));
["drawSnap", "drawClick", "addSiteLine", "paintDraw", "eachSeg", "snapColor"].forEach(fn =>
  ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));

api.call("loadSheet", fresh());
const stage = document.getElementById("stage");
stage.scrollLeft = 120; stage.scrollTop = 80;

// ================================================================ 1. ONE LINE, TWO CLICKS
document.getElementById("tline").onclick();
ok("the line button puts the line tool in his hand, and looks pressed",
   api.get("MODE") === "line" && /on/.test(document.getElementById("tline").className) && !/on/.test(document.getElementById("thand").className),
   [api.get("MODE"), document.getElementById("tline").className]);
ok("the line under the tools says what to do", /1 לחץ איפה שהקו מתחיל/.test(info()), info());

global.sent.length = 0;
tapM(-350, 200);
ok("the first click draws nothing yet", n() === 9 && msgs("add_site_line").length === 0, n());
ok("...it is remembered, and he is told to click the end", JSON.stringify(api.get("PEND")) === "[-350,200]" && /2 עכשיו לחץ איפה שהקו נגמר/.test(info()),
   [api.get("PEND"), info()]);
hoverM(-250, 230);
ok("a line is pulled out from the first click to the mouse, before he clicks", !!rubber() && rubber().stroke === "#1f6feb", hi());
tapM(-250, 230);
ok("THE SECOND CLICK MAKES THE LINE  <<< THE RULE", n() === 10 && PTS(last()) === "[[-350,200],[-250,230]]", [n(), last()]);
ok("it is the same kind of shape as every other loose line",
   last().type === "polyline" && last().weight === site().shapes[0].weight && !last().closed && !last().fill, last());
ok("it is on the sheet he is looking at", /M[0-9. ]+L[0-9. ]+/.test(document.getElementById("sheetWrap").innerHTML) &&
   api.call("hitSite", ev(...S(-300, 215))) === 9, api.call("hitSite", ev(...S(-300, 215))));
let m = msgs("add_site_line");
ok("Ruby is told once: the two points, the quick way, and how many lines there were",
   m.length === 1 && JSON.stringify(m[0].p) === "[[-350,200],[-250,230]]" && m[0].quiet === true && m[0].n === 9, m);
ok("the count of lines on the sheet went up", api.get("STATE").site_count === 10, api.get("STATE").site_count);
ok("the line tool is still in his hand, with nothing half drawn", api.get("MODE") === "line" && api.get("PEND") === null,
   [api.get("MODE"), api.get("PEND")]);
ok("THE VIEW DID NOT MOVE: same zoom, same place", api.get("ZOOM") === null && stage.scrollLeft === 120 && stage.scrollTop === 80,
   [api.get("ZOOM"), stage.scrollLeft, stage.scrollTop]);

// the next two clicks are a NEW line, not a continuation
tapM(-150, 220); tapM(-50, 240);
ok("the line tool: the next two clicks are a line of their own", n() === 11 && PTS(last()) === "[[-150,220],[-50,240]]", last());

// twice on the same spot is not a line
tapM(50, 230); tapM(50, 230);
ok("two clicks on the same spot do not make a line", n() === 11 && JSON.stringify(api.get("PEND")) === "[50,230]", [n(), api.get("PEND")]);
// two quick clicks must not open the label panel either
let dbl = null; try { svg().ondblclick(ev(...S(0, 0))); } catch (e) { dbl = e; }
ok("two quick clicks while drawing do not open the label panel", !dbl && document.getElementById("textbar").className === "", [String(dbl), document.getElementById("textbar").className]);

// ================================================================ 2. ESCAPE
key("Escape");
ok("ESCAPE WITH A LINE HALF DRAWN: nothing is added", n() === 11, n());
ok("...the half-drawn line is forgotten", api.get("PEND") === null && api.get("DRAWSNAP") === null);
ok("...and he is back on the select arrow", api.get("MODE") === "hand" && /on/.test(document.getElementById("thand").className) && !/on/.test(document.getElementById("tline").className));
ok("nothing is left painted over the sheet", hi() === null, hi());

// ================================================================ 3. IT LOCKS, AND SHOWS WHERE
api.call("loadSheet", fresh());
document.getElementById("tline").onclick();
hoverM(-100, 100, 5, -4);                       // five pixels off the top end of line 3
ok("NEAR THE END OF A LINE IT LOCKS ON THE END", api.get("DRAWSNAP").kind === "end" && JSON.stringify(api.get("DRAWSNAP").p) === "[-100,100]", api.get("DRAWSNAP"));
ok("...and shows it with a GREEN ring, on that point", !!ring() && ring().stroke === "#2fbf5f" &&
   Math.abs(+ring().cx - S(-100, 100)[0]) < 0.2 && Math.abs(+ring().cy - S(-100, 100)[1]) < 0.2, ring());
hoverM(-100, 0, 4, 3);
ok("near the MIDDLE of a line it locks on the middle, with a CYAN ring",
   api.get("DRAWSNAP").kind === "mid" && JSON.stringify(api.get("DRAWSNAP").p) === "[-100,0]" && ring().stroke === "#00b8d4", [api.get("DRAWSNAP"), ring()]);
hoverM(-100, 50, 4, 0);                          // on the line, away from its end and its middle
ok("anywhere else ALONG a line it locks onto the line, with a MAGENTA ring",
   api.get("DRAWSNAP").kind === "edge" && api.get("DRAWSNAP").p[0] === -100 && Math.abs(api.get("DRAWSNAP").p[1] - 50) < 0.5 && ring().stroke === "#d63fd6",
   [api.get("DRAWSNAP"), ring()]);
hoverM(-350, 200);
ok("on empty paper there is NO ring - nothing is locked", api.get("DRAWSNAP").kind === null && ring() === null, [api.get("DRAWSNAP"), ring()]);
hoverM(200, 200, 3, -3);                         // the end of the WALL line
ok("it locks on the corners of walls too, not only on loose lines", api.get("DRAWSNAP").kind === "end" && JSON.stringify(api.get("DRAWSNAP").p) === "[200,200]", api.get("DRAWSNAP"));

// the click lands on the point the ring showed
hoverM(-100, 100, 5, -4);
const shown = JSON.stringify(api.get("DRAWSNAP").p);
tapM(-100, 100, 5, -4);
ok("THE CLICK LANDS ON THE POINT THE RING SHOWED - not on the mouse", JSON.stringify(api.get("PEND")) === shown, [api.get("PEND"), shown]);
tapM(100, 100, -4, 5);
ok("a line drawn from one end to another joins them EXACTLY", PTS(last()) === "[[-100,100],[100,100]]", last());
tapM(0, 100, 3, 3);                              // the middle of the line just drawn
ok("the line he just drew can be locked onto like any other", JSON.stringify(api.get("PEND")) === "[0,100]", api.get("PEND"));
key("Escape");

// ================================================================ 4. THE RUNNING LINE
api.call("loadSheet", fresh());
document.getElementById("tchain").onclick();
ok("the running-line button puts that tool in his hand", api.get("MODE") === "chain" && /on/.test(document.getElementById("tchain").className) &&
   !/on/.test(document.getElementById("tline").className), api.get("MODE"));
global.sent.length = 0;
tapM(-350, 200); tapM(-250, 230); tapM(-150, 200); tapM(-50, 230);
ok("THE RUNNING LINE: four clicks are three lines  <<< THE RULE", n() === 12, n());
const run = site().shapes.slice(9).map(PTS);
ok("each one starts exactly where the one before ended",
   JSON.stringify(run) === JSON.stringify(["[[-350,200],[-250,230]]", "[[-250,230],[-150,200]]", "[[-150,200],[-50,230]]"]), run);
m = msgs("add_site_line");
ok("Ruby is told of each, with the count as it grew", m.length === 3 && m.map(x => x.n).join() === "9,10,11" && m.every(x => x.quiet === true), m);
ok("the run is still going: the next line would start at the last click", JSON.stringify(api.get("PEND")) === "[-50,230]" && api.get("MODE") === "chain");
ok("and he is told how to stop", /Esc מסיים/.test(info()), info());
hoverM(50, 200);
ok("the line to the next point follows the mouse", !!rubber());
key("Escape");
ok("ESCAPE ENDS THE RUN: the three lines stay, nothing more is added", n() === 12 && api.get("PEND") === null && api.get("MODE") === "hand", [n(), api.get("MODE")]);

// coming back to where it started closes the shape and ends the run
api.call("loadSheet", fresh());
document.getElementById("tchain").onclick();
tapM(-350, 200); tapM(-250, 260); tapM(-150, 200);
tapM(-350, 200, 4, -3);                          // back near the first point
ok("back at the first point the shape CLOSES exactly on it", n() === 12 && PTS(last()) === "[[-150,200],[-350,200]]", last());
ok("...and the run is over, with the tool still in his hand", api.get("PEND") === null && api.get("MODE") === "chain", [api.get("PEND"), api.get("MODE")]);
tapM(100, 220); tapM(200, 240);
ok("the next clicks start a new run", n() === 13 && PTS(last()) === "[[100,220],[200,240]]", last());
key("Escape");

// ================================================================ 5. CTRL+Z
api.call("loadSheet", fresh());
document.getElementById("tchain").onclick();
tapM(-350, 200); tapM(-250, 230); tapM(-150, 200);
global.sent.length = 0;
key("z", { code: "KeyZ", ctrlKey: true });
ok("CTRL+Z TAKES THE LAST DRAWN LINE OFF  <<< THE RULE", n() === 10 && PTS(last()) === "[[-350,200],[-250,230]]", [n(), last()]);
m = msgs("undo_site_add");
ok("Ruby is told which line came off, and how many there were",
   m.length === 1 && m[0].n === 11 && m[0].items.length === 1 && m[0].items[0].i === 10 && JSON.stringify(m[0].items[0].p) === "[[-250,230],[-150,200]]", m);
ok("nothing is left half drawn after it", api.get("PEND") === null);
key("z", { code: "KeyZ", ctrlKey: true });
ok("a second press takes the one before", n() === 9 && api.get("STATE").site_count === 9, n());
ok("the nine lines of the yard are untouched", JSON.stringify(xs()) === JSON.stringify([-400, -300, -200, -100, 0, 100, 200, 300, 400]), xs());

// drawing and rubbing out, taken back in the order they were done
api.call("loadSheet", fresh());
document.getElementById("tline").onclick();
tapM(-350, 200); tapM(-250, 230);
api.call("eraseSweep", [{ kind: "site", i: 2 }]);            // then a yard line is rubbed out
ok("one drawn, one rubbed out: nine on the sheet, the drawn one last", n() === 9 && PTS(last()) === "[[-350,200],[-250,230]]", n());
key("z", { code: "KeyZ", ctrlKey: true });
ok("Ctrl+Z brings the rubbed-out line back first", n() === 10 && xs()[2] === -200, xs());
key("z", { code: "KeyZ", ctrlKey: true });
ok("and the next press takes the drawn line off", n() === 9 && JSON.stringify(xs()) === JSON.stringify([-400, -300, -200, -100, 0, 100, 200, 300, 400]), xs());

// ================================================================ 6. A DRAWN LINE IS A LINE LIKE ANY OTHER
api.call("loadSheet", fresh());
document.getElementById("tline").onclick();
tapM(150, 230); tapM(250, 260);         // (away from the dimension: a mark wins a click near it)
api.call("setMode", "hand");
click(...S(200, 245));
ok("the select arrow picks a drawn line", JSON.stringify(picked()) === "[9]", picked());
global.sent.length = 0;
key("Delete");
ok("and Delete takes it, the way it takes any loose line", n() === 9 && msgs("drop_site_line").length === 1 && msgs("drop_site_line")[0].is[0] === 9, msgs("drop_site_line"));

// ================================================================ 7. THE AWKWARD SHEETS
// the loose-line layer is switched off
let sw = fresh(); sw.state.hidden = ["SITE"];
api.call("loadSheet", sw);
document.getElementById("tline").onclick();
global.sent.length = 0;
tapM(-350, 200); tapM(-250, 230);
ok("with the SITE layer switched off nothing is drawn where he cannot see it",
   api.get("DOC").canvases[0].layers.find(l => l.name === "SITE").shapes.length === 9 && msgs("add_site_line").length === 0);
ok("...and he is told why", /SITE כבויה/.test(info()), info());

// a sheet with no loose lines at all: there is no layer to add to
let bare = fresh(); bare.doc.canvases[0].layers = bare.doc.canvases[0].layers.filter(l => l.name !== "SITE"); bare.state.site_count = 0;
api.call("loadSheet", bare);
document.getElementById("tline").onclick();
global.sent.length = 0;
tapM(-350, 200); tapM(-250, 230);
m = msgs("add_site_line");
ok("on a sheet with no loose lines Ruby is asked to make the layer and send the sheet",
   m.length === 1 && JSON.stringify(m[0].p) === "[[-350,200],[-250,230]]" && m[0].quiet !== true, m);
// Ruby answers with the sheet, the line on it
let back = fresh(); back.doc.canvases[0].layers.find(l => l.name === "SITE").shapes = [{ type: "polyline", points: [[-350, 200], [-250, 230]], closed: false, weight: 0.01 }];
back.state.site_count = 1;
api.call("loadSheet", back);
ok("the tool is still in his hand when the sheet comes back", api.get("MODE") === "line");
global.sent.length = 0;
key("z", { code: "KeyZ", ctrlKey: true });
m = msgs("undo_site_add");
ok("and Ctrl+Z takes that first line off too", n() === 0 && m.length === 1 && m[0].n === 1 && m[0].items[0].i === 0, [n(), m]);

// a sheet arriving from Ruby in the middle of a run does not cut the run
api.call("loadSheet", fresh());
document.getElementById("tchain").onclick();
tapM(-350, 200); tapM(-250, 230);
let again = fresh(); again.doc.canvases[0].layers.find(l => l.name === "SITE").shapes.push({ type: "polyline", points: [[-350, 200], [-250, 230]], closed: false, weight: 0.01 });
again.state.site_count = 10;
api.call("loadSheet", again);
tapM(-150, 200);
ok("a sheet sent again in the middle of a run does not cut the run", n() === 11 && PTS(last()) === "[[-250,230],[-150,200]]", last());
key("Escape");

// ================================================================ the switch
let off = fresh(); off.line_draw = false;
api.call("loadSheet", off);
ok("switched off: the two buttons are not shown", document.getElementById("tools2").style.display === "none", document.getElementById("tools2").style.display);
document.getElementById("tline").onclick();
ok("switched off: the tool cannot be picked up", api.get("MODE") === "hand", api.get("MODE"));
api.call("loadSheet", fresh());
ok("switched on again the buttons are back", document.getElementById("tools2").style.display === "");

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
