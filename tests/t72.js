// t72 - the drawing sits in a box of its own: moved about the sheet, and made
// bigger or smaller by its corners (2026-10-07), the window's side.
//
// The user, on what he likes in Rayon: "השרטוט הוא כאילו חצי תמונה - הוא נמצא
// בתוך כמו קופסה משל עצמו. את הקופסה אני יכול להגדיל ולהקטין בעיקר מהפינות...
// ולהזיז אותה על הדף." And on how it should behave: "הקופסה לא צריכה להיצמד,
// אבל כן טוב לקבוע שוליים לדף שהקופסה לא תוכל לצאת מהם. לא רוצה שקנה המידה
// יקפוץ - אני רוצה שתהיה אופציה להגדיל ידנית, ושלהגדיר בגדלים נכונים."
//
// THE RULE:
//   a corner     the box and the drawing grow or shrink TOGETHER, about the
//                opposite corner: what he sees in the box stays what he saw.
//                Any size at all - nothing snaps, nothing jumps.
//   the box      dragged by its grip or by a side, it moves about the sheet
//                and the drawing goes with it, the same size.
//   the margins  the box cannot leave what the margins leave.
//   the list     picking a scale from the list puts the drawing back on that
//                exact scale; the box stays where it is.
//   Escape puts a half-done move or resize back; Ctrl+Z takes the last one
//   back; Ruby is told once, on letting go; the zoom and the place stay.
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

ok("the window has the switch, and it is on", safe("BOXON") === true, safe("BOXON"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby sends the switch with the sheet", /view_box: InteriorPro::PlanCanvas::USE_VIEW_BOX/.test(rb));
const page = fs.readFileSync("sheet.html", "utf8");
ok("the window has a square for each corner, a grip, and four sides to hold",
   ["boxc-nw", "boxc-ne", "boxc-sw", "boxc-se", "boxmove", "boxe-n", "boxe-s", "boxe-w", "boxe-e"].every(id => page.indexOf('id="' + id + '"') > page.indexOf('<div id="sheetWrap">')));
["startBox", "dragBox", "restoreBox", "paintBoxH", "paintScale", "boxArea", "planView"].forEach(fn =>
  ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));

// ================================================================ 1. a sheet as it always was
api.call("loadSheet", sheet());
api.call("setMode", "hand");
const html0 = document.getElementById("sheetWrap").innerHTML;
ok("a sheet that never heard of the box: the box is the whole of what the margins leave", sameBox(box(), [1, 1, 30, 22]) && api.get("STATE").view_box === undefined);
ok("and the drawing is at the scale from the list", near(api.call("scaleFactor", api.get("STATE").scale), 0.25 / 12, 1e-12));
const k0 = K();
ok("THE FOUR CORNERS EACH HAVE A SQUARE, exactly on the corner  <<< THE RULE",
   ["nw", "ne", "sw", "se"].every(c => { const h = el("boxc-" + c), p = cornerAt(c); return h.className === "boxc on" && near(parseFloat(h.style.left), p[0], 0.06) && near(parseFloat(h.style.top), p[1], 0.06); }),
   ["nw", "ne", "sw", "se"].map(c => [el("boxc-" + c).className, el("boxc-" + c).style.left, el("boxc-" + c).style.top, cornerAt(c)]));
ok("there is a grip to move it by, outside its top left corner", el("boxmove").className === "on" && parseFloat(el("boxmove").style.left) < cornerAt("nw")[0] && parseFloat(el("boxmove").style.top) < cornerAt("nw")[1]);
ok("and its four sides can be held", ["n", "s", "w", "e"].every(d => el("boxe-" + d).className === "boxe on"));
ok("none of it is written into the drawing - it cannot print or reach a thumbnail", html0.indexOf("boxc") < 0 && html0.indexOf("boxmove") < 0);
api.call("setMode", "dim");
ok("with another tool in the hand the handles are put away", ["boxc-nw", "boxc-se", "boxmove", "boxe-n"].every(id => !/\bon\b/.test(el(id).className)), el("boxc-nw").className);
api.call("setMode", "hand");

// a sheet from before Ruby said which part the margins leave: the window works it out the same way
api.call("loadSheet", fresh());
ok("with nothing said about the margins, the window works them out the way Ruby does", sameBox(api.call("boxArea"), [0.75, 1.85, 34.5, 21.4]), api.call("boxArea"));
api.call("loadSheet", sheet());
api.call("setMode", "hand");

// ================================================================ 2. a corner: the box and the drawing together
const stage = document.getElementById("stage");
stage.scrollLeft = 120; stage.scrollTop = 80;
global.sent.length = 0;
// the bottom right corner, pulled half way to the top left one
let v0 = V(), W0 = v0.w * k0, H0 = v0.h * k0;
const held = pull("boxc-se", -W0 / 2, -H0 / 2, true);
ok("WHILE HE PULLS A CORNER THE BOX SHRINKS ABOUT THE OPPOSITE CORNER  <<< THE RULE", sameBox(box(), [1, 12, 15, 11]), box());
ok("...AND THE DRAWING SHRINKS WITH IT: half the box, half the size", near(api.call("scaleFactor", api.get("STATE").scale), 0.125 / 12, 1e-12), api.call("scaleFactor", api.get("STATE").scale) * 12);
ok("Ruby is not told on every step", states().length === 0, states().length);
up(held[0], held[1]);
let m = states();
ok("ON LETTING GO Ruby is told once: where the box is and how big the drawing is",
   m.length === 1 && sameBox(m[0].view_box, [1, 12, 15, 11]) && near(m[0].scale_f, 0.125, 1e-12), m.map(x => [x.view_box, x.scale_f]));
ok("what he saw in the middle of the box is still in the middle of the box",
   near(S(0, 0)[0], (1 + 7.5) * K(), 1e-6) && near(S(0, 0)[1], (PH() - (12 + 5.5)) * K(), 1e-6), [S(0, 0), (1 + 7.5) * K(), (PH() - 17.5) * K()]);
ok("a hundred inches of house is now half as long on the sheet", near(S(100, 0)[0] - S(0, 0)[0], 100 * (0.125 / 12) * K(), 1e-6));
ok("the squares went with the corners", ["nw", "ne", "sw", "se"].every(c => { const p = cornerAt(c); return near(parseFloat(el("boxc-" + c).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + c).style.top), p[1], 0.06); }));
ok("THE VIEW DID NOT MOVE: same zoom, same place, same tool", api.get("ZOOM") === null && stage.scrollLeft === 120 && stage.scrollTop === 80 && api.get("MODE") === "hand");
ok("the mouse still lands on the right spot in the house",
   [[0, 0], [-400, 100], [137.25, -12.5]].every(p => { const q = S(p[0], p[1]); const b = api.call("atMouse", ev(q[0], q[1])); return near(b[0], p[0], 1e-6) && near(b[1], p[1], 1e-6); }));

// any size at all: nothing snaps
v0 = V();
pull("boxc-se", v0.w * K() * 0.2274, v0.h * K() * 0.2274);
const sf1 = api.get("STATE").scale_f;
ok("ANY SIZE AT ALL - the size is exactly what he pulled it to, not the nearest scale in the list",
   near(sf1, 0.125 * 1.2274, 1e-9) && [12, 6, 3, 1.5, 1, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 0.09375, 0.0625].every(x => Math.abs(sf1 - x) > 1e-4), sf1);
ok("the scale list says so: \"any size\", on top and picked",
   el("scale").children[0].value === "גודל חופשי" && el("scale").children[0].selected === true && el("scale").children.length === 2, el("scale").children.map(o => [o.value, o.selected]));
ok("and so does the heading of that box", /חופשי/.test(el("papertag").textContent), el("papertag").textContent);

// every corner works, each about the one across from it
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxc-nw", V().w * K() * 0.25, V().h * K() * 0.25);
ok("the top left corner: the bottom right one stays put", sameBox(box(), [8.5, 1, 22.5, 16.5]), box());
pull("boxc-ne", -V().w * K() * 0.2, V().h * K() * 0.2);
ok("the top right corner: the bottom left one stays put", sameBox(box(), [8.5, 1, 18, 13.2]), box());
pull("boxc-sw", V().w * K() * 0.5, -V().h * K() * 0.5);
ok("the bottom left corner: the top right one stays put", sameBox(box(), [17.5, 7.6, 9, 6.6]), box());

// ================================================================ 3. the margins
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxc-se", -V().w * K() / 2, -V().h * K() / 2);          // [1, 12, 15, 11]
pull("boxc-se", 5000, 5000);
ok("PULLED OUT AS FAR AS HE LIKES, THE BOX STOPS AT THE MARGINS  <<< THE RULE", sameBox(box(), [1, 1, 30, 22]), box());
ok("and the drawing is the size that box makes it - it did not go on growing", near(api.get("STATE").scale_f, 0.25, 1e-9), api.get("STATE").scale_f);
pull("boxc-nw", 5000, 5000);
ok("pulled in as far as he likes, a box is still left: an inch at least", near(Math.min(V().w, V().h), 1, 1e-9) && V().w > 0.99 && V().h > 0.99, box());

// ================================================================ 4. moving it
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxc-se", -V().w * K() / 2, -V().h * K() / 2);          // [1, 12, 15, 11]
const before = S(0, 0), sfm = api.get("STATE").scale_f;
global.sent.length = 0;
const mheld = pull("boxmove", 100, 50, true);
ok("THE BOX MOVES WITH THE MOUSE  <<< THE RULE", sameBox(box(), [1 + 100 / K(), 12 - 50 / K(), 15, 11]), box());
ok("the drawing goes with it, the same size", near(S(0, 0)[0] - before[0], 100, 1e-6) && near(S(0, 0)[1] - before[1], 50, 1e-6) && api.get("STATE").scale_f === sfm,
   [S(0, 0)[0] - before[0], S(0, 0)[1] - before[1]]);
ok("Ruby is not told on every step", states().length === 0);
up(mheld[0], mheld[1]);
m = states();
ok("on letting go Ruby is told once, the new place", m.length === 1 && sameBox(m[0].view_box, [1 + 100 / K(), 12 - 50 / K(), 15, 11]) && near(m[0].scale_f, sfm, 1e-12), m.map(x => x.view_box));
pull("boxmove", 9000, -9000);
ok("MOVED AS FAR AS HE LIKES, IT STOPS AT THE MARGINS: right and top", sameBox(box(), [16, 12, 15, 11]), box());
pull("boxmove", -9000, 9000);
ok("and left and bottom", sameBox(box(), [1, 1, 15, 11]), box());
pull("boxmove", 60, 0);          // (a side of the box moved it too, the day it was built; since then a side CUTS - see t73)
// nothing snaps: an odd place stays an odd place
pull("boxmove", 37.3, -21.7);
ok("NOTHING SNAPS: the box stays exactly where he left it", near(V().x, 1 + 60 / K() + 37.3 / K(), 1e-9) && near(V().y, 1 + 21.7 / K(), 1e-9), box());

// a box that fills the sheet has nowhere to go: holding it changes nothing at all
api.call("loadSheet", sheet());
api.call("setMode", "hand");
global.sent.length = 0;
const steps0 = api.get("UNDO").length;
pull("boxmove", 80, 60);
ok("a box that fills the sheet has nowhere to go - and nothing is saved, sent or remembered",
   sameBox(box(), [1, 1, 30, 22]) && states().length === 0 && api.get("UNDO").length === steps0 && !api.get("STATE").view_box, [box(), states().length, api.get("STATE").view_box]);

// ================================================================ 5. Escape, Ctrl+Z
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxc-se", -V().w * K() / 2, -V().h * K() / 2);          // [1, 12, 15, 11], half size
global.sent.length = 0;
const eh = pull("boxc-se", -80, -60, true);
key("Escape");
ok("ESCAPE IN THE MIDDLE OF A RESIZE PUTS THE BOX AND THE SIZE BACK", sameBox(box(), [1, 12, 15, 11]) && near(api.get("STATE").scale_f, 0.125, 1e-12) && api.get("BOXD") === null, [box(), api.get("STATE").scale_f]);
up(eh[0], eh[1]);
ok("...and letting go afterwards tells Ruby nothing", states().length === 0, states().length);
const mh = pull("boxmove", 90, 0, true);
key("Escape");
up(mh[0], mh[1]);
ok("Escape in the middle of a move puts it back too", sameBox(box(), [1, 12, 15, 11]) && states().length === 0, box());
pull("boxmove", 100, 0);
ok("(moved: the box is 100 pixels to the right)", near(V().x, 1 + 100 / K(), 1e-9));
global.sent.length = 0;
key("z", { code: "KeyZ", ctrlKey: true });
ok("CTRL+Z TAKES THE MOVE BACK", sameBox(box(), [1, 12, 15, 11]), box());
m = states();
ok("and Ruby is told, so the paper goes back with it", m.length === 1 && sameBox(m[0].view_box, [1, 12, 15, 11]), m.map(x => x.view_box));
key("z", { code: "KeyZ", ctrlKey: true });
ok("a second press takes the resize back: the whole sheet, the scale from the list",
   sameBox(box(), [1, 1, 30, 22]) && !api.get("STATE").view_box && !api.get("STATE").scale_f && near(api.call("scaleFactor", api.get("STATE").scale), 0.25 / 12, 1e-12),
   [box(), api.get("STATE").view_box, api.get("STATE").scale_f]);
ok("and the scale list is back on the scale from the list", el("scale").children.length === 1 && el("scale").children[0].value === '1/4"', el("scale").children.map(o => o.value));

// ================================================================ 6. the scale list: an exact scale
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxc-se", -V().w * K() * 0.37, -V().h * K() * 0.37);
const b6 = box();
global.sent.length = 0;
el("scale").value = '1/4"';
el("scale").onchange.call(el("scale"));
ok("PICKING A SCALE FROM THE LIST PUTS THE DRAWING ON THAT EXACT SCALE", !api.get("STATE").scale_f && near(api.call("scaleFactor", api.get("STATE").scale), 0.25 / 12, 1e-12), api.get("STATE").scale_f);
ok("the box stays where it is and the size it is", sameBox(box(), b6), [box(), b6]);
m = states();
ok("Ruby is told the size set by hand is gone", m.length === 1 && m[0].scale_f === null && m[0].scale === '1/4"' && sameBox(m[0].view_box, b6), m.map(x => [x.scale, x.scale_f]));
ok("\"any size\" is gone from the list", el("scale").children.length === 1, el("scale").children.map(o => o.value));
// "any size" itself is not something to pick
pull("boxc-se", -40, -30);
const sf6 = api.get("STATE").scale_f;
global.sent.length = 0;
el("scale").value = "גודל חופשי";
el("scale").onchange.call(el("scale"));
ok("picking \"any size\" itself changes nothing", api.get("STATE").scale_f === sf6 && states().length === 0);

// ================================================================ 7. the other tools, in a small box
api.call("loadSheet", sheet());
api.call("setMode", "hand");
pull("boxc-se", -V().w * K() * 0.3, -V().h * K() * 0.3);
pull("boxmove", 150, 70);
document.getElementById("tline").onclick();
ok("with the line tool in the hand the handles are put away", !/\bon\b/.test(el("boxc-se").className) && el("boxmove").className === "");
let e1 = S(-100, 100), e2 = S(100, 100);
tap(e1[0] + 4, e1[1] - 3); tap(e2[0] - 3, e2[1] + 4);
const last = site().shapes[site().shapes.length - 1];
ok("THE LINE TOOL IN A SMALL, MOVED BOX joins the two ends it was pointed at, exactly", JSON.stringify(last.points) === "[[-100,100],[100,100]]", last.points);
api.call("setMode", "hand");
// the turning handle belongs to the box
const rh = api.call("rotHandleAt", V(), K(), PH());
ok("the turning handle sits by the corner of the box, wherever the box is",
   near(parseFloat(el("rothandle").style.left), rh[0], 0.06) && near(rh[0], cornerAt("se")[0] + 22, 1e-6) && near(rh[1], cornerAt("se")[1] + 8, 1e-6), [el("rothandle").style.left, rh]);
// turned AND boxed: it turns about the middle of its own box
api.get("STATE").rotation = 30; api.call("render");
const vv = V();
ok("a turned drawing turns about the middle of ITS box", near(S(0, 0)[0], (vv.x + vv.w / 2) * K(), 1e-6) && near(S(0, 0)[1], (PH() - (vv.y + vv.h / 2)) * K(), 1e-6));
api.get("STATE").rotation = 0;

// Ruby's answer: the pages, with the box as Ruby held it inside the margins
const pages = JSON.parse(JSON.stringify(api.get("DOC").pages));
pages[0].views[0].x = 5; pages[0].views[0].y = 6; pages[0].views[0].w = 10; pages[0].views[0].h = 8;
api.call("applyPages", pages, null);
ok("when Ruby answers, the handles go where Ruby put the box", sameBox(box(), [5, 6, 10, 8]) && near(parseFloat(el("boxc-nw").style.left), 5 * K(), 0.06) && near(parseFloat(el("boxc-nw").style.top), (PH() - 14) * K(), 0.06),
   [box(), el("boxc-nw").style.left]);

// zooming keeps the squares on the corners
api.call("zoomAt", 300, 300, 2);
ok("after a zoom the squares are on the corners again", ["nw", "se"].every(c => { const p = cornerAt(c); return near(parseFloat(el("boxc-" + c).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + c).style.top), p[1], 0.06); }));

// ================================================================ the switch
let off = sheet(); off.view_box = false; off.state.scale_f = 0.1; off.state.view_box = [5, 5, 10, 8];
api.call("loadSheet", off);
api.call("setMode", "hand");
ok("switched off: no handles", ["boxc-nw", "boxc-se", "boxmove", "boxe-n"].every(id => !/\bon\b/.test(el(id).className)));
ok("switched off: a size set by hand is ignored - the scale from the list", near(api.call("scaleFactor", api.get("STATE").scale), 0.25 / 12, 1e-12) && el("scale").children.length === 1);
el("boxc-se").onmousedown(ev(100, 100)); move(50, 50); up(50, 50);
ok("switched off: holding a corner does nothing", sameBox(box(), [1, 1, 30, 22]) && api.get("BOXD") === null, box());

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
