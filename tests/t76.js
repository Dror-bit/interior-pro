// t76 - the number of a dimension written over by hand (2026-10-07), the window's side.
//
// The user: "אני רוצה שיהיה אפשרי לערוך את המידות - את המספרים שלהם בתוך." He
// chose 1: his words REPLACE the number and stay when the dimension is stretched.
//
//   two clicks on a dimension's number (or its line)   the label bar opens with
//                                                       a box for the words
//   Enter                                               the words go: onto the
//                                                       mark for a hand dimension,
//                                                       to Ruby under the key for
//                                                       any other label
//   emptied                                             the number again
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

const near = (a, b, tol) => Math.abs(a - b) < (tol === undefined ? 1e-6 : tol);
const el = id => document.getElementById(id);
const ST = () => api.get("STATE");
const PG = () => api.get("PAGE");
const K = () => api.get("LIVEK");
const PH = 24;
const states = () => msgs("set_state");
const html = () => document.getElementById("sheetWrap").innerHTML;
const pic = id => { let f = null; PG().layers.forEach(l => l.shapes.forEach(s => { if (s.pic === id) f = s; })); return f; };
const R = id => api.call("picRect", pic(id));
const rect = id => { const r = R(id); return [r.x, r.y, r.w, r.h]; };
const same4 = (a, b, tol) => a.every((n, i) => near(n, b[i], tol === undefined ? 1e-6 : tol));
// paper inches -> the pixel on the screen
const scr = (px, py) => [px * K(), (PH - py) * K()];
// a spot of the PICTURE FILE (u across, v up, each 0..1 of the whole file) -> where it is on the paper now
const spot = (id, u, v) => { const r = R(id), c = r.crop, fw = r.w / (1 - c[0] - c[2]), fh = r.h / (1 - c[1] - c[3]);
  const lx = -r.w / 2 + (u - c[0]) * fw, ly = -r.h / 2 + (v - c[1]) * fh, t = r.rot * Math.PI / 180;
  return [r.x + r.w / 2 + lx * Math.cos(t) - ly * Math.sin(t), r.y + r.h / 2 + lx * Math.sin(t) + ly * Math.cos(t)]; };
const SPOTS = [[0.5, 0.5], [0.2, 0.9], [0.45, 0.4]];
const spots = id => SPOTS.map(p => spot(id, p[0], p[1]));
const stayed = (a, b) => a.every((p, i) => near(p[0], b[i][0], 1e-6) && near(p[1], b[i][1], 1e-6));
// a corner of the picture (as it is turned) on the paper: 'nw' 'ne' 'sw' 'se'
const corner = (id, c) => { const r = R(id), t = r.rot * Math.PI / 180, lx = (c.indexOf("e") >= 0 ? 1 : -1) * r.w / 2, ly = (c.indexOf("n") >= 0 ? 1 : -1) * r.h / 2;
  return [r.x + r.w / 2 + lx * Math.cos(t) - ly * Math.sin(t), r.y + r.h / 2 + lx * Math.sin(t) + ly * Math.cos(t)]; };
// hold a handle and move the mouse by (dx, dy) pixels in two steps; let go unless told to keep hold
const pull = (id, dx, dy, keep) => { const c = [400, 300];
  el(id).onmousedown(ev(c[0], c[1])); move(c[0] + dx / 2, c[1] + dy / 2); move(c[0] + dx, c[1] + dy); if (!keep) up(c[0] + dx, c[1] + dy); return [c[0] + dx, c[1] + dy]; };
// press on the picture itself and drag it
const grab = (id, dx, dy, keep) => { const r = R(id), c = scr(r.x + r.w / 2, r.y + r.h / 2);
  down(c[0], c[1]); if (dx || dy) { move(c[0] + dx / 2, c[1] + dy / 2); move(c[0] + dx, c[1] + dy); } if (!keep) up(c[0] + dx, c[1] + dy); return [c[0] + dx, c[1] + dy]; };
const undo = () => key("z", { code: "KeyZ", ctrlKey: true });
{ const sc = el("scale"); let h = ""; Object.defineProperty(sc, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") sc.children = []; } }); }

const sheet = () => { const s = fresh();
  // the number of a hand dimension, as Ruby writes it on the NOTES layer, and the plugin's own
  s.doc.canvases[0].layers.push({ name: "NOTES", visible: true, shapes: [
    { type: "text", text: "8'-4\"", x: -350, y: 274, h: 5, h0: 5, key: "NOTES|8'-4\"|1", align: "center", rotation: 0, follow: true } ] });
  s.doc.canvases[0].layers.push({ name: "DIMENSIONS", visible: true, shapes: [
    { type: "text", text: "12'-0\"", x: 100, y: -150, h: 5, h0: 5, key: "DIMENSIONS|12'-0\"|1", align: "center", rotation: 0 } ] });
  s.state.marks = [{ t: "dim", x1: -400, y1: 250, x2: -300, y2: 250, off: 20 }];
  s.text_words = true;
  return s; };
const open = () => { api.call("loadSheet", sheet()); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };
const barOn = () => el("textbar").className === "on";
const dbl = (mx, my) => { const c = api.call("screenOf", mx, my); svg().ondblclick(ev(c[0], c[1])); };
const wordsIn = (t, enter) => { el("txwords").value = t; if (enter) el("txwords").onkeydown({ key: "Enter", preventDefault() {} }); else el("txwords").onchange(); };

ok("the window has the switch, and it is on", safe("TXWORDS") === true, safe("TXWORDS"));
ok("it defines sendTextWords and dimLabelText", typeof safe("sendTextWords") === "function" && typeof safe("dimLabelText") === "function");
const page = fs.readFileSync("sheet.html", "utf8");
ok("the label bar has a box for the words", /<input id="txwords"/.test(page));

open();
ok("the number of a hand dimension reads the way Ruby prints it (fmt_feet)", api.call("dimLabelText", ST().marks[0]) === "8'-4\"" && api.call("dimLabelText", { t: "dim", x1: 0, y1: 0, x2: 7.26, y2: 0 }) === "7.3\"" && api.call("dimLabelText", { t: "dim", x1: 0, y1: 0, x2: 143.97, y2: 0 }) === "12'-0\"", [api.call("dimLabelText", ST().marks[0]), api.call("dimLabelText", { t: "dim", x1: 0, y1: 0, x2: 7.26, y2: 0 })]);

// ---- a hand dimension: the words go onto the mark
const lab = api.call("dimLabelXY", ST().marks[0]);
dbl(lab[0], lab[1]);
ok("TWO CLICKS ON A HAND DIMENSION'S NUMBER OPEN THE BAR  <<< THE RULE", barOn() && api.get("TSEL") && api.get("TSEL").dim === 0, api.get("TSEL"));
ok("the words box is empty and shows the number as a hint", el("txwords").value === "" && el("txwords").placeholder === "8'-4\"", [el("txwords").value, el("txwords").placeholder]);
wordsIn("8'-4\" V.I.F.", true);
let m = states();
ok("ENTER: THE WORDS GO ONTO THE MARK ITSELF, and Ruby is told once", ST().marks[0].label === "8'-4\" V.I.F." && m.length === 1 && m[0].marks[0].label === "8'-4\" V.I.F." && !barOn(), [ST().marks[0], m.length]);
ok("not under the label's key - nothing in text_marks", Object.keys(ST().text_marks || {}).length === 0 && msgs("set_text_mark").length === 0);
ok("the number on the sheet reads his words now", api.call("dimLabelText", ST().marks[0]) === "8'-4\" V.I.F.");
ok("it is one step for Ctrl+Z", api.get("UNDO").length === 1);
// two clicks on the LINE of the dimension, not its number: the same bar
api.call("closeTextBar");
{ const L = api.call("dimLine", ST().marks[0]); dbl((L[0] + L[2]) / 2 + 10, L[1]); }
ok("two clicks on the dimension's LINE open its number too", barOn() && api.get("TSEL") && api.get("TSEL").dim === 0 && el("txwords").value === "8'-4\" V.I.F.", [barOn(), api.get("TSEL")]);
global.sent.length = 0;
wordsIn("   ", false);
ok("EMPTIED = THE NUMBER AGAIN", ST().marks[0].label === undefined && states().length === 1);
wordsIn("", false);
ok("emptied twice sends nothing more", states().length === 1);
undo();
ok("Ctrl+Z brings the words back", ST().marks[0].label === "8'-4\" V.I.F.");
// stretched: the words stay (Ruby draws them - rt276; here the mark still carries them)
api.call("moveMark", ST().marks[0], "b", 100, 0); api.call("push");
ok("STRETCHED, THE WORDS STAY  <<< THE RULE (he chose 1)", ST().marks[0].label === "8'-4\" V.I.F." && ST().marks[0].x2 === -200);
api.call("closeTextBar");

// ---- the plugin's own dimension: the words go to Ruby under the key
open();
dbl(100, -150);
ok("two clicks on the plugin's own dimension number open the bar, with no mark", barOn() && api.get("TSEL").key === "DIMENSIONS|12'-0\"|1" && (api.get("TSEL").dim === undefined || api.get("TSEL").dim === null));
ok("the hint is the number", el("txwords").placeholder === "12'-0\"");
wordsIn("12'-0\" +/-", true);
let tm = msgs("set_text_mark");
ok("ENTER: the words go to Ruby UNDER THE LABEL'S KEY, as its size does", tm.length === 1 && tm[0].key === "DIMENSIONS|12'-0\"|1" && tm[0].text === "12'-0\" +/-" && tm[0].pct === undefined && states().length === 0, tm);
// Ruby answers with the label rewritten; the bar, opened again, shows the words
{ const s = sheet(); s.state.text_marks = { "DIMENSIONS|12'-0\"|1": { text: "12'-0\" +/-" } }; s.doc.canvases[0].layers[s.doc.canvases[0].layers.length - 1].shapes[0].text = "12'-0\" +/-"; api.call("loadSheet", s); api.call("setMode", "hand"); global.sent.length = 0; }
dbl(100, -150);
ok("opened again after Ruby's answer: the words are in the box, the key is the one as built", barOn() && el("txwords").value === "12'-0\" +/-" && api.get("TSEL").key === "DIMENSIONS|12'-0\"|1");
wordsIn("12'-0\" +/-", false);
ok("the same words again send nothing", msgs("set_text_mark").length === 0);
wordsIn("", true);
tm = msgs("set_text_mark");
ok("emptied: Ruby is told to take the words away", tm.length === 1 && tm[0].text === "" && !barOn(), tm);
// a room name too
open(); dbl(0, 0);
ok("any label: a room name can be written over the same way", barOn() && api.get("TSEL").key === "ROOMS|ROOM 2|1" && el("txwords").placeholder === "מה כתוב" && el("txwords").value === "ROOM 2");
wordsIn("MASTER", true);
tm = msgs("set_text_mark");
ok("and goes to Ruby under its key", tm.length === 1 && tm[0].key === "ROOMS|ROOM 2|1" && tm[0].text === "MASTER", tm);
// the size box still does what it did, and does not carry the words
open(); dbl(100, -150); global.sent.length = 0;
el("txsize").value = String(api.call("labelPt", api.get("TSEL").shape, api.get("TSEL").paper, true) * 1.5); api.call("sendTextMark");     // points since 2026-10-08; kept as a percentage of the built size
tm = msgs("set_text_mark");
ok("the size box still sends the size alone - a size does not reset the words", tm.length === 1 && tm[0].pct === 150 && tm[0].text === undefined, tm);

// ---- switched off
{ const s = sheet(); s.text_words = false; api.call("loadSheet", s); api.call("setMode", "hand"); global.sent.length = 0; }
dbl(100, -150);
ok("SWITCHED OFF BY RUBY: the bar opens as it always did, the words box is put away", barOn() && el("txwords").style.display === "none");
wordsIn("X", true);
ok("and nothing is sent for words", msgs("set_text_mark").length === 0 && states().length === 0);
{ const s = sheet(); s.state.marks[0].label = "HOLD"; s.text_words = false; api.call("loadSheet", s); }
ok("with it off a hand dimension reads its number, whatever is on the mark", api.call("dimLabelText", ST().marks[0]) === "8'-4\"");
api.call("loadSheet", sheet());
ok("and on again with the next sheet", safe("TXWORDS") === true && el("txwords").style.display !== "none");

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
