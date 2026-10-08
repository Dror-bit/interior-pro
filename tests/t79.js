// t79 - the sheets go into the PDF in the order he drags them (2026-10-07), the window's side.
//
// The user: "להחליף את מיקום הסדר של הדפים בפידיאף ע"י גרירה". A row of the page
// list is pressed and dragged up or down: the sheet goes there (the list, the
// strip and DOC.pages at once, the open sheet stays open), STATE.page_order is
// sent to Ruby ONCE, a press that does not move is still a click, the x is not a
// handle, Escape drops a drag, Ctrl+Z puts the old order back (from the list too).
// rt278 pins what Ruby does with page_order (the numbers, the PDF).
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

const el = id => document.getElementById(id);
const ST = () => api.get("STATE");
const msgs = name => global.sent.filter(m => m.name === name).map(m => JSON.parse(m.args[0]));
const keysNow = () => api.get("DOC").pages.map(p => api.call("pageKey", p));
const page = (name, kind, ref, num) => ({ name, width: 36, height: 24, kind, ref, sheet_number: num, views: [], layers: [] });
const sheet = () => { const s = JSON.parse(JSON.stringify(SHEET));
  s.doc.pages.push(page("RENDERING 1", "image", 0, "A-102"), page("RENDERING 2", "image", 1, "A-103"), page("RENDERING 3", "image", 2, "A-104"));
  s.state.images = ["a.png", "b.png", "c.png"]; return s; };
{ const pg = el("pages"); let h = ""; Object.defineProperty(pg, "innerHTML", { get() { return h; }, set(v) { h = v; if (v === "") pg.children = []; } }); }
// the rows of the page list, 20 px each, from the top
const rows = () => el("pages").children.filter(c => /(^| )pg( |$)/.test(c.className));
el("pages").querySelectorAll = () => rows().map((r, i) => { r.getBoundingClientRect = () => ({ top: i * 20, height: 20, left: 0, width: 150 }); return r; });
const ev = (y, m) => Object.assign({ clientX: 50, clientY: y, button: 0, target: { tagName: "DIV", id: "" }, preventDefault() {}, stopPropagation() {} }, m || {});
const press = (i, m) => rows()[i].onmousedown(ev(i * 20 + 10, m));
const move = y => (LISTEN.mousemove || []).forEach(fn => fn(ev(y)));
const up = y => (LISTEN.mouseup || []).forEach(fn => fn(ev(y)));
const key = (k, m) => (LISTEN.keydown || []).forEach(fn => fn(Object.assign({ key: k, code: k, target: { tagName: "BODY", id: "" }, preventDefault() {}, stopPropagation() {} }, m || {})));
const listKey = (k, m) => el("pages").onkeydown(Object.assign({ key: k, code: k, target: { tagName: "DIV", id: "pages" }, preventDefault() {} }, m || {}));
const open = (extra) => { api.call("loadSheet", Object.assign(sheet(), extra || {})); api.set("UNDO", []); api.set("PGJUST", false); global.sent.length = 0; };   // (PGJUST: the timer that clears it has run by then)

["pageDragStart", "pageDragMove", "pageDragEnd", "pageDragCancel", "orderPages", "movePage"].forEach(fn => ok("it defines " + fn, typeof api.get(fn) === "function"));
let wired = null;
try { (LISTEN.load || []).forEach(fn => fn({})); } catch (e) { wired = e; }
ok("the window wires itself up without throwing", !wired, wired && String(wired));

open();
ok("four rows, the old order", rows().length === 4 && JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]', keysNow());

// the last sheet dragged to the top
press(3); move(60); move(30); move(5);
ok("WHILE DRAGGING: the row he holds is faded, a yellow line over the first row; nothing sent yet",
   /drag/.test(rows()[3].className) && /dropb/.test(rows()[0].className) && msgs("set_state").length === 0, rows().map(r => r.className));
up(5);
ok("LET GO AT THE TOP: the sheet is first - in the list and in DOC.pages", JSON.stringify(keysNow()) === '["image:2","plan","image:0","image:1"]', keysNow());
ok("the order is in the state and Ruby is told ONCE", JSON.stringify(ST().page_order) === '["image:2","plan","image:0","image:1"]' &&
   msgs("set_state").length === 1 && JSON.stringify(msgs("set_state")[0].page_order) === JSON.stringify(ST().page_order), [ST().page_order, msgs("set_state").length]);
ok("the sheet he had open (the plan) is still the open one", ST().active === 1 && api.get("DOC").pages[1].kind === "plan", ST().active);
ok("no yellow line left behind", rows().every(r => !/drop|drag/.test(r.className)), rows().map(r => r.className));
ok("one step for Ctrl+Z", api.get("UNDO").length === 1);
rows()[0].onclick();
ok("the click the browser sends after the drag is not a click on a sheet", ST().active === 1, ST().active);

// down to the bottom
global.sent.length = 0;
press(0); move(40); move(79);
ok("dragged below the last row: the line is UNDER the last row", /dropa/.test(rows()[3].className), rows().map(r => r.className));
up(79);
ok("LET GO AT THE BOTTOM: it is last", JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]', keysNow());

// Ctrl+Z, twice
global.sent.length = 0;
key("z", { ctrlKey: true, code: "KeyZ" });
ok("CTRL+Z: the order before the last drag, and Ruby is told", JSON.stringify(keysNow()) === '["image:2","plan","image:0","image:1"]' &&
   JSON.stringify(ST().page_order) === '["image:2","plan","image:0","image:1"]' && msgs("set_state").length === 1, [keysNow(), ST().page_order]);
listKey("z", { ctrlKey: true, code: "KeyZ" });
ok("CTRL+Z with the list in focus too: back to how it was before any drag (no order saved)", JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]' &&
   ST().page_order === null && ST().active === 0, [keysNow(), ST().page_order, ST().active]);

// a press that does not move is a click
open(); api.call("goToPage", 0); global.sent.length = 0;
press(2); move(52); up(52);
rows()[2].onclick();
ok("A PRESS THAT HARDLY MOVES (2 px) IS A CLICK: that sheet opens, the order stays", ST().active === 2 && JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]' &&
   !ST().page_order && api.get("UNDO").length === 0, [ST().active, keysNow()]);

// Escape in the middle
open();
press(3); move(40); move(5);
key("Escape");
ok("ESCAPE MID-DRAG: the drag is dropped, the line goes", api.get("PGDRAG") === null && rows().every(r => !/drop|drag/.test(r.className)));
up(5);
ok("and letting go after it changes nothing", JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]' && msgs("set_state").length === 0);
press(3); move(40); listKey("Escape");
ok("Escape with the list in focus drops it the same way", api.get("PGDRAG") === null);
up(5);

// the x is not a handle; the right button is not a drag
open();
rows()[1].onmousedown(ev(30, { target: { tagName: "BUTTON", id: "" } })); move(5); up(5);
ok("A PRESS ON THE x does not drag", api.get("PGDRAG") === null && JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]');
rows()[1].onmousedown(ev(30, { button: 2 })); move(5); up(5);
ok("nor does the right button", JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]');

// what Ruby answers keeps the open sheet
open(); press(2); move(5); up(5);
const back = api.get("DOC").pages.map((p, i) => Object.assign({}, p, { sheet_number: "A-10" + (i + 1) }));
api.call("applyPages", back, null);
ok("RUBY'S ANSWER (renumbered) lands: the numbers in the list are the new ones, the same sheet open",
   rows().map(r => r.children[0].textContent).join(",") === "A-101,A-102,A-103,A-104" && api.get("DOC").pages[ST().active].kind === "plan", rows().map(r => r.children[0].textContent));

// switched off
open({ page_order: false });
press(3); move(40); move(5); up(5);
ok("SWITCHED OFF (page_order): dragging a row does nothing", JSON.stringify(keysNow()) === '["plan","image:0","image:1","image:2"]' && msgs("set_state").length === 0);

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
