// t77 - one label's settings in the side panel, like Word (2026-10-07).
//
// The user: "אני לוחץ על טקסט מסוים ואז אני משנה את ההגדרות בחלון ההגדרות שכוללות
// גודל כיתוב, אפשרות להדגשה, קו מתחת, סוג כתב וצבע."
//
//   ONE click on a label      its settings show in the "גודל טקסט" box at the
//                             side - and the keyboard stays with the sheet
//   size, B, I, U, colour     each sent to Ruby under the label's key
//   the sheet                 draws the colour and the line
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
{ const sc = el("scale"); let h = ""; Object.defineProperty(sc, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") sc.children = []; } }); }
const sheet = () => { const s = fresh(); s.doc.canvases[0].layers[0].shapes[0].underline = true; s.doc.canvases[0].layers[0].shapes[0].color = "#c02020"; return s; };
const open = () => { api.call("loadSheet", sheet()); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };
const barOn = () => el("textbar").className === "on";
const tm = () => msgs("set_text_mark");

open();
let focused = false; el("txsize").focus = () => { focused = true; };
{ const c = api.call("screenOf", 120, 60); down(c[0], c[1]); }
ok("ONE CLICK ON A LABEL OPENS ITS SETTINGS IN THE SIDE PANEL  <<< THE RULE", barOn() && api.get("TSEL") && api.get("TSEL").key === "WINDOWS|W101|1" && el("txwhat").textContent === "W101", [barOn(), api.get("TSEL")]);
ok("and the box at the side is opened for him", el("texttag") && (ST().open || {}).text === true, ST().open);
ok("the keyboard stays with the sheet: the size box is not focused by a click", !focused);
ok("nothing is sent by the click itself", tm().length === 0);
{ const c = api.call("screenOf", 120, 60); up(c[0], c[1]); }
ok("letting go without moving picks the label up to carry, as it always did", !!api.get("TCARRY"));
api.call("cancelCarry");
el("txunder").onclick.call(el("txunder"));
let m = tm();
ok("U: underline is sent under the label's key, with everything else on the panel", m.length === 1 && m[0].key === "WINDOWS|W101|1" && m[0].underline === true && m[0].bold === false && m[0].color === "#000000" && m[0].pct === 100, m);
el("txcolor").value = "#1F6FEB"; el("txcolor").onchange.call(el("txcolor"));
m = tm();
ok("COLOUR: sent as #rrggbb, lower case", m.length === 2 && m[1].color === "#1f6feb" && m[1].underline === true, m[1]);
api.call("closeTextBar");
ok("done: the panel is put away", !barOn());

// what the label already has shows in the panel
{ const c = api.call("screenOf", 0, 0); down(c[0], c[1]); up(c[0], c[1]); api.call("cancelCarry"); }
ok("a label that is underlined and red shows so in the panel", api.get("TSEL").key === "ROOMS|ROOM 2|1" && el("txunder").className === "tool on" && el("txcolor").value === "#c02020", [el("txunder").className, el("txcolor").value]);
const h = html();
ok("THE SHEET DRAWS IT: red, with a line under it", h.indexOf('fill="#c02020"') > 0 && h.indexOf('text-decoration="underline"') > 0 && h.indexOf('>ROOM 2</text>') > 0);
ok("and the others are black, with no line", (h.match(/fill="#000"/g) || []).length >= 3 && (h.match(/text-decoration="underline"/g) || []).length === 1);
api.call("closeTextBar");

// two clicks still open it too, and then the size box IS ready to type in
focused = false;
{ const c = api.call("screenOf", 120, 60); svg().ondblclick(ev(c[0], c[1])); }
ok("two clicks: open, and the size box takes the keyboard", barOn() && focused);
api.call("closeTextBar");

// the old floating bar is gone from over the sheet
const page = fs.readFileSync("sheet.html", "utf8");
const stage = page.slice(page.indexOf('<div id="stage">'));
ok("the bar is no longer floating over the sheet: it is in the side panel", stage.indexOf('id="textbar"') < 0 && page.indexOf('id="textbar"') > 0 && page.indexOf('id="txunder"') > 0 && page.indexOf('id="txcolor"') > 0);

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
