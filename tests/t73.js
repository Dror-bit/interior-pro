// t73 - a SIDE of the drawing's box CUTS the drawing (2026-10-07), the window's side.
//
// The user, on what he likes in Rayon: "את הקופסה אני יכול להגדיל ולהקטין בעיקר
// מהפינות, אני יכול לחתוך מהצלעות..." - and, earlier the same day, with two
// pictures of it: "אני גם יכול לבחור מה יראו מהתמונה או מהשרטוט - חיתוך."
//
// THE RULE:
//   a side       only that side of the box moves. THE DRAWING STAYS EXACTLY
//                WHERE IT IS ON THE SHEET - every line on the spot of the paper
//                it was on - and less of it, or more of it, is seen.
//   its size     is not touched: a drawing at 1/4" is still at 1/4".
//   the margins  the side cannot pass them, and cannot come closer than an inch
//                to the side across from it.
//   Escape puts a half-done cut back; Ctrl+Z takes the last one back; Ruby is
//   told once, on letting go; the zoom and the place stay.
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

const S = (mx, my) => api.call("screenOf", mx, my);
const near = (a, b, tol) => Math.abs(a - b) < (tol === undefined ? 1e-6 : tol);
const el = id => document.getElementById(id);
const V = () => api.get("PAGE").views[0];
const box = () => { const v = V(); return [v.x, v.y, v.w, v.h]; };
const sameBox = (a, b, tol) => a.every((n, i) => near(n, b[i], tol === undefined ? 1e-6 : tol));
const K = () => api.get("VIEW").k;
const ST = () => api.get("STATE");
// hold a handle, move the mouse by (dx, dy) pixels in two steps, and (unless told not to) let go
const pull = (id, dx, dy, keep) => { const c = [300, 300];
  el(id).onmousedown(ev(c[0], c[1])); move(c[0] + dx / 2, c[1] + dy / 2); move(c[0] + dx, c[1] + dy); if (!keep) up(c[0] + dx, c[1] + dy); return [c[0] + dx, c[1] + dy]; };
const states = () => msgs("set_state");
{ const sc = el("scale"); let h = ""; Object.defineProperty(sc, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") sc.children = []; } }); }
const sheet = () => { const s = fresh(); s.doc.pages[0].view_area = [1, 1, 30, 22]; return s; };
// spots of the house, and where each one is on the screen right now
const SPOTS = [[0, 0], [-400, 100], [137.25, -12.5], [300, -250]];
const where = () => SPOTS.map(p => S(p[0], p[1]));
const stayed = (a, b, tol) => a.every((p, i) => near(p[0], b[i][0], tol === undefined ? 1e-6 : tol) && near(p[1], b[i][1], tol === undefined ? 1e-6 : tol));
const SF = 0.25 / 12;                 // the scale from the list, paper inches to the model inch

ok("the window has the switch, and it is on", safe("CROPON") === true, safe("CROPON"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby has the switch, and sends it with the sheet", /USE_BOX_CROP = true/.test(rb) && /box_crop: USE_BOX_CROP/.test(rb));
const page = fs.readFileSync("sheet.html", "utf8");
ok("each side has a bar in its middle to hold it by, drawn by the style sheet", /#boxe-n::after, #boxe-s::after/.test(page) && /#boxe-w::after, #boxe-e::after/.test(page));
ok("it defines dropBox", typeof safe("dropBox") === "function");

api.call("loadSheet", sheet());
api.call("setMode", "hand");
ok("a side says which way it goes: up-and-down for the top and bottom, left-and-right for the sides",
   el("boxe-n").style.cursor === "ns-resize" && el("boxe-s").style.cursor === "ns-resize" && el("boxe-w").style.cursor === "ew-resize" && el("boxe-e").style.cursor === "ew-resize",
   ["n", "s", "w", "e"].map(d => el("boxe-" + d).style.cursor));
ok("and the grip still says \"move\"", el("boxmove").style.cursor === "move");

// ================================================================ 1. the right side, pulled in ten inches
const stage = document.getElementById("stage");
stage.scrollLeft = 120; stage.scrollTop = 80;
global.sent.length = 0;
const k0 = K(), w0 = where();
const held = pull("boxe-e", -10 * k0, 33, true);
ok("WHILE HE PULLS THE RIGHT SIDE ONLY THAT SIDE MOVES  <<< THE RULE", sameBox(box(), [1, 1, 20, 22]), box());
ok("THE DRAWING STAYS EXACTLY WHERE IT IS ON THE SHEET  <<< THE RULE", stayed(where(), w0), [where(), w0]);
ok("Ruby is not told on every step", states().length === 0, states().length);
up(held[0], held[1]);
let m = states();
ok("ON LETTING GO Ruby is told once: the box, and which point of the house is now in its middle",
   m.length === 1 && sameBox(m[0].view_box, [1, 1, 20, 22]) && near(m[0].origin_x, -5 / SF, 1e-6) && near(m[0].origin_y, 0, 1e-9), m.map(x => [x.view_box, x.origin_x, x.origin_y]));
ok("ITS SIZE IS NOT TOUCHED: still the scale from the list, and the list says so",
   !ST().scale_f && near(api.call("scaleFactor", ST().scale), SF, 1e-12) && el("scale").children.length === 1, [ST().scale_f, el("scale").children.length]);
ok("a hundred inches of house is as long on the sheet as it was", near(S(100, 0)[0] - S(0, 0)[0], 100 * SF * K(), 1e-6));
ok("THE VIEW DID NOT MOVE: same zoom, same place, same tool", api.get("ZOOM") === null && stage.scrollLeft === 120 && stage.scrollTop === 80 && api.get("MODE") === "hand");
ok("the mouse still lands on the right spot in the house",
   SPOTS.every(p => { const q = S(p[0], p[1]); const b = api.call("atMouse", ev(q[0], q[1])); return near(b[0], p[0], 1e-6) && near(b[1], p[1], 1e-6); }));
ok("the squares and the bars went with the box",
   near(parseFloat(el("boxc-se").style.left), 21 * K(), 0.06) && near(parseFloat(el("boxe-e").style.left), 21 * K() - 4, 0.06), [el("boxc-se").style.left, el("boxe-e").style.left]);
ok("none of it is written into the drawing", document.getElementById("sheetWrap").innerHTML.indexOf("boxe") < 0);

// ================================================================ 2. the other three sides
pull("boxe-w", 3 * K(), -20);
ok("the left side: only it moves", sameBox(box(), [4, 1, 17, 22]), box());
pull("boxe-n", 17, 2 * K());
ok("the top: only it moves", sameBox(box(), [4, 1, 17, 20]), box());
pull("boxe-s", -9, -1.5 * K());
ok("the bottom: only it moves", sameBox(box(), [4, 2.5, 17, 18.5]), box());
ok("AFTER FOUR CUTS EVERY LINE IS STILL ON THE SPOT IT WAS ON", stayed(where(), w0), [where(), w0]);
ok("and the drawing is still at its scale", !ST().scale_f && near(api.call("scaleFactor", ST().scale), SF, 1e-12));
// nothing snaps
pull("boxe-e", -37.3, 0);
ok("NOTHING SNAPS: the side stays exactly where he left it", near(V().w, 17 - 37.3 / K(), 1e-9), V().w);

// ================================================================ 3. the margins, and an inch at least
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxe-e", -10 * K(), 0); pull("boxe-w", 5 * K(), 0); pull("boxe-n", 0, 6 * K()); pull("boxe-s", 0, -4 * K());
ok("(cut on all four sides)", sameBox(box(), [6, 5, 15, 12]), box());
const w1 = where();
pull("boxe-e", 9000, 0);
ok("PULLED OUT AS FAR AS HE LIKES, A SIDE STOPS AT THE MARGIN: right", sameBox(box(), [6, 5, 25, 12]), box());
pull("boxe-w", -9000, 0);
ok("left", sameBox(box(), [1, 5, 30, 12]), box());
pull("boxe-n", 0, -9000);
ok("top", sameBox(box(), [1, 5, 30, 18]), box());
pull("boxe-s", 0, 9000);
ok("bottom", sameBox(box(), [1, 1, 30, 22]), box());
ok("and the drawing never moved while the box was opened up again", stayed(where(), w1), [where(), w1]);
pull("boxe-e", -9000, 0);
ok("PULLED IN AS FAR AS HE LIKES, AN INCH OF BOX IS LEFT: from the right", sameBox(box(), [1, 1, 1, 22]), box());
pull("boxe-e", 9000, 0);
pull("boxe-w", 9000, 0);
ok("from the left", sameBox(box(), [30, 1, 1, 22]), box());
pull("boxe-w", -9000, 0);
pull("boxe-n", 0, 9000);
ok("from the top", sameBox(box(), [1, 1, 30, 1]), box());
pull("boxe-n", 0, -9000);
pull("boxe-s", 0, -9000);
ok("from the bottom", sameBox(box(), [1, 22, 30, 1]), box());
pull("boxe-s", 0, 9000);
ok("opened right up again, the drawing is where it always was", stayed(where(), w1) && sameBox(box(), [1, 1, 30, 22]), [where(), w1]);

// a side that has nowhere to go: nothing is saved, sent or remembered
api.call("loadSheet", sheet());
api.call("setMode", "hand");
global.sent.length = 0;
const steps0 = api.get("UNDO").length;
pull("boxe-e", 80, 0);
ok("a side already on the margin has nowhere to go - and nothing is saved, sent or remembered",
   sameBox(box(), [1, 1, 30, 22]) && states().length === 0 && api.get("UNDO").length === steps0 && !ST().view_box && ST().origin_x === 0, [box(), states().length]);

// ================================================================ 4. Escape, Ctrl+Z
api.call("loadSheet", sheet());
api.call("setMode", "hand");
api.set("UNDO", []);
const w2 = where();
global.sent.length = 0;
const eh = pull("boxe-w", 8 * K(), 0, true);
ok("(half way through a cut)", sameBox(box(), [9, 1, 22, 22]) && near(ST().origin_x, 4 / SF, 1e-6));
key("Escape");
ok("ESCAPE IN THE MIDDLE OF A CUT PUTS THE BOX BACK, AND THE DRAWING WITH IT",
   sameBox(box(), [1, 1, 30, 22]) && ST().origin_x === 0 && ST().origin_y === 0 && !ST().view_box && api.get("BOXD") === null && stayed(where(), w2), [box(), ST().origin_x]);
up(eh[0], eh[1]);
ok("...and letting go afterwards tells Ruby nothing, and leaves nothing to undo", states().length === 0 && api.get("UNDO").length === 0, [states().length, api.get("UNDO").length]);

pull("boxe-w", 8 * K(), 0);
pull("boxe-n", 0, 5 * K());
ok("(two cuts)", sameBox(box(), [9, 1, 22, 17]) && near(ST().origin_x, 4 / SF, 1e-6) && near(ST().origin_y, -2.5 / SF, 1e-6), [box(), ST().origin_x, ST().origin_y]);
global.sent.length = 0;
key("z", { code: "KeyZ", ctrlKey: true });
ok("CTRL+Z TAKES THE LAST CUT BACK", sameBox(box(), [9, 1, 22, 22]) && near(ST().origin_x, 4 / SF, 1e-6) && near(ST().origin_y, 0, 1e-6) && stayed(where(), w2), [box(), ST().origin_x, ST().origin_y]);
m = states();
ok("and Ruby is told, so the paper goes back with it", m.length === 1 && sameBox(m[0].view_box, [9, 1, 22, 22]) && near(m[0].origin_y, 0, 1e-6), m.map(x => [x.view_box, x.origin_y]));
// he slides the drawing inside the box (Alt+drag), and THEN takes the first cut back
ST().origin_x += 50;
const w3 = where();
key("z", { code: "KeyZ", ctrlKey: true });
ok("a second press takes the first cut back: the whole sheet again", sameBox(box(), [1, 1, 30, 22]) && !ST().view_box, [box(), ST().view_box]);
ok("...and a slide of the drawing made since the cut is KEPT - only the cut is taken back", near(ST().origin_x, 50, 1e-6) && stayed(where(), w3), [ST().origin_x]);
ok("nothing is left to take back", api.get("UNDO").length === 0);

// ================================================================ 5. a turned drawing, and a size set by hand
api.call("loadSheet", sheet());
api.call("setMode", "hand");
ST().rotation = 30; api.call("render");
const w4 = where();
pull("boxe-e", -7 * K(), 0);
pull("boxe-n", 0, 3 * K());
pull("boxe-w", 2 * K(), 0);
ok("A TURNED DRAWING: cut on three sides, every line is still on the spot it was on", sameBox(box(), [3, 1, 21, 19]) && stayed(where(), w4), [box(), where(), w4]);
ok("and the mouse still lands on the right spot in the turned house",
   SPOTS.every(p => { const q = S(p[0], p[1]); const b = api.call("atMouse", ev(q[0], q[1])); return near(b[0], p[0], 1e-6) && near(b[1], p[1], 1e-6); }));
ST().rotation = 0;

api.call("loadSheet", sheet());
api.call("setMode", "hand");
// a corner first: half the box, half the size ...
{ const v = V(), k = K(); el("boxc-se").onmousedown(ev((v.x + v.w) * k, (24 - v.y) * k)); move((v.x + v.w) * k - v.w * k / 2, (24 - v.y) * k - v.h * k / 2); up(0, 0); }
ok("(a corner first: the drawing is at a size set by hand)", sameBox(box(), [1, 12, 15, 11]) && near(ST().scale_f, 0.125, 1e-12), [box(), ST().scale_f]);
const w5 = where();
pull("boxe-e", -4 * K(), 0);
ok("A SIZE SET BY HAND IS NOT TOUCHED BY A CUT, and the drawing stays put", near(ST().scale_f, 0.125, 1e-12) && sameBox(box(), [1, 12, 11, 11]) && stayed(where(), w5), [ST().scale_f, box()]);
ok("the middle of the box holds the right point of the house at that size", near(ST().origin_x, -2 / (0.125 / 12), 1e-6), ST().origin_x);

// ================================================================ the switch
let off = sheet(); off.box_crop = false;
api.call("loadSheet", off);
api.call("setMode", "hand");
const w6 = S(0, 0);
pull("boxc-se", -V().w * K() / 2, -V().h * K() / 2);          // [1, 12, 15, 11]
const w7 = S(0, 0);
pull("boxe-n", 60, 0);
ok("switched off: a side moves the whole box, as it did before", sameBox(box(), [1 + 60 / K(), 12, 15, 11]) && near(S(0, 0)[0] - w7[0], 60, 1e-6), box());
let on = sheet();
api.call("loadSheet", on);
ok("and switched on again with the next sheet", safe("CROPON") === true);

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
