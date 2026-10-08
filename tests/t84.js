// t84 - stage 4 of the box: "playing inside" (2026-10-08).
//
// His plan for the drawing's box (HANDOFF_2026-10-07, part ד'): 4 = "משחקים
// בפנים" - the scale and the place of the drawing INSIDE the box, with the
// box staying where it is - "לוודא בקופסה קטנה". The two were already there
// (the scale list; Alt+drag moves the drawing); this suite holds them to a
// SMALL box, on the real handlers:
//   Alt+drag inside the box      the drawing slides inside, the box does not move,
//                                the lines stay clipped to it, Ruby is told once
//   a scale from the list        the drawing changes size about the middle of the
//                                box; the box does not move
//   Alt+drag over a mark/label   still moves the drawing (Alt wins), not the mark
//
// The DOM stand-in is the one t72 uses, copied: each suite stands alone.
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

const tap = (x, y, m) => { svg().onmousemove(ev(x, y, m)); svg().onmousedown(ev(x, y, m)); up(x, y, m); svg().onclick(ev(x, y, m)); };
const S = (mx, my) => api.call("screenOf", mx, my);
const near = (a, b, tol) => Math.abs(a - b) < (tol === undefined ? 1e-6 : tol);
const el = id => document.getElementById(id);
const V = () => api.get("PAGE").views[0];
const box = () => { const v = V(); return [v.x, v.y, v.w, v.h]; };
const sameBox = (a, b, tol) => a.every((n, i) => near(n, b[i], tol === undefined ? 1e-6 : tol));
const K = () => api.get("VIEW").k;
const PH = () => api.get("PAGE").height;
// where a corner of the box is on the screen: 'nw' 'ne' 'sw' 'se'
const cornerAt = c => { const v = V(), k = K(); return [(c.indexOf("e") >= 0 ? v.x + v.w : v.x) * k, (PH() - (c.indexOf("n") >= 0 ? v.y + v.h : v.y)) * k]; };
// hold a handle, move the mouse by (dx, dy) pixels in two steps, and (unless told not to) let go
const pull = (id, dx, dy, keep) => { const c = id.indexOf("boxc-") === 0 ? cornerAt(id.slice(5)) : [300, 300];
  el(id).onmousedown(ev(c[0], c[1])); move(c[0] + dx / 2, c[1] + dy / 2); move(c[0] + dx, c[1] + dy); if (!keep) up(c[0] + dx, c[1] + dy); return [c[0] + dx, c[1] + dy]; };
const states = () => msgs("set_state");
// the stand-in page keeps every option ever added to a list; a real one empties it when it is filled again
{ const sc = el("scale"); let h = ""; Object.defineProperty(sc, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") sc.children = []; } }); }
// the sheet, with the part the margins leave said out loud the way Ruby says it
const sheet = () => { const s = fresh(); s.doc.pages[0].view_area = [1, 1, 30, 22]; return s; };


const sheet4 = () => { const s = sheet(); s.scales = ['1/4"', '1/8"', '1/16"']; return s; };
api.call("loadSheet", sheet4());
api.call("setMode", "hand");
const stage = document.getElementById("stage");
const k0 = K();
// a small box: the bottom right corner pulled half way to the top left one (as t72 does), then let go
{ const v0 = V(), W0 = v0.w * k0, H0 = v0.h * k0; const held = pull("boxc-se", -W0 / 2, -H0 / 2, true); up(held[0], held[1]); }
ok("(a small box, a quarter of the sheet, with the drawing at half size)", sameBox(box(), [1, 12, 15, 11]) && near(api.get("STATE").scale_f, 0.125, 1e-12), [box(), api.get("STATE").scale_f]);
const BOX = box();
const clipOf = () => { const m = html().match(/<clipPath[^>]*>\s*<rect[^>]*x="([-\d.]+)"[^>]*y="([-\d.]+)"[^>]*width="([-\d.]+)"[^>]*height="([-\d.]+)"/); return m ? m.slice(1, 5).map(Number) : null; };
function html() { return document.getElementById("sheetWrap").innerHTML; }
const centre = () => [(BOX[0] + BOX[2] / 2) * K(), (PH() - (BOX[1] + BOX[3] / 2)) * K()];

// ================================================================ 1. Alt+drag inside: the drawing slides, the box stays
global.sent.length = 0; api.set("UNDO", []);
const o0 = [api.get("STATE").origin_x, api.get("STATE").origin_y];
const p0 = S(0, 0);                                     // where the house's origin is on the screen
const c = centre();
drag(c[0], c[1], c[0] + 100, c[1] + 50, { altKey: true });
const p1 = S(0, 0);
ok("ALT+DRAG INSIDE THE BOX SLIDES THE DRAWING: the house went where the mouse went", near(p1[0] - p0[0], 100, 1e-6) && near(p1[1] - p0[1], 50, 1e-6), [p0, p1]);
ok("...by moving the origin of the drawing, not the box", !sameBox([api.get("STATE").origin_x, api.get("STATE").origin_y, 0, 0], [o0[0], o0[1], 0, 0]) && sameBox(box(), BOX), [api.get("STATE").origin_x, api.get("STATE").origin_y, box()]);
ok("the size of the drawing did not change", near(api.get("STATE").scale_f, 0.125, 1e-12), api.get("STATE").scale_f);
ok("the lines are still clipped to the box", (() => { const cl = clipOf(); return cl && near(cl[0], BOX[0] * K(), 0.1) && near(cl[1], (PH() - (BOX[1] + BOX[3])) * K(), 0.1) && near(cl[2], BOX[2] * K(), 0.1) && near(cl[3], BOX[3] * K(), 0.1); })(), [clipOf(), BOX.map(v => v * K())]);
ok("Ruby was told once, with the new origin", states().length === 1 && near(states()[0].origin_x, api.get("STATE").origin_x, 1e-9) && sameBox(states()[0].view_box, BOX), states().map(s => [s.origin_x, s.origin_y, s.view_box]));
ok("THE VIEW DID NOT MOVE: same zoom, same tool", api.get("ZOOM") === null && api.get("MODE") === "hand");
ok("the handles are still on the box", ["nw", "ne", "sw", "se"].every(cn => { const p = cornerAt(cn); return near(parseFloat(el("boxc-" + cn).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + cn).style.top), p[1], 0.06); }));

// ================================================================ 2. a scale from the list: the drawing changes size about the middle of the box
global.sent.length = 0;
const mid = centre();
const atMid = api.call("atMouse", ev(mid[0], mid[1]));     // the point of the house in the middle of the box, before
el("scale").value = '1/8"'; el("scale").onchange.call(el("scale"));
ok("A SCALE FROM THE LIST: the drawing is at that scale now", api.get("STATE").scale === '1/8"' && api.get("STATE").scale_f === null && near(api.call("scaleFactor", api.get("STATE").scale), 0.125 / 12, 1e-12), [api.get("STATE").scale, api.get("STATE").scale_f]);
ok("the box did not move", sameBox(box(), BOX), box());
{ const q = S(atMid[0], atMid[1]); ok("what was in the middle of the box is still in the middle of the box", near(q[0], mid[0], 1e-6) && near(q[1], mid[1], 1e-6), [q, mid]); }
el("scale").value = '1/16"'; el("scale").onchange.call(el("scale"));
ok("a smaller scale: a hundred inches of house is half as long on the sheet, the box the same", near(S(100, 0)[0] - S(0, 0)[0], 100 * (0.0625 / 12) * K(), 1e-6) && sameBox(box(), BOX));
ok("Ruby was told each time", states().length === 2);

// ================================================================ 3. Alt wins over whatever is under the mouse
api.call("loadSheet", sheet4()); api.call("setMode", "hand"); global.sent.length = 0;
{ const d = api.get("STATE").marks.find(m => m.t === "dim"); const lp = api.call("dimLabelXY", d); const q = S(lp[0], lp[1]);
  const o1 = [api.get("STATE").origin_x, api.get("STATE").origin_y];
  const before = JSON.stringify(d);
  drag(q[0], q[1], q[0] + 60, q[1] + 30, { altKey: true });
  ok("ALT+DRAG STARTING ON A DIMENSION'S NUMBER moves the drawing, not the number", JSON.stringify(api.get("STATE").marks.find(m => m.t === "dim")) === before && !near(api.get("STATE").origin_x, o1[0], 1e-9) && api.get("SEL") === null && !api.get("CARRY"),
     [api.get("STATE").marks.find(m => m.t === "dim"), api.get("STATE").origin_x, o1, api.get("SEL")]); }
{ const q = S(0, 0);        // ROOM 2's label is at the house's origin
  const o2 = [api.get("STATE").origin_x, api.get("STATE").origin_y];
  drag(q[0], q[1], q[0] + 40, q[1], { altKey: true });
  ok("Alt+drag starting on a room name moves the drawing, not the name", !near(api.get("STATE").origin_x, o2[0], 1e-9) && !api.get("TSEL") && !api.get("TCARRY") && msgs("set_text_mark").length === 0, [api.get("STATE").origin_x, o2, api.get("TSEL")]); }
{ const q = S(-350, 0);     // on a loose line of the yard
  const o3 = [api.get("STATE").origin_x, api.get("STATE").origin_y];
  drag(q[0], q[1], q[0] + 40, q[1], { altKey: true });
  ok("Alt+drag starting on a loose line moves the drawing, and picks nothing", !near(api.get("STATE").origin_x, o3[0], 1e-9) && api.get("SSEL").length === 0, [api.get("STATE").origin_x, o3, api.get("SSEL")]); }
// without Alt a press on the number still picks it, as it always did
{ const d = api.get("STATE").marks.find(m => m.t === "dim"); const lp = api.call("dimLabelXY", d); const q = S(lp[0], lp[1]);
  down(q[0], q[1]);
  ok("(without Alt a press on the number still picks the dimension)", api.get("SEL") === 0 && !!api.get("MDRAG"), [api.get("SEL"), api.get("MDRAG")]);
  up(q[0], q[1]); key("Escape"); }

console.log(fails === 0 ? "t84 ALL PASS" : "\n*** " + fails + " FAILED ***");
process.exit(fails === 0 ? 0 : 1);
