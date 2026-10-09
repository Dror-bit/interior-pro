// t86 - a note written on an elevation's picture (2026-10-09), the next of his list:
// "תאפשר לי גם להשתמש בכל הכלים ... מדידות הערות וכו גם על האליווישין ... חייב להינעל על פינות וסופי קווים".
// Three clicks through the window's own handlers: the tip (locks onto the picture's lines), the knee, the
// shoulder's end (right angle wins); the words typed on the sheet; Enter or a press keeps them. Saved in
// STATE.image_hand[path] as {t:'note', p:[6 shares], text, arrow}; Escape drops one half made; Ctrl+Z takes it back.
//
// The DOM stand-in below is t85's, copied: each suite stands alone.
// The DOM stand-in below is t82's, copied: each suite stands alone.
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
// the tools of 2026-10-08 are the road with PlanCanvas::USE_PIC_MARKS off (t87 has the plan's own road)
api.set('PICMARKS', false);
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

api.call('setMode', 'note');
global.sent = [];
move(...at(0.5, 0.5));
ok('the note tool asks Ruby for the picture\'s lines too', global.sent.some(m => m.name === 'elev_snaps' && m.args[0] === PATH), global.sent);
api.call('picSnaps', PATH, { segs: [[0.2, 0.2, 0.8, 0.2], [0.8, 0.2, 0.8, 0.9]], w_in: 100, h_in: 120 });

// 1: the tip, 3 px off the corner - it locks onto it, and the ring shows it first
const tip = at(0.8, 0.2);
move(tip[0] - 3, tip[1] + 2);
ok('the ring shows the corner before the click', api.get('PNHOV') && api.get('PNHOV').kind === 'end' && near(api.get('PNHOV').u, 0.8), api.get('PNHOV'));
ok('and it is drawn (green)', svg().children.some(c => c.id === 'picnote' && /2fbf5f/.test(c.innerHTML)));
click(tip[0] - 3, tip[1] + 2);
ok('the first click is the corner itself', api.get('PN') && near(api.get('PN').a.u, 0.8) && near(api.get('PN').a.v, 0.2), api.get('PN'));
// 2: the knee, up and to the right
const knee = at(0.9, 0.4);
click(knee[0], knee[1]);
ok('the second click is where the leader bends, where he clicked', api.get('PN').b && near(api.get('PN').b.u, 0.9, 1e-3) && near(api.get('PN').b.v, 0.4, 1e-3), api.get('PN'));
// 3: the shoulder's end, a little off level - the right angle wins
const end = at(1.05, 0.405);
move(end[0], end[1]);
ok('the shoulder follows the mouse, held level', api.get('PNHOV') && near(api.get('PNHOV').v, 0.4, 1e-3), api.get('PNHOV'));
click(end[0], end[1]);
const pn = api.get('PN');
ok('the third click: level with the knee', pn.c && near(pn.c.v, 0.4, 1e-3) && near(pn.c.u, 1.05, 1e-3), pn);
ok('and the words open ON the sheet, nothing saved yet', api.get('LED') && api.get('LED').kind === 'pnote' && ed().className.indexOf('on') === 0 &&
   !(api.get('STATE').image_hand && (api.get('STATE').image_hand[PATH] || []).length), [api.get('LED'), ed().className]);
const ex = at(1.05, 0.4);
ok('the editor starts just past the end of the shoulder', near(parseFloat(ed().style.left), ex[0] + 4, 1.5) && ed().style.textAlign === 'left', ed().style);
global.sent = [];
ed().value = 'Grab bar  here';
edKey('Enter');
const hand = api.get('STATE').image_hand;
ok('Enter keeps it, by the picture\'s path', hand && hand[PATH] && hand[PATH].length === 1, hand);
const n = hand[PATH][0];
ok('saved: a note, its three points, its words', n.t === 'note' && n.p.length === 6 && near(n.p[0], 0.8) && near(n.p[3], 0.4, 1e-3) &&
   near(n.p[5], 0.4, 1e-3) && n.text === 'Grab bar here' && n.arrow === true, n);
ok('sent to Ruby, which draws it', global.sent.some(m => m.name === 'set_state' && JSON.parse(m.args[0]).image_hand[PATH].length === 1));
ok('and written in the trace', global.sent.some(m => m.name === 'pic_dim_trace' && /note "Grab bar here" pointing at end/.test(m.args[0])), global.sent);
ok('the editor is put away', api.get('LED') === null && api.get('PN') === null);

// a second one, kept by a press on the sheet instead of Enter
click(...at(0.5, 0.2)); click(...at(0.5, 0.5)); click(...at(0.3, 0.5));
ok('a shoulder run to the LEFT types to the left', api.get('LED') && ed().style.textAlign === 'right', ed().style.textAlign);
ed().value = 'Floor';
svg().onmousedown(ev(...at(0.1, 0.9)));
svg().onclick(ev(...at(0.1, 0.9)));
ok('a press on the sheet keeps it, and starts nothing new', api.get('STATE').image_hand[PATH].length === 2 && api.get('PN') === null,
   [api.get('STATE').image_hand[PATH].length, api.get('PN')]);

// Escape drops one half made
click(...at(0.5, 0.2)); click(...at(0.5, 0.5));
key('Escape');
ok('Escape drops the half-drawn note', api.get('PN') === null && api.get('STATE').image_hand[PATH].length === 2);
api.call('setMode', 'note');
click(...at(0.5, 0.2)); click(...at(0.5, 0.5)); click(...at(0.7, 0.5));
ed().value = 'nothing';
edKey('Escape');
ok('Escape while typing drops it too', api.get('PN') === null && api.get('LED') === null && api.get('STATE').image_hand[PATH].length === 2);
// no words, no note
click(...at(0.5, 0.2)); click(...at(0.5, 0.5)); click(...at(0.7, 0.5));
ed().value = '   ';
edKey('Enter');
ok('no words, no note', api.get('STATE').image_hand[PATH].length === 2);

// Ctrl+Z
global.sent = [];
api.call('undoLast');
ok('Ctrl+Z takes the last note off the picture', api.get('STATE').image_hand[PATH].length === 1 && api.get('STATE').image_hand[PATH][0].text === 'Grab bar here',
   api.get('STATE').image_hand[PATH]);
ok('and tells Ruby', global.sent.some(m => m.name === 'set_state'));

// another tool in the middle drops it
click(...at(0.5, 0.2));
api.call('setMode', 'dim');
ok('another tool drops a half-made note', api.get('PN') === null);

// the letters' size rides with the sheet
const rb = fs.readFileSync('plan_sheet_dialog.rb', 'utf8');
ok('Ruby sends the elevation\'s letter size', rb.includes('elev_text_h: (InteriorPro::PlanCanvas.elev_style(st)[0] rescue 0.11)') &&
   rb.includes('PICNOTE_H = (+p.elev_text_h>0) ? +p.elev_text_h : 0.11;'));

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
