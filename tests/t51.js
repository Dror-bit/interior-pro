// t51 - the eraser takes dimensions, and a dimension locks onto corners
// (2026-08-19).
//
// The user sent two pictures of SketchUp: the eraser passing over a dimension,
// the dimension lit up blue, an eraser for a cursor. And: "אני דוקר שתי נקודות
// שאגב הלחיצה צריכה להינעל על פינות וקצוות כמו בשאר הכלים".
//
// Before today the eraser rubbed out free SITE geometry and NOTHING else, so
// the only way to lose a dimension was to pick it and press Delete - and when
// the click landed on a label instead of the mark, even that did nothing. That
// is the "אני גם לא יכול למחוק את המידות" he hit.
//
// This suite runs the window's own script. It does not re-implement any of it.

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
    focus() {}, select() {}, addEventListener() {}, removeAttribute() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 800, height: 600 }; },
    clientWidth: 800, clientHeight: 600, firstChild: null
  };
}
const nodes = {};
const calls = [];
const sandbox = {
  console,
  document: {
    getElementById(id) { if (!nodes[id]) { nodes[id] = el(); nodes[id].id = id; } return nodes[id]; },
    createElement() { return el(); },
    createElementNS() { return el(); },
    addEventListener() {}
  },
  window: { addEventListener() {} },
  sketchup: new Proxy({}, { get: (_t, name) => (...a) => calls.push([name, a[0]]) }),
  Image: function () {}, FileReader: function () {},
  JSON, Math, Number, String, Array, Object, parseInt, parseFloat, setTimeout,
  encodeURIComponent
};
sandbox.window.document = sandbox.document;
vm.createContext(sandbox);
vm.runInContext(js, sandbox);

// ------------------------------------------------------- a sheet to work on
//
// 1 model inch = 1 screen pixel, so a distance in the test IS a distance in
// pixels and the snap radius can be reasoned about.
function setup(marks, siteShapes) {
  sandbox.PAGE = { height: 1000, width: 1000, views: [{ canvas: 'MODEL', x: 0, y: 0, w: 1000, h: 1000 }] };
  sandbox.VIEW = { k: 1, sf: 1, cx: 0, cy: 0, toPaper: function (mx, my) { return [mx, my]; } };
  sandbox.DOC = {
    pages: [sandbox.PAGE],
    canvases: [{
      name: 'MODEL',
      layers: [
        { name: 'WALLS', shapes: [
          { type: 'line', x1: 0, y1: 0, x2: 200, y2: 0 },
          { type: 'polygon', points: [[300, 300], [400, 300], [400, 380]] }
        ] },
        { name: 'SITE', shapes: siteShapes || [] }
      ]
    }]
  };
  sandbox.STATE = { marks: marks || [], hidden: [], origin_x: 0, origin_y: 0, active: 0 };
  sandbox.SEL = null;
  // mouseAt() measures from the drawing itself, so there has to BE one
  const svg = el();
  svg.getBoundingClientRect = function () { return { left: 0, top: 0, width: 1000, height: 1000 }; };
  nodes.sheetWrap = el();
  nodes.sheetWrap.id = 'sheetWrap';
  nodes.sheetWrap.firstChild = svg;
  calls.length = 0;
}

// a mouse event landing on a model point (x, y), given the 1:1 setup
function at(x, y) { return { clientX: x, clientY: 1000 - y, stopPropagation() {}, preventDefault() {} }; }

// ------------------------------------------------------------ the cursor

ok('the eraser has a cursor of its own', typeof sandbox.eraserCursor === 'function');
const cur = sandbox.eraserCursor();
ok('and it is a picture, not a crosshair',
   cur.indexOf('data:image/svg+xml') >= 0, cur.slice(0, 40));
ok('with a fallback for a browser that will not take it',
   cur.indexOf('crosshair') > 0, cur.slice(-20));

// -------------------------------------------------- the eraser sees a mark

setup([{ t: 'dim', x1: 0, y1: 0, x2: 200, y2: 0, off: 40 }]);
sandbox.MODE = 'erase';

ok('the eraser knows how to look for anything', typeof sandbox.hitErase === 'function');

// the DIMENSION LINE stands 40 off the wall, so that is where it is grabbed
let hit = sandbox.hitErase(at(100, 40));
ok('THE CHANGE: the eraser finds a dimension where it actually stands',
   hit && hit.kind === 'mark' && hit.i === 0, hit);
ok('and nothing where there is nothing',
   sandbox.hitErase(at(700, 700)) === null, sandbox.hitErase(at(700, 700)));

// a mark WINS over a site line lying under it - it is the small thing on top
setup([{ t: 'dim', x1: 0, y1: 0, x2: 200, y2: 0 }],
      [{ type: 'polyline', points: [[0, 0], [200, 0]] }]);
sandbox.MODE = 'erase';
hit = sandbox.hitErase(at(100, 0));
ok('a dimension wins over a site line lying under it',
   hit && hit.kind === 'mark', hit);

// -------------------------------------------------------- taking them out

setup([{ t: 'dim', x1: 0, y1: 0, x2: 100, y2: 0 },
       { t: 'dim', x1: 0, y1: 50, x2: 100, y2: 50 },
       { t: 'note', x: 10, y: 90, text: 'hi' }]);
sandbox.MODE = 'erase';
sandbox.eraseSweep([{ kind: 'mark', i: 1 }]);
ok('erasing a dimension really removes it', sandbox.STATE.marks.length === 2,
   sandbox.STATE.marks.length);
ok('and it is the RIGHT one', sandbox.STATE.marks[1].t === 'note',
   sandbox.STATE.marks.map(function (m) { return m.t; }));
ok('the settings go back to Ruby', calls.some(c => c[0] === 'set_state'),
   calls.map(c => c[0]));

// a sweep takes several at once, and taking one out must not move the next
setup([{ t: 'dim', x1: 0, y1: 0, x2: 10, y2: 0 },
       { t: 'dim', x1: 0, y1: 10, x2: 10, y2: 10 },
       { t: 'dim', x1: 0, y1: 20, x2: 10, y2: 20 },
       { t: 'dim', x1: 0, y1: 30, x2: 10, y2: 30 }]);
sandbox.MODE = 'erase';
sandbox.eraseSweep([{ kind: 'mark', i: 0 }, { kind: 'mark', i: 2 }]);
ok('a sweep takes them all', sandbox.STATE.marks.length === 2,
   sandbox.STATE.marks.length);
ok('and the ones left are the ones he did NOT cross',
   sandbox.STATE.marks.map(m => m.y1).join(',') === '10,30',
   sandbox.STATE.marks.map(m => m.y1));

// the same item crossed twice in one sweep is still one deletion
setup([{ t: 'dim', x1: 0, y1: 0, x2: 10, y2: 0 },
       { t: 'dim', x1: 0, y1: 10, x2: 10, y2: 10 }]);
sandbox.MODE = 'erase';
sandbox.eraseSweep([{ kind: 'mark', i: 0 }, { kind: 'mark', i: 0 }]);
ok('crossing the same thing twice does not eat its neighbour',
   sandbox.STATE.marks.length === 1 && sandbox.STATE.marks[0].y1 === 10,
   sandbox.STATE.marks.map(m => m.y1));

// site lines go to Ruby in ONE message, not one per line
setup([], [{ type: 'polyline', points: [[0, 0], [10, 0]] },
           { type: 'polyline', points: [[0, 10], [10, 10]] }]);
sandbox.MODE = 'erase';
calls.length = 0;
sandbox.eraseSweep([{ kind: 'site', i: 0 }, { kind: 'site', i: 1 }]);
const drops = calls.filter(c => c[0] === 'drop_site_line');
ok('a sweep of site lines is ONE trip to Ruby, not one per line',
   drops.length === 1, drops.length);
ok('and it names them all', drops[0] && JSON.parse(drops[0][1]).is.length === 2,
   drops[0] && drops[0][1]);

// marks and site lines in one sweep: both happen
setup([{ t: 'dim', x1: 0, y1: 0, x2: 10, y2: 0 }],
      [{ type: 'polyline', points: [[0, 50], [10, 50]] }]);
sandbox.MODE = 'erase';
calls.length = 0;
sandbox.eraseSweep([{ kind: 'mark', i: 0 }, { kind: 'site', i: 0 }]);
ok('a mixed sweep takes the mark', sandbox.STATE.marks.length === 0,
   sandbox.STATE.marks.length);
ok('and asks Ruby for the site line', calls.some(c => c[0] === 'drop_site_line'),
   calls.map(c => c[0]));

ok('an empty sweep does nothing at all and does not throw',
   (function () { sandbox.eraseSweep([]); sandbox.eraseSweep(null); return true; })());

// ------------------------------------------------------------- the snap

setup([]);
sandbox.MODE = 'dim';
ok('the window knows how to lock onto a corner',
   typeof sandbox.snapPoint === 'function');

// the wall runs (0,0) -> (200,0); the triangle has a corner at (400,380)
let s = sandbox.snapPoint([4, 3]);
ok('a click near a wall end locks onto the end',
   close(s[0], 0) && close(s[1], 0), s);
s = sandbox.snapPoint([197, 2]);
ok('and onto the other end', close(s[0], 200) && close(s[1], 0), s);
s = sandbox.snapPoint([398, 377]);
ok('a polygon corner counts too', close(s[0], 400) && close(s[1], 380), s);

s = sandbox.snapPoint([100, 0]);
ok('the MIDDLE of a wall is not a corner - it does not lock',
   close(s[0], 100) && close(s[1], 0), s);
s = sandbox.snapPoint([600, 600]);
ok('and out in the open it leaves the point exactly where it was',
   close(s[0], 600) && close(s[1], 600), s);
ok('nothing to lock onto means no marker', sandbox.SNAPPED === null,
   sandbox.SNAPPED);

s = sandbox.snapPoint([4, 3]);
ok('when it does lock, the marker knows where', sandbox.SNAPPED &&
   close(sandbox.SNAPPED[0], 0) && close(sandbox.SNAPPED[1], 0), sandbox.SNAPPED);

// 12px is the reach, and it is measured on the SCREEN so it does not change
// with the zoom - the whole reason it is not measured in inches
s = sandbox.snapPoint([20, 0]);
ok('a corner too far away does not drag the click to it',
   close(s[0], 20), s);

// a hidden layer offers no corners: what he cannot see, he cannot snap to
setup([]);
sandbox.MODE = 'dim';
sandbox.STATE.hidden = ['WALLS'];
s = sandbox.snapPoint([4, 3]);
ok('a switched-off layer offers nothing to lock onto',
   close(s[0], 4) && close(s[1], 3), s);

// the ends of dimensions already drawn, so a run of them lines up
setup([{ t: 'dim', x1: 500, y1: 500, x2: 600, y2: 500 }]);
sandbox.MODE = 'dim';
sandbox.STATE.hidden = [];
s = sandbox.snapPoint([503, 502]);
ok('a dimension already on the sheet offers its ends too',
   close(s[0], 500) && close(s[1], 500), s);

// ------------------------------------------------ how near is near enough
//
// THE BUG, and it was one number. Over three rounds the user could not pick up
// or erase a dimension. The click probe wrote down every press he made: they
// landed 11 to 43 pixels from the dimension line, most of them 11 to 22. The
// catch radius was 10. Not one of those presses could ever have caught, and
// each of them DID catch one of the 1622 free lines lying over the same spot -
// which is what "המחק מתמקד על קווים שאי אפשר למחוק" was.
//
// So the radius is now 26, and these checks are his own numbers.

ok('a mark is caught from further away than a free line',
   sandbox.MARK_GRAB > sandbox.GRAB, [sandbox.MARK_GRAB, sandbox.GRAB]);

setup([{ t: 'dim', x1: 0, y1: 500, x2: 400, y2: 500 }]);
sandbox.MODE = 'hand';

// his own presses, in pixels off the line
[11, 15, 18, 22, 25].forEach(function (off) {
  const h = sandbox.hitMark(at(200, 500 - off));
  ok('a press ' + off + 'px off the line catches it, as his did not before',
     h !== null && h.i === 0, h);
});
ok('and a press 60px away still does not - it is a catch radius, not a magnet',
   sandbox.hitMark(at(200, 440)) === null, sandbox.hitMark(at(200, 440)));

// the same press, with a free line lying right on top of the dimension
setup([{ t: 'dim', x1: 0, y1: 500, x2: 400, y2: 500 }],
      [{ type: 'polyline', points: [[0, 515], [400, 515]] }]);
sandbox.MODE = 'erase';
const both = sandbox.hitErase(at(200, 513));
ok('with a free line 2px away and the dimension 13px away, the DIMENSION wins',
   both && both.kind === 'mark', both);

console.log(fails === 0 ? 't51 ALL PASS' : 't51 ' + fails + ' FAILED');
process.exit(fails === 0 ? 0 : 1);
