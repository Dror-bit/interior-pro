// t71 - the drawing can be turned on its sheet (2026-10-07), the window's side.
//
// The user: "אני רוצה שתהיה אפשרות לסובב את השרטוט... כמו בתמונה שיש סימון על
// הפינה למטה של סיבוב."
//
// THE RULE:
//   a handle sits by the bottom right corner of the drawing's frame; holding
//   it and dragging turns the drawing about the middle of the frame, by the
//   angle the mouse swept;
//   near a quarter turn it locks onto the quarter turn;
//   Escape in the middle puts it back; Ctrl+Z takes the last turn back;
//   the zoom and the place do not change; Ruby is told once, on letting go;
//   and every tool still lands where the mouse is on a turned sheet - the
//   turn lives in toPaper and atMouse and nowhere else.
// Which writing turns and which stays level is Ruby's decision (rt271); here
// the window only has to add the sheet's angle to each piece's own.
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
const near = (a, b, tol) => Math.abs(a - b) < (tol === undefined ? 0.01 : tol);
const handle = () => document.getElementById("rothandle");
const deg = () => api.get("STATE").rotation;
const html = () => document.getElementById("sheetWrap").innerHTML;
const centre = () => { const V = api.get("VIEW"), P = api.get("PAGE"); return [V.cx * V.k, (P.height - V.cy) * V.k]; };
// a point on the screen at angle a (degrees, anticlockwise) and distance r from the middle of the frame
const around = (a, r) => { const c = centre(); return [c[0] + r * Math.cos(a * Math.PI / 180), c[1] - r * Math.sin(a * Math.PI / 180)]; };
const hpos = () => { const V = api.get("VIEW"), P = api.get("PAGE"), v = P.views[0]; return api.call("rotHandleAt", v, V.k, P.height); };
const hang = () => { const c = centre(), h = hpos(); return [Math.atan2(-(h[1] - c[1]), h[0] - c[0]) * 180 / Math.PI, Math.hypot(h[0] - c[0], h[1] - c[1])]; };
// hold the handle, sweep the mouse by `by` degrees, and (unless told not to) let go
const turn = (by, keep) => { const [a0, r] = hang(); const h = hpos(); handle().onmousedown(ev(h[0], h[1]));
  const mid = around(a0 + by / 2, r), end = around(a0 + by, r); move(mid[0], mid[1]); move(end[0], end[1]); if (!keep) up(end[0], end[1]); return end; };

ok("the window has the switch, and it is on", safe("ROTON") === true, safe("ROTON"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby sends the switch with the sheet", /rotate: InteriorPro::PlanCanvas::USE_VIEW_ROTATION/.test(rb));
const page = fs.readFileSync("sheet.html", "utf8");
ok("the window has the handle, outside the drawing itself", /<div id="rothandle"/.test(page) && page.indexOf('<div id="rothandle"') > page.indexOf('<div id="sheetWrap">'));
["viewTurn", "snapTurn", "startTurn", "paintRot", "rotHandleAt", "rotAngleAt", "applyLayers", "turnedSize"].forEach(fn =>
  ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));

// ================================================================ 1. a sheet that was never turned
api.call("loadSheet", fresh());
api.call("setMode", "hand");
ok("a sheet that never heard of turning opens at 0", deg() === 0, deg());
const V0 = api.get("VIEW"), ST0 = api.get("STATE");
const oldWay = (mx, my) => { const P = api.get("PAGE"); const px = V0.cx + (mx - ST0.origin_x) * V0.sf, py = V0.cy + (my - ST0.origin_y) * V0.sf; return [px * V0.k, (P.height - py) * V0.k]; };
ok("NOT TURNED: every point is drawn exactly where it always was - not nearly, exactly",
   [[0, 0], [-400, 100], [137.25, -12.5]].every(p => { const a = S(p[0], p[1]), b = oldWay(p[0], p[1]); return a[0] === b[0] && a[1] === b[1]; }));
const html0 = html();
ok("the room name is drawn level", /<text [^>]*>ROOM 2<\/text>/.test(html0) && !/transform="rotate[^>]*>ROOM 2</.test(html0));

// ---- the handle
const hp = hpos(), fr = api.get("PAGE").views[0], k0 = V0.k;
ok("THE HANDLE IS THERE, by the bottom right corner of the drawing's frame  <<< THE RULE",
   handle().className === "on" && near(parseFloat(handle().style.left), (fr.x + fr.w) * k0 + 22, 0.1) &&
   near(parseFloat(handle().style.top), (api.get("PAGE").height - fr.y) * k0 + 8, 0.1), [handle().className, handle().style]);
ok("it is not written into the drawing - it cannot print or reach a thumbnail", html0.indexOf("rothandle") < 0);
ok("the pointer over it is the round arrow, a picture", /data:image\/svg\+xml/.test(String(handle().style.cursor)), String(handle().style.cursor).slice(0, 30));
api.call("setMode", "dim");
ok("with another tool in the hand the handle is put away", handle().className === "");
api.call("setMode", "hand");
ok("and back with the select arrow", handle().className === "on");

// ================================================================ 2. turning it
const stage = document.getElementById("stage");
stage.scrollLeft = 120; stage.scrollTop = 80;
global.sent.length = 0;
const at30 = turn(30, true);                         // held, swept 30 degrees, NOT let go yet
ok("WHILE HE DRAGS, THE DRAWING TURNS BY THE ANGLE THE MOUSE SWEPT  <<< THE RULE", deg() === 30, deg());
ok("the angle is written beside the handle while he turns", document.getElementById("rotdeg").textContent === "30°" && document.getElementById("rotdeg").style.display === "block",
   document.getElementById("rotdeg").textContent);
ok("Ruby is not told on every step", msgs("set_rotation").length === 0, msgs("set_rotation").length);
up(at30[0], at30[1]);
let m = msgs("set_rotation");
ok("ON LETTING GO Ruby is told once, the angle", m.length === 1 && m[0].rotation === 30, m);
ok("the angle beside the handle goes away", document.getElementById("rotdeg").style.display === "none");
ok("THE VIEW DID NOT MOVE: same zoom, same place, same tool", api.get("ZOOM") === null && stage.scrollLeft === 120 && stage.scrollTop === 80 && api.get("MODE") === "hand",
   [api.get("ZOOM"), stage.scrollLeft, stage.scrollTop]);

// the drawing really is turned, about the middle of the frame
const c = centre(), sfk = api.get("VIEW").sf * api.get("VIEW").k, O = [api.get("STATE").origin_x, api.get("STATE").origin_y];
ok("the middle of the frame did not move", near(S(O[0], O[1])[0], c[0]) && near(S(O[0], O[1])[1], c[1]));
const p100 = S(O[0] + 100, O[1]);
ok("a point 100 inches to the right of the middle is now up and to the right, 30 degrees round",
   near(p100[0], c[0] + 100 * sfk * Math.cos(Math.PI / 6)) && near(p100[1], c[1] - 100 * sfk * Math.sin(Math.PI / 6)), [p100, c]);
ok("the lines on the sheet were drawn again, turned", html() !== html0);
ok("the frame the drawing is clipped to is NOT turned", /<clipPath id="vclip"><rect [^>]*\/><\/clipPath>/.test(html()) &&
   html().match(/<clipPath id="vclip">.*?<\/clipPath>/)[0] === html0.match(/<clipPath id="vclip">.*?<\/clipPath>/)[0]);
// the writing carries the sheet's turn plus its own - and nothing more is decided here
ok("writing on the plan is turned by its own angle PLUS the sheet's", /transform="rotate\(-30,[^>]*>ROOM 2</.test(html()), (html().match(/<text[^>]*>ROOM 2</) || [""])[0]);
ok("writing put straight on the paper (the title block) is not turned", /<text [^>]*>A-101  FLOOR PLAN<\/text>/.test(html()) && !/transform="rotate[^>]*>A-101  FLOOR PLAN</.test(html()));

// the mouse still finds the house
ok("ON A TURNED SHEET THE MOUSE STILL LANDS ON THE RIGHT SPOT IN THE HOUSE",
   [[0, 0], [-400, 100], [137.25, -12.5], [300, -100]].every(p => { const q = S(p[0], p[1]); const b = api.call("atMouse", ev(q[0], q[1])); return near(b[0], p[0], 1e-6) && near(b[1], p[1], 1e-6); }));

// Ruby answers with the layers, the writing decided: a name level on the page arrives as -30
const st2 = fresh();
const rooms = st2.doc.canvases[0].layers.find(l => l.name === "ROOMS");
rooms.shapes[0].rotation = -30;
api.call("applyLayers", JSON.parse(JSON.stringify(api.get("DOC").pages)), [rooms]);
ok("when Ruby sends the writing back, a name it held level is drawn level", /<text [^>]*>ROOM 2<\/text>/.test(html()) && !/transform="rotate[^>]*>ROOM 2</.test(html()),
   (html().match(/<text[^>]*>ROOM 2</) || [""])[0]);
ok("and the loose lines, which were not sent, are still there", site().shapes.length === 9);

// ================================================================ 3. a right angle wins
global.sent.length = 0;
turn(57.5);                                           // 30 + 57.5 = 87.5: inside the pull of 90
ok("NEAR A QUARTER TURN IT LOCKS ONTO THE QUARTER TURN", deg() === 90, deg());
const q100 = S(O[0] + 100, O[1]);
ok("and a quarter turn is exact: right of the middle is now straight above it", near(q100[0], c[0], 1e-6) && near(q100[1], c[1] - 100 * sfk, 1e-6), q100);
turn(-42.74);
ok("away from a quarter turn it keeps the angle, to a tenth of a degree", deg() === 47.3, deg());
turn(-47.3 - 1.2);
ok("back near zero it locks onto zero - and zero is the drawing as it always was", deg() === 0 && html().replace(/<text[^>]*>ROOM 2<\/text>/, "") === html0.replace(/<text[^>]*>ROOM 2<\/text>/, ""), deg());

// ================================================================ 4. Escape, Ctrl+Z
api.call("loadSheet", fresh());
api.call("setMode", "hand");
turn(30);
global.sent.length = 0;
const mid2 = turn(25, true);
ok("(half way through a second turn the drawing is at 55)", deg() === 55, deg());
key("Escape");
ok("ESCAPE IN THE MIDDLE OF A TURN PUTS IT BACK AS IT WAS", deg() === 30 && api.get("ROT") === null, deg());
up(mid2[0], mid2[1]);
ok("...and letting go afterwards changes nothing and tells Ruby nothing", deg() === 30 && msgs("set_rotation").length === 0, [deg(), msgs("set_rotation")]);
turn(60);
ok("(two turns made: 30, then on to 90)", deg() === 90, deg());
global.sent.length = 0;
key("z", { code: "KeyZ", ctrlKey: true });
ok("CTRL+Z TAKES THE LAST TURN BACK", deg() === 30, deg());
ok("and Ruby is told, so the writing goes back with it", msgs("set_rotation").length === 1 && msgs("set_rotation")[0].rotation === 30, msgs("set_rotation"));
key("z", { code: "KeyZ", ctrlKey: true });
ok("a second press takes the one before", deg() === 0, deg());
// a click on the handle that goes nowhere is not a turn
global.sent.length = 0;
const steps0 = api.get("UNDO").length;
const h0 = hpos(); handle().onmousedown(ev(h0[0], h0[1])); up(h0[0], h0[1]);
ok("a click on the handle that goes nowhere is not a turn", deg() === 0 && msgs("set_rotation").length === 0 && api.get("UNDO").length === steps0, [deg(), api.get("UNDO").length, steps0]);

// ================================================================ 5. the tools on a turned sheet
let turned = fresh(); turned.state.rotation = 90;
api.call("loadSheet", turned);
api.call("setMode", "hand");
ok("a sheet saved turned opens turned", deg() === 90 && near(S(100, 0)[0], centre()[0], 1e-6) && S(100, 0)[1] < centre()[1], [deg(), S(100, 0), centre()]);
// moving the plan (Alt+drag) goes the way the mouse goes
const before = S(0, 0);
down(400, 300, { altKey: true }); move(425, 300, { altKey: true }); move(450, 310, { altKey: true }); up(450, 310, { altKey: true });
const after = S(0, 0);
ok("ALT+DRAG ON A TURNED SHEET: the plan goes the way the mouse goes", near(after[0] - before[0], 50, 0.01) && near(after[1] - before[1], 10, 0.01), [after[0] - before[0], after[1] - before[1]]);
// the line tool locks onto the ends of the yard lines, wherever the turn put them
document.getElementById("tline").onclick();
ok("with the line tool in the hand the handle is put away", handle().className === "");
global.sent.length = 0;
let e1 = S(-100, 100), e2 = S(100, 100);
tap(e1[0] + 4, e1[1] - 3); tap(e2[0] - 3, e2[1] + 4);
const last = site().shapes[site().shapes.length - 1];
ok("THE LINE TOOL ON A TURNED SHEET joins the two ends it was pointed at, exactly", JSON.stringify(last.points) === "[[-100,100],[100,100]]", last.points);
api.call("setMode", "hand");
const midp = S(50, 100);                 // (not its middle: the end of a yard line sits exactly there)
click(midp[0], midp[1]);
ok("the select arrow picks that line where it is drawn", JSON.stringify(picked()) === "[9]", picked());
key("Escape");
// what would fit is worked out for the drawing as turned
api.set("BOUNDS", [0, 0, 1200, 100]);
ok("how big the drawing is, is measured AS TURNED", near(api.call("turnedSize")[0], 100, 1e-6) && near(api.call("turnedSize")[1], 1200, 1e-6), api.call("turnedSize"));

// zooming puts the handle back by the corner of the sheet's new size
api.call("loadSheet", fresh());
api.call("setMode", "hand");
api.call("zoomAt", 300, 300, 2);
const hz = hpos();
ok("after a zoom the handle is by the corner again", near(parseFloat(handle().style.left), hz[0], 0.1) && near(parseFloat(handle().style.top), hz[1], 0.1), [handle().style.left, hz]);

// ================================================================ the switch
let off = fresh(); off.rotate = false; off.state.rotation = 35;
api.call("loadSheet", off);
api.call("setMode", "hand");
ok("switched off: no handle", handle().className === "");
ok("switched off: the angle is ignored and the drawing is laid square", near(S(O[0] + 100, O[1])[1], centre()[1], 1e-9) && api.call("viewTurn").deg === 0, S(O[0] + 100, O[1]));

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
