// t64 - a sheet sent again leaves the view where he has it (2026-10-07).
//
// The user, rubbing lines out of his yard: "כשאני מוחק משהו הוא כאילו קופץ לי
// אחורה ואז אני מתחיל מהתחלה כאילו נכנסתי לתוכנה. הוא לא פשוט מוחק ואפשר
// להמשיך."
//
// Measured on his drawing in a real browser before anything was changed:
//   zoomed to 3.06, scrolled to 901, 665, eraser on;
//   one sweep of the eraser;
//   zoom "fit", scrolled to 0, 0.
//
// Why: rubbing a line out makes Ruby build the sheet again and send ALL of it,
// with the settings saved on the model. The wheel never saves - a trip to Ruby
// and a full redraw for every click of it is what made zooming crawl - so the
// saved zoom is stale, and loadSheet obeyed it.
//
// THE RULE: the FIRST sheet a window is given opens on the saved zoom. Every
// sheet after that is a refresh, and the zoom on the screen is the one that
// counts. Through the real loadSheet, with a real second sheet.
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
global.window = { addEventListener() {}, devicePixelRatio: 1 };
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

const again = () => JSON.parse(JSON.stringify(SHEET));     // what Ruby sends: a new object every time

const safe = n => { try { return api.get(n); } catch (e) { return undefined; } };
ok("the window has the switch, and it is on", safe("KEEPVIEW") === true, safe("KEEPVIEW"));
const rb = fs.readFileSync("plan_sheet_dialog.rb", "utf8");
ok("Ruby owns the switch and sends it with the sheet",
   /USE_KEEP_VIEW = true unless const_defined/.test(rb) && /keep_view: USE_KEEP_VIEW/.test(rb));

// ------------------------------------------------------------ the first sheet
const first = again(); first.state.zoom = 2;
api.call("loadSheet", first);
ok("the FIRST sheet opens on the WHOLE sheet, whatever zoom was saved (2026-10-07: \"הדף קטן מדי בחלון\")", api.get("ZOOM") === null, api.get("ZOOM"));

// ------------------------------------------------------------------ his case
api.call("setZoom", 3.06);                       // the wheel: nothing is saved
api.call("setMode", "erase");
const stale = again(); delete stale.state.zoom;   // Ruby has never heard of the wheel
stale.doc.canvases[0].layers.find(l => l.name === "SITE").shapes.pop();   // the line he rubbed out
api.call("loadSheet", stale);
ok("AFTER RUBBING OUT A LINE THE ZOOM IS WHERE HE LEFT IT  <<< THE RULE", api.get("ZOOM") === 3.06, api.get("ZOOM"));
ok("the line really is gone from the sheet he is looking at",
   api.get("DOC").canvases[0].layers.find(l => l.name === "SITE").shapes.length === 0);
ok("and he is still holding the eraser", api.get("MODE") === "erase", api.get("MODE"));
ok("the sheet was drawn again at that zoom, not at fit", (() => {
  const w = Number((document.getElementById("sheetWrap").innerHTML.match(/<svg [^>]*width="([0-9.]+)"/) || [])[1]);
  return Math.abs(w - 36 * api.call("fitK") * 3.06) < 2;
})());
ok("the zoom travels with the next thing that IS saved", api.get("STATE").zoom === 3.06, api.get("STATE").zoom);

// a refresh that carries an OLD saved zoom must not win either
const old = again(); old.state.zoom = 1.3;
api.call("loadSheet", old);
ok("a stale zoom saved on the model does not pull him back", api.get("ZOOM") === 3.06, api.get("ZOOM"));

// zoomed all the way out to fit is a choice too
api.call("setZoom", null);
const z5 = again(); z5.state.zoom = 5;
api.call("loadSheet", z5);
ok("\"fit\" on the screen stays fit", api.get("ZOOM") === null, api.get("ZOOM"));

// ------------------------------------------------------------------ the switch
api.call("setZoom", 4);
const off = again(); off.keep_view = false; delete off.state.zoom;
api.call("loadSheet", off);
ok("switched off: every refresh goes back to the saved zoom, as before", api.get("ZOOM") === null, api.get("ZOOM"));

console.log(fails ? "\n*** " + fails + " FAILED ***" : "\nALL PASS");
process.exit(fails ? 1 : 0);
