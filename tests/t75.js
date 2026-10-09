// t75 - a piece of writing sits in a box of its own (2026-10-07), the window's side.
//
// The user: "אני רוצה להוסיף אופציה של קופסא עם כיתוב. כמובן שהקופסא צריכה להתנהג
// כמו שאר הקופסאות, ובקופסא יהיה אפשר לכתוב ולקבוע את גודל הכיתוב."
//
// THE RULE:
//   the T button, a click   a box of writing starts there; he types in the bar
//                           and the words are on the sheet at once
//   a click on it           picks it: the same squares, bars, grip and round
//                           arrow a picture has go onto it
//   dragging it             moves it about the sheet
//   a corner                box and letters bigger or smaller together
//   a side (left, right)    wider or narrower - the lines are laid again, the
//                           top of the box stays where it is
//   the round arrow         turns the whole box about its middle
//   two clicks on it        opens its words and its size again
//   Delete                  takes it off the sheet
//   the margins             it cannot leave what they leave
//   Escape drops what is half done; Ctrl+Z takes the last step back; Ruby is
//   told once, on letting go; the zoom and the place stay.
//
// The window lays the lines by the same sums Ruby does. THE NUMBERS IN SECTION 1
// ARE THE NUMBERS IN rt275.
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

// ---- Ruby's own rules and letter widths, read out of the files that ship
const pdfrb = fs.readFileSync("plan_pdf.rb", "utf8");
const WID = pdfrb.slice(pdfrb.indexOf("W = ["), pdfrb.indexOf("].freeze unless\n      const_defined?(:W, false)")).replace("W = [", "").split(",").map(n => parseInt(n, 10));
const canrb = fs.readFileSync("plan_canvas.rb", "utf8");
const num = name => parseFloat(new RegExp(name + "\\s*=\\s*([0-9.]+)").exec(canrb)[1]);
const RULES = { pad: num("TEXT_PAD"), lead: num("TEXT_LEAD"), ascent: num("TEXT_ASCENT"), pt: num("TEXT_PT"),
                pt_min: num("TEXT_PT_MIN"), pt_max: num("TEXT_PT_MAX"), cap: 0.717, w: WID };
ok("(the test reads Ruby's 95 Helvetica widths and its rules out of the real files)", WID.length === 95 && WID[0] === 278 && WID[94] === 584 && RULES.pad === 0.25 && RULES.lead === 1.25 && RULES.ascent === 0.8 && RULES.pt === 24, [WID.length, RULES]);

// the plan sheet with ONE box of writing on it, exactly as Ruby lays and sends it (rt275, T1),
// and a picture sheet with none
const AREA = [1, 2, 34, 21];
const T1 = { text: "Pool deck", on: "plan", box: [10, 8, 3, 0.75], rot: 0, pt: 36 };
const sheet = () => { const s = fresh();
  s.doc.pages[0].view_area = [1, 1, 30, 22]; s.doc.pages[0].pic_area = AREA.slice();
  s.doc.pages[0].text_boxes = [{ pic: "t:0", txt: true, placed: true, x: 10, y: 8, w: 3, h: 0.75, rot: 0, crop: [0, 0, 0, 0], pt: 36, text: "Pool deck", lines: ["Pool deck"] }];
  s.doc.pages[0].layers.push({ name: "TEXT", visible: true, shapes: [
    { type: "text", text: "Pool deck", x: 10.125, y: 8.225, h: 0.5 * 0.717, align: "left", rotation: 0, tbox: "t:0", li: 0 } ] });
  s.doc.pages.push({ name: "RENDERING 1", width: 36, height: 24, kind: "image", ref: 0, sheet_number: "A-102", views: [], pic_area: AREA.slice(), text_boxes: [],
    layers: [{ name: "TITLE", visible: true, shapes: [] }, { name: "IMAGES", visible: true, shapes: [
      { type: "image", path: "C:/r/1.jpg", x: 1, y: 2, w: 34, h: 21, pic: "m:0", iw: 2000, ih: 1000, frame: false, stretch: false } ] }] });
  s.state.texts = [JSON.parse(JSON.stringify(T1))]; s.state.pics = []; s.state.image_geo = {}; s.state.images = ["C:/r/1.jpg"];
  s.images = [{ i: 0, path: "C:/r/1.jpg", url: "file:///C:/r/1.jpg", there: true }];
  s.text_rules = JSON.parse(JSON.stringify(RULES));
  return s; };
const open = () => { api.call("loadSheet", sheet()); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };
const tb = id => (PG().text_boxes || []).find(e => e.pic === id) || null;
const TR = id => api.call("picRect", tb(id));
const trect = id => { const r = TR(id); return [r.x, r.y, r.w, r.h]; };
const lines = id => tb(id).lines.slice();
const words = () => { const l = PG().layers.find(x => x.name === "TEXT"); return l ? l.shapes : []; };
const tcorner = (id, c) => { const r = TR(id), t = r.rot * Math.PI / 180, lx = (c.indexOf("e") >= 0 ? 1 : -1) * r.w / 2, ly = (c.indexOf("n") >= 0 ? 1 : -1) * r.h / 2;
  return [r.x + r.w / 2 + lx * Math.cos(t) - ly * Math.sin(t), r.y + r.h / 2 + lx * Math.sin(t) + ly * Math.cos(t)]; };
const tgrab = (id, dx, dy, keep) => { const r = TR(id), c = scr(r.x + r.w / 2, r.y + r.h / 2);
  down(c[0], c[1]); if (dx || dy) { move(c[0] + dx / 2, c[1] + dy / 2); move(c[0] + dx, c[1] + dy); } if (!keep) up(c[0] + dx, c[1] + dy); return [c[0] + dx, c[1] + dy]; };
const type = t => { el("tbtext").value = t; el("tbtext").oninput({}); };
const keyIn = (id, k, m) => el(id).onkeydown(Object.assign({ key: k, shiftKey: false, preventDefault() {} }, m || {}));
const tclick = (px, py) => { const c = scr(px, py); svg().onmousedown(ev(c[0], c[1])); svg().onclick(ev(c[0], c[1])); };
const dbl = (px, py) => { const c = scr(px, py); click(c[0], c[1]); click(c[0], c[1]); svg().ondblclick(ev(c[0], c[1])); };
const barOpen = () => el("tbbar").className === "on";

ok("the window has the switch, and it is on", safe("TXTON") === true, safe("TXTON"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby sends the switch and its rules with the sheet", /text_box: InteriorPro::PlanCanvas::USE_TEXT_BOX && InteriorPro::PlanCanvas::USE_PIC_BOX/.test(rb) && /text_rules: text_rules_for_window/.test(rb) && /def text_rules_for_window[\s\S]{0,200}InteriorPro::PlanCanvas\.text_rules/.test(rb));   // (since 2026-10-08 the rules go through text_rules_for_window, which adds the letterings' files)
["tbWidth", "tbWrap", "tbHeight", "tbNatural", "tbShapes", "pageTexts", "tbRebuild", "tbFit", "tbHold", "tbOpen", "tbLive", "tbSave", "tbCancel", "textClick"].forEach(fn =>
  ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));
const page = fs.readFileSync("sheet.html", "utf8");
ok("there is ONE button for it, with a picture on it, and one bar to write in", (page.match(/<button id="ttext"/g) || []).length === 1 && /<button id="ttext"[^>]*>\s*<svg/.test(page) && /<textarea id="tbtext"/.test(page) && /<input id="tbsize" type="number"/.test(page));

// ================================================================ 1. the sums - rt275's numbers
open();
ok("'Pool' at 72 points is 2.001 inches wide", near(api.call("tbWidth", "Pool", 72), 2.001, 1e-12), api.call("tbWidth", "Pool", 72));
ok("'Pool deck' at 36 points is 2.1955", near(api.call("tbWidth", "Pool deck", 36), 2.1955, 1e-12), api.call("tbWidth", "Pool deck", 36));
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
ok("the words fit: one line", eq(api.call("tbWrap", "Pool deck", 2.3, 36), ["Pool deck"]));
ok("a hair too narrow: two lines", eq(api.call("tbWrap", "Pool deck", 2.19, 36), ["Pool", "deck"]));
ok("exactly as wide as the words is wide enough", eq(api.call("tbWrap", "Pool deck", 2.1955, 36), ["Pool deck"]));
ok("a line he broke himself stays broken, and an empty line stays a line", eq(api.call("tbWrap", "A\n\nB C", 100, 12), ["A", "", "B C"]), api.call("tbWrap", "A\n\nB C", 100, 12));
ok("a word wider than the box stays whole", eq(api.call("tbWrap", "Supercalifragilistic pool", 0.5, 36), ["Supercalifragilistic", "pool"]));
ok("runs of spaces, tabs and Windows line ends are tidied", eq(api.call("tbWrap", "A   B\tC\r\nD", 100, 12), ["A B C", "D"]), api.call("tbWrap", "A   B\tC\r\nD", 100, 12));
ok("one line at 72 points is 1.5 inches tall, two are 2.75", near(api.call("tbHeight", 1, 72), 1.5, 1e-12) && near(api.call("tbHeight", 2, 72), 2.75, 1e-12));
ok("'Pool deck' at 36 points needs a box 2.4455 wide", near(api.call("tbNatural", "Pool deck", 36), 2.4455, 1e-12), api.call("tbNatural", "Pool deck", 36));
let sh = api.call("tbShapes", { pic: "t:0", x: 10, y: 8, w: 3, h: 0.75, rot: 0, pt: 36, lines: ["Pool deck"] });
ok("THE LINE IS HUNG WHERE RUBY HANGS IT: x = 10.125, y = 8.225, 36 points", sh.length === 1 && near(sh[0].x, 10.125, 1e-12) && near(sh[0].y, 8.225, 1e-12) && near(sh[0].h / 0.717 * 72, 36, 1e-9) && sh[0].text === "Pool deck" && sh[0].rotation === 0 && sh[0].tbox === "t:0", sh);
sh = api.call("tbShapes", { pic: "t:0", x: 10, y: 7.375, w: 2, h: 1.375, rot: 0, pt: 36, lines: ["Pool", "deck"] });
ok("two lines: the second 0.625 lower", near(sh[0].y, 8.225, 1e-12) && near(sh[1].y, 7.6, 1e-12) && near(sh[1].x, 10.125, 1e-12), sh.map(q => [q.x, q.y]));
sh = api.call("tbShapes", { pic: "t:0", x: 10, y: 8, w: 3, h: 0.75, rot: 90, pt: 36, lines: ["Pool deck"] });
ok("turned a quarter turn about the middle of the box: 11.65, 7.0, and it carries the angle", near(sh[0].x, 11.65, 1e-9) && near(sh[0].y, 7.0, 1e-9) && sh[0].rotation === 90, sh[0]);
sh = api.call("tbShapes", { pic: "t:0", x: 10, y: 8, w: 3, h: 2, rot: 0, pt: 36, lines: ["A", "", "B"] });
ok("an empty line is room on the sheet, not a shape", sh.length === 2 && sh[1].li === 2 && near(sh[0].y - sh[1].y, 1.25, 1e-12), sh);

// ================================================================ 2. what Ruby laid is drawn, and laid the same here
open();
let h0 = html();
ok("THE WORDS RUBY LAID ARE ON THE SHEET, at 36 points", h0.indexOf(">Pool deck</text>") > 0 && h0.indexOf('font-size="' + (0.5 * K()).toFixed(1) + '"') > 0 && h0.indexOf('<text x="' + (10.125 * K()).toFixed(1) + '" y="' + ((PH - 8.225) * K()).toFixed(1) + '"') > 0, h0.slice(h0.indexOf("Pool deck") - 220, h0.indexOf("Pool deck") + 20));
ok("until he picks it there is no frame round it and the handles are on the DRAWING", h0.indexOf('id="tbframe"') < 0 && near(parseFloat(el("boxc-nw").style.left), 1 * K(), 0.06) && api.get("BSEL") === null);
const strip = l => JSON.stringify(l.map(q => { const c = Object.assign({}, q); delete c.__paper; return c; }));
const rubyWords = strip(words());
api.call("tbRebuild");
ok("LAID AGAIN BY THE WINDOW FROM WHAT IS SAVED, IT IS THE SAME TO THE LAST DIGIT  <<< two copies of one rule", strip(words()) === rubyWords && eq(trect("t:0"), [10, 8, 3, 0.75]) && eq(lines("t:0"), ["Pool deck"]), [strip(words()), rubyWords]);

// ================================================================ 3. the T tool
open();
el("ttext").onclick();
ok("the T button is a tool like the others: it is the one that is lit", api.get("MODE") === "text" && el("ttext").className === "tool on" && el("thand").className === "tool");
ok("nothing is explained under the tools (2026-10-08)", el("markinfo").textContent === "", el("markinfo").textContent);
tclick(5, 20);
ok("A CLICK ON THE SHEET OPENS THE BAR TO WRITE IN  <<< THE RULE", barOpen() && el("tbtext").value === "" && el("tbsize").value === 24 && el("tbok").textContent === "הוסף", [el("tbbar").className, el("tbsize").value]);
ok("nothing is sent and nothing can be undone yet", states().length === 0 && api.get("UNDO").length === 0);
type("Hello");
const wHello = api.call("tbNatural", "Hello", 24), hOne = api.call("tbHeight", 1, 24);
ok("WHAT HE TYPES IS ON THE SHEET AT ONCE  <<< THE RULE", html().indexOf(">Hello</text>") > 0 && eq(lines("t:1"), ["Hello"]));
ok("the box starts where he clicked and is as wide as its words", same4(trect("t:1"), [5, 20 - hOne, wHello, hOne], 1e-9), trect("t:1"));
ok("a thin frame shows the box while he writes - on the screen only", html().indexOf('id="tbframe"') > 0);
ok("the handles are put away while he writes", el("boxc-nw").className === "boxc" && el("rothandle").className === "");
ok("Ruby is not told on every letter", states().length === 0);
keyIn("tbtext", "Enter");
ok("ENTER IS A NEW LINE, NOT THE END - he asked for exactly this", barOpen() && states().length === 0 && ST().texts.length === 2);
type("Hello\nthere");
ok("a second line: the box is two lines tall and its TOP stays where he clicked", eq(lines("t:1"), ["Hello", "there"]) && near(trect("t:1")[1] + trect("t:1")[3], 20, 1e-9) && near(trect("t:1")[3], api.call("tbHeight", 2, 24), 1e-12), trect("t:1"));
el("tbsize").value = 48; el("tbsize").oninput({});
ok("THE SIZE BOX SETS HOW BIG THE LETTERS ARE  <<< THE RULE", tb("t:1").pt === 48 && near(trect("t:1")[2], api.call("tbNatural", "Hello\nthere", 48), 1e-9) && near(trect("t:1")[1] + trect("t:1")[3], 20, 1e-9) && html().indexOf('font-size="' + (48 / 72 * K()).toFixed(1) + '"') > 0, [tb("t:1").pt, trect("t:1")]);
const stage = document.getElementById("stage");
stage.scrollLeft = 120; stage.scrollTop = 80;
keyIn("tbtext", "Enter", { ctrlKey: true });
let m = states();
ok("CTRL+ENTER: Ruby is told once - the words, the sheet, the size, the box", !barOpen() && m.length === 1 && m[0].texts.length === 2 && m[0].texts[1].text === "Hello\nthere" && m[0].texts[1].on === "plan" && m[0].texts[1].pt === 48 && m[0].texts[1].rot === 0 && same4(m[0].texts[1].box, trect("t:1"), 1e-12), m.map(x => x.texts));
ok("the arrow is back in his hand with the new box picked, so he can move it at once", api.get("MODE") === "hand" && api.get("BSEL") === "t:1" && el("boxc-nw").className === "boxc on");
ok("THE VIEW DID NOT MOVE: same zoom, same place", api.get("ZOOM") === null && stage.scrollLeft === 120 && stage.scrollTop === 80);
ok("it is one step", api.get("UNDO").length === 1);
undo();
m = states();
ok("CTRL+Z TAKES THE NEW BOX OFF AGAIN, and Ruby is told", ST().texts.length === 1 && !tb("t:1") && html().indexOf("Hello") < 0 && m.length === 2 && m[1].texts.length === 1, [ST().texts.length, m.length]);
ok("the box that was there is untouched", eq(trect("t:0"), [10, 8, 3, 0.75]) && html().indexOf(">Pool deck</text>") > 0);

// Escape, Cancel, nothing typed
open(); el("ttext").onclick(); tclick(5, 20); type("Not this");
keyIn("tbtext", "Escape");
ok("ESCAPE WHILE WRITING: as if the bar had never been opened  <<< THE IRON LAW", !barOpen() && ST().texts.length === 1 && states().length === 0 && api.get("UNDO").length === 0 && html().indexOf("Not this") < 0 && api.get("BSEL") === null, [ST().texts.length, states().length]);
tclick(5, 20); type("Nor this"); el("tbcancel").onclick();
ok("the Cancel button does the same", !barOpen() && ST().texts.length === 1 && states().length === 0 && html().indexOf("Nor this") < 0);
tclick(5, 20); keyIn("tbtext", "Enter", { ctrlKey: true });
ok("Ctrl+Enter with nothing written adds nothing", !barOpen() && ST().texts.length === 1 && states().length === 0 && api.get("UNDO").length === 0);
tclick(5, 20); type("   \n  "); el("tbok").onclick();
ok("and so do spaces alone", ST().texts.length === 1 && states().length === 0);
tclick(5, 20); type("Kept");
{ const c = scr(30, 5); svg().onmousedown(ev(c[0], c[1])); }
ok("A PRESS ON THE SHEET WHILE WRITING KEEPS THE WORDS - it is 'I am done'", !barOpen() && ST().texts.length === 2 && ST().texts[1].text === "Kept" && states().length === 1 && api.get("MODE") === "hand");
el("ttext").onclick(); tclick(5, 12); type("Dropped"); key("Escape", { target: { tagName: "BODY", id: "" } });
ok("Escape from anywhere else in the window drops them too, and gives the arrow back", !barOpen() && ST().texts.length === 2 && api.get("MODE") === "hand" && html().indexOf("Dropped") < 0);

// the margins while writing
open(); el("ttext").onclick(); tclick(33, 20);
type("A long line of writing that cannot fit between here and the margin of the sheet");
ok("NEAR THE MARGIN THE LINES BREAK INSTEAD OF RUNNING OFF THE SHEET", lines("t:1").length > 1 && trect("t:1")[0] + trect("t:1")[2] <= 35 + 1e-9 && trect("t:1")[1] >= 2 - 1e-9, [trect("t:1"), lines("t:1")]);
keyIn("tbtext", "Escape");
tclick(0.2, 23.9); type("Corner");
ok("a click outside the margins starts the box inside them", trect("t:1")[0] >= 1 - 1e-9 && trect("t:1")[1] + trect("t:1")[3] <= 23 + 1e-9, trect("t:1"));
keyIn("tbtext", "Escape");

// a click with the T tool on a box that is there opens THAT box
tclick(11, 8.3);
ok("with the T tool, a click on writing that is there opens it - it does not put a second box on top", barOpen() && el("tbtext").value === "Pool deck" && el("tbsize").value === 36 && el("tbok").textContent === "סיים" && ST().texts.length === 1);
keyIn("tbtext", "Escape");

// a sheet with no drawing on it
open(); api.call("goToPage", 1); global.sent.length = 0;
el("ttext").onclick(); tclick(6, 6); type("On the render"); keyIn("tbtext", "Enter", { ctrlKey: true });
m = states();
ok("IT GOES ON ANY SHEET: on a picture sheet, with no drawing on it", m.length === 1 && m[0].texts.length === 2 && m[0].texts[1].on === "image:0" && m[0].texts[1].text === "On the render" && html().indexOf(">On the render</text>") > 0, m.map(x => x.texts));
ok("on that sheet the handles stay on the PICTURE until the writing is picked", (() => { api.set("BSEL", null); api.call("render"); return api.call("boxTarget").pic.pic === "m:0"; })());

// ================================================================ 4. picked and moved
open();
svg().onmousemove(ev(scr(11, 8.3)[0], scr(11, 8.3)[1]));
ok("over the writing the pointer says it can be moved", svg().style.cursor === "move", svg().style.cursor);
tgrab("t:0", 0, 0);
ok("A CLICK ON THE WRITING PICKS ITS BOX  <<< THE RULE", api.get("BSEL") === "t:0" && html().indexOf('id="tbframe"') > 0);
ok("THE SAME HANDLES GO ONTO IT: a square on each corner, the grip, the round arrow",
   ["nw", "ne", "sw", "se"].every(c => { const p = scr.apply(null, tcorner("t:0", c)); return el("boxc-" + c).className === "boxc on" && near(parseFloat(el("boxc-" + c).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + c).style.top), p[1], 0.06); }) &&
   el("boxmove").className === "on" && el("rothandle").className === "on");
ok("a bar on its left and its right - and none on its top or bottom: a box of writing is as tall as its lines", el("boxe-w").className === "boxe on" && el("boxe-e").className === "boxe on" && el("boxe-n").className === "boxe" && el("boxe-s").className === "boxe");
ok("a click alone changes nothing: nothing sent, nothing to undo", states().length === 0 && api.get("UNDO").length === 0 && eq(ST().texts[0].box, [10, 8, 3, 0.75]));
ok("nothing is explained under the tools (2026-10-08)", el("markinfo").textContent === "", el("markinfo").textContent);
const gh = tgrab("t:0", 100, 50, true);
ok("DRAGGED, IT MOVES WITH THE MOUSE - the box and its words  <<< THE RULE", same4(trect("t:0"), [10 + 100 / K(), 8 - 50 / K(), 3, 0.75], 1e-9) && near(words()[0].x, 10.125 + 100 / K(), 1e-9) && near(words()[0].y, 8.225 - 50 / K(), 1e-9), [trect("t:0"), words()[0]]);
ok("Ruby is not told on every step", states().length === 0);
up(gh[0], gh[1]);
m = states();
ok("ON LETTING GO Ruby is told once, where the box is", m.length === 1 && same4(m[0].texts[0].box, [10 + 100 / K(), 8 - 50 / K(), 3, 0.75], 1e-9) && m[0].texts[0].pt === 36 && m[0].texts[0].text === "Pool deck", m.map(x => x.texts));
tgrab("t:0", 9000, -9000);
ok("DRAGGED AS FAR AS HE LIKES, IT STOPS AT THE MARGINS: right and top", same4(trect("t:0"), [32, 22.25, 3, 0.75], 1e-9), trect("t:0"));
tgrab("t:0", -9000, 9000);
ok("and left and bottom", same4(trect("t:0"), [1, 2, 3, 0.75], 1e-9), trect("t:0"));
pull("boxmove", 5 * K(), -3 * K());
ok("the grip moves it too", same4(trect("t:0"), [6, 5, 3, 0.75], 1e-9), trect("t:0"));
undo();
ok("CTRL+Z takes the last move back - one step a press", same4(trect("t:0"), [1, 2, 3, 0.75], 1e-9), trect("t:0"));
// Escape with it held
open(); tgrab("t:0", 0, 0); tgrab("t:0", 80, 40, true);
key("Escape");
ok("ESCAPE WITH IT HELD puts it back where it was", same4(trect("t:0"), [10, 8, 3, 0.75], 1e-12) && eq(ST().texts[0].box, [10, 8, 3, 0.75]) && states().length === 0 && api.get("UNDO").length === 0, trect("t:0"));
up(0, 0);

// ================================================================ 5. a corner
open(); tgrab("t:0", 0, 0); global.sent.length = 0;
pull("boxc-se", 3 * K(), 0.75 * K());
ok("A CORNER MAKES BOX AND LETTERS BIGGER TOGETHER, the corner across from it stays put  <<< THE RULE", same4(trect("t:0"), [10, 7.25, 6, 1.5], 1e-9) && near(tb("t:0").pt, 72, 1e-9), [trect("t:0"), tb("t:0").pt]);
ok("the lines break where they did", eq(lines("t:0"), ["Pool deck"]) && html().indexOf('font-size="' + (1 * K()).toFixed(1) + '"') > 0);
m = states();
ok("Ruby is told once: the box and the size", m.length === 1 && same4(m[0].texts[0].box, [10, 7.25, 6, 1.5], 1e-9) && near(m[0].texts[0].pt, 72, 1e-9), m.map(x => x.texts[0]));
pull("boxc-se", -9000, -9000);
ok("PULLED IN AS FAR AS HE LIKES, THE LETTERS STOP AT 4 POINTS", near(tb("t:0").pt, 4, 1e-9) && near(trect("t:0")[2], 6 * 4 / 72, 1e-9), [tb("t:0").pt, trect("t:0")]);
pull("boxc-se", 9000, 9000);
ok("pulled out as far as he likes, it stops at the margin and the letters with it", trect("t:0")[0] + trect("t:0")[2] <= 35 + 1e-6 && trect("t:0")[1] >= 2 - 1e-6 && near(tb("t:0").pt / trect("t:0")[2], 12, 1e-6) && eq(lines("t:0"), ["Pool deck"]), [trect("t:0"), tb("t:0").pt]);

// ================================================================ 6. a side
open(); tgrab("t:0", 0, 0); global.sent.length = 0;
const sd = pull("boxe-e", -1 * K(), 30, true);
ok("WHILE HE PULLS THE RIGHT SIDE IN, THE LINES ARE LAID AGAIN  <<< THE RULE", eq(lines("t:0"), ["Pool", "deck"]) && html().indexOf(">Pool</text>") > 0 && html().indexOf(">deck</text>") > 0, lines("t:0"));
ok("THE TOP OF THE BOX STAYS WHERE IT IS, the box is as tall as two lines, the left side has not moved", same4(trect("t:0"), [10, 8.75 - 1.375, 2, 1.375], 1e-9), trect("t:0"));
ok("the letters are the size they were", tb("t:0").pt === 36);
up(sd[0], sd[1]);
m = states();
ok("on letting go Ruby is told once: the box Ruby would have laid itself (rt275)", m.length === 1 && same4(m[0].texts[0].box, [10, 7.375, 2, 1.375], 1e-9) && m[0].texts[0].pt === 36, m.map(x => x.texts[0]));
pull("boxe-e", -9000, 0);
const longest = api.call("tbWidth", "deck", 36) + 0.25;
ok("PULLED IN AS FAR AS HE LIKES, IT IS NEVER NARROWER THAN ITS LONGEST WORD", near(trect("t:0")[2], Math.max(longest, api.call("tbWidth", "Pool", 36) + 0.25), 1e-9) && eq(lines("t:0"), ["Pool", "deck"]), [trect("t:0"), longest]);
pull("boxe-e", 5 * K(), 0);
ok("pulled back out: one line again, one line tall, the top where it was", eq(lines("t:0"), ["Pool deck"]) && near(trect("t:0")[3], 0.75, 1e-9) && near(trect("t:0")[1] + trect("t:0")[3], 8.75, 1e-9), trect("t:0"));
pull("boxe-w", 9000, 0);
ok("the LEFT side: the right side stays put", near(trect("t:0")[0] + trect("t:0")[2], 10 + Math.max(api.call("tbWidth", "Pool", 36), api.call("tbWidth", "deck", 36)) + 0.25 + 5, 1e-6) && eq(lines("t:0"), ["Pool", "deck"]), trect("t:0"));
ok("the top and bottom cannot be pulled: there is no bar to pull", (() => { const before = JSON.stringify(trect("t:0")); el("boxe-n").onmousedown(ev(400, 300)); move(400, 200); up(400, 200); return JSON.stringify(trect("t:0")) === before; })());

// ================================================================ 7. the round arrow
open(); tgrab("t:0", 0, 0); global.sent.length = 0;
const turnBy = (id, deg, keep) => { const r = TR(id), c = scr(r.x + r.w / 2, r.y + r.h / 2), t = deg * Math.PI / 180;
  el("rothandle").onmousedown(ev(c[0] + 200, c[1])); move(c[0] + 200 * Math.cos(t / 2), c[1] - 200 * Math.sin(t / 2)); move(c[0] + 200 * Math.cos(t), c[1] - 200 * Math.sin(t));
  if (!keep) up(0, 0); };
turnBy("t:0", 30, true);
ok("THE ROUND ARROW TURNS THE WHOLE BOX ABOUT ITS MIDDLE  <<< THE RULE", near(TR("t:0").rot, 30, 1e-9) && same4(trect("t:0"), [10, 8, 3, 0.75], 1e-9), TR("t:0"));
ok("the words are turned with it", words()[0].rotation === 30 && /transform="rotate\(-30,/.test(html().slice(html().indexOf(">Pool deck</text>") - 120, html().indexOf(">Pool deck</text>"))), words()[0]);
ok("and so is the frame", /id="tbframe"[^>]*transform="rotate\(-30,/.test(html()));
ok("Ruby is not told while he turns", states().length === 0);
up(0, 0);
m = states();
ok("on letting go Ruby is told once: the angle", m.length === 1 && m[0].texts[0].rot === 30 && same4(m[0].texts[0].box, [10, 8, 3, 0.75], 1e-9) && m[0].texts[0].pt === 36, m.map(x => x.texts[0]));
ok("THE HANDLES TURN WITH IT", ["nw", "se"].every(c => { const p = scr.apply(null, tcorner("t:0", c)); return near(parseFloat(el("boxc-" + c).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + c).style.top), p[1], 0.06) && el("boxc-" + c).style.transform === "rotate(-30deg)"; }));
turnBy("t:0", 58);
ok("NEAR A QUARTER TURN IT LOCKS ONTO THE QUARTER TURN", TR("t:0").rot === 90, TR("t:0").rot);
const tl = tcorner("t:0", "nw");
{ const c = scr.apply(null, tcorner("t:0", "ne")); el("boxe-e").onmousedown(ev(c[0], c[1])); move(c[0], c[1] + 1 * K()); up(0, 0); }
ok("TURNED: a side still lays the lines again, and the top left corner as it is turned stays put", eq(lines("t:0"), ["Pool", "deck"]) && near(tcorner("t:0", "nw")[0], tl[0], 1e-9) && near(tcorner("t:0", "nw")[1], tl[1], 1e-9), [lines("t:0"), tcorner("t:0", "nw"), tl]);
undo(); undo(); undo();
ok("three presses of Ctrl+Z: level again, as Ruby laid it", TR("t:0").rot === 0 && same4(trect("t:0"), [10, 8, 3, 0.75], 1e-9) && eq(lines("t:0"), ["Pool deck"]) && api.get("UNDO").length === 0, TR("t:0"));

// ================================================================ 8. two clicks open it again
open(); global.sent.length = 0;
dbl(11, 8.3);
ok("TWO CLICKS ON THE WRITING OPEN ITS WORDS AND ITS SIZE  <<< THE RULE", barOpen() && el("tbtext").value === "Pool deck" && el("tbsize").value === 36 && el("tbok").textContent === "סיים" && states().length === 0, [el("tbbar").className, el("tbtext").value, states().length]);
type("Pool deck and spa");
ok("more words in a box that has a width: the lines break at that width and the top stays put", eq(lines("t:0"), ["Pool deck", "and spa"]) && near(trect("t:0")[2], 3, 1e-12) && near(trect("t:0")[1] + trect("t:0")[3], 8.75, 1e-9), [lines("t:0"), trect("t:0")]);
el("tbsize").value = 18; el("tbsize").oninput({});
ok("half the size: half the width, the lines break where they did", tb("t:0").pt === 18 && near(trect("t:0")[2], 1.5, 1e-9) && eq(lines("t:0"), ["Pool deck", "and spa"]) && near(trect("t:0")[0], 10, 1e-9) && near(trect("t:0")[1] + trect("t:0")[3], 8.75, 1e-9), [tb("t:0").pt, trect("t:0")]);
keyIn("tbsize", "Enter");
m = states();
ok("Enter in the size box ends it too: Ruby is told once, and it is ONE step", !barOpen() && m.length === 1 && m[0].texts[0].text === "Pool deck and spa" && m[0].texts[0].pt === 18 && api.get("UNDO").length === 1 && api.get("BSEL") === "t:0");
undo();
ok("Ctrl+Z: the words and the size it had", ST().texts[0].text === "Pool deck" && ST().texts[0].pt === 36 && eq(trect("t:0"), [10, 8, 3, 0.75]) && html().indexOf(">Pool deck</text>") > 0);
dbl(11, 8.3); keyIn("tbtext", "Enter", { ctrlKey: true });
ok("opened and ended with nothing changed: nothing sent, nothing to undo", !barOpen() && states().length === 2 && api.get("UNDO").length === 0, [states().length, api.get("UNDO").length]);
dbl(11, 8.3); type(""); el("tbok").onclick();
ok("EMPTIED = THROWN AWAY, and Ctrl+Z brings it back", ST().texts.length === 0 && html().indexOf("Pool deck") < 0 && (undo(), ST().texts.length === 1 && html().indexOf(">Pool deck</text>") > 0));

// two clicks on a handle of the box open it too: at the zoom that shows the
// whole sheet a line of writing is a dozen pixels tall and the corner squares
// cover it - his second click landed on a square (2026-10-07, "ניסיתי, לא נפתח")
open(); tgrab("t:0", 0, 0); global.sent.length = 0;
{ const c = scr.apply(null, tcorner("t:0", "se")); el("boxc-se").onmousedown(ev(c[0], c[1])); up(c[0], c[1]); el("boxc-se").onmousedown(ev(c[0], c[1])); up(c[0], c[1]); el("boxc-se").ondblclick(ev(c[0], c[1])); }
ok("TWO CLICKS ON A CORNER SQUARE OF THE BOX OPEN ITS WORDS TOO", barOpen() && el("tbtext").value === "Pool deck" && api.get("BOXD") === null && states().length === 0, [el("tbbar").className, states().length]);
keyIn("tbtext", "Escape");
tgrab("t:0", 0, 0);
{ const c = scr.apply(null, tcorner("t:0", "ne")); el("boxe-e").onmousedown(ev(c[0], c[1] + 2)); up(c[0], c[1] + 2); el("boxe-e").ondblclick(ev(c[0], c[1] + 2)); }
ok("and on a side bar", barOpen() && el("tbtext").value === "Pool deck" && eq(trect("t:0"), [10, 8, 3, 0.75]));
keyIn("tbtext", "Escape");
open(); api.call("goToPage", 1); api.set("BSEL", "m:0"); api.call("render");
ok("on a PICTURE's handles two clicks do nothing", (() => { el("boxc-se").ondblclick(ev(0, 0)); return !barOpen() && api.get("BSEL") === "m:0"; })());

// TWO PRESSES on the words, close together, open the box - counted by the
// window, because a press redraws the sheet and the browser's own double
// click never comes (2026-10-07, "זה עובד רק אם אני לוחץ על סימן ההזזה")
open(); global.sent.length = 0;
tgrab("t:0", 0, 0); tgrab("t:0", 0, 0);
ok("TWO QUICK PRESSES ON THE WORDS OPEN THEM, with no double click from the browser at all", barOpen() && el("tbtext").value === "Pool deck" && api.get("BOXD") === null && states().length === 0, [el("tbbar").className, states().length]);
keyIn("tbtext", "Escape");
tgrab("t:0", 60, 0); tgrab("t:0", 0, 0);
ok("a drag and then a press is not a double click", !barOpen() && api.get("BSEL") === "t:0");
up(0, 0);
api.set("TBLAST", { pic: "t:0", t: Date.now() - 2000, x: 0, y: 0 });
tgrab("t:0", 0, 0);
ok("nor is a press two seconds after the last", !barOpen());
{ const r = TR("t:0"), c = scr(r.x + r.w / 2, r.y + r.h / 2); down(c[0], c[1]); up(c[0], c[1]); down(c[0] + 40, c[1]); up(c[0] + 40, c[1]); }
ok("nor two presses far apart on the sheet", !barOpen());
keyIn("tbtext", "Escape");

// ================================================================ 9. Delete
open(); tgrab("t:0", 0, 0); global.sent.length = 0;
key("Delete");
m = states();
ok("DELETE TAKES THE PICKED BOX OFF THE SHEET  <<< THE RULE", ST().texts.length === 0 && !tb("t:0") && html().indexOf("Pool deck") < 0 && m.length === 1 && m[0].texts.length === 0 && api.get("BSEL") === null);
undo();
ok("and Ctrl+Z puts it back", ST().texts.length === 1 && eq(trect("t:0"), [10, 8, 3, 0.75]) && html().indexOf(">Pool deck</text>") > 0);

// ================================================================ 10. Ruby's answer, the layer, the switch
open(); el("ttext").onclick(); tclick(5, 20); type("Still here");
api.call("applyPages", JSON.parse(JSON.stringify(sheet().doc.pages)), null);
ok("RUBY ANSWERS SOMETHING ELSE WHILE HE WRITES: what he is typing stays on the sheet", barOpen() && html().indexOf(">Still here</text>") > 0 && html().indexOf(">Pool deck</text>") > 0);
keyIn("tbtext", "Escape");
api.call("loadSheet", sheet());
ok("a whole new sheet from Ruby shuts the bar: what Ruby has is the truth", (() => { el("ttext").onclick(); tclick(5, 20); type("Gone"); api.call("loadSheet", sheet()); return !barOpen() && ST().texts.length === 1 && html().indexOf("Gone") < 0; })());

open(); ST().hidden.push("TEXT"); api.call("render");
tgrab("t:0", 0, 0);
ok("THE TEXT LAYER SWITCHED OFF: the writing is not drawn and cannot be picked", html().indexOf("Pool deck") < 0 && api.get("BSEL") === null);
el("ttext").onclick(); tclick(5, 20);
ok("and the T tool says why it will not write", !barOpen() && /כיתובים כבויים/.test(el("markinfo").textContent), el("markinfo").textContent);

{ const s = sheet(); s.text_box = false; api.call("loadSheet", s); api.call("setMode", "hand"); global.sent.length = 0; }
ok("SWITCHED OFF BY RUBY: the button is put away and the tool cannot be taken", safe("TXTON") === false && el("ttext").style.display === "none" && (api.call("setMode", "text"), api.get("MODE") === "hand"));
tgrab("t:0", 40, 0);
ok("and a box Ruby still sent is not handled", api.get("BSEL") === null && states().length === 0);
{ const s = sheet(); s.pic_box = false; api.call("loadSheet", s); }
ok("it needs the picture handles: with those off it is off too", safe("TXTON") === false);
api.call("loadSheet", sheet());
ok("and switched on again with the next sheet", safe("TXTON") === true && el("ttext").style.display === "");

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 0 + 1 : 0);
