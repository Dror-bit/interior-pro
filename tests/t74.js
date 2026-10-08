// t74 - a picture sits in a box of its own (2026-10-07), the window's side.
//
// The user: "אני רוצה שתהיה אפשרות לסובב את השרטוט וגם את התמונות", "אני גם יכול
// לבחור מה יראו מהתמונה או מהשרטוט - חיתוך", "שיהיה אפשרי להוסיף כמה תמונות
// בדף, או תמונות גם בדף השרטוט". And: "הסקייל הוא רק לבחירה של שרטוטים, התמונות
// לא צריכות סקייל."
//
// THE RULE:
//   a click on a picture   picks it: the same squares, bars, grip and round
//                          arrow the drawing's box has go onto it
//   dragging it            moves it about the sheet
//   a corner               bigger or smaller, about the opposite corner, at
//                          its own proportions
//   a side                 CUTS it: the picture stays exactly where it is and
//                          less of it is seen - or more, up to its own edge
//   the round arrow        turns the whole box about its middle
//   Delete                 takes a picture that was added to a sheet off it
//   the margins            it cannot leave what they leave
//   Escape puts a half-done step back; Ctrl+Z takes the last one back; Ruby is
//   told once, on letting go; the zoom and the place stay. No scale anywhere.
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

// the plan sheet with one picture ADDED to it, and a picture sheet whose picture was never touched
const AREA = [1, 2, 34, 21];
const sheet = () => { const s = fresh();
  s.doc.pages[0].view_area = [1, 1, 30, 22]; s.doc.pages[0].pic_area = AREA.slice();
  s.doc.pages[0].layers.push({ name: "IMAGES", visible: true, shapes: [
    { type: "image", path: "C:/r/x.jpg", x: 20, y: 10, w: 8, h: 4, placed: true, pic: "x:0", rot: 0, crop: [0, 0, 0, 0], iw: 2000, ih: 1000 } ] });
  s.doc.pages.push({ name: "RENDERING 1", width: 36, height: 24, kind: "image", ref: 0, sheet_number: "A-102", views: [], pic_area: AREA.slice(),
    layers: [{ name: "TITLE", visible: true, shapes: [] }, { name: "IMAGES", visible: true, shapes: [
      { type: "image", path: "C:/r/1.jpg", x: 1, y: 2, w: 34, h: 21, pic: "m:0", iw: 2000, ih: 1000, frame: false, stretch: false } ] }] });
  s.state.pics = [{ path: "C:/r/x.jpg", on: "plan" }]; s.state.image_geo = {}; s.state.images = ["C:/r/1.jpg"];
  s.images = [{ i: 0, path: "C:/r/1.jpg", url: "file:///C:/r/1.jpg", there: true }];
  s.pics = [{ path: "C:/r/x.jpg", url: "file:///C:/r/x.jpg", there: true }];
  return s; };
const open = () => { api.call("loadSheet", sheet()); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };

ok("the window has the switch, and it is on", safe("PICON") === true, safe("PICON"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby sends the switch with the sheet, and an address for every added picture", /pic_box: InteriorPro::PlanCanvas::USE_PIC_BOX/.test(rb) && /pics: pic_payload\(st\)/.test(rb));
["pagePics", "picRect", "setPic", "picHold", "hitPic", "boxTarget", "startPic", "dragPic", "dropPic", "picsSnap", "picsBack"].forEach(fn =>
  ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));
const page = fs.readFileSync("sheet.html", "utf8");
ok("there is still ONE button for adding pictures, and a tick for where they land", (page.match(/<button id="addmany"/g) || []).length === 1 && /<input type="checkbox" id="pichere">/.test(page));

// ================================================================ 1. a picture on the plan sheet
open();
const h0 = html();
ok("THE PICTURE ADDED TO THE PLAN SHEET IS DRAWN ON IT, in its box", h0.indexOf('href="file:///C:/r/x.jpg"') > 0 && h0.indexOf('<svg x="' + (20 * K()).toFixed(2) + '" y="' + ((PH - 14) * K()).toFixed(2) + '" width="' + (8 * K()).toFixed(2) + '" height="' + (4 * K()).toFixed(2) + '"') > 0, h0.slice(h0.indexOf("<svg x"), h0.indexOf("<svg x") + 200));
ok("all of it: nothing cut", h0.indexOf('viewBox="0.000 0.000 2000.000 1000.000"') > 0);
ok("until he picks it the handles are on the DRAWING, as they were", near(parseFloat(el("boxc-nw").style.left), 1 * K(), 0.06) && near(parseFloat(el("boxc-se").style.left), 31 * K(), 0.06) && api.get("BSEL") === null);
svg().onmousemove(ev(scr(24, 12)[0], scr(24, 12)[1]));
ok("over the picture the pointer says it can be moved", svg().style.cursor === "move", svg().style.cursor);
svg().onmousemove(ev(scr(5, 20)[0], scr(5, 20)[1]));
ok("and off it, it is the arrow again", /^url\(/.test(svg().style.cursor), svg().style.cursor);

grab("x:0", 0, 0);
ok("A CLICK ON THE PICTURE PICKS IT  <<< THE RULE", api.get("BSEL") === "x:0");
ok("THE SAME HANDLES GO ONTO IT: a square on each of its corners",
   ["nw", "ne", "sw", "se"].every(c => { const p = scr.apply(null, corner("x:0", c)); return el("boxc-" + c).className === "boxc on" && near(parseFloat(el("boxc-" + c).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + c).style.top), p[1], 0.06); }),
   ["nw", "se"].map(c => [el("boxc-" + c).style.left, el("boxc-" + c).style.top, scr.apply(null, corner("x:0", c))]));
ok("a bar on each side, the grip, and the round arrow by its bottom right corner",
   ["n", "s", "w", "e"].every(d => el("boxe-" + d).className === "boxe on") && el("boxmove").className === "on" && el("rothandle").className === "on" &&
   near(parseFloat(el("rothandle").style.left), 28 * K() + 22, 0.06) && near(parseFloat(el("rothandle").style.top), (PH - 10) * K() + 8, 0.06), [el("rothandle").style.left, el("rothandle").style.top]);
ok("a click alone changes nothing: nothing sent, nothing to undo", states().length === 0 && api.get("UNDO").length === 0 && same4(rect("x:0"), [20, 10, 8, 4]) && !ST().pics[0].box);
ok("nothing is explained under the tools (2026-10-08)", el("markinfo").textContent === "", el("markinfo").textContent);

// ---- dragging it
const stage = document.getElementById("stage");
stage.scrollLeft = 120; stage.scrollTop = 80;
const gh = grab("x:0", 100, 50, true);
ok("DRAGGED, IT MOVES WITH THE MOUSE  <<< THE RULE", same4(rect("x:0"), [20 + 100 / K(), 10 - 50 / K(), 8, 4]), rect("x:0"));
ok("Ruby is not told on every step", states().length === 0);
up(gh[0], gh[1]);
let m = states();
ok("ON LETTING GO Ruby is told once, where the picture is", m.length === 1 && same4(m[0].pics[0].box, [20 + 100 / K(), 10 - 50 / K(), 8, 4]) && m[0].pics[0].rot === 0 && same4(m[0].pics[0].crop, [0, 0, 0, 0]), m.map(x => x.pics));
ok("NO SCALE ANYWHERE: the drawing's box and its scale are what they were", !ST().scale_f && !ST().view_box && ST().scale === '1/4"' && same4([PG().views[0].x, PG().views[0].y, PG().views[0].w, PG().views[0].h], [1, 1, 30, 22]));
ok("THE VIEW DID NOT MOVE: same zoom, same place, same tool", api.get("ZOOM") === null && stage.scrollLeft === 120 && stage.scrollTop === 80 && api.get("MODE") === "hand");
ok("the handles went with it", near(parseFloat(el("boxc-nw").style.left), scr.apply(null, corner("x:0", "nw"))[0], 0.06));
grab("x:0", 9000, -9000);
ok("DRAGGED AS FAR AS HE LIKES, IT STOPS AT THE MARGINS: right and top", same4(rect("x:0"), [27, 19, 8, 4]), rect("x:0"));
grab("x:0", -9000, 9000);
ok("and left and bottom", same4(rect("x:0"), [1, 2, 8, 4]), rect("x:0"));
pull("boxmove", 5 * K(), -3 * K());
ok("the grip moves it too", same4(rect("x:0"), [6, 5, 8, 4]), rect("x:0"));

// ---- a corner
pull("boxc-se", 4 * K(), 2 * K());
ok("A CORNER MAKES IT BIGGER, the corner across from it stays put, the proportions are kept  <<< THE RULE", same4(rect("x:0"), [6, 3, 12, 6]), rect("x:0"));
ok("all of the picture is still seen", same4(R("x:0").crop, [0, 0, 0, 0]) && html().indexOf('viewBox="0.000 0.000 2000.000 1000.000"') > 0);
pull("boxc-nw", 3 * K(), 1.5 * K());
ok("the top left corner: the bottom right one stays put", same4(rect("x:0"), [9, 3, 9, 4.5]), rect("x:0"));
pull("boxc-nw", -3 * K(), -1.5 * K());
pull("boxc-ne", 9000, -9000);
ok("PULLED OUT AS FAR AS HE LIKES, IT STOPS AT THE MARGIN and keeps its proportions", near(R("x:0").w / R("x:0").h, 2, 1e-6) && near(R("x:0").x, 6, 1e-6) && near(R("x:0").y, 3, 1e-6) && near(R("x:0").x + R("x:0").w, 35, 1e-4), rect("x:0"));
pull("boxc-ne", -9000, 9000);
ok("pulled in as far as he likes, half an inch is left", near(R("x:0").h, 0.5, 1e-9) && near(R("x:0").w, 1, 1e-9), rect("x:0"));

// ================================================================ 2. a side cuts
open();
grab("x:0", 0, 0);
pull("boxc-se", 4 * K(), 2 * K());                        // [20, 8, 12, 6]
ok("(the picture, 12 by 6)", same4(rect("x:0"), [20, 8, 12, 6]), rect("x:0"));
global.sent.length = 0;
let s0 = spots("x:0");
const ch = pull("boxe-e", -2 * K(), 40, true);
ok("WHILE HE PULLS THE RIGHT SIDE IN, ONLY THAT SIDE MOVES  <<< THE RULE", same4(rect("x:0"), [20, 8, 10, 6]), rect("x:0"));
ok("THE PICTURE STAYS EXACTLY WHERE IT IS ON THE SHEET  <<< THE RULE", stayed(spots("x:0"), s0), [spots("x:0"), s0]);
ok("a sixth of it is cut off on the right", same4(R("x:0").crop, [0, 0, 1 / 6, 0], 1e-9), R("x:0").crop);
ok("and that is what is drawn: the left five sixths of the file", html().indexOf('viewBox="0.000 0.000 1666.667 1000.000"') > 0, html().slice(html().indexOf("viewBox=\"0.000"), html().indexOf("viewBox=\"0.000") + 60));
up(ch[0], ch[1]);
m = states();
ok("on letting go Ruby is told once: the box and the crop", m.length === 1 && same4(m[0].pics[0].box, [20, 8, 10, 6]) && same4(m[0].pics[0].crop, [0, 0, 1 / 6, 0], 1e-9), m.map(x => x.pics[0]));
pull("boxe-n", 0, 1.5 * K());
pull("boxe-w", 3 * K(), 0);
pull("boxe-s", 0, -0.6 * K());
ok("the top, the left and the bottom: each cuts its own side", same4(rect("x:0"), [23, 8.6, 7, 3.9]) && same4(R("x:0").crop, [0.25, 0.1, 1 / 6, 0.25], 1e-9), [rect("x:0"), R("x:0").crop]);
ok("AFTER FOUR CUTS THE PICTURE HAS NOT MOVED", stayed(spots("x:0"), s0), [spots("x:0"), s0]);
ok("what is drawn is that part of the file", html().indexOf('viewBox="500.000 250.000 1166.667 650.000"') > 0, html().slice(html().indexOf("viewBox=\"500"), html().indexOf("viewBox=\"500") + 60));
pull("boxe-e", 9000, 0);
ok("PULLED BACK OUT, A SIDE STOPS AT THE EDGE OF THE PICTURE - there is no more of it to show", same4(rect("x:0"), [23, 8.6, 9, 3.9]) && near(R("x:0").crop[2], 0, 1e-12) && stayed(spots("x:0"), s0), [rect("x:0"), R("x:0").crop]);
pull("boxe-w", -9000, 0); pull("boxe-n", 0, -9000); pull("boxe-s", 0, 9000);
ok("all four pulled back out: the whole picture again, where it was", same4(rect("x:0"), [20, 8, 12, 6]) && same4(R("x:0").crop, [0, 0, 0, 0], 1e-12) && stayed(spots("x:0"), s0), [rect("x:0"), R("x:0").crop]);
pull("boxe-w", 9000, 0);
ok("pulled in as far as he likes, half an inch of it is left", same4(rect("x:0"), [31.5, 8, 0.5, 6]) && stayed(spots("x:0"), s0), rect("x:0"));
pull("boxe-w", -9000, 0);
// a corner after a cut keeps what is seen
pull("boxe-e", -6 * K(), 0);                               // [20, 8, 6, 6], the right half cut
s0 = spots("x:0");
pull("boxc-se", -3 * K(), -3 * K());
ok("a corner after a cut: smaller, the same part of the picture seen", same4(rect("x:0"), [20, 11, 3, 3]) && same4(R("x:0").crop, [0, 0, 0.5, 0], 1e-9), [rect("x:0"), R("x:0").crop]);

// ================================================================ 3. the round arrow
open();
grab("x:0", 0, 0);
const turnBy = (id, deg, keep) => { const r = R(id), c = scr(r.x + r.w / 2, r.y + r.h / 2), t = deg * Math.PI / 180;
  el("rothandle").onmousedown(ev(c[0] + 200, c[1])); move(c[0] + 200 * Math.cos(t / 2), c[1] - 200 * Math.sin(t / 2)); move(c[0] + 200 * Math.cos(t), c[1] - 200 * Math.sin(t));
  if (!keep) up(0, 0); };
const mid0 = [24, 12];
turnBy("x:0", 30, true);
ok("THE ROUND ARROW TURNS THE WHOLE BOX ABOUT ITS MIDDLE  <<< THE RULE", near(R("x:0").rot, 30, 1e-9) && near(R("x:0").x + 4, mid0[0], 1e-9) && near(R("x:0").y + 2, mid0[1], 1e-9) && same4([R("x:0").w, R("x:0").h], [8, 4]), R("x:0"));
ok("the angle is written beside the arrow while he turns", el("rotdeg").textContent === "30°" && el("rotdeg").style.display === "block", el("rotdeg").textContent);
ok("the picture is drawn turned", html().indexOf('<g transform="rotate(-30,' + (24 * K()).toFixed(2) + "," + ((PH - 12) * K()).toFixed(2) + ')">') > 0);
ok("Ruby is not told while he turns", states().length === 0);
up(0, 0);
m = states();
ok("on letting go Ruby is told once: the angle", m.length === 1 && m[0].pics[0].rot === 30 && same4(m[0].pics[0].box, [20, 10, 8, 4]), m.map(x => x.pics[0]));
ok("THE HANDLES TURN WITH IT: each square on its turned corner, and turned itself",
   ["nw", "ne", "sw", "se"].every(c => { const p = scr.apply(null, corner("x:0", c)); return near(parseFloat(el("boxc-" + c).style.left), p[0], 0.06) && near(parseFloat(el("boxc-" + c).style.top), p[1], 0.06) && el("boxc-" + c).style.transform === "rotate(-30deg)"; }),
   [el("boxc-ne").style.left, el("boxc-ne").style.top, scr.apply(null, corner("x:0", "ne")), el("boxc-ne").style.transform]);
turnBy("x:0", 58);
ok("NEAR A QUARTER TURN IT LOCKS ONTO THE QUARTER TURN", R("x:0").rot === 90, R("x:0").rot);
// turned, it is still handled the same way
const far = corner("x:0", "nw");
s0 = spots("x:0");
{ const c = scr.apply(null, corner("x:0", "se")); el("boxc-se").onmousedown(ev(c[0], c[1])); const fx = scr.apply(null, far); move(c[0] + (c[0] - fx[0]) * 0.5, c[1] + (c[1] - fx[1]) * 0.5); up(0, 0); }
ok("TURNED: a corner still makes it bigger about the corner across from it", near(R("x:0").w, 12, 1e-6) && near(R("x:0").h, 6, 1e-6) && near(corner("x:0", "nw")[0], far[0], 1e-6) && near(corner("x:0", "nw")[1], far[1], 1e-6), [rect("x:0"), corner("x:0", "nw"), far]);
s0 = spots("x:0");
// the box's own right side now points UP the sheet: pulling it in is pulling the mouse DOWN
pull("boxe-e", 0, 3 * K());
ok("TURNED: a side still cuts, and the picture still does not move", near(R("x:0").w, 9, 1e-6) && near(R("x:0").crop[2], 0.25, 1e-9) && stayed(spots("x:0"), s0), [rect("x:0"), R("x:0").crop, spots("x:0"), s0]);
grab("x:0", 60, -40);
ok("TURNED: dragged, it goes the way the mouse goes", near(spots("x:0")[0][0] - s0[0][0], 60 / K(), 1e-6) && near(spots("x:0")[0][1] - s0[0][1], 40 / K(), 1e-6));
grab("x:0", 9000, 9000);
{ const hf = api.call("picHalf", R("x:0")), r = R("x:0"); ok("TURNED: at the margins it is the room it takes up TURNED that is held in", near(r.x + r.w / 2 + hf[0], 35, 1e-6) && near(r.y + r.h / 2 - hf[1], 2, 1e-6), [r, hf]); }
// a big one turned upright is too tall for the sheet: it is made to fit
open();
grab("x:0", 0, 0);
pull("boxc-ne", 9000, -9000); pull("boxc-sw", -9000, 9000);
ok("(as big as the sheet lets it be)", R("x:0").w > 25, rect("x:0"));
turnBy("x:0", 90);
{ const hf = api.call("picHalf", R("x:0")), r = R("x:0"); ok("TURNED UPRIGHT, A PICTURE TOO TALL FOR THE SHEET IS MADE TO FIT, at its proportions", r.rot === 90 && near(r.w, 21, 1e-6) && near(r.w / r.h, 2, 1e-6) && r.y + r.h / 2 - hf[1] >= 2 - 1e-6 && r.y + r.h / 2 + hf[1] <= 23 + 1e-6, [r, hf]); }

// ================================================================ 4. Escape, Ctrl+Z, Delete
open();
grab("x:0", 0, 0);
let eh = grab("x:0", 120, 0, true);
key("Escape");
ok("ESCAPE IN THE MIDDLE OF A DRAG PUTS IT BACK", same4(rect("x:0"), [20, 10, 8, 4]) && !ST().pics[0].box && api.get("BOXD") === null, [rect("x:0"), ST().pics[0]]);
up(eh[0], eh[1]);
ok("...and letting go afterwards tells Ruby nothing and leaves nothing to undo", states().length === 0 && api.get("UNDO").length === 0);
ok("Escape also lets the picture go: the handles are back on the drawing", api.get("BSEL") === null && near(parseFloat(el("boxc-nw").style.left), 1 * K(), 0.06));
grab("x:0", 0, 0);
eh = pull("boxe-n", 0, 2 * K(), true); key("Escape"); up(eh[0], eh[1]);
grab("x:0", 0, 0);
eh = pull("boxc-se", 80, 40, true); key("Escape"); up(eh[0], eh[1]);
grab("x:0", 0, 0);
turnBy("x:0", 40, true); key("Escape"); up(0, 0);
ok("Escape in the middle of a cut, of a corner, and of a turn: all put back", same4(rect("x:0"), [20, 10, 8, 4]) && (+pic("x:0").rot || 0) === 0 && same4(pic("x:0").crop, [0, 0, 0, 0]) && states().length === 0 && api.get("UNDO").length === 0 && !ST().pics[0].box, [pic("x:0"), states().length]);

grab("x:0", 100, 0);                                       // 1 moved
pull("boxe-e", -2 * K(), 0);                               // 2 cut
turnBy("x:0", 30);                                         // 3 turned
ok("(moved, cut, turned: three steps)", api.get("UNDO").length === 3 && R("x:0").rot === 30 && near(R("x:0").w, 6));
global.sent.length = 0;
undo();
ok("CTRL+Z TAKES THE TURN BACK", R("x:0").rot === 0 && same4(rect("x:0"), [20 + 100 / K(), 10, 6, 4]), R("x:0"));
m = states();
ok("and Ruby is told, so the paper goes back with it", m.length === 1 && m[0].pics[0].rot === 0 && same4(m[0].pics[0].crop, [0, 0, 0.25, 0], 1e-9), m.map(x => x.pics[0]));
undo();
ok("a second press takes the cut back", same4(rect("x:0"), [20 + 100 / K(), 10, 8, 4]) && same4(R("x:0").crop, [0, 0, 0, 0]), [rect("x:0"), R("x:0").crop]);
undo();
ok("a third takes the move back: the picture as Ruby first laid it, with no box of its own saved", !ST().pics[0].box && api.get("UNDO").length === 0, ST().pics[0]);

open();
grab("x:0", 0, 0);
key("Delete");
ok("DELETE TAKES AN ADDED PICTURE OFF ITS SHEET  <<< THE RULE", ST().pics.length === 0 && pic("x:0") === null && html().indexOf("x.jpg") < 0 && api.get("BSEL") === null);
m = states();
ok("Ruby is told", m.length === 1 && m[0].pics.length === 0);
ok("the handles are back on the drawing", near(parseFloat(el("boxc-nw").style.left), 1 * K(), 0.06));
undo();
ok("CTRL+Z PUTS IT BACK ON THE LIST - Ruby's answer draws it", ST().pics.length === 1 && ST().pics[0].path === "C:/r/x.jpg" && states().length === 2 && states()[1].pics.length === 1, ST().pics);
// two added: the second takes the first one's number when the first goes
{ const s = sheet(); s.doc.pages[0].layers[1].shapes.push({ type: "image", path: "C:/r/y.jpg", x: 4, y: 14, w: 6, h: 3, placed: true, pic: "x:1", rot: 0, crop: [0, 0, 0, 0], iw: 2000, ih: 1000 });
  s.state.pics.push({ path: "C:/r/y.jpg", on: "plan", box: [4, 14, 6, 3] }); s.pics.push({ path: "C:/r/y.jpg", url: "file:///C:/r/y.jpg", there: true });
  api.call("loadSheet", s); api.call("setMode", "hand"); }
grab("x:0", 0, 0); key("Delete");
ok("with two added pictures, taking the first off leaves the second under the first one's number", ST().pics.length === 1 && ST().pics[0].path === "C:/r/y.jpg" && pic("x:0") && pic("x:0").path === "C:/r/y.jpg" && pic("x:1") === null);
grab("x:0", 50, 0);
ok("and dragging it saves ITS place", same4(ST().pics[0].box, [4 + 50 / K(), 14, 6, 3]), ST().pics[0]);

// ================================================================ 5. the drawing's own box is still the drawing's
open();
down(scr(5, 20)[0], scr(5, 20)[1]); up(scr(5, 20)[0], scr(5, 20)[1]);
ok("a press off the picture lets it go", api.get("BSEL") === null);
pull("boxc-se", -15 * K(), -11 * K());
ok("with no picture picked the handles are the drawing's: a corner sizes the DRAWING, the picture is not touched",
   same4([PG().views[0].x, PG().views[0].y, PG().views[0].w, PG().views[0].h], [1, 12, 15, 11]) && same4(rect("x:0"), [20, 10, 8, 4]) && near(ST().scale_f, 0.125, 1e-9), [PG().views[0], rect("x:0")]);
grab("x:0", 0, 0);
pull("boxc-se", 4 * K(), 2 * K());
ok("with the picture picked the same square sizes the PICTURE, and the drawing is not touched",
   same4(rect("x:0"), [20, 8, 12, 6]) && same4([PG().views[0].x, PG().views[0].y, PG().views[0].w, PG().views[0].h], [1, 12, 15, 11]) && near(ST().scale_f, 0.125, 1e-9));
api.call("setMode", "dim");
ok("with another tool in the hand the handles are put away and the picture is let go", ["boxc-nw", "boxmove", "boxe-n", "rothandle"].every(id => !/\bon\b/.test(el(id).className)) && api.get("BSEL") === null);
api.call("setMode", "hand");
ok("the little sheets down the side show the picture in its box too", api.call("sheetSVG", api.get("DOC").pages[0], 10, false).indexOf('<svg x="200.00"') > 0);

// ================================================================ 6. a picture sheet
open();
api.call("goToPage", 1);
global.sent.length = 0;
ok("ON A PICTURE SHEET THE HANDLES ARE ON THE PICTURE WITHOUT A CLICK - where it really is, not round the whole sheet",
   same4(rect("m:0"), [1, 4, 34, 17]) && near(parseFloat(el("boxc-nw").style.left), 1 * K(), 0.06) && near(parseFloat(el("boxc-nw").style.top), (PH - 21) * K(), 0.06) && el("rothandle").className === "on", [rect("m:0"), el("boxc-nw").style.top]);
ok("a picture never touched is still drawn the old way", html().indexOf('preserveAspectRatio="xMidYMid meet"') > 0 && !pic("m:0").placed);
pull("boxc-se", -17 * K(), -8.5 * K());
ok("A CORNER: it is in a box of its own now, half the size, top left corner where it was", same4(rect("m:0"), [1, 12.5, 17, 8.5]) && pic("m:0").placed === true, rect("m:0"));
m = states();
ok("Ruby is told, under the number of its sheet", m.length === 1 && same4(m[0].image_geo["0"].box, [1, 12.5, 17, 8.5]) && m[0].image_geo["0"].rot === 0, m.map(x => x.image_geo));
grab("m:0", 200, 100);
pull("boxe-s", 0, -2 * K());
turnBy("m:0", -20);
ok("dragged, cut and turned like any other", near(R("m:0").rot, -20, 1e-9) && near(R("m:0").h, 6.5, 1e-6) && near(R("m:0").crop[1], 2 / 8.5, 1e-9) && api.get("BSEL") === "m:0", R("m:0"));
key("Delete");
ok("DELETE DOES NOT TAKE THE PICTURE A SHEET WAS MADE FOR - the sheet goes by its x, and the hint says so",
   pic("m:0") !== null && ST().images.length === 1 && /ברשימת הדפים/.test(el("markinfo").textContent), el("markinfo").textContent);
undo(); undo(); undo(); undo();
ok("Ctrl+Z all the way back: the picture fills its sheet again, with no box saved", !pic("m:0").placed && same4([pic("m:0").x, pic("m:0").y, pic("m:0").w, pic("m:0").h], AREA) && !ST().image_geo["0"] && same4(rect("m:0"), [1, 4, 34, 17]), [pic("m:0"), ST().image_geo]);
const eh2 = pull("boxc-se", -100, 50, true); key("Escape"); up(eh2[0], eh2[1]);
ok("Escape on a picture never touched leaves it never touched", !pic("m:0").placed && !ST().image_geo["0"] && same4([pic("m:0").x, pic("m:0").w], [1, 34]));
api.call("goToPage", 0);
ok("turning the page lets a picked picture go", api.get("BSEL") === null);

// ================================================================ 7. adding pictures onto the open sheet
open();
const file = n => ({ name: n, size: 10, slice() { return {}; } });
const carry = list => { api.call("takeFiles", list); list.forEach(() => { api.call("dropReady", true); api.call("fileDone"); }); };
carry([file("a.jpg")]);
let fin = global.sent.filter(x => x.name === "drop_finish");
ok("NOT TICKED: pictures get a sheet each, as always - Ruby is told nothing about where", fin.length === 1 && fin[0].args.length === 0, fin.map(x => x.args));
api.call("imageReport", 1, null);
ok("and that is not a step for Ctrl+Z here", api.get("UNDO").length === 0 && el("imginfo").textContent === "נוספה תמונה אחת", el("imginfo").textContent);
el("pichere").checked = true;
global.sent.length = 0;
carry([file("b.jpg"), file("c.png")]);
fin = global.sent.filter(x => x.name === "drop_finish");
ok("TICKED: THEY GO ONTO THE SHEET THAT IS OPEN - Ruby is told which  <<< THE RULE", fin.length === 1 && JSON.parse(fin[0].args[0]).on === "plan", fin.map(x => x.args));
api.call("imageReport", 2, null);
ok("it says so, and it is one step for Ctrl+Z", el("imginfo").textContent === "נוספו 2 תמונות לדף הזה" && api.get("UNDO").length === 1 && api.get("UNDO")[0].pics !== undefined, el("imginfo").textContent);
api.call("goToPage", 1);
global.sent.length = 0;
carry([file("d.jpg")]);
fin = global.sent.filter(x => x.name === "drop_finish");
ok("on a picture sheet they go beside its picture", JSON.parse(fin[0].args[0]).on === "image:0", fin.map(x => x.args));
api.call("imageReport", 0, "boom");
ok("a failure is not a step", api.get("UNDO").length === 1 && /שגיאה/.test(el("imginfo").textContent));
el("pichere").checked = false;

// ================================================================ the switch
let off = sheet(); off.pic_box = false;
api.call("loadSheet", off); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0;
{ const c = scr(24, 12); down(c[0], c[1]); move(c[0] + 80, c[1]); up(c[0] + 80, c[1]); }
ok("switched off: a press on a picture does not pick it or move it", api.get("BSEL") === null && pic("x:0").x === 20 && states().length === 0);
api.call("goToPage", 1);
ok("switched off: no handles on a picture sheet", ["boxc-nw", "boxmove", "boxe-n", "rothandle"].every(id => !/\bon\b/.test(el(id).className)));
el("pichere").checked = true; global.sent.length = 0;
carry([file("e.jpg")]);
ok("switched off: pictures get a sheet each whatever is ticked", global.sent.filter(x => x.name === "drop_finish")[0].args.length === 0 && el("pichererow").style.display === "none");
el("pichere").checked = false;
api.call("loadSheet", sheet());
ok("and switched on again with the next sheet", safe("PICON") === true && el("pichererow").style.display === "");

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 0 + 1 : 0);
