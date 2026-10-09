// t85 - a dimension drawn on an elevation's picture, locked onto its lines (2026-10-08 19:46).
//
// The user: "תאפשר לי גם להשתמש בכל הכלים שישי לי פה בין מדידות הערות וכו גם על האליווישין -
// כי כרגע אני לא יכול להוסיף מדידה ... וכמובן שזה חייב להינעל על פינות וסופי קווים".
// The picture's lines come from Ruby (picSnaps); three clicks through the window's own
// handlers: from (locks onto an end), to (locks), where the line stands. Saved in
// STATE.image_hand[path] in shares of the picture; Escape drops one half drawn; Ctrl+Z takes it back.
//
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

api.call('setMode', 'dim');
global.sent = [];
move(...at(0.5, 0.5));
ok('the window asks Ruby for the picture\'s lines, once', global.sent.filter(m => m.name === 'elev_snaps').length === 1 &&
   global.sent.find(m => m.name === 'elev_snaps').args[0] === PATH, global.sent);
move(...at(0.5, 0.6));
ok('and not again while they are on the way', global.sent.filter(m => m.name === 'elev_snaps').length === 1);
// Ruby answers: a floor line and a wall corner line; the picture stands for 100" x 120" of the room
api.call('picSnaps', PATH, { segs: [[0.2, 0.2, 0.8, 0.2], [0.8, 0.2, 0.8, 0.9]], w_in: 100, h_in: 120 });
const sn = api.get('PSNAPS')[PATH];
ok('its ends and middles are points to lock onto', sn && sn.pts.length === 5, sn && sn.pts);

// 1: near the floor line's left end (3 px off) - it locks onto the end
const a = at(0.2, 0.2);
move(a[0] + 3, a[1] - 2);
ok('the ring shows the end it will lock onto BEFORE the click', api.get('PDHOV') && api.get('PDHOV').kind === 'end' &&
   near(api.get('PDHOV').u, 0.2) && near(api.get('PDHOV').v, 0.2), api.get('PDHOV'));
ok('and it is drawn (green)', svg().children.some(c => c.id === 'picdim' && /2fbf5f/.test(c.innerHTML)));
click(a[0] + 3, a[1] - 2);
ok('the first click is the end itself, not the mouse', api.get('PD') && near(api.get('PD').a.u, 0.2) && near(api.get('PD').a.v, 0.2), api.get('PD'));
// 2: the corner where the two lines meet
const b = at(0.8, 0.2);
click(b[0] - 4, b[1] + 3);
const pd = api.get('PD');
ok('the second click locks onto the corner', pd && pd.b && near(pd.b.u, 0.8) && near(pd.b.v, 0.2), pd);
ok('across, 60" (0.6 of 100")', pd.o === 'h' && near(pd.n, 60), pd);
// 3: pull it down under the floor, and leave it there
const c = at(0.5, 0.1);
move(c[0], c[1]);
ok('the line follows the mouse, up and down only', near(api.get('PD').at, 0.1, 1e-3), api.get('PD').at);
global.sent = [];
click(c[0], c[1]);
const hand = api.get('STATE').image_hand;
ok('the third click leaves it there, by the picture\'s path', hand && hand[PATH] && hand[PATH].length === 1, hand);
const d = hand[PATH][0];
ok('saved: the two points, the way, where the line stands, the inches', JSON.stringify(d.p) === JSON.stringify([0.2, 0.2, 0.8, 0.2]) &&
   d.o === 'h' && near(d.at, 0.1, 1e-3) && near(d.n, 60), d);
ok('and sent to Ruby, which draws it', global.sent.some(m => m.name === 'set_state' && JSON.parse(m.args[0]).image_hand[PATH].length === 1));
ok('and written in the trace', global.sent.some(m => m.name === 'pic_dim_trace'));

// a vertical one up the corner line, the mouse nowhere near a point in between: locks onto the line
click(...at(0.8, 0.2));
const mid = at(0.8, 0.55);
move(mid[0] + 2, mid[1]);
ok('between the points it locks onto the middle of the line', api.get('PDHOV').kind === 'mid' && near(api.get('PDHOV').v, 0.55), api.get('PDHOV'));
const on = at(0.8, 0.7);
move(on[0] + 3, on[1]);
ok('away from any point, onto the line itself (magenta)', api.get('PDHOV').kind === 'edge' && near(api.get('PDHOV').u, 0.8) && near(api.get('PDHOV').v, 0.7, 1e-3), api.get('PDHOV'));
click(on[0] + 3, on[1]);
ok('up, 0.5 of 120" = 60"', api.get('PD').o === 'v' && near(api.get('PD').n, 60, 1e-3), api.get('PD'));
key('Escape');
ok('Escape drops the one half drawn, and nothing is saved', api.get('PD') === null && api.get('STATE').image_hand[PATH].length === 1);

// Ctrl+Z takes the first one back
global.sent = [];
api.call('undoLast');
ok('Ctrl+Z takes the dimension off the picture', (api.get('STATE').image_hand[PATH] || []).length === 0, api.get('STATE').image_hand);
ok('and tells Ruby', global.sent.some(m => m.name === 'set_state'));

// a picture with no lines beside it says so
api.call('setMode', 'dim');
api.call('picSnaps', PATH, null);
global.sent = [];
click(...at(0.5, 0.5));
ok('a picture with no lines says so, and draws nothing', api.get('PD') === null && /Elevations/.test(document.getElementById('markinfo').textContent));

// the switch
const rb = fs.readFileSync('plan_sheet_dialog.rb', 'utf8');
ok('the switch rides with the sheet', rb.includes('pic_dims: InteriorPro::PlanCanvas::USE_PIC_DIMS') && rb.includes("PICDIMS = (p.pic_dims!==false);"));

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
