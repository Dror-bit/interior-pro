// t80 - the drawing's box turns AS A WHOLE (2026-10-07, stage 5 of the box),
// the window's side.
//
// The user, on Rayon: "השרטוט הוא כאילו חצי תמונה - הוא נמצא בתוך כמו קופסה
// משל עצמו... וכמובן אני גם יכול לסובב אותה ולהזיז אותה על הדף." Until now
// the lines turned inside a frame that stayed square to the paper.
//
// THE RULE, when Ruby says the frame turns (view.box_turn):
//   the frame       the clip and the dashed frame are the rectangle turned
//                   about its middle; the handles turn with it, like a picture's
//   the round arrow turns the whole box; a box that would hang off the margins
//                   is made smaller as a whole (the scale is not touched) and
//                   pushed in; Ruby is told the angle AND the box it left
//   a corner        the box and the drawing grow together, the corner across
//                   stays put - in the box's own frame
//   a side          cuts, in the box's own frame: every line stays on its spot
//   the grip        moves the box; it cannot leave the margins, turned
//   Escape puts a half-done turn, pull or cut back; Ctrl+Z takes the last one
//   back - a turn's box with its angle; Ruby is told once.
// Not turned, or the switch off: everything as t71/t72/t73 pin it.
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
// the stand-in page keeps every option ever added to a list; a real one empties it when it is filled again
{ const sc = el("scale"); let h = ""; Object.defineProperty(sc, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") sc.children = []; } }); }
// the sheet, with the part the margins leave said out loud the way Ruby says it
const sheet = () => { const s = fresh(); s.doc.pages[0].view_area = [1, 1, 30, 22]; return s; };
// the sheet, with the part the margins leave, and the frame told to turn
const turning = (rot, vbox) => { const s = sheet(); s.doc.pages[0].views[0].box_turn = true;
  if (rot) s.state.rotation = rot;
  if (vbox) { s.state.view_box = vbox.slice(); Object.assign(s.doc.pages[0].views[0], { x: vbox[0], y: vbox[1], w: vbox[2], h: vbox[3] }); }
  return s; };
const states = () => msgs("set_state");
const open = (s) => { api.call("loadSheet", s); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };
const html = () => document.getElementById("sheetWrap").innerHTML;
const deg = () => api.get("STATE").rotation || 0;
const SF = () => api.call("scaleFactor", api.get("STATE").scale);
// where a spot of the house is on the screen
const S2 = (mx, my) => api.call("screenOf", mx, my);
// a corner of the TURNED box on the screen (picScreen's sum)
const tcorner = c => { const r = api.call("viewRect"), k = K(), t = r.rot * Math.PI / 180, u = (c.indexOf("e") >= 0 ? 1 : -1) * r.w * k / 2, v = (c.indexOf("n") >= 0 ? -1 : 1) * r.h * k / 2;
  return [(r.x + r.w / 2) * k + u * Math.cos(t) + v * Math.sin(t), (PH() - (r.y + r.h / 2)) * k - u * Math.sin(t) + v * Math.cos(t)]; };
const hull = () => { const r = api.call("viewRect"), t = r.rot * Math.PI / 180, c = Math.abs(Math.cos(t)), n = Math.abs(Math.sin(t)), hw = (r.w * c + r.h * n) / 2, hh = (r.w * n + r.h * c) / 2;
  return [r.x + r.w / 2 - hw, r.y + r.h / 2 - hh, r.x + r.w / 2 + hw, r.y + r.h / 2 + hh]; };
const inArea = (a) => { const h = hull(), e = 1e-6; return h[0] >= a[0] - e && h[1] >= a[1] - e && h[2] <= a[0] + a[2] + e && h[3] <= a[1] + a[3] + e; };
// hold the round arrow and sweep by d degrees about the middle of the box
const turnBy = (d, keep) => { const v = api.get("VIEW"), c = [v.cx * v.k, (PH() - v.cy) * v.k], h = el("rothandle"), p0 = [parseFloat(h.style.left), parseFloat(h.style.top)];
  const a0 = Math.atan2(-(p0[1] - c[1]), p0[0] - c[0]), R = Math.hypot(p0[0] - c[0], p0[1] - c[1]);
  const at = x => [c[0] + R * Math.cos(a0 + x * Math.PI / 180), c[1] - R * Math.sin(a0 + x * Math.PI / 180)];
  h.onmousedown(ev(p0[0], p0[1])); move(at(d / 2)[0], at(d / 2)[1]); move(at(d)[0], at(d)[1]); if (!keep) up(at(d)[0], at(d)[1]); return at(d); };

["boxTurns", "viewRect", "viewHold", "turnBoxTo", "dragBoxTurned"].forEach(fn => ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));
const rbsrc = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby takes the box with the turn (set_rotation), and writes a trace line", /r\.key\?\('view_box'\)/.test(rbsrc) && /erase_trace\(format\('turn: /.test(rbsrc));

// ================================================================ 1. not turned: nothing changes
open(turning(0));
ok("a sheet whose frame may turn, not turned: the box is all the margins leave, the handles square on the corners",
   api.call("boxTurns") === true && sameBox(box(), [1, 1, 30, 22]) && api.call("viewRect").rot === 0 &&
   ["nw", "ne", "sw", "se"].every(c => { const h = el("boxc-" + c), p = cornerAt(c); return h.className === "boxc on" && near(parseFloat(h.style.left), p[0], 0.06) && near(parseFloat(h.style.top), p[1], 0.06) && !h.style.transform; }));
ok("no turn on the clip or the frame", !/clipPath id="vclip"><rect[^>]*transform/.test(html()) && !/stroke-dasharray="5 4" transform/.test(html()));
const rh0 = api.call("rotHandleAt", V(), K(), PH());
ok("the round arrow by the bottom right corner, as always", near(parseFloat(el("rothandle").style.left), rh0[0], 0.06) && near(parseFloat(el("rothandle").style.top), rh0[1], 0.06));

// ================================================================ 2. turned 30, a box that fits
open(turning(30, [8, 5, 12, 8]));
const k = K(), cx = (8 + 6) * k, cy = (PH() - 9) * k;
ok("TURNED 30: the clip is the rectangle turned about its middle", new RegExp('<clipPath id="vclip"><rect x="' + (8 * k).toFixed(1) + '" y="' + ((PH() - 13) * k).toFixed(1) + '" width="' + (12 * k).toFixed(1) + '" height="' + (8 * k).toFixed(1) + '" transform="rotate\\(-30,' + cx.toFixed(2) + ',' + cy.toFixed(2) + '\\)"/></clipPath>').test(html()), html().match(/<clipPath[^]*?<\/clipPath>/)[0]);
ok("and the dashed frame with it", new RegExp('stroke-dasharray="5 4" transform="rotate\\(-30,' + cx.toFixed(2) + ',' + cy.toFixed(2) + '\\)"').test(html()));
ok("THE HANDLES TURN WITH THE BOX: each square on ITS turned corner, turned",
   ["nw", "ne", "sw", "se"].every(c => { const h = el("boxc-" + c), p = tcorner(c); return h.className === "boxc on" && near(parseFloat(h.style.left), p[0], 0.06) && near(parseFloat(h.style.top), p[1], 0.06) && h.style.transform === "rotate(-30deg)"; }),
   ["nw", "ne", "sw", "se"].map(c => [el("boxc-" + c).style.left, el("boxc-" + c).style.top, tcorner(c)]));
ok("the sides and the grip too", ["boxe-n", "boxe-s", "boxe-w", "boxe-e", "boxmove"].every(id => el(id).className.indexOf("on") >= 0 && el(id).style.transform === "rotate(-30deg)"));
{ const se = tcorner("se"), t = 30 * Math.PI / 180, want = [se[0] + 22 * Math.cos(t) + 8 * Math.sin(t), se[1] - 22 * Math.sin(t) + 8 * Math.cos(t)];
  ok("the round arrow by the TURNED bottom right corner", near(parseFloat(el("rothandle").style.left), want[0], 0.06) && near(parseFloat(el("rothandle").style.top), want[1], 0.06), [el("rothandle").style.left, el("rothandle").style.top, want]); }
ok("the house hangs from the middle of the box, turned", (() => { const p = S2(0, 0); return near(p[0], cx, 1e-6) && near(p[1], cy, 1e-6); })());

// a corner: along the box's own diagonal
{ const se = tcorner("se"), t = 30 * Math.PI / 180, d = 60;          // 60 px out along the box's diagonal, in the box's frame
  const dl = [d * 12 / Math.hypot(12, 8), -d * 8 / Math.hypot(12, 8)];  // (right, up) in the box's frame, pixels
  const px = [dl[0] * Math.cos(t) - (-dl[1]) * Math.sin(t), -(dl[0] * Math.sin(t) + (-dl[1]) * Math.cos(t))];   // on the screen (y down)
  const nw0 = tcorner("nw"), s0 = SF();
  el("boxc-se").onmousedown(ev(se[0], se[1])); move(se[0] + px[0] / 2, se[1] + px[1] / 2); move(se[0] + px[0], se[1] + px[1]);
  const b = box(), f = b[2] / 12;
  ok("A CORNER PULLED OUT ALONG THE BOX'S OWN DIAGONAL: the box grows, the same shape, and the corner ACROSS stays put",
     f > 1.05 && near(b[3] / b[2], 8 / 12, 1e-9) && near(tcorner("nw")[0], nw0[0], 1e-6) && near(tcorner("nw")[1], nw0[1], 1e-6) && deg() === 30, [b, tcorner("nw"), nw0]);
  ok("and the drawing grows with it: a size set by hand", near(SF(), s0 * f, 1e-12) && api.get("STATE").scale_f > 0, [SF(), s0 * f]);
  ok("Ruby is not told on every step", states().length === 0);
  key("Escape");
  ok("ESCAPE: the box, the size and the handles back", sameBox(box(), [8, 5, 12, 8]) && !api.get("STATE").scale_f && near(parseFloat(el("boxc-se").style.left), se[0], 0.06), [box(), api.get("STATE").scale_f]);
  up(se[0] + px[0], se[1] + px[1]);
  ok("letting go after Escape changes nothing", sameBox(box(), [8, 5, 12, 8]) && states().length === 0 && api.get("UNDO").length === 0); }

// a side: a cut in the box's own frame, the lines stay
{ const t = 30 * Math.PI / 180, spots = [S2(0, 0), S2(240, 0), S2(-300, 410.5)], o0 = [api.get("STATE").origin_x, api.get("STATE").origin_y];
  const e0 = [el("boxe-e").style.left, el("boxe-e").style.top].map(parseFloat), d = 3 * K();      // 3 inches IN, along the box's own x
  const px = [-d * Math.cos(t), d * Math.sin(t)];
  el("boxe-e").onmousedown(ev(e0[0], e0[1])); move(e0[0] + px[0] / 2, e0[1] + px[1] / 2); move(e0[0] + px[0], e0[1] + px[1]);
  const b = box();
  ok("A SIDE OF THE TURNED BOX PULLED IN BY 3 INCHES: 3 inches narrower, the same height, still turned 30", near(b[2], 9, 1e-9) && near(b[3], 8, 1e-9) && deg() === 30, b);
  ok("the west corner of the box did not move", near(tcorner("nw")[0], (() => { const r = { x: 8, y: 5, w: 12, h: 8 }; return (r.x + r.w / 2) * K() - r.w * K() / 2 * Math.cos(t) + (-r.h * K() / 2) * Math.sin(t); })(), 1e-6));
  ok("EVERY LINE STAYS ON ITS SPOT OF THE PAPER", [S2(0, 0), S2(240, 0), S2(-300, 410.5)].every((p, i) => near(p[0], spots[i][0], 1e-6) && near(p[1], spots[i][1], 1e-6)), [[S2(0, 0), S2(240, 0)], spots]);
  ok("(the house slid in the box by half the cut, the size untouched)", !near(api.get("STATE").origin_x, o0[0], 1e-6) && !api.get("STATE").scale_f, [api.get("STATE").origin_x, o0[0]]);
  up(e0[0] + px[0], e0[1] + px[1]);
  ok("letting go: one step for Ctrl+Z, Ruby told once, with the box", api.get("UNDO").length === 1 && states().length === 1 && sameBox(states()[0].view_box, b, 1e-9) && states()[0].rotation === 30, [api.get("UNDO").length, states().length]);
  key("z", { ctrlKey: true, code: "KeyZ" });
  ok("CTRL+Z: the box and the house back where they were", sameBox(box(), [8, 5, 12, 8]) && near(api.get("STATE").origin_x, o0[0], 1e-9) && near(api.get("STATE").origin_y, o0[1], 1e-9) && [S2(0, 0), S2(240, 0)].every((p, i) => near(p[0], spots[i][0], 1e-6) && near(p[1], spots[i][1], 1e-6)), box()); }

// the grip: the box moves, and cannot leave the margins turned
{ global.sent.length = 0; api.set("UNDO", []);
  const g0 = [el("boxmove").style.left, el("boxmove").style.top].map(parseFloat), sp = S2(0, 0);
  el("boxmove").onmousedown(ev(g0[0], g0[1])); move(g0[0] + 15, g0[1] + 10); move(g0[0] + 30, g0[1] + 20);
  const b = box(), dx = 30 / K(), dy = -20 / K();
  ok("THE GRIP: the box moves by the pull, turned as it was, the house with it", near(b[0], 8 + dx, 1e-9) && near(b[1], 5 + dy, 1e-9) && near(b[2], 12, 1e-9) && near(S2(0, 0)[0], sp[0] + 30, 1e-6) && near(S2(0, 0)[1], sp[1] + 20, 1e-6) && deg() === 30, b);
  move(g0[0] + 3000, g0[1] + 3000);
  ok("pulled far past the corner: it stops where the TURNED box still fits inside the margins", inArea([1, 1, 30, 22]) && (hull()[2] > 30.999 || hull()[1] < 1.001), [hull(), box()]);
  up(g0[0] + 3000, g0[1] + 3000);
  ok("one step, Ruby told once", api.get("UNDO").length === 1 && states().length === 1); }

// ================================================================ 3. the round arrow turns the whole box
open(turning(0));
{ const s0 = SF();
  turnBy(90);
  const b = box();
  ok("A QUARTER TURN OF THE WHOLE-OF-THE-MARGINS BOX: it would hang off the sheet, so it is made smaller as a whole, in the middle, the shape kept",
     deg() === 90 && inArea([1, 1, 30, 22]) && near(b[2] / b[3], 30 / 22, 1e-9) && near(b[2], 22, 1e-9) && near(b[0] + b[2] / 2, 16, 1e-9) && near(b[1] + b[3] / 2, 12, 1e-9), [deg(), b]);
  ok("THE SCALE IS NOT TOUCHED BY A TURN", near(SF(), s0, 1e-12) && !api.get("STATE").scale_f);
  ok("the box is saved, and Ruby is told the angle AND the box, once", sameBox(api.get("STATE").view_box, b, 1e-9) && msgs("set_rotation").length === 1 && msgs("set_rotation")[0].rotation === 90 && sameBox(msgs("set_rotation")[0].view_box, b, 1e-9), msgs("set_rotation"));
  ok("the handles are on the turned, smaller box", ["nw", "ne", "sw", "se"].every(c => { const h = el("boxc-" + c), p = tcorner(c); return near(parseFloat(h.style.left), p[0], 0.06) && near(parseFloat(h.style.top), p[1], 0.06) && h.style.transform === "rotate(-90deg)"; }));
  ok("one step for Ctrl+Z", api.get("UNDO").length === 1);
  global.sent.length = 0;
  key("z", { ctrlKey: true, code: "KeyZ" });
  ok("CTRL+Z: the angle AND the box back - all the margins leave again, no box saved; Ruby told once with null for the box",
     deg() === 0 && sameBox(box(), [1, 1, 30, 22]) && !api.get("STATE").view_box && msgs("set_rotation").length === 1 && msgs("set_rotation")[0].rotation === 0 && msgs("set_rotation")[0].view_box === null, [deg(), box(), api.get("STATE").view_box, msgs("set_rotation")]);
  // a small turn that still fits: the box is not touched
  global.sent.length = 0; api.set("UNDO", []);
  open(turning(0, [8, 5, 12, 8]));
  turnBy(20);
  ok("a turn that still fits: the box is left exactly as it was", deg() === 20 && sameBox(box(), [8, 5, 12, 8]) && sameBox(api.get("STATE").view_box, [8, 5, 12, 8]) && msgs("set_rotation").length === 1 && sameBox(msgs("set_rotation")[0].view_box, [8, 5, 12, 8]), [deg(), box()]);
  // Escape in the middle of a turn that shrank the box
  global.sent.length = 0; api.set("UNDO", []);
  open(turning(0));
  const p = turnBy(90, true);
  ok("held at a quarter turn: the box is already smaller on the screen", deg() === 90 && box()[2] < 29);
  key("Escape");
  ok("ESCAPE MID-TURN: the angle and the box back", deg() === 0 && sameBox(box(), [1, 1, 30, 22]) && !api.get("STATE").view_box, [deg(), box()]);
  up(p[0], p[1]);
  ok("letting go after Escape tells Ruby nothing", msgs("set_rotation").length === 0 && api.get("UNDO").length === 0); }

// ================================================================ 4. the switch (the frame told not to turn)
{ const s = sheet(); s.state.rotation = 30; open(s);
  ok("SWITCHED OFF (box_turn not on the view): the frame stays square, no turn on the clip, the handles square", api.call("boxTurns") === false && api.call("viewRect").rot === 0 &&
     !/clipPath id="vclip"><rect[^>]*transform/.test(html()) && ["nw", "ne", "sw", "se"].every(c => { const h = el("boxc-" + c), p = cornerAt(c); return near(parseFloat(h.style.left), p[0], 0.06) && near(parseFloat(h.style.top), p[1], 0.06) && !h.style.transform; }));
  global.sent.length = 0;
  turnBy(30);
  ok("a turn: the box is not touched and Ruby is told the angle only, as before", deg() === 60 && sameBox(box(), [1, 1, 30, 22]) && msgs("set_rotation").length === 1 && msgs("set_rotation")[0].view_box === undefined, msgs("set_rotation")); }

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
