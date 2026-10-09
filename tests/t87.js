// t87 - the plan's own tools on an elevation's sheet (2026-10-09, PlanCanvas::USE_PIC_MARKS).
//
// The user: "תסתכל על איך כל הכלים האלו עובדים עם סירטוט רגיל ... ותחל את אותם הכללים על האלווישין"
// and "כל הסירטוטים חייבים להתנהג אותו הדבר". So the sheet gets a VIEW in paper inches and the plan's
// marks (STATE.page_marks[its picture]) - the dimension, the note, the line, the arrow, the eraser,
// Delete, Ctrl+Z all run the plan's road. Locks onto the picture's lines. The old ones come over.
//
// The DOM stand-in below is t85's, copied: each suite stands alone.
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

const PATH = 'C:/x/elevations/Room_2_North_lines.png';
const SHEET = {
  doc: { job_address: 'x', canvases: [{ name: 'MODEL', layers: [] }],
    pages: [{ name: 'Room 2', width: 36, height: 24, kind: 'image', ref: 0, sheet_number: 'A-201',
      views: [], pic_area: [1, 1, 34, 22],
      layers: [{ name: 'IMAGE', visible: true, shapes: [
        { type: 'image', path: PATH, x: 2, y: 2, w: 10, h: 12, placed: true, pic: 'm:0', rot: 0, crop: [0, 0, 0, 0], iw: 1000, ih: 1200 } ] }] }] },
  state: { size: 'ARCH D', orientation: 'landscape', scale: '1/4"', hidden: [], origin_x: 0, origin_y: 0, active: 0,
    marks: [], images: [PATH], open: {}, text_scale: { dims: 100, rooms: 100, tags: 100, tables: 100 }, text_marks: {} },
  page_sizes: ['ARCH D'], scales: ['1/4"'], images: [PATH], logo: null, bounds: [0, 0, 1, 1]
};
let wired = null;
try { (LISTEN.load || []).forEach(fn => fn({})); } catch (e) { wired = e; }
ok('the window wires itself up', !wired, wired && String(wired));
api.call('loadSheet', JSON.parse(JSON.stringify(SHEET)));
api.call('render');
ok('the picture sheet is the one open, with no plan view on it', api.get('PAGE').kind === 'image' && api.call('pageView') === null);
const K = () => api.get('LIVEK');
ok('it has a size on the screen', K() > 0, K());
const svg = () => document.getElementById('sheetWrap').firstChild;
const ev = (x, y, m) => Object.assign({ clientX: x, clientY: y, button: 0, shiftKey: false, altKey: false, ctrlKey: false,
  target: { tagName: 'svg', id: '' }, preventDefault() {}, stopPropagation() {} }, m || {});
const move = (x, y) => svg().onmousemove(ev(x, y));
const click = (x, y) => { move(x, y); svg().onclick(ev(x, y)); };
const key = (k, m) => (LISTEN.keydown || []).forEach(fn => fn(Object.assign({ key: k, code: k, target: { tagName: 'BODY', id: '' }, preventDefault() {}, stopPropagation() {} }, m || {})));
// a spot of the picture (u across, v up) -> the screen
const at = (u, v) => [(2 + u * 10) * K(), (24 - (2 + v * 12)) * K()];
const near = (a, b, t) => Math.abs(a - b) < (t || 1e-6);


const ed = () => document.getElementById('tbedit');
const edKey = (k) => ed().onkeydown({ key: k, preventDefault() {}, stopPropagation() {} });
const pm = () => (api.get('STATE').page_marks || {})[PATH] || [];
const down = (x, y, m) => svg().onmousedown(ev(x, y, m));

ok('the sheet has a view of its own, in paper inches', api.get('VIEW') && api.get('VIEW').paper === true && api.call('onPaper') === true, api.get('VIEW'));
ok('its marks are kept under its picture', api.call('pageMarkKey') === PATH);
const P = api.call('atMouse', ev(...at(0.5, 0.5)));
ok('the mouse is read in paper inches, no plan origin in it', near(P[0], 7, 1e-6) && near(P[1], 8, 1e-6), P);

// ---------------------------------------------------------------- the dimension
api.call('setMode', 'dim');
global.sent = [];
move(...at(0.5, 0.5));
ok('the dimension tool asks for the picture\'s lines', global.sent.some(m => m.name === 'elev_snaps' && m.args[0] === PATH), global.sent);
api.call('picSnaps', PATH, { segs: [[0.2, 0.2, 0.8, 0.2], [0.8, 0.2, 0.8, 0.9]], w_in: 100, h_in: 120 });
const c0 = at(0.2, 0.2);
move(c0[0] + 3, c0[1] - 2);
ok('the ring shows the end before the click (green)', svg().children.some(c => c.id === 'snaphi' && c.stroke === '#2fbf5f'), svg().children.map(c => c.id));
click(c0[0] + 3, c0[1] - 2);
const pe = api.get('PEND');
ok('the first click is the end itself, in paper inches', pe && near(pe[0], 4) && near(pe[1], 4.4), pe);
const c1 = at(0.8, 0.2);
click(c1[0] - 4, c1[1] + 3);
ok('the second locks onto the corner', api.get('PEND2') && near(api.get('PEND2')[0], 10) && near(api.get('PEND2')[1], 4.4), api.get('PEND2'));
const c2 = at(0.5, 0.1);
move(c2[0], c2[1]);
global.sent = [];
click(c2[0], c2[1]);
ok('the third leaves it: one dimension on the sheet, none on the plan', pm().length === 1 && (api.get('STATE').marks || []).length === 0, [pm(), api.get('STATE').marks]);
const d = pm()[0];
ok('it is the plan\'s dimension, in paper inches', d.t === 'dim' && near(d.x1, 4) && near(d.x2, 10) && near(d.y1, 4.4) && d.off < 0, d);
ok('it knows its picture and its scale: 10" of paper is 100" of room', d.pic === PATH && near(d.per, 0.1) && near(d.pw, 10), d);
ok('and Ruby is told', global.sent.some(m => m.name === 'set_state' && JSON.parse(m.args[0]).page_marks[PATH].length === 1));

// ---------------------------------------------------------------- the note
api.call('setMode', 'note');
const t0 = at(0.8, 0.2);
move(t0[0] - 3, t0[1] + 2);
ok('the note tool shows the ring where its tip locks', svg().children.some(c => c.id === 'snaphi'), svg().children.map(c => c.id));
click(t0[0] - 3, t0[1] + 2);
ok('its tip is the corner', api.get('PEND') && near(api.get('PEND')[0], 10) && near(api.get('PEND')[1], 4.4), api.get('PEND'));
click(...at(0.9, 0.4));
click(...at(1.05, 0.405));
ok('the words open on the sheet, the plan\'s way', api.get('LED') && api.get('LED').kind === 'note', api.get('LED'));
ed().value = 'Grab bar';
edKey('Enter');
const n = pm()[1];
ok('Enter keeps it: the plan\'s note, on the sheet', pm().length === 2 && n.t === 'note' && n.text === 'Grab bar' && near(n.lx, 10) && near(n.ly, 4.4) && near(n.ky, n.y, 1e-6), n);

// ---------------------------------------------------------------- a line
api.call('setMode', 'line');
global.sent = [];
click(...at(0.2, 0.2));
click(...at(0.2, 0.9));
const ln = pm()[2];
ok('the line tool draws a line on the sheet - not into the plan\'s loose lines', ln && ln.t === 'line' && near(ln.x1, 4) && near(ln.y2, 12.8) &&
   !global.sent.some(m => m.name === 'add_site_line'), [ln, global.sent.map(m => m.name)]);

// ---------------------------------------------------------------- the arrow picks a mark over the picture
api.call('setMode', 'hand');
const onLine = at(0.5, 0.1);
down(onLine[0], onLine[1]);
ok('a press on the dimension\'s line picks the dimension, not the picture under it', api.get('SEL') === 0 && api.get('BSEL') === null,
   [api.get('SEL'), api.get('BSEL')]);
ok('and it is drawn picked', api.get('MDRAG') && api.get('MDRAG').part === 'off', api.get('MDRAG'));
api.set('MDRAG', null);
// a press on bare picture still picks the picture
down(...at(0.4, 0.6));
ok('a press on the picture itself still picks the picture', api.get('BSEL') === 'm:0', api.get('BSEL'));
api.call('escapeAll');

// ---------------------------------------------------------------- the eraser, Delete, Ctrl+Z
api.call('setMode', 'erase');
const he = api.call('hitErase', ev(...at(0.2, 0.55)));
ok('the eraser finds the line', he && he.kind === 'mark' && pm()[he.i].t === 'line', he);
api.call('eraseSweepNow', [he]);
ok('and takes it off', pm().length === 2 && !pm().some(m => m.t === 'line'));
api.call('undoLast');
ok('Ctrl+Z puts it back', pm().length === 3 && pm()[2].t === 'line', pm());
api.call('setMode', 'hand');
api.set('SEL', 1);
key('Delete');
ok('Delete takes the picked note', pm().length === 2 && !pm().some(m => m.t === 'note'), pm());
api.call('undoLast');
ok('and Ctrl+Z brings it back', pm().some(m => m.t === 'note'));

// ---------------------------------------------------------------- the picture moves: its marks go with it
const pic0 = api.call('pagePics')[0];
const before = JSON.parse(JSON.stringify(pm()));
api.call('setPic', pic0, { x: 5, y: 3, w: 5, h: 6, rot: 0, crop: [0, 0, 0, 0] });   // moved, and half the size
const dm = pm().find(m => m.t === 'dim'), nm = pm().find(m => m.t === 'note'), lm = pm().find(m => m.t === 'line');
ok('the dimension keeps its spot ON the picture (u .2 v .2 and u .8 v .2)', near(dm.x1, 6) && near(dm.y1, 4.2) && near(dm.x2, 9) && near(dm.y2, 4.2), dm);
ok('its distance off shrinks with the picture, its number stays (per and pw untouched)', near(dm.off, before[0].off / 2) && dm.per === before[0].per && dm.pw === before[0].pw, [dm.off, before[0].off]);
ok('the note\'s tip stays on the corner it points at', near(nm.lx, 9) && near(nm.ly, 4.2), nm);
ok('the line goes too', near(lm.x1, 6) && near(lm.y1, 4.2), lm);
ok('each now knows its picture', pm().every(m => m.pic === PATH));
api.call('picPut', pic0, { placed: true, x: 2, y: 2, w: 10, h: 12, rot: 0, crop: [0, 0, 0, 0] });
const back = pm();
ok('put back (Escape, or back where it started): every mark exactly where it was',
   back.every((m, i) => ['x1', 'y1', 'x2', 'y2', 'x', 'y', 'kx', 'ky', 'lx', 'ly', 'off'].every(k => before[i][k] === undefined || near(m[k], before[i][k], 1e-9))), [back, before]);
api.call('setPic', pic0, { x: 2, y: 2, w: 10, h: 12, rot: 90, crop: [0, 0, 0, 0] });
const dt = pm().find(m => m.t === 'dim');
ok('turned a quarter: the dimension turns with it about the middle', near(dt.x1, 7 - (4.4 - 8)) && near(dt.y1, 8 + (4 - 7)), dt);
api.call('picPut', pic0, { placed: true, x: 2, y: 2, w: 10, h: 12, rot: 0, crop: [0, 0, 0, 0] });
// ---------------------------------------------------------------- the plan is the plan
ok('the plan\'s own marks were never touched', (api.get('STATE').marks || []).length === 0);

// ---------------------------------------------------------------- what was drawn the old way comes over
const st = api.get('STATE');
st.image_hand = { [PATH]: [{ p: [0.2, 0.2, 0.8, 0.2], o: 'h', at: 0.1, n: 60 },
                          { t: 'note', p: [0.8, 0.2, 0.9, 0.4, 1.05, 0.4], text: 'old', arrow: true }] };
global.sent = [];
const undoN = api.get('UNDO').length;
api.call('render');
ok('the old ones become the sheet\'s marks, once', pm().length === 5 && !(st.image_hand[PATH]) &&
   pm()[3].t === 'dim' && near(pm()[3].per, 6 / 60) && near(pm()[3].x2, 10) && near(pm()[3].y2, 4.4) && pm()[4].text === 'old', pm());
ok('kept, told, and not a step of Ctrl+Z', global.sent.some(m => m.name === 'set_state') && api.get('UNDO').length === undoN, [api.get('UNDO').length, undoN]);
const off = pm()[3].off;
ok('the old one\'s line stands where it stood (under the floor)', off < 0 && near(Math.abs(off), 1.2, 1e-6), off);

// ---------------------------------------------------------------- writing centred on the paper
const html = api.call('shapeSVG', { type: 'text', text: 'X', x: 3, y: 3, h: 0.11, align: 'center', __paper: true }, (x, y) => [x, y], K(), 24);
ok('a mark\'s words straight on the paper are drawn centred on their point', /text-anchor="middle"/.test(html) && /dominant-baseline="central"/.test(html), html);
const plain = api.call('shapeSVG', { type: 'text', text: 'X', x: 3, y: 3, h: 0.11, __paper: true }, (x, y) => [x, y], K(), 24);
ok('other writing on the paper still starts at its point', /text-anchor="start"/.test(plain), plain);

// ---------------------------------------------------------------- the switch
api.set('PICMARKS', false);
api.call('render');
ok('switched off: no view on the sheet, the plan\'s marks list again', api.get('VIEW') === null && api.call('marks') === api.get('STATE').marks);
const rb = fs.readFileSync('plan_sheet_dialog.rb', 'utf8');
ok('the switch rides with the sheet', rb.includes('pic_marks: InteriorPro::PlanCanvas::USE_PIC_MARKS') && rb.includes('PICMARKS = (p.pic_marks!==false);'));

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
