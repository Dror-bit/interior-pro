// t53 - pick it up, move it, put it down (2026-08-19).
//
// The user, after the note tool was fixed:
//   "כשאני רוצה להזיז משהו... הוא כאילו מזיז לי שתי נקודות כחולות, ובתכלס אני
//    רוצה שהוא יזיז את הקו או כל דבר אחר בלייב, ואז עוד לחיצה זה יקבע אותם שם.
//    ...מספיק עם העיגולים הכחולים האלו."
//
// So a mark is no longer dragged by a handle. A click PICKS IT UP, it follows
// the mouse with no button held, and the next click PUTS IT DOWN - SketchUp's
// move tool, and Rayon's. Esc while carrying puts it back where it came from,
// so a slip does not cost him the position he had.
//
// Press-and-drag still works for anyone who reaches for it. What decides which
// one happened is whether the mouse moved before the button came up.
//
// This suite drives the window's REAL handlers - svg.onmousedown, onmousemove
// and the mouseup - not a copy of them. That is the only way this class of bug
// gets found here: an error inside a handler is swallowed by the page and a
// dead handler looks exactly like a feature that was never installed (t46).

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const RB = path.join(__dirname, 'plan_sheet_dialog.rb');
const js = fs.readFileSync(RB, 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}
function close(a, b, tol) {
  tol = tol === undefined ? 1e-6 : tol;
  return typeof a === 'number' && typeof b === 'number' && Math.abs(a - b) < tol;
}

function el() {
  return {
    className: '', innerHTML: '', textContent: '', value: '', title: '',
    type: '', checked: false, disabled: false, style: {}, id: '', children: [],
    appendChild(c) { this.children.push(c); return c; },
    querySelector() { return null; },
    focus() {}, select() {}, addEventListener() {},
    setAttribute(k, v) { this[k] = v; }, removeAttribute() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 1000, height: 1000 }; },
    clientWidth: 1000, clientHeight: 1000, firstChild: null
  };
}
const nodes = {};
const calls = [];
const sandbox = {
  console,
  document: {
    getElementById(id) { if (!nodes[id]) { nodes[id] = el(); nodes[id].id = id; } return nodes[id]; },
    createElement() { return el(); }, createElementNS() { return el(); },
    addEventListener() {}
  },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: (_t, n) => (...a) => calls.push([n, a[0]]) }),
  Image: function () {}, FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout,
  encodeURIComponent
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

// 1 model inch = 1 screen pixel, so the numbers in the test are the numbers
// on the screen.
function setup(marks) {
  sandbox.PAGE = { height: 1000, width: 1000, views: [{ canvas: 'MODEL', x: 0, y: 0, w: 1000, h: 1000 }] };
  sandbox.VIEW = { k: 1, sf: 1, cx: 0, cy: 0, toPaper: function (mx, my) { return [mx, my]; } };
  sandbox.DOC = { pages: [sandbox.PAGE], canvases: [{ name: 'MODEL', layers: [] }] };
  sandbox.STATE = { marks: marks || [], hidden: [], origin_x: 0, origin_y: 0, active: 0 };
  sandbox.SEL = null;
  sandbox.MODE = 'hand';
  sandbox.CARRY = null;
  sandbox.MDRAG = null;
  sandbox.SELS = [];
  sandbox.BAND = null;
  const svg = el();
  svg.getBoundingClientRect = function () { return { left: 0, top: 0, width: 1000, height: 1000 }; };
  nodes.sheetWrap = el(); nodes.sheetWrap.id = 'sheetWrap';
  nodes.sheetWrap.firstChild = svg;
  calls.length = 0;
  // render() rebuilds VIEW from the page and the zoom, which would throw away
  // the 1 inch = 1 pixel frame the test is reasoning in. The movement maths is
  // what is under test here, not the redraw, so hold the frame still.
  sandbox.render = function () { };
  return svg;
}
function ev(x, y) {
  return { clientX: x, clientY: 1000 - y, shiftKey: false, button: 0,
           preventDefault() {}, stopPropagation() {} };
}

// A horizontal dimension along y = 500, sitting on the wall it measures.
const DIM = () => ([{ t: 'dim', x1: 100, y1: 500, x2: 500, y2: 500 }]);

let svg = setup(DIM());
ok('the window installs its own mouse handlers',
   typeof svg.onmousedown === 'function' || typeof sandbox.hookDrag === 'function',
   typeof svg.onmousedown);

// hookDrag is what wires them, and render() calls it. Wire them by hand here
// so the real handlers are the ones under test.
sandbox.hookDrag();
svg = nodes.sheetWrap.firstChild;
ok('mousedown is wired', typeof svg.onmousedown === 'function', typeof svg.onmousedown);
ok('mousemove is wired', typeof svg.onmousemove === 'function', typeof svg.onmousemove);
ok('and the window handles movement and release, so a drag survives the '
   + 'mouse leaving the sheet',
   typeof sandbox.onMove === 'function' && typeof sandbox.onUp === 'function',
   [typeof sandbox.onMove, typeof sandbox.onUp]);

// ------------------------------------------------- click, move, click

// The window listens for movement and release on the WINDOW, not on the
// drawing - a drag has to keep working when the mouse leaves the sheet. So
// those are the handlers under test; svg.onmousemove is only the hover.
function move(e) { sandbox.onMove(e); }
function up() { sandbox.onUp(); }

setup(DIM()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;

svg.onmousedown(ev(300, 500));       // press on the dimension
ok('pressing on it picks the mark', sandbox.SEL === 0, sandbox.SEL);
ok('and nothing is being carried yet - the button is still down',
   sandbox.CARRY === null, sandbox.CARRY);

up();                                 // release WITHOUT moving = pick it up
ok('THE CHANGE: letting go without moving PICKS IT UP',
   sandbox.CARRY !== null, sandbox.CARRY);
ok('and it knows which mark it is holding',
   sandbox.CARRY && sandbox.CARRY.i === 0, sandbox.CARRY);
ok('it remembers where the mark was, in case he presses Esc',
   sandbox.CARRY && sandbox.CARRY.snap && sandbox.CARRY.snap.y1 === 500,
   sandbox.CARRY && sandbox.CARRY.snap);

move(ev(300, 620));                   // move with NO button held
const m0 = sandbox.STATE.marks[0];
// Grabbing the LINE of a dimension moves the line, not the thing it measures:
// the two clicked points stay on the wall and `off` is what changes. That is
// the whole point of `off` - see t50.
ok('it follows the mouse with no button held - live',
   close(m0.off, 120), m0.off);
ok('and the points it measures stay ON the wall, where he put them',
   close(m0.x1, 100) && close(m0.y1, 500) &&
   close(m0.x2, 500) && close(m0.y2, 500), [m0.x1, m0.y1, m0.x2, m0.y2]);

calls.length = 0;
svg.onmousedown(ev(300, 620));        // the second click PUTS IT DOWN
ok('the next click puts it down', sandbox.CARRY === null, sandbox.CARRY);
ok('and only then is it saved', calls.some(c => c[0] === 'set_state'),
   calls.map(c => c[0]));
ok('it stayed where he left it',
   close(sandbox.STATE.marks[0].off, 120), sandbox.STATE.marks[0].off);

// a further click does not pick it straight back up by accident
ok('putting it down does not pick it up again', sandbox.CARRY === null);

// ------------------------------------------------------------ Esc puts it back

setup(DIM()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;
svg.onmousedown(ev(300, 500));
up();
move(ev(300, 800));
ok('carried a long way', close(sandbox.STATE.marks[0].off, 300),
   sandbox.STATE.marks[0].off);
sandbox.cancelCarry();
ok('Esc puts it back exactly where it was picked up from',
   !sandbox.STATE.marks[0].off &&
   close(sandbox.STATE.marks[0].y1, 500) && close(sandbox.STATE.marks[0].y2, 500),
   [sandbox.STATE.marks[0].off, sandbox.STATE.marks[0].y1]);
ok('and it is no longer being carried', sandbox.CARRY === null);

// ------------------------------------------------- press-and-drag still works

setup(DIM()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;
svg.onmousedown(ev(300, 500));
move(ev(300, 560));                  // moved WHILE the button is down
ok('dragging with the button down still moves it',
   close(sandbox.STATE.marks[0].off, 60), sandbox.STATE.marks[0].off);
up();
ok('and letting go after a real drag does NOT leave it stuck to the mouse',
   sandbox.CARRY === null, sandbox.CARRY);

// ------------------------------- carrying a NOTE moves the note itself
//
// A note has no `off` - the words, the knee and the arrow are real places, so
// carrying one really does move its coordinates.
setup([{ t: 'note', x: 400, y: 400, kx: 340, ky: 400, lx: 200, ly: 300, text: 'x' }]);
sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;
svg.onmousedown(ev(400, 400));
up();
ok('a note picks up too', sandbox.CARRY !== null, sandbox.CARRY);
move(ev(450, 470));
const nn = sandbox.STATE.marks[0];
ok('and the whole note travels - words and knee together',
   close(nn.x, 450) && close(nn.y, 470) && close(nn.kx, 390) && close(nn.ky, 470),
   [nn.x, nn.y, nn.kx, nn.ky]);
ok('the arrow stays on what it points at',
   close(nn.lx, 200) && close(nn.ly, 300), [nn.lx, nn.ly]);
svg.onmousedown(ev(450, 470));
ok('and the next click puts it down', sandbox.CARRY === null);

// ------------------------------------------------------- no more blue circles

const sel = sandbox.sheetSVG ? null : null;   // sheetSVG needs a whole document
const src = js;
ok('the picked mark is no longer drawn with handle dots',
   src.indexOf("r=\"4\" fill=\"#fff\" stroke=\"#1f6feb\"") < 0,
   'a 4px white dot is still being drawn');
ok('and there is no dot() helper left to draw them',
   src.indexOf('var dot=function(p)') < 0, 'dot() is still there');

// what IS drawn is the thing itself, in blue
ok('a picked dimension is shown by drawing the dimension in blue',
   src.indexOf('// and its witness lines, so the whole dimension reads as') > 0);
ok('and a picked note by drawing its leader in blue',
   src.indexOf('// a note: its leader, drawn over itself in blue') > 0);

// ------------------------------------------- the rubber band, like SketchUp
//
// "כמו בסקאצ'אפ אני רוצה למתוח נגיד ריבוע לבחירת דברים ומחוק ביחד."
//
// Empty paper used to drag the DRAWING around the sheet on this gesture. That
// moved to Alt-drag; the plain one pulls a band. Shift still pans.

function threeDims() {
  return [{ t: 'dim', x1: 100, y1: 100, x2: 300, y2: 100 },
          { t: 'dim', x1: 100, y1: 200, x2: 300, y2: 200 },
          { t: 'dim', x1: 100, y1: 900, x2: 300, y2: 900 }];
}

setup(threeDims()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;

svg.onmousedown(ev(600, 50));          // empty paper
ok('empty paper starts a band, not a drag of the drawing',
   sandbox.BAND !== null, sandbox.BAND);
ok('and the drawing is NOT being dragged', !sandbox.DRAG, sandbox.DRAG);

move(ev(50, 250));                     // pull it back over the first two
ok('the band follows the mouse', sandbox.BAND && sandbox.BAND.moved,
   sandbox.BAND);
up();
ok('letting go picks everything inside it', sandbox.SELS.length === 2,
   sandbox.SELS);
ok('and it is the RIGHT two - the far one is left alone',
   sandbox.SELS.join(',') === '0,1', sandbox.SELS);
ok('the band is gone once it has done its job', sandbox.BAND === null);
ok('SEL still names one of them, for the panels',
   sandbox.SEL === 0, sandbox.SEL);

// carrying moves them ALL, and whole
svg.onmousedown(ev(200, 100));
up();
ok('picking one of a group picks the group up', sandbox.CARRY !== null);
move(ev(260, 160));
ok('both travelled together',
   close(sandbox.STATE.marks[0].y1, 160) && close(sandbox.STATE.marks[1].y1, 260),
   [sandbox.STATE.marks[0].y1, sandbox.STATE.marks[1].y1]);
ok('and WHOLE - both ends of each, not one end',
   close(sandbox.STATE.marks[0].y2, 160) && close(sandbox.STATE.marks[0].x1, 160),
   [sandbox.STATE.marks[0].x1, sandbox.STATE.marks[0].y2]);
ok('the one outside the band never moved',
   close(sandbox.STATE.marks[2].y1, 900), sandbox.STATE.marks[2].y1);
sandbox.cancelCarry();
ok('Esc puts the whole group back',
   close(sandbox.STATE.marks[0].y1, 100) && close(sandbox.STATE.marks[1].y1, 200),
   [sandbox.STATE.marks[0].y1, sandbox.STATE.marks[1].y1]);

// and Delete takes them all
setup(threeDims()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;
svg.onmousedown(ev(600, 50)); move(ev(50, 250)); up();
ok('two picked again', sandbox.SELS.length === 2, sandbox.SELS);
sandbox.dropMark();
ok('Delete takes every one of them', sandbox.STATE.marks.length === 1,
   sandbox.STATE.marks.length);
ok('and the survivor is the one he did not pick',
   close(sandbox.STATE.marks[0].y1, 900), sandbox.STATE.marks[0].y1);
ok('nothing is left picked afterwards',
   sandbox.SELS.length === 0 && sandbox.SEL === null, [sandbox.SELS, sandbox.SEL]);

// a band round nothing clears the pick instead of leaving it stale
setup(threeDims()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;
svg.onmousedown(ev(200, 100)); up();
ok('one picked by clicking', sandbox.SELS.length === 1, sandbox.SELS);
sandbox.CARRY = null;
svg.onmousedown(ev(700, 500)); move(ev(800, 600)); up();
ok('a band round empty paper clears the pick',
   sandbox.SELS.length === 0 && sandbox.SEL === null, [sandbox.SELS, sandbox.SEL]);

// Alt-drag still moves the drawing around the sheet
setup(threeDims()); sandbox.hookDrag(); svg = nodes.sheetWrap.firstChild;
const alt = ev(600, 50); alt.altKey = true;
svg.onmousedown(alt);
ok('Alt-drag still moves the drawing on the sheet, and does NOT band',
   sandbox.BAND === null && !!sandbox.DRAG, [sandbox.BAND, sandbox.DRAG]);

// ------------------------------------------------------------ the cursor

ok('the select tool has a black arrow of its own',
   typeof sandbox.arrowCursor === 'function', typeof sandbox.arrowCursor);
const ac = sandbox.arrowCursor();
ok('and it is a picture, not the grabbing hand',
   ac.indexOf('data:image/svg+xml') >= 0 && ac.indexOf('grab') < 0, ac.slice(0, 40));
ok('it is BLACK', ac.indexOf(encodeURIComponent('fill="#000"')) >= 0, ac.slice(0, 120));
ok('and nothing asks for a grabbing hand any more',
   js.indexOf("'grab'") < 0 && js.indexOf("'grabbing'") < 0,
   'a grab cursor is still in the source');

console.log(fails === 0 ? 't53 ALL PASS' : 't53 ' + fails + ' FAILED');
process.exit(fails === 0 ? 0 : 1);
