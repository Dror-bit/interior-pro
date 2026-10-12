// t82 - a note's words, changed the way any label's are (2026-10-08).
//
// The user: "אין אפשרות לערוך את הכיתוב" (of a note), and then: "כל כיתוב
// שקיים כרגע בתוכנה לא יפתח לו קופסא אלא הקופסא תהיה על הכיתוב עצמו
// וההגדרות יהיו בהגדרות טקסט". So:
//   two quick presses on a note     its words open OVER THEMSELVES on the sheet
//                                   (#tbedit, like a label's) - not in the
//                                   note bar. Counted by the window (pressTwice):
//                                   the browser's own double click never comes,
//                                   the first press draws the sheet again.
//   one press on a note             picked, and its settings are in the box
//                                   at the side (size, B, I, U, colour, the
//                                   words, and the head on its leader)
//   Enter                           the words go onto the note; Escape drops them
//
// The DOM stand-in below is the one t78 uses, copied: each suite stands alone.
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


// ================================================================ the note
const LONG = 'a long note that runs far past the grab of its own middle, both ways';
const noteSheet = () => { const s = sheet();
  s.state.marks = [{ t: 'note', x: -100, y: 150, kx: -200, ky: 150, lx: -300, ly: 100, text: 'קירות פנים', arrow: true },
                   { t: 'dim', x1: -400, y1: 250, x2: -300, y2: 250, off: 20 },
                   { t: 'note', x: 100, y: -100, kx: -50, ky: -100, lx: -150, ly: -150, text: LONG, arrow: true }];
  // the words, as Ruby draws them on the NOTES layer (draw_mark_note centres them on x/y; name_texts! keys them)
  s.doc.canvases[0].layers.find(l => l.name === "NOTES").shapes.push(
    { type: "text", text: "קירות פנים", x: -100, y: 150, h: 5, h0: 5, key: "NOTES|קירות פנים|1", align: "center", rotation: 0, follow: true },
    { type: "text", text: LONG, x: 100, y: -100, h: 5, h0: 5, key: "NOTES|" + LONG + "|1", align: "center", rotation: 0, follow: true });
  return s; };
const reload = () => { api.call("loadSheet", noteSheet()); api.call("setMode", "hand"); api.set("UNDO", []); global.sent.length = 0; };
reload();
const N = () => ST().marks.find(m => m.t === 'note');
const noteBar = () => el('notebar').className;
const panel = () => el('textbar').className;
const ed = () => el('tbedit');
const edKey = k => el('tbedit').onkeydown({ key: k, preventDefault() {}, stopPropagation() {} });
const twice = (mx, my) => { api.set("LBLAST", null); const c = api.call("screenOf", mx, my); down(c[0], c[1]); up(c[0], c[1]); down(c[0], c[1]); up(c[0], c[1]); return c; };

["noteWords", "noteOfText", "markUnder"].forEach(fn => ok("it defines " + fn, typeof safe(fn) === "function"));
ok("the bar a note used to open in is NOT the road any more", typeof safe("noteWordsOpen") !== "function");
ok("a note is on the sheet, its words are a label with a key, and nothing is open",
   !!N() && !!api.call("noteWords", 0) && noteBar() !== 'on' && panel() !== 'on', [N(), api.call("noteWords", 0), noteBar(), panel()]);
ok("the words know their note, and the note its words",
   api.call("noteWords", 0).note === 0 && api.call("noteOfText", api.call("noteWords", 0)) === 0);

// ---- ONE press on the words: picked, settings at the side
let c = api.call("screenOf", -100, 150);
api.set("LBLAST", null);
down(c[0], c[1]);
ok("ONE press on the words picks the note (it drags from this press)", api.get("SEL") === 0 && !!api.get("MDRAG"), [api.get("SEL"), api.get("MDRAG")]);
ok("and its settings are in the box at the side at once - quiet, like a label's",
   panel() === 'on' && api.get("TSEL") && api.get("TSEL").note === 0, [panel(), api.get("TSEL")]);
ok("the words are in the words box", el('txwords').value === 'קירות פנים', el('txwords').value);
ok("the head of the leader is offered there, and it is on", el('txnote').style.display !== 'none' && /on/.test(el('txarrow').className), [el('txnote').style.display, el('txarrow').className]);
ok("no bar opened at the top", noteBar() !== 'on' && !api.get("LED"), [noteBar(), api.get("LED")]);
up(c[0], c[1]);

// ---- the head on the leader, from the panel
global.sent.length = 0;
el('txarrow').onclick.call(el('txarrow'));
ok("the button at the side takes the head off the leader", N().arrow === false && !/on/.test(el('txarrow').className), [N().arrow, el('txarrow').className]);
ok("and Ruby was told", states().length >= 1 && states()[states().length - 1].marks.find(m => m.t === 'note').arrow === false, states().length);
ok("the next note starts without a head too, as the bar had it", ST().note_arrow === false, ST().note_arrow);
el('txarrow').onclick.call(el('txarrow'));
ok("and puts it back", N().arrow === true, N().arrow);
key('Escape');
ok("Escape lets go of everything", panel() !== 'on' && api.get("SEL") === null && !api.get("CARRY"), [panel(), api.get("SEL")]);

// ---- TWO quick presses on the words: typed over themselves
c = twice(-100, 150);
ok("TWO QUICK PRESSES ON THE WORDS OPEN THEM OVER THEMSELVES ON THE SHEET - the editor, not a bar",
   api.get("LED") && api.get("LED").kind === 'label' && /on/.test(ed().className) && noteBar() !== 'on', [api.get("LED"), ed().className, noteBar()]);
ok("with the note's words in it, ready to change", ed().value === 'קירות פנים', ed().value);
ok("the panel at the side is on the note", api.get("TSEL") && api.get("TSEL").note === 0, api.get("TSEL"));
{ const b = api.call("textBox", api.get("TSEL").shape, false), L = parseFloat(ed().style.left), T = parseFloat(ed().style.top);
  ok("the editor sits over the words themselves", Math.abs(L + parseFloat(ed().style.width) / 2 - (b.x + b.w / 2)) < 2 && Math.abs(T + parseFloat(ed().style.height) / 2 - (b.y + b.h / 2)) < 2, [L, T, b]); }
ok("and the note is not being carried or dragged", !api.get("CARRY") && api.get("MDRAG") === null, [api.get("CARRY"), api.get("MDRAG")]);

// the browser's own double click, coming late, must not start over
ed().value = 'קירות חוץ';
svg().ondblclick(ev(c[0], c[1]));
ok("the browser's late double click does not open it all over again", ed().value === 'קירות חוץ' && /on/.test(ed().className), ed().value);

// ---- Enter keeps the words ON THE NOTE
global.sent.length = 0;
edKey('Enter');
ok("Enter keeps the new words ON THE NOTE", N().text === 'קירות חוץ', N());
ok("the editor and the panel are shut", !api.get("LED") && panel() !== 'on', [api.get("LED"), panel()]);
ok("the leader and the box did not move", N().kx === -200 && N().ky === 150 && N().lx === -300 && N().ly === 100 && N().x === -100 && N().y === 150, N());
ok("and Ruby was told", states().length >= 1 && states()[states().length - 1].marks.find(m => m.t === 'note').text === 'קירות חוץ', states().length);
ok("the dimension's own words were not touched", ST().marks.find(m => m.t === 'dim').label === undefined, ST().marks.find(m => m.t === 'dim'));

// ---- Ctrl+Z brings the old words back
key('z', { ctrlKey: true });
ok("Ctrl+Z brings the old words back", N().text === 'קירות פנים', N().text);

// ---- two quick presses on the KNEE open the words too
c = twice(-200, 150);
ok("two quick presses on the knee open the words too", api.get("LED") && api.get("LED").kind === 'label' && ed().value === 'קירות פנים', [api.get("LED"), ed().value]);
ed().value = 'שונה';
edKey('Escape');
ok("Escape drops them: the words are as they were", !api.get("LED") && N().text === 'קירות פנים', [api.get("LED"), N().text]);

// ---- the FAR END of long words, past the grab of their middle, is still the note
api.set("LBLAST", null);
{ const b = api.call("textBox", api.call("noteWords", 2).shape, false);
  c = [b.x + b.w - 2, b.y + b.h / 2];
  ok("(the far end of the long words is out of the plain grab)", api.call("hitMark", ev(c[0], c[1])) === null, api.call("hitMark", ev(c[0], c[1])));
  down(c[0], c[1]); up(c[0], c[1]);
  ok("a press on the far end of the words picks the NOTE, not a loose label", api.get("SEL") === 2 && api.get("TSEL") && api.get("TSEL").note === 2 && !api.get("TCARRY"), [api.get("SEL"), api.get("TSEL"), api.get("TCARRY")]);
  down(c[0], c[1]); up(c[0], c[1]);
  ok("and two quick presses there open the words", api.get("LED") && api.get("LED").kind === 'label', api.get("LED"));
  edKey('Escape'); }

// ---- words typed in the box at the side go onto the note too
api.set("LBLAST", null);
c = api.call("screenOf", -100, 150);
down(c[0], c[1]); up(c[0], c[1]);
el('txwords').value = 'מהצד';
el('txwords').onkeydown({ key: 'Enter', preventDefault() {} });
ok("words typed in the box at the side go onto the note", N().text === 'מהצד', N().text);
key('Escape');

// ---- emptied = thrown away, as the bar had it
c = twice(-100, 150);
ed().value = '';
edKey('Enter');
ok("emptied, the note is thrown away", ST().marks.length === 2 && !ST().marks.some(m => m.text === 'מהצד'), ST().marks);
key('z', { ctrlKey: true });
ok("and Ctrl+Z brings it back", ST().marks.length === 3 && N().text === 'מהצד', N());

// ---- two SLOW presses are two picks, not an opening
reload();
api.set("LBLAST", null);
c = api.call("screenOf", -200, 150);
down(c[0], c[1]); up(c[0], c[1]);
api.set("LBLAST", Object.assign({}, api.get("LBLAST"), { t: Date.now() - 1000 }));
down(c[0], c[1]); up(c[0], c[1]);
ok("two SLOW presses do not open the words", !api.get("LED") && noteBar() !== 'on', [api.get("LED"), noteBar()]);
key('Escape');

// ---- a hand DIMENSION's number still opens its own way
api.set("LBLAST", null);
const lp = api.call("dimLabelXY", ST().marks.find(m => m.t === 'dim'));
twice(lp[0], lp[1]);
ok("two quick presses on a dimension's number still open the number, for the dimension",
   api.get("LED") && api.get("LED").kind === 'label' && api.get("TSEL") && api.get("TSEL").dim === 1 && api.get("TSEL").note === undefined, [api.get("LED"), api.get("TSEL")]);
edKey('Escape');

// ================================================================ a NEW note, typed where it will stand (2026-10-08)
// His rule: "כל כיתוב... לא יפתח לו קופסא אלא הקופסא תהיה על הכיתוב עצמו".
// Three clicks as before - the thing, the knee, the end of the shoulder - and
// then the words are typed on the sheet past the end of the shoulder, not in
// the bar at the top. Enter (or a press on the sheet) makes the note; Escape
// drops it.
reload();
const tap = (x, y) => { svg().onmousemove(ev(x, y)); svg().onmousedown(ev(x, y)); up(x, y); svg().onclick(ev(x, y)); };
const tapM = (mx, my) => { const q = api.call("screenOf", mx, my); tap(q[0], q[1]); return q; };
ok("the window has the switch, and it is on", api.get("NOTEPLACE") === true);
api.call("setMode", "note");
tapM(-300, -200); tapM(-200, -150);
ok("two clicks: the tip and the knee, nothing to type yet", api.get("PEND") && api.get("PEND2") && !api.get("PEND3") && !api.get("LED"), [api.get("PEND"), api.get("PEND2"), api.get("LED")]);
const endq = tapM(0, -150);
ok("THE THIRD CLICK OPENS THE WORDS ON THE SHEET - not the bar at the top", api.get("LED") && api.get("LED").kind === 'note' && /on/.test(ed().className) && noteBar() !== 'on', [api.get("LED"), ed().className, noteBar()]);
ok("empty, ready to type", ed().value === '', ed().value);
ok("just past the end of the shoulder, running the way it runs (to the right: the words start there)",
   Math.abs(parseFloat(ed().style.left) - endq[0]) < 40 && parseFloat(ed().style.left) >= endq[0] - 1 && ed().style.textAlign === 'left' && Math.abs(parseFloat(ed().style.top) + parseFloat(ed().style.height) / 2 - endq[1]) < 2,
   [ed().style.left, ed().style.top, ed().style.height, endq]);
ok("in a note's letters: as tall as a note's words on this sheet",
   Math.abs(parseFloat(ed().style.fontSize) - api.call("markTextH") * api.get("VIEW").sf * api.get("VIEW").k / 0.717) < 0.01, ed().style.fontSize);
ok("the three clicks are kept while he types", api.get("PEND") && api.get("PEND2") && api.get("PEND3"));
// typing, then Enter
ed().value = 'מטבח חדש';
global.sent.length = 0; api.set("UNDO", []);
const before = ST().marks.length;
edKey('Enter');
ok("ENTER MAKES THE NOTE, with his words, from the three clicks - exactly as the bar made one",
   ST().marks.length === before + 1 && ST().marks[before].t === 'note' && ST().marks[before].text === 'מטבח חדש' &&
   Math.abs(ST().marks[before].lx + 300) < 1e-6 && Math.abs(ST().marks[before].kx + 200) < 1e-6 && Math.abs(ST().marks[before].ky + 150) < 1e-6, ST().marks[before]);
{ const m = ST().marks[before], want = api.call("noteMark", [-300, -200], [-200, -150], [0, -150], 'מטבח חדש', true, api.call("scaleFactor", ST().scale));
  ok("the words stand where noteMark puts them (past the end of the shoulder)", Math.abs(m.x - want.x) < 1e-6 && Math.abs(m.y - want.y) < 1e-6, [m, want]); }
ok("the editor is shut, the clicks are forgotten, and Ruby was told", !api.get("LED") && !api.get("PEND") && states().length >= 1 && states()[states().length - 1].marks.length === before + 1, [api.get("LED"), api.get("PEND"), states().length]);
ok("it is one step for Ctrl+Z", api.get("UNDO").length === 1);
ok("he is still in the note tool, for the next one", api.get("MODE") === 'note');
// the sheet comes back from Ruby with the new note: its settings are at the side
{ const back = noteSheet(); back.state.marks = JSON.parse(JSON.stringify(ST().marks));
  const nm = back.state.marks[before];
  back.doc.canvases[0].layers.find(l => l.name === "NOTES").shapes.push({ type: "text", text: nm.text, x: nm.x, y: nm.y, h: 5, h0: 5, key: "NOTES|" + nm.text + "|1", align: "center", rotation: 0, follow: true });
  api.call("loadSheet", back); }
ok("when the sheet comes back, the new note's settings are at the side (size, B, I, U, colour, the head)", panel() === 'on' && api.get("TSEL") && api.get("TSEL").note === before && el('txnote').style.display !== 'none', [panel(), api.get("TSEL")]);
// a press on the sheet while typing keeps the words too; the press itself starts nothing
api.call("setMode", "note"); api.set("NOTEJUST", 0);
tapM(-300, 100); tapM(-200, 150); tapM(0, 150);
ed().value = 'שנייה';
const n2 = ST().marks.length;
tapM(100, 100);
ok("a press on the sheet while typing keeps the note, and that press starts no new one", ST().marks.length === n2 + 1 && ST().marks[n2].text === 'שנייה' && !api.get("PEND") && !api.get("LED"), [ST().marks.length, api.get("PEND"), api.get("LED")]);
// Escape drops a half-written one
api.set("NOTEJUST", 0);
tapM(-300, 300); tapM(-200, 350); tapM(0, 350);
ed().value = 'לא';
const n3 = ST().marks.length;
edKey('Escape');
ok("Escape drops the half-written note: nothing is made, the clicks are forgotten, the editor is shut", ST().marks.length === n3 && !api.get("PEND") && !api.get("LED"), [ST().marks.length, api.get("PEND"), api.get("LED")]);
// Enter with nothing typed makes nothing
api.set("NOTEJUST", 0);
tapM(-300, 300); tapM(-200, 350); tapM(0, 350);
edKey('Enter');
ok("Enter with nothing typed makes no note", ST().marks.length === n3 && !api.get("LED"));
// a shoulder running LEFT: the words end at the end of the shoulder
api.set("NOTEJUST", 0);
tapM(300, 300); tapM(200, 350); const lend = tapM(0, 350);
ok("a shoulder running left: the words END at its end", ed().style.textAlign === 'right' && Math.abs(parseFloat(ed().style.left) + parseFloat(ed().style.width) - lend[0]) < 40, [ed().style.left, ed().style.width, lend]);
edKey('Escape');
// the switch
api.set("NOTEPLACE", false); api.set("NOTEJUST", 0);
tapM(-300, 500); tapM(-200, 550); tapM(0, 550);
ok("SWITCHED OFF: the third click opens the bar at the top, as before", noteBar() === 'on' && !api.get("LED"), [noteBar(), api.get("LED")]);
key('Escape'); api.set("NOTEPLACE", true);

console.log(fails === 0 ? "t82 ALL PASS" : "\n*** " + fails + " FAILED ***");
process.exit(fails === 0 ? 0 : 1);
