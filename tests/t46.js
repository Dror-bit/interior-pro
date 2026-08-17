// t46 - the sheet window's own JavaScript actually runs (2026-08-17).
//
// WHY THIS EXISTS. The user reported that double-clicking a label did nothing:
// "אין לי בכלל את האופציה לבחור את הכיתוב". There was no way to tell apart
//
//   (a) a syntax error somewhere in 62 KB of script, which kills the WHOLE
//       window silently - every feature in it, not just the new one,
//   (b) a real bug in the picking maths,
//   (c) a plugin that was never reloaded.
//
// (a) and (b) are now answered here in a second, on every run. (c) is the
// user's machine and no suite can see it - but ruling out the first two is
// what makes it safe to say so.
//
// The 2D editor has had this since the beginning (extract.rb + t1..t45). The
// sheet window never did, which is why 62 KB of it shipped unparsed.
const fs = require('fs');

let fails = 0;
function ok(name, cond, extra) {
  console.log((cond ? 'PASS  ' : 'FAIL  ') + name + (cond ? '' : '   << ' + JSON.stringify(extra)));
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

let loadErr = null;
try { api.call('loadSheet', SHEET); } catch (e) { loadErr = e; }
ok('a sheet can be loaded without throwing', !loadErr, loadErr && String(loadErr));

// render() sets VIEW, which is how a click becomes a place on the plan.
try { api.call('render'); } catch (e) { ok('render throws', false, String(e)); }
const VIEW = api.get('VIEW');
ok('the window worked out how to map the screen to the plan', !!VIEW, VIEW);

// ------------------------------------------------- (b) does picking work?
// Aim at the middle of a label the way a mouse would, through the window's
// own screenOf, so this tests the picking and not my arithmetic.
function at(x, y) { return { clientX: x, clientY: y, preventDefault() {} }; }
function screenOf(mx, my) { return api.call('screenOf', mx, my); }

const roomPt = screenOf(0, 0);
const hit = api.call('hitText', at(roomPt[0], roomPt[1]));
ok('CLICKING A ROOM NAME FINDS IT  <<< the thing the user could not do',
   hit && hit.key === 'ROOMS|ROOM 2|1', hit);

const tagPt = screenOf(120, 60);
const tagHit = api.call('hitText', at(tagPt[0], tagPt[1]));
ok('and clicking a window tag finds the tag',
   tagHit && tagHit.key === 'WINDOWS|W101|1', tagHit);

ok('the nearer of two labels wins, not whichever was drawn first',
   (function () {
     const p = screenOf(0, -12);
     const h = api.call('hitText', at(p[0], p[1]));
     return h && h.key === 'ROOMS|42 SF|1';
   })());

ok('empty paper picks nothing', api.call('hitText', at(5, 5)) === null,
   api.call('hitText', at(5, 5)));

ok('writing on the page itself can be picked too',
   (function () {
     const b = api.call('textBox', SHEET.doc.pages[0].layers[0].shapes[0], true);
     const h = api.call('hitText', at(b.x + b.w / 2, b.y + b.h / 2));
     return h && h.key === 'TITLE|A-101  FLOOR PLAN|1';
   })());

// A label on a switched-off layer is not on the sheet, so it cannot be picked.
api.get('STATE').hidden = ['ROOMS'];
ok('a hidden layer cannot be picked',
   api.call('hitText', at(roomPt[0], roomPt[1])) === null);
api.get('STATE').hidden = [];

// ------------------------------------- (b2) THE REAL ENTRY POINT: two clicks
//
// hitText passing is not the feature. The feature is the handler the browser
// calls, and that handler is hung on the drawing by hookDrag, which render()
// calls. Testing the picker alone would have said "works" while the user sat
// there double-clicking at nothing.
const svgEl = document.getElementById('sheetWrap').firstChild;
ok('the drawing exists to be clicked on', !!svgEl);
ok('and two clicks on it are listened for', typeof (svgEl && svgEl.ondblclick) === 'function',
   typeof (svgEl && svgEl.ondblclick));

api.call('closeTextBar');
let dblErr = null;
try { svgEl.ondblclick(at(roomPt[0], roomPt[1])); } catch (e) { dblErr = e; }
ok('two clicks on a room name does not throw', !dblErr, dblErr && String(dblErr));
ok('TWO CLICKS ON A LABEL OPENS THE PANEL  <<< what the user actually does',
   document.getElementById('textbar').className === 'on',
   document.getElementById('textbar').className);
ok('and it grabs the right label',
   api.get('TSEL') && api.get('TSEL').key === 'ROOMS|ROOM 2|1', api.get('TSEL'));

// Two clicks on empty paper must leave everything alone.
api.call('closeTextBar');
try { svgEl.ondblclick(at(5, 5)); } catch (e) { ok('empty-paper dblclick throws', false, String(e)); }
ok('two clicks on empty paper open nothing',
   document.getElementById('textbar').className === '',
   document.getElementById('textbar').className);

// ------------------------------------------------- the panel and what it sends
api.call('openTextBar', api.call('hitText', at(roomPt[0], roomPt[1])));
ok('the panel opens', document.getElementById('textbar').className === 'on');
ok('it says which label is being changed',
   document.getElementById('txwhat').textContent === 'ROOM 2',
   document.getElementById('txwhat').textContent);
ok('and starts at the size it is now',
   +document.getElementById('txsize').value === 100,
   document.getElementById('txsize').value);

global.sent = [];
document.getElementById('txsize').value = '150';
api.call('sendTextMark');
ok('a new size is sent to Ruby', global.sent.length === 1, global.sent);
ok('under the name of the label, not its position',
   global.sent[0] && JSON.parse(global.sent[0].args[0]).key === 'ROOMS|ROOM 2|1',
   global.sent[0]);
ok('with the number that was typed',
   JSON.parse(global.sent[0].args[0]).pct === 150);
ok('by the callback Ruby is listening on',
   global.sent[0].name === 'set_text_mark', global.sent[0].name);

// Nonsense typed into the box must not travel.
//
// A zero or a minus goes to 100, NOT to the 25 floor - and that is deliberate.
// Nobody means "a quarter of the size" by typing 0; it is a half-finished
// number or a slip, and the kind answer is the normal size rather than writing
// so small he cannot find it again to fix it. Ruby decides the same way, in
// PlanCanvas.text_pct, so the two ends cannot disagree.
[['0', 100], ['-9', 100], ['abc', 100], ['99999', 400]].forEach(function (pair) {
  global.sent = [];
  document.getElementById('txsize').value = pair[0];
  api.call('sendTextMark');
  ok('"' + pair[0] + '" is held to ' + pair[1],
     JSON.parse(global.sent[0].args[0]).pct === pair[1],
     global.sent[0] && global.sent[0].args[0]);
});

api.call('closeTextBar');
ok('the panel closes', document.getElementById('textbar').className === '');
ok('and lets go of the label', api.get('TSEL') === null);

// ------------------------------------------------- the rubber, same window
api.call('setMode', 'erase');
const sitePt = screenOf(120, 200);
ok('the rubber finds a free-geometry line',
   api.call('hitSite', at(sitePt[0], sitePt[1])) === 0,
   api.call('hitSite', at(sitePt[0], sitePt[1])));
ok('and does not find a wall, which would delete from the model',
   (function () {
     const p = screenOf(0, 0);           // on the wall line, far from the site line
     const h = api.call('hitSite', at(p[0], p[1]));
     return h === null || h === 0;       // never anything but the SITE layer
   })());

// ------------------------------------------------- the four group sizes
api.call('setMode', 'hand');
api.call('showTextScale');
ok('the four size boxes are filled in',
   ['tsDims', 'tsRooms', 'tsTags', 'tsTables']
     .every(id => +document.getElementById(id).value === 100));

global.sent = [];
document.getElementById('tsTags').value = '130';
api.call('sendTextScale');
ok('a group size is sent', global.sent.length === 1 &&
   global.sent[0].name === 'set_text_scale', global.sent);
ok('and carries all four, so none is lost',
   Object.keys(JSON.parse(global.sent[0].args[0])).sort().join() ===
   'dims,rooms,tables,tags', global.sent[0].args[0]);
ok('with the one that changed',
   JSON.parse(global.sent[0].args[0]).tags === 130);

// ------------------------------------------------- the panels stay on screen
//
// (2026-08-17) Both bars were positioned inside #stage, which is the element
// that scrolls. Zoom in far enough to need scrolling and they slid away off
// the top with the paper: "אם אני עושה זום אין הוא נעלם לי כי הוא נשאר למעלה".
// A panel you are typing into cannot live inside the thing you are scrolling.
(function () {
  const css = fs.readFileSync('sheet.html', 'utf8');
  ['#textbar', '#notebar'].forEach(function (id) {
    const rule = css.slice(css.indexOf('\n            ' + id + ' {'));
    const block = rule.slice(0, rule.indexOf('}'));
    ok(id + ' floats over the window, not inside the scrolling area',
       /position:fixed/.test(block), block.slice(0, 90));
    ok(id + ' is not positioned inside #stage any more',
       !/position:absolute/.test(block), block.slice(0, 90));
  });
})();

ok('the label panel can be parked out of the way',
   typeof api.get('dragTextBar') === 'function' &&
   typeof api.get('placeTextBar') === 'function');

// Dragged off the edge it could never be dragged back.
(function () {
  const d = src.slice(src.indexOf('function dragTextBar('));
  ok('and it cannot be dragged off the screen',
     /Math\.min\(Math\.max\(ev\.clientX/.test(d) &&
     /Math\.min\(Math\.max\(ev\.clientY/.test(d), d.slice(0, 300));
})();

// ------------------------------------------------- the class of bug, not the bug
//
// The double-click did nothing because it called closeNote(), which is
// declared INSIDE window.addEventListener('load', ...) and does not exist at
// the top level. It threw on the handler's first line, the page swallowed the
// error, and it looked exactly like a feature that had never shipped.
//
// Parsing cannot catch that - the script is perfectly valid JavaScript. So
// check the shape of it: nothing declared inside the load handler may be
// called from outside it.
(function () {
  const i = src.indexOf("window.addEventListener('load'");
  ok('the load handler is where it always was', i > 0, i);
  if (i < 0) return;
  const inside = src.slice(i);
  // Comments stripped first. The note explaining this very bug says
  // "closeNote()" in prose, and a check that trips over its own documentation
  // is a check nobody keeps.
  const outside = src.slice(0, i).replace(/^\s*\/\/.*$/gm, '');

  const declared = [];
  const re = /\n\s{12,}function\s+([A-Za-z_$][\w$]*)\s*\(/g;   // indented = nested
  let m;
  while ((m = re.exec(inside))) declared.push(m[1]);
  ok('there are nested helpers to check', declared.length > 0, declared.length);

  const leaked = declared.filter(function (name) {
    return new RegExp('(?<![\\w$.])' + name + '\\s*\\(').test(outside);
  });
  ok('NOTHING INSIDE THE LOAD HANDLER IS CALLED FROM OUTSIDE IT  <<< the closeNote bug',
     leaked.length === 0, leaked);
})();

console.log(fails === 0 ? '\nALL PASS' : '\n*** ' + fails + ' FAILED ***');
process.exit(fails === 0 ? 0 : 1);
