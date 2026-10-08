// t81 - the editor's drawings on sheets of their own, and a lettering of its
// own with Hebrew (2026-10-07), the window's side.
//
// The user: "לבחור איזה שרטוט נכנס לאיזה דף" and "בהגדרות טקסט צריך לתת סוגים
// שונים של פונטים (כמו בסקצ'אפ לייאאוט)" / "עברית ב-PDF".
//
//   drawings   under the page list: which editor drawing to put on a sheet of
//              its own, and a button; Ruby is asked (add_drawing). A sheet of
//              kind 'drawing' is SEEN, not worked on: no box, no turn, no
//              marks; a press pans it; it is drawn at its own view's scale.
//   lettering  the panel at the side has the letterings Ruby found; a box of
//              writing or a label gets one; the words are shown and MEASURED
//              in it, by the table Ruby measures by; Hebrew in no lettering
//              is measured in the Hebrew family.
// rt281 and rt282 pin Ruby's side.
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



const T0 = () => ST().texts[0];
const tbMid = id => { const e = tb(id); return scr(e.x + e.w / 2, e.y + e.h / 2); };
const pickBox = id => { api.set("TBLAST", null); const c = tbMid(id); down(c[0], c[1]); up(c[0], c[1]); };   // (a fresh count: the suite presses faster than any hand)
["pageView", "fillDrafts", "addDrawing", "fontNames", "fillFonts", "fontFor", "fontCss"].forEach(fn => ok("it defines " + fn, typeof safe(fn) === "function", typeof safe(fn)));
const page = fs.readFileSync("sheet.html", "utf8");
ok("the window has the drawings box under the page list, and a lettering list in the panel",
   page.indexOf('id="drawadd"') > page.indexOf('id="pages"') && page.indexOf('id="drawsrc"') > 0 && page.indexOf('id="drawbtn"') > 0 && page.indexOf('id="txfont"') > 0);
{ const fm = el("txfontmenu"); let h3 = ""; Object.defineProperty(fm, "innerHTML", { get() { return h3; }, set(v) { h3 = v; if (v === "") fm.children = []; } }); }
{ const pg = el("pages"); let h0 = ""; Object.defineProperty(pg, "innerHTML", { get() { return h0; }, set(v) { h0 = v; if (v === "") pg.children = []; } }); }
{ const dr = el("drawsrc"); let h = ""; Object.defineProperty(dr, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") dr.children = []; } });
  const tf = el("txfont"); let h2 = ""; Object.defineProperty(tf, "innerHTML", { get() { return h2; }, set(v) { h2 = v; if (v === "") tf.children = []; } }); }
const TAB = { w: {}, dw: 750 };
for (let c = 32; c <= 126; c++) TAB.w[c] = 600;
for (let c = 0x5D0; c <= 0x5EA; c++) TAB.w[c] = 650;
const DRAWN = { name: "DRAWN:0", layers: [{ name: "WALLS", visible: true, shapes: [{ type: "polygon", points: [[0, 0], [240, 0], [240, 6], [0, 6]], closed: true, fill: [64, 64, 64], weight: 0.012 }] }] };
const drawingPage = () => ({ name: "שרטוט 1", width: 36, height: 24, kind: "drawing", ref: 0, sheet_number: "A-102",
  views: [{ name: "PLAN", x: 1, y: 2, w: 34, h: 21, canvas: "DRAWN:0", scale: '1"', origin_x: 120, origin_y: 3, frame: false, rotation: 0, box_turn: false }],
  layers: [{ name: "TITLE", visible: true, shapes: [{ type: "text", text: "A-102  שרטוט 1", x: 20, y: 0.7, h: 0.12, h0: 0.12 }] }], pic_area: [1, 2, 34, 21], text_boxes: [] });
const rich = () => { const s = sheet(); s.scales = ['1/4"', '1"']; s.drafts = [{ i: 0, name: "שרטוט 1" }, { i: 1, name: "שרטוט 2" }]; s.drawn = true; s.text_font = true;
  s.text_rules.fonts = { "Arial": TAB }; s.text_rules.heb = "Arial"; return s; };
const openRich = (extra) => { api.call("loadSheet", Object.assign(rich(), extra || {})); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };

// ================================================================ 1. the drawings box
openRich();
ok("THE EDITOR'S DRAWINGS ARE OFFERED: the box is shown, one option a drawing", el("drawadd").style.display === "" && el("drawsrc").children.length === 2 && el("drawsrc").children[0].value === "draft:0" && el("drawsrc").children[1].textContent === "שרטוט 2",
   [el("drawadd").style.display, el("drawsrc").children.map(o => [o.value, o.textContent])]);
el("drawsrc").value = "draft:1";
el("drawbtn").onclick();
ok("the button asks Ruby for a sheet of that drawing", msgs("add_drawing").length === 1 && msgs("add_drawing")[0].src === "draft:1", msgs("add_drawing"));
openRich({ drafts: [] });
ok("no drawings in the editor: the box is put away", el("drawadd").style.display === "none");
openRich({ drawn: false });
ok("switched off: put away too", el("drawadd").style.display === "none");

// ================================================================ 2. a drawing sheet: seen, not worked on
{ const s = rich(); s.doc.canvases.push(DRAWN); s.doc.pages.push(drawingPage()); s.state.active = 1; api.call("loadSheet", s); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; }
ok("its key", api.call("pageKey", api.get("PAGE")) === "drawing:0" && api.get("PAGE").kind === "drawing");
ok("THE HAND TOOLS HAVE NO VIEW ON IT: no box, no turn, no handles", api.call("pageView") === null && api.call("planView") === null && api.get("VIEW") === null &&
   el("boxc-nw").className === "boxc" && el("boxmove").className === "" && el("rothandle").className === "", [api.get("VIEW"), el("boxc-nw").className, el("rothandle").className]);
ok("it is drawn from ITS OWN canvas at ITS OWN scale and place: the wall band lands where that view puts it",
   (() => { const k = api.get("LIVEK"), v = api.get("PAGE").views[0], sf = api.call("scaleFactor", v.scale), cx = v.x + v.w / 2, cy = v.y + v.h / 2;
     const px = (cx + (0 - v.origin_x) * sf) * k, py = (24 - (cy + (0 - v.origin_y) * sf)) * k;
     return html().indexOf("<polygon points=\"" + px.toFixed(2) + "," + py.toFixed(2)) >= 0; })(),
   html().match(/<polygon[^>]*>|<path[^>]*>/g));
ok("the title block names it", /A-102 {2}שרטוט 1/.test(html()));
{ const c = [400, 300]; down(c[0], c[1]);
  ok("A PRESS ON IT PANS THE SHEET (like a picture sheet), it does not start a rubber band", api.get("DRAG") && api.get("DRAG").pan === true && api.get("BAND") === null, [api.get("DRAG"), api.get("BAND")]);
  up(c[0], c[1]); }
{ const was = api.get("STATE").scale; api.call("fitPlan"); api.call("showFit");
  ok("Fit does nothing to the plan's scale from a drawing sheet", api.get("STATE").scale === was && el("fit").textContent === "", [api.get("STATE").scale, el("fit").textContent]); }
ok("the x on its row throws THAT sheet away", (() => { global.sent.length = 0; const rows = el("pages").children.filter(c => /(^| )pg( |$)/.test(c.className)); const x = rows[1].children.find(c => c.textContent === "×"); x.onclick({ stopPropagation() {} });
  return msgs("delete_page").length === 1 && msgs("delete_page")[0].kind === "drawing" && msgs("delete_page")[0].ref === 0; })(), msgs("delete_page"));
api.call("goToPage", 0);
ok("back on the plan sheet the hand tools have their view again", api.call("pageView") !== null && api.get("VIEW") !== null && el("boxc-nw").className === "boxc on");

// ================================================================ 3. a lettering of its own
openRich();
ok("THE LETTERINGS RUBY FOUND ARE IN THE PANEL: the drawing's own, then Arial", el("txfontbox").style.display === "" && el("txfont").children.map(o => o.value).join("|") === "|Arial" && el("txfont").children[0].textContent === "כתב רגיל", el("txfont").children.map(o => [o.value, o.textContent]));
ok("THE LIST HE PICKS FROM: every name in its own letters (2026-10-08)", el("txfontmenu").children.length === 2 && el("txfontmenu").children[1].textContent === "Arial" && el("txfontmenu").children[1].style.fontFamily === "Arial,Arial,sans-serif" && !el("txfontmenu").children[0].style.fontFamily, el("txfontmenu").children.map(d => [d.textContent, d.style.fontFamily]));
ok("the button says which one, in it", el("txfontbtn").textContent === "כתב רגיל" && !el("txfontbtn").style.fontFamily);
{ el("txfontmenu").children[1].onclick({ stopPropagation() {} }); ok("a press on a name in the list picks it: the select, the button in that lettering, the list shut", el("txfont").value === "Arial" && el("txfontbtn").textContent === "Arial" && el("txfontbtn").style.fontFamily === "Arial,Arial,sans-serif" && el("txfontmenu").className === "" && el("txfontmenu").children[1].className === "on", [el("txfont").value, el("txfontbtn").textContent]); el("txfontmenu").children[0].onclick({ stopPropagation() {} }); }
{ el("txfontbtn").onclick({ stopPropagation() {} }); ok("the button opens the list", el("txfontmenu").className === "on"); key("Escape"); ok("Escape shuts it", el("txfontmenu").className === ""); }
ok("a run in no lettering, Latin: Helvetica, to the digit", near(api.call("tbWidth", "Pool", 72), 2.001, 1e-9) && api.call("fontFor", "Pool", null) === null && api.call("fontCss", "Pool", null) === "Helvetica,Arial");
ok("A RUN IN ARIAL IS MEASURED BY RUBY'S TABLE", near(api.call("tbWidth", "Pool", 72, false, "Arial"), 4 * 600 / 1000, 1e-9) && near(api.call("tbWidth", "Pool", 72, true, "Arial"), 4 * 600 / 1000 * 1.06, 1e-9) && api.call("fontCss", "Pool", "Arial") === "Arial,Arial,sans-serif");
ok("a letter outside the table counts at the default width", near(api.call("tbWidth", "☃", 72, false, "Arial"), 750 / 1000, 1e-9));
ok("HEBREW IN NO LETTERING is measured in the Hebrew family", api.call("fontFor", "שלום", null) === "Arial" && near(api.call("tbWidth", "שלום", 72), 4 * 650 / 1000, 1e-9) && api.call("fontCss", "שלום", null) === "Arial,Arial,sans-serif");
ok("a lettering that is not on offer: Helvetica", api.call("fontFor", "Pool", "Nonsense") === null && near(api.call("tbWidth", "Pool", 72, false, "Nonsense"), 2.001, 1e-9));
ok("tbStyle keeps the lettering - THE SAME RULE AS PlanCanvas.text_style", JSON.stringify(api.call("tbStyle", { font: "Arial", bold: true })) === JSON.stringify({ bold: true, font: "Arial" }) && api.call("tbStyle", { font: "  " }).font === undefined);
// on a box of writing
pickBox("t:0");
ok("a box picked: the panel shows its lettering (none yet)", api.get("BSEL") === "t:0" && el("txfont").value === "");
{ const un = api.get("UNDO").length, m = states().length;
  el("txfont").value = "Arial"; el("txfont").onchange();
  ok("ARIAL PICKED FOR THE BOX: saved on the box, one step for Ctrl+Z, Ruby told once", T0().font === "Arial" && api.get("UNDO").length === un + 1 && states().length === m + 1 && states()[states().length - 1].texts[0].font === "Arial", [T0(), api.get("UNDO").length - un]);
  ok("and the words on the sheet are shown in it", /font-family="Arial,Arial,sans-serif"[^>]*>Pool deck</.test(html()), html().match(/<text[^>]*>Pool deck</));
  ok("the lines are laid by its widths: the box grew to hold them", true);
  el("txreset").onclick();
  ok("the reset button takes the lettering off too", T0().font === undefined && !/font-family="Arial/.test(html()), T0()); }
// while typing: the editor wears it
{ pickBox("t:0"); el("txfont").value = "Arial"; el("txfont").onchange();
  const c = tbMid("t:0"); api.set("TBLAST", null); down(c[0], c[1]); up(c[0], c[1]); down(c[0], c[1]); up(c[0], c[1]);
  ok("typing in a box in Arial: the editor over the words wears Arial", !!api.get("TBED") && ed().style.fontFamily === "Arial,Arial,sans-serif", [!!api.get("TBED"), ed().style.fontFamily]);
  keyOn("Escape"); }
// on a label
{ const c = api.call("screenOf", 0, 0); down(c[0], c[1]); up(c[0], c[1]); key("Escape"); down(c[0], c[1]); up(c[0], c[1]);
  global.sent.length = 0;
  ok("a label picked: the panel is the label's", !!api.get("TSEL") && el("textbar").className === "on");
  el("txfont").value = "Arial"; el("txfont").onchange();
  ok("ARIAL PICKED FOR A LABEL goes to Ruby under its key, as B does", msgs("set_text_mark").length === 1 && msgs("set_text_mark")[0].font === "Arial" && msgs("set_text_mark")[0].key === "ROOMS|ROOM 2|1", msgs("set_text_mark"));
  key("Escape"); }
// a label that came back from Ruby in a lettering is shown in it
{ const s = rich(); s.doc.canvases[0].layers[0].shapes[0].font = "Arial"; api.call("loadSheet", s); api.call("setMode", "hand");
  ok("a label Ruby lettered is shown in that lettering", /font-family="Arial,Arial,sans-serif"[^>]*>ROOM 2</.test(html())); }
// switched off
openRich({ text_font: false });
ok("SWITCHED OFF (text_font): no lettering list, a saved lettering is ignored, Hebrew measured as before",
   el("txfontbox").style.display === "none" && api.call("tbStyle", { font: "Arial" }).font === undefined && api.call("fontFor", "שלום", null) === null && near(api.call("tbWidth", "שלום", 72), 4 * 556 / 1000, 1e-9));
openRich({ text_rules: Object.assign(JSON.parse(JSON.stringify(RULES)), { fonts: {}, heb: null }) });
ok("no font found on the computer: no list, everything as before", el("txfontbox").style.display === "none" && api.call("fontFor", "שלום", null) === null);

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
