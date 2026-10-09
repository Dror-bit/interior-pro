// t88 - the layers list is his groups (2026-10-09, PlanCanvas::USE_LAYER_GROUPS): walls, doors, windows,
// dimensions, notes, writing (rooms, door and window names, boxes of writing), pictures - and lines / tile /
// plumbing / electric once there is something of them. A group off takes its shapes off the sheet, out of
// reach of the mouse, and is told to Ruby (STATE.hide) for the PDF. Door names go with writing, not with doors;
// a hand dimension with dimensions, not with notes.
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


const SHEET = {
  doc: { job_address: 'x', canvases: [{ name: 'MODEL', layers: [
      { name: 'WALLS', visible: true, shapes: [{ type: 'polygon', points: [[0, 0], [120, 0], [120, 6], [0, 6]], closed: true }] },
      { name: 'DOORS', visible: true, shapes: [{ type: 'line', x1: 20, y1: 0, x2: 50, y2: 0 }, { type: 'text', text: 'D101', x: 35, y: 20, h: 5, key: 'DOORS|D101|1' }] },
      { name: 'WINDOWS', visible: true, shapes: [{ type: 'line', x1: 70, y1: 0, x2: 100, y2: 0 }, { type: 'text', text: 'W101', x: 85, y: 20, h: 5, key: 'WINDOWS|W101|1' }] },
      { name: 'DIMENSIONS', visible: true, shapes: [{ type: 'line', x1: 0, y1: -20, x2: 120, y2: -20 }, { type: 'text', text: "10'-0\"", x: 60, y: -18, h: 5, key: "DIMENSIONS|10'-0\"|1" }] },
      { name: 'ROOMS', visible: true, shapes: [{ type: 'text', text: 'ROOM 2', x: 60, y: 60, h: 6, key: 'ROOMS|ROOM 2|1' }] },
      { name: 'NOTES', visible: true, shapes: [{ type: 'line', x1: 0, y1: 80, x2: 40, y2: 80, mdim: true }, { type: 'text', text: "3'-4\"", x: 20, y: 84, h: 5, key: "NOTES|3'-4\"|1", mdim: true },
                                                 { type: 'text', text: 'Tile here', x: 90, y: 90, h: 5, key: 'NOTES|Tile here|1', note: 1 }] } ] }],
    pages: [{ name: 'Plan', width: 36, height: 24, kind: 'plan', sheet_number: 'A-101', margin: 0.5,
      views: [{ canvas: 'MODEL', x: 1, y: 2, w: 30, h: 20, scale: '1/4"' }],
      layers: [{ name: 'TITLE', visible: true, shapes: [{ type: 'text', text: 'A-101', x: 33, y: 1, h: 0.2, key: 'TITLE|A-101|1' }] }] }] },
  state: { size: 'ARCH D', orientation: 'landscape', scale: '1/4"', hidden: [], origin_x: 60, origin_y: 40, active: 0, strip: false,
    marks: [{ t: 'dim', x1: 0, y1: 80, x2: 40, y2: 80 }, { t: 'note', x: 90, y: 90, kx: 70, ky: 90, lx: 60, ly: 70, text: 'Tile here' }],
    images: [], open: { layers: true }, text_scale: { dims: 100, rooms: 100, tags: 100, tables: 100 }, text_marks: {} },
  page_sizes: ['ARCH D'], scales: ['1/4"'], images: [], logo: null, bounds: [0, -20, 120, 90]
};
let wired = null;
try { (LISTEN.load || []).forEach(fn => fn({})); } catch (e) { wired = e; }
ok('the window wires itself up', !wired, wired && String(wired));
api.call('loadSheet', JSON.parse(JSON.stringify(SHEET)));
api.call('render');
const rows = () => document.getElementById('layers').children.map(l => l.children[1].textContent);
ok('the list is his groups, in his words, in his order', JSON.stringify(rows()) === JSON.stringify(['קירות', 'דלתות', 'חלונות', 'מידות', 'הערות', 'כיתובים', 'תמונות', 'TILE', 'PLUMBING', 'ELECTRICAL']), rows());
const html = () => document.getElementById('sheetWrap').innerHTML;
const cb = (name) => document.getElementById('layers').children.find(l => l.children[1].textContent === name).children[0];
ok('everything is on the sheet', /D101/.test(html()) && /ROOM 2/.test(html()) && /Tile here/.test(html()) && /3'-4/.test(html()));

global.sent = [];
const t = cb('כיתובים'); t.checked = false; t.onchange();
ok('writing off: the room names and the door and window names go', !/ROOM 2/.test(html()) && !/D101/.test(html()) && !/W101/.test(html()), html().slice(0, 300));
ok('the doors themselves stay, and the numbers of the dimensions', /3'-4/.test(html()) && /10'-0/.test(html()) && html().split('<line').length > 3);
ok('and Ruby is told, for the PDF', global.sent.some(m => m.name === 'set_state' && JSON.stringify(JSON.parse(m.args[0]).hide) === '["text"]'), global.sent.map(m => m.name));
ok('the count says one is off', /1/.test(document.getElementById('laycount').textContent), document.getElementById('laycount').textContent);
t.checked = true; t.onchange();

const d = cb('מידות'); d.checked = false; d.onchange();
ok('dimensions off: his hand dimension goes with them, the note stays', !/3'-4/.test(html()) && !/10'-0/.test(html()) && /Tile here/.test(html()));
ok('and the hand dimension cannot be grabbed', api.call('markOff', api.get('STATE').marks[0]) === true && api.call('markOff', api.get('STATE').marks[1]) === false);
d.checked = true; d.onchange();
const n = cb('הערות'); n.checked = false; n.onchange();
ok('notes off: the note goes, the hand dimension stays', !/Tile here/.test(html()) && /3'-4/.test(html()));
n.checked = true; n.onchange();
const w = cb('קירות'); w.checked = false; w.onchange();
ok('walls off: the wall is not drawn', api.call('layerOff', 'WALLS') === true && !/polygon/.test(html().replace(/<rect[^>]*>/g, '')), html().slice(0, 200));
w.checked = true; w.onchange();
ok('the title block has no switch: always there', !rows().some(r => /TITLE/.test(r)) && /A-101/.test(html()));

// the same rule as Ruby's
const rb = fs.readFileSync('plan_canvas.rb', 'utf8');
ok('Ruby says the same: a door\'s name is writing, a hand dimension a dimension',
   rb.includes("when LAYERS[:doors] then text ? 'text' : 'doors'") && rb.includes("when MARK_LAYER, PAGE_MARK_LAYER then s[:mdim] ? 'dims' : 'notes'"));
const groups = { WALLS: 'walls', SKETCH: 'walls', DIMENSIONS: 'dims', ELEV_DIMS: 'dims', ROOMS: 'text', TEXT: 'text', IMAGES: 'pics', SITE: 'lines', TILE: 'tile', PLUMBING: 'plumbing', ELECTRIC: 'electric', TITLE: null, SCHEDULES: null };
ok('every layer goes to the same group in both', Object.keys(groups).every(k => api.call('shapeGroup', k, { type: 'line' }) === groups[k]),
   Object.keys(groups).map(k => [k, api.call('shapeGroup', k, { type: 'line' })]));

// tile, plumbing, electric: a row once there is something of them
const S2 = JSON.parse(JSON.stringify(SHEET));
S2.doc.canvases[0].layers.push({ name: 'PLUMBING', visible: true, shapes: [{ type: 'line', x1: 0, y1: 0, x2: 1, y2: 1 }] });
api.call('loadSheet', S2); api.call('render');
ok('TILE, PLUMBING, ELECTRICAL always have their rows, in English', ['TILE', 'PLUMBING', 'ELECTRICAL'].every(r => rows().indexOf(r) >= 0), rows());

// an elevation taken in layers (ElevationTool USE_ELEV_LAYERS): the picture without what is off, at once
const EP = 'C:/e/Room_2_North_lines.png', NP = 'C:/e/Room_2_North_lines__no_plumbing.png', NT = 'C:/e/Room_2_North_lines__no_plumbing+tile.png';
const S3 = JSON.parse(JSON.stringify(SHEET));
S3.doc.pages.push({ name: 'Room 2', width: 36, height: 24, kind: 'image', ref: 0, sheet_number: 'A-201', views: [], pic_area: [1, 1, 34, 22],
  layers: [{ name: 'IMAGES', visible: true, shapes: [{ type: 'image', path: EP, x: 2, y: 2, w: 10, h: 12, placed: true, pic: 'm:0', rot: 0, crop: [0, 0, 0, 0], iw: 1000, ih: 1200,
             layers: { cats: ['plumbing', 'tile'], files: { plumbing: NP, 'plumbing+tile': NT, tile: 'C:/e/x__no_tile.png' } } }] },
           { name: 'ELEV_DIMS', visible: true, shapes: [{ type: 'text', text: '87"', x: 3, y: 1.5, h: 0.11, key: 'ELEV_DIMS|87"|1' },
                                                        { type: 'text', text: '30"', x: 1.5, y: 5, h: 0.11, key: 'ELEV_DIMS|30"|1', grp: 'plumbing' }] }] });
S3.state.images = [EP]; S3.state.active = 1; S3.state.hide = [];
S3.images = [{ i: 0, path: EP, url: 'file:///full.png', variants: [{ path: NP, url: 'file:///noplumb.png' }, { path: NT, url: 'file:///nothing.png' }] }];
api.call('loadSheet', S3); api.call('render');
ok('a picture in layers: its rows are there', rows().indexOf('PLUMBING') >= 0 && rows().indexOf('TILE') >= 0, rows());
ok('all on: the whole picture', /full\.png/.test(html()) && /30"/.test(html()));
const pl = cb('PLUMBING'); pl.checked = false; pl.onchange();
ok('plumbing off: the picture without it, and its numbers go - the wall\'s stay', /noplumb\.png/.test(html()) && !/full\.png/.test(html()) && !/>30"/.test(html()) && /87"/.test(html()), html().slice(0, 400));
const tl = cb('TILE'); tl.checked = false; tl.onchange();
ok('and the tiles too: the picture without both', /nothing\.png/.test(html()));
const pc2 = cb('תמונות'); pc2.checked = false; pc2.onchange();
ok('pictures off: no picture at all', !/<image/.test(html()));

// the switch
api.set('LGROUPS', false);
api.call('buildLayers');
ok('switched off: the document\'s own layer names again', rows().indexOf('WALLS') >= 0, rows());

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
