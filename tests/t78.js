// t78 - the words are typed ON the sheet, over the writing itself (2026-10-07).
//
// The user: "אני לא רוצה שייפתח חלון עריכה עם כתיבה לכל טקסט... אני רוצה שהחלון
// ייפתח שהוא הכיתוב עצמו, אני חושב שיש את זה בלייאאוט."
//
//   a box of writing   #tbedit lies exactly over the box: same place, size,
//                      width, turn; every letter typed reshapes the box; Enter
//                      is a new line; Ctrl+Enter or a press outside keeps;
//                      Escape drops. The hidden bar keeps the words (one road).
//   a label            one line over the label; Enter keeps (to the mark, or
//                      to Ruby under the key); Escape drops.
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
const eq2 = (a, b) => JSON.stringify(a) === JSON.stringify(b);
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
{ const sc = el("scale"); let h = ""; Object.defineProperty(sc, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") sc.children = []; } }); }
const pdfrb = fs.readFileSync("plan_pdf.rb", "utf8");
const WID = pdfrb.slice(pdfrb.indexOf("W = ["), pdfrb.indexOf("].freeze unless\n      const_defined?(:W, false)")).replace("W = [", "").split(",").map(n => parseInt(n, 10));
const RULES = { pad: 0.25, lead: 1.25, ascent: 0.8, pt: 24, pt_min: 4, pt_max: 400, cap: 0.717, w: WID };
const AREA = [1, 2, 34, 21];
const sheet = () => { const s = fresh();
  s.doc.pages[0].view_area = [1, 1, 30, 22]; s.doc.pages[0].pic_area = AREA.slice();
  s.doc.pages[0].text_boxes = [{ pic: "t:0", txt: true, placed: true, x: 10, y: 8, w: 3, h: 0.75, rot: 30, crop: [0, 0, 0, 0], pt: 36, text: "Pool deck", lines: ["Pool deck"] }];
  s.doc.pages[0].layers.push({ name: "TEXT", visible: true, shapes: [
    { type: "text", text: "Pool deck", x: 10.125, y: 8.225, h: 0.3585, align: "left", rotation: 30, tbox: "t:0", li: 0 } ] });
  s.doc.canvases[0].layers.push({ name: "NOTES", visible: true, shapes: [
    { type: "text", text: "8'-4\"", x: -350, y: 274, h: 5, h0: 5, key: "NOTES|8'-4\"|1", align: "center", rotation: 0, follow: true } ] });
  s.state.marks = [{ t: "dim", x1: -400, y1: 250, x2: -300, y2: 250, off: 20 }];
  s.state.texts = [{ text: "Pool deck", on: "plan", box: [10, 8, 3, 0.75], rot: 30, pt: 36 }]; s.state.pics = []; s.state.image_geo = {};
  s.text_rules = JSON.parse(JSON.stringify(RULES)); s.text_words = true;
  return s; };
const open = () => { api.call("loadSheet", sheet()); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };
const ed = () => el("tbedit");
const edOn = () => /^on/.test(ed().className);
const tb = id => (PG().text_boxes || []).find(e => e.pic === id) || null;
const trect = id => { const r = tb(id); return [r.x, r.y, r.w, r.h]; };
const typeOn = t => { ed().value = t; ed().oninput({}); };
const keyOn = (k, m) => ed().onkeydown(Object.assign({ key: k, preventDefault() {} }, m || {}));
const dbl = (mx, my) => { const c = api.call("screenOf", mx, my); svg().ondblclick(ev(c[0], c[1])); };
const tclick = (px, py) => { const c = scr(px, py); svg().onmousedown(ev(c[0], c[1])); svg().onclick(ev(c[0], c[1])); };
const wrapL = () => (el("sheetWrap").offsetLeft || 0), wrapT = () => (el("sheetWrap").offsetTop || 0);

const page = fs.readFileSync("sheet.html", "utf8");
ok("there is an editor on the sheet, inside #stage with the handles, and the bar is not shown", /<textarea id="tbedit"/.test(page) && page.indexOf('id="tbedit"') > page.indexOf('<div id="stage">') && /#tbbar\.on \{ display:none; \}/.test(page));
["tbEditPlace", "tbEditShow", "tbEditHide", "tbEditInput", "labelEditOpen", "labelEditKeep"].forEach(fn => ok("it defines " + fn, typeof safe(fn) === "function"));

// ================================================================ 1. a box of writing
open();
ok("closed: the editor is not shown", !edOn());
const tbox = () => { const c = api.call("picScreen", api.call("picRect", tb("t:0")), 0, 0); svg().onmousedown(ev(c[0], c[1])); up(c[0], c[1]); svg().onmousedown(ev(c[0], c[1])); up(c[0], c[1]); };
tbox();
ok("TWO PRESSES ON THE WORDS: THE EDITOR OPENS OVER THEM  <<< THE RULE", edOn() && ed().value === "Pool deck" && api.get("TBED") && api.get("TBED").n === 0, [ed().className, ed().value]);
ok("the bar is open underneath, as the keeper of the words, but not shown", el("tbbar").className === "on" && el("tbtext").value === "Pool deck");
const fs36 = 36 / 72 * K();
ok("EXACTLY OVER THE BOX: same place, same width and height, the letters the same size, turned the same way",
   near(parseFloat(ed().style.left), wrapL() + 10 * K(), 0.06) && near(parseFloat(ed().style.top), wrapT() + (PH - 8.75) * K(), 0.06) &&
   near(parseFloat(ed().style.width), 3 * K(), 0.06) && near(parseFloat(ed().style.height), 0.75 * K(), 0.06) &&
   near(parseFloat(ed().style.fontSize), fs36, 0.01) && near(parseFloat(ed().style.lineHeight), 1.25 * fs36, 0.01) && near(parseFloat(ed().style.padding), 0.25 * fs36, 0.01) &&
   ed().style.transform === "rotate(-30deg)", [ed().style.left, ed().style.top, ed().style.width, ed().style.height, ed().style.fontSize, ed().style.transform]);
typeOn("Pool deck and spa");
ok("EVERY LETTER TYPED RESHAPES THE BOX: two lines now, the top where it was, and the editor grows with it", tb("t:0").lines.length === 2 && near(parseFloat(ed().style.height), trect("t:0")[3] * K(), 0.06) && states().length === 0, [tb("t:0").lines, ed().style.height]);
ok("the hidden bar holds the same words", el("tbtext").value === "Pool deck and spa");
keyOn("Enter");
ok("Enter alone is a new line, not the end", edOn() && states().length === 0);
keyOn("Enter", { ctrlKey: true });
let m = states();
ok("CTRL+ENTER KEEPS: Ruby is told once, the editor is gone, the box is picked", !edOn() && m.length === 1 && m[0].texts[0].text === "Pool deck and spa" && api.get("BSEL") === "t:0" && !api.get("TBED"), [edOn(), m.length]);
tbox(); typeOn("Not this"); keyOn("Escape");
ok("ESCAPE DROPS: the words as they were, nothing sent", !edOn() && ST().texts[0].text === "Pool deck and spa" && states().length === 1);
tbox(); typeOn("Kept by a press");
{ const c = scr(30, 4); svg().onmousedown(ev(c[0], c[1])); }
ok("A PRESS OUTSIDE KEEPS", !edOn() && ST().texts[0].text === "Kept by a press" && states().length === 2);
// a new one from the T tool: typed on the sheet at once
open(); el("ttext").onclick(); tclick(5, 20);
ok("THE T TOOL: a click on the sheet opens the editor right there, empty, 24 points", edOn() && ed().value === "" && near(parseFloat(ed().style.fontSize), 24 / 72 * K(), 0.01) && near(parseFloat(ed().style.left), wrapL() + 5 * K(), 0.06), [ed().className, ed().style.fontSize]);
typeOn("Hello");
ok("typed: on the sheet at once, the box as wide as the word", html().indexOf(">Hello</text>") > 0 && near(trect("t:1")[2], api.call("tbNatural", "Hello", 24), 1e-9));
// the zoom: the editor stays over its box
api.call("setZoom", 2);
ok("ZOOMED WHILE TYPING: the editor is still over its box, twice as big", near(parseFloat(ed().style.left), wrapL() + 5 * K(), 0.06) && near(parseFloat(ed().style.fontSize), 24 / 72 * K(), 0.01) && api.get("ZOOM") === 2);
keyOn("Escape");
ok("Escape on a new one: it is gone", !edOn() && ST().texts.length === 1);
api.call("setZoom", null);

// ================================================================ 2. a label
open();
const lab = api.call("dimLabelXY", ST().marks[0]);
dbl(lab[0], lab[1]);
ok("TWO CLICKS ON A LABEL: one line typed over it, with its words", edOn() && ed().className === "on one" && ed().value === "8'-4\"" && api.get("TSEL") && api.get("TSEL").dim === 0, [ed().className, ed().value]);
const lb = api.call("textBox", api.get("TSEL").shape, false);
// 2026-10-07: "שהכיתוב ייפתח באותה הקופסה של הכיתוב עצמו ולא בקופסה נפרדת" - the editor has the label's own middle
const lfp = lb.h / 0.717, lew = Math.max(lb.w + 4, lfp * 6, 60), leh = lfp * 1.3 + 4;
ok("over the label ITSELF: the same middle, not a box beside it; the letters its size, centred",
   near(parseFloat(ed().style.left) + lew / 2, wrapL() + lb.x + lb.w / 2, 0.06) && near(parseFloat(ed().style.top) + leh / 2, wrapT() + lb.y + lb.h / 2, 0.06) &&
   near(parseFloat(ed().style.width), lew, 0.06) && ed().style.textAlign === "center" && near(parseFloat(ed().style.fontSize), lfp, 0.01),
   [ed().style.left, ed().style.top, ed().style.width, ed().style.textAlign, lb, ed().style.fontSize]);
ok("and the settings of that label are in the side panel at the same time", el("textbar").className === "on");
ed().value = "8'-4\" V.I.F."; keyOn("Enter");
m = states();
ok("ENTER KEEPS: a hand dimension's words go onto the mark, Ruby is told once, the editor is gone", !edOn() && ST().marks[0].label === "8'-4\" V.I.F." && m.length === 1 && el("textbar").className === "", [ST().marks[0], m.length]);
dbl(100, -150);
ok("(no label there: nothing opens)", !edOn());
dbl(0, 0);
ok("the plugin's own label: its words over it", edOn() && ed().value === "ROOM 2" && api.get("TSEL").key === "ROOMS|ROOM 2|1");
ed().value = "MASTER"; keyOn("Enter");
const tm = msgs("set_text_mark");
ok("Enter: to Ruby under its key", tm.length === 1 && tm[0].key === "ROOMS|ROOM 2|1" && tm[0].text === "MASTER" && !edOn(), tm);
dbl(0, 0); ed().value = "Dropped"; keyOn("Escape");
ok("Escape drops: nothing more sent, the panel shut", !edOn() && msgs("set_text_mark").length === 1 && el("textbar").className === "");
dbl(0, 0);
{ const c = scr(30, 4); svg().onmousedown(ev(c[0], c[1])); }
ok("a press on the sheet while typing over a label keeps what is there (its own words: nothing to send)", !edOn() && msgs("set_text_mark").length === 1);
{ const s = sheet(); s.text_words = false; api.call("loadSheet", s); api.call("setMode", "hand"); }
dbl(0, 0);
ok("SWITCHED OFF (text_words): two clicks open the panel the old way, nothing on the sheet", !edOn() && el("textbar").className === "on");

// ================================================================ 3. two quick presses (2026-10-07)
// "לחיצה כפולה על מספר של מידה לא פותחת עריכה אצלי." In a real browser the first press draws the sheet again, the
// element that was pressed is gone, and the browser sends no click and no double click (tests/browser/dbltest.js).
// So the window counts the presses itself. Driven here through onmousedown and the mouse-up only - never ondblclick.
["labelUnder", "pressName", "pressTwice"].forEach(fn => ok("it defines " + fn, typeof safe(fn) === "function"));
open();
{ const lp = api.call("dimLabelXY", ST().marks[0]), c = api.call("screenOf", lp[0], lp[1]), m0 = JSON.stringify(ST().marks[0]);
  down(c[0], c[1]); up(c[0], c[1]);
  ok("one press on a hand dimension's number picks it up, as before", !!api.get("CARRY") && !edOn());
  down(c[0], c[1]); up(c[0], c[1]);
  ok("TWO QUICK PRESSES on it, with no double click from the browser: its words open over it",
     edOn() && ed().className === "on one" && ed().value === "8'-4\"" && !!api.get("TSEL") && api.get("TSEL").dim === 0, [ed().className, ed().value]);
  ok("nothing is carried, and the dimension did not move", !api.get("CARRY") && JSON.stringify(ST().marks[0]) === m0, ST().marks[0]);
  svg().ondblclick(ev(c[0], c[1]));
  ok("the browser's own double click, if it does come late, changes nothing", edOn() && ed().value === "8'-4\"");
  ed().value = "TWICE"; keyOn("Enter");
  ok("Enter keeps the words on the mark", ST().marks[0].label === "TWICE" && !edOn(), ST().marks[0]); }
open();
{ const lp = api.call("dimLabelXY", ST().marks[0]), c = api.call("screenOf", lp[0], lp[1]), real = Date.now; let t = real();
  Date.now = () => t; down(c[0], c[1]); up(c[0], c[1]); t += 700; down(c[0], c[1]); up(c[0], c[1]); Date.now = real;
  ok("two SLOW presses (700 ms apart): picked up and put down, nothing opens", !edOn() && !api.get("CARRY")); }
open();
{ const c = api.call("screenOf", 0, 0);
  down(c[0], c[1]); up(c[0], c[1]); down(c[0], c[1]); up(c[0], c[1]);
  ok("two quick presses on the plugin's own label: its words open, and it is not carried",
     edOn() && ed().value === "ROOM 2" && api.get("TSEL").key === "ROOMS|ROOM 2|1" && !api.get("TCARRY"), [ed().className, ed().value]);
  keyOn("Escape"); }
open();
{ const a = api.call("screenOf", 0, 0), lp = api.call("dimLabelXY", ST().marks[0]), b = api.call("screenOf", lp[0], lp[1]);
  down(a[0], a[1]); up(a[0], a[1]); down(b[0], b[1]); up(b[0], b[1]);
  ok("a quick press on one thing and then on another is not two presses on one thing", !edOn()); }
// A turned drawing with the page strip on (his window, 2026-10-07): the little sheets are drawn after the big one, a
// picture sheet has no turn, and it left 0 behind - the words opened a quarter turn off the number (tests/browser/edpos.js).
{ const s = sheet(); s.state.rotation = 90; s.state.strip = true; s.rotate = true;
  s.doc.pages.push({ name: "RENDERING 1", width: 36, height: 24, kind: "image", ref: 0, sheet_number: "A-102", layers: [] });
  api.call("loadSheet", s); api.call("setMode", "hand");
  ok("A TURNED DRAWING, THE PAGE STRIP ON, A PICTURE SHEET LAST: the little sheets do not leave their own turn behind",
     el("strip").className === "on" && api.get("VROT") === 90, [el("strip").className, api.get("VROT")]);
  const lp = api.call("dimLabelXY", ST().marks[0]), c = api.call("screenOf", lp[0], lp[1]);
  down(c[0], c[1]); up(c[0], c[1]); down(c[0], c[1]); up(c[0], c[1]);
  ok("so the words open at the number's own turn", edOn() && ed().style.transform === "rotate(" + (-((api.get("TSEL").shape.rotation || 0) + 90)) + "deg)", ed().style.transform); }

// ================================================================ 4. the settings at the side, on a box of writing (2026-10-07)
// He sent a picture of himself typing in a box of writing with the panel at the side greyed out:
// "כשאני רוצה להקליד פה זה לא נותן לי לשחק עם ההגדרות של הכיתוב." The same panel a label has now works on the box.
["tbStyle", "boxBarWant", "boxBarUnits", "paintBoxBar", "boxBarSet"].forEach(fn => ok("it defines " + fn, typeof safe(fn) === "function"));
const tbMid = id => { const e = tb(id); return scr(e.x + e.w / 2, e.y + e.h / 2); };
const pickBox = id => { const c = tbMid(id); down(c[0], c[1]); up(c[0], c[1]); };
const T0 = () => ST().texts[0];
// two quick presses on the box: a fresh count each time (the suite presses faster than any hand)
const twice = id => { api.set("TBLAST", null); const c = tbMid(id); down(c[0], c[1]); up(c[0], c[1]); down(c[0], c[1]); up(c[0], c[1]); };
open(); key("Escape");       // (the label the last section left picked is let go)
ok("nothing picked: the panel is on no box, and grey", api.call("boxBarWant") === null && el("textbar").className === "");
pickBox("t:0");
ok("A BOX OF WRITING PICKED: the panel is alive on it, the size in POINTS, the words box put away",
   api.get("BSEL") === "t:0" && el("textbar").className === "on" && el("txunit").textContent === "pt" && +el("txsize").value === 36 && el("txwords").style.display === "none" && api.get("TXB") === 0,
   [api.get("BSEL"), el("textbar").className, el("txunit").textContent, el("txsize").value, el("txwords").style.display]);
let un = api.get("UNDO").length; m = states().length;
el("txbold").onclick();
ok("B: bold on the sheet at once - one step for Ctrl+Z, Ruby told once, the box still picked",
   T0().bold === true && /font-weight="700"[^>]*>Pool deck</.test(html()) && api.get("UNDO").length === un + 1 && states().length === m + 1 && api.get("BSEL") === "t:0" && /on/.test(el("txbold").className),
   [T0(), api.get("UNDO").length - un, states().length - m]);
ok("what Ruby is sent says so", states()[states().length - 1].texts[0].bold === true);
ok("bold letters are wider by plan_pdf's own amount - the same number rt275 holds Ruby to", near(api.call("tbWidth", "Pool", 72, true), 2.001 * 1.06, 1e-9) && near(api.call("tbWidth", "Pool", 72), 2.001, 1e-9));
ok("so a width that holds the plain words breaks the bold ones", eq2(api.call("tbWrap", "Pool deck", 2.1955, 36), ["Pool deck"]) && eq2(api.call("tbWrap", "Pool deck", 2.1955, 36, true), ["Pool", "deck"]));
el("txitalic").onclick(); el("txunder").onclick();
ok("I and U the same way", T0().italic === true && T0().underline === true && /font-style="italic"/.test(html()) && /text-decoration="underline"/.test(html()));
{ const w0 = T0().box[2]; el("txsize").value = "72"; el("txsize").onchange();
  ok("THE SIZE BOX, in points: twice the letters, twice the width, the lines where they were", T0().pt === 72 && near(T0().box[2], w0 * 2, 1e-9) && tb("t:0").lines.length === 1, T0()); }
el("txcolor").value = "#C0392B"; el("txcolor").onchange();
ok("the colour, kept small-lettered; on the sheet at once", T0().color === "#c0392b" && /fill="#c0392b"[^>]*>Pool deck</.test(html()), T0());
el("txcolor").value = "#000000"; el("txcolor").onchange();
ok("black is no colour: nothing is kept", T0().color === undefined);
key("z", { ctrlKey: true, code: "KeyZ" });
ok("Ctrl+Z: one setting back at a time", T0().color === "#c0392b" && T0().pt === 72, T0());
ok("(an undo lets the box go, as it does a picture: the panel is grey until it is picked again)", api.get("BSEL") === null && el("textbar").className === "");
pickBox("t:0");
el("txreset").onclick();
ok("the reset button: plain black letters again, its size is his", T0().bold === undefined && T0().italic === undefined && T0().underline === undefined && T0().color === undefined && T0().pt === 72, T0());
// while he is typing in it
open();
twice("t:0");
ok("TYPING IN THE BOX: the panel is alive (it was grey in his picture)", !!api.get("TBED") && edOn() && el("textbar").className === "on" && el("txunit").textContent === "pt", [!!api.get("TBED"), el("textbar").className]);
un = api.get("UNDO").length; m = states().length;
el("txunder").onclick();
ok("U while typing: on the sheet and in the editor at once; no step and no word to Ruby yet",
   T0().underline === true && ed().style.textDecoration === "underline" && !!api.get("TBED") && api.get("UNDO").length === un && states().length === m, [T0(), ed().style.textDecoration]);
el("txsize").value = "18"; el("txsize").onkeydown({ key: "Enter", preventDefault() {} });
ok("the size while typing: the box follows, he is still typing", T0().pt === 18 && !!api.get("TBED") && near(parseFloat(ed().style.fontSize), 18 / 72 * K(), 0.01), [T0().pt, ed().style.fontSize]);
typeOn("Pool deck now");
keyOn("Enter", { ctrlKey: true });
ok("done: the words, the line under them and the size are ONE step, and Ruby is told once",
   !api.get("TBED") && T0().text === "Pool deck now" && T0().underline === true && T0().pt === 18 && api.get("UNDO").length === un + 1 && states().length === m + 1, [T0(), api.get("UNDO").length - un, states().length - m]);
key("z", { ctrlKey: true, code: "KeyZ" });
ok("Ctrl+Z takes all three back together", T0().text === "Pool deck" && T0().underline === undefined && T0().pt === 36, T0());
twice("t:0");
el("txitalic").onclick(); keyOn("Escape");
ok("Escape while typing drops the setting with the words", !api.get("TBED") && T0().italic === undefined, T0());
// let go; a label has its own road still
{ const c = scr(30, 4); down(c[0], c[1]); up(c[0], c[1]); }
ok("the box let go: the panel is grey again and counts in % again", api.get("BSEL") === null && el("textbar").className === "" && el("txunit").textContent === "%" && api.get("TXB") === null, [api.get("BSEL"), el("textbar").className, el("txunit").textContent]);
{ const c = api.call("screenOf", 0, 0); down(c[0], c[1]); up(c[0], c[1]); key("Escape"); down(c[0], c[1]); up(c[0], c[1]); }
ok("a label picked: the panel is the label's, in %, and B goes to Ruby under its key as it always did",
   !!api.get("TSEL") && el("textbar").className === "on" && el("txunit").textContent === "%" && (global.sent.length = 0, el("txbold").onclick(), msgs("set_text_mark").length === 1 && msgs("set_text_mark")[0].bold === true), [el("textbar").className, el("txunit").textContent]);
// switched off
{ const s = sheet(); s.text_style = false; s.state.texts[0].bold = true; api.call("loadSheet", s); api.call("setMode", "hand"); }
pickBox("t:0");
ok("SWITCHED OFF (text_style): the panel does not go onto a box, and a saved 'bold' is not drawn", api.get("BSEL") === "t:0" && api.call("boxBarWant") === null && el("textbar").className === "" && !/font-weight="700"[^>]*>Pool deck</.test(html()));

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
