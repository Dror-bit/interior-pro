// t42 - an interior wall stops at the exterior wall (2026-08-14).
//
// He said it plainly, with a screenshot:
//
//   "when I draw an interior wall I cannot cross the exterior wall and I
//    cannot go into it either - it has to stop at the inside face of the
//    exterior wall"
//
// The rule and the maths were already there: clampToBoundary, written
// 2026-08-03. It was reached from exactly ONE place - currentEnd(), the
// path that draws a NEW wall. The screenshot was of the other path: pulling
// an EXISTING wall by its green handle, which computes a length straight
// off the cursor and asked nobody anything. So the wall walked into the
// dark band, and no test noticed, because reading clampToBoundary's source
// proves it exists - not that anything calls it.
//
// This suite runs the real functions, on a real little floor plan, and
// measures where the end actually lands.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const JS = fs.readFileSync(path.join(__dirname, 'out.js'), 'utf8');

let fails = 0;
function ok(n, c, x) {
  console.log((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : '   << ' + JSON.stringify(x)));
  if (!c) fails++;
}
function near(a, b, tol) { return Math.abs(a - b) <= (tol === undefined ? 0.01 : tol); }

function lift(sig) {
  const at = JS.indexOf('function ' + sig);
  if (at < 0) return '';
  let d = 0;
  for (let i = JS.indexOf('{', at); i < JS.length; i++) {
    if (JS[i] === '{') d++;
    if (JS[i] === '}') { d--; if (!d) return JS.slice(at, i + 1); }
  }
  return '';
}

// ---------------------------------------------------------------- the scene
//
// One exterior wall lying flat along the top, 6" thick, anchored 'right' so
// its band hangs BELOW its drawn line: drawn line at y = 0, band from
// y = -6 up to y = 0. The room is underneath it, so the face the room sees -
// the inside face - is y = -6.
//
//        y=0    ________________________  drawn line
//        y=-6   ------------------------  INSIDE face   <- the wall must stop here
//                          |
//                          |  interior wall, pinned at y = -200, pulled up
//
const EXT = { id:'ext', sx:-400, sy:0, ex:400, ey:0, th:6, ha:'right', cat:'exterior' };
const INT = { id:'int', sx:0, sy:-200, ex:0, ey:-100, th:4, ha:'center', cat:'interior' };
const INSIDE_FACE_Y = -6;

const box = { console, walls: [], pending: [], cat: 'interior' };
vm.createContext(box);
['bandQuad(w)', 'lineInt(p1, d1, p2, d2)', 'endCorners(w, all, b)',
 'segCross(a, b, c, d)', 'clampToBoundary(a, bpt, whoWith)',
 'dragLenLimit(d, pinned, sgn, wantLen)'].forEach(function (sig) {
  const src = lift(sig);
  ok('the editor has ' + sig.split('(')[0], !!src, sig);
  vm.runInContext(src, box);
});

// the band really is where this test thinks it is - measure, do not assume
box.walls = [EXT];
const bq = vm.runInContext('bandQuad(walls[0])', box);
const C = vm.runInContext('endCorners(walls[0], walls, bandQuad(walls[0]))', box);
ok('the exterior band hangs below its line, inside face at y = -6',
   near(Math.max(C.sp.y, C.sq.y), 0) && near(Math.min(C.sp.y, C.sq.y), INSIDE_FACE_Y),
   { p: C.sp.y, q: C.sq.y });

// ------------------------------------------------- 1. the drag is held back
box.walls = [EXT, INT];
const pinned = { x: 0, y: -200 };          // the wall's own start, which stays put
const drag = { w: INT, b: bqOf(INT), len: 100, start: 100 };
function bqOf(w) { box.walls = [EXT, INT]; return vm.runInContext(
  'bandQuad(' + JSON.stringify(w) + ')', box); }

function pull(wantLen, d, sgn) {
  return vm.runInContext('dragLenLimit(' +
    JSON.stringify(d || drag) + ',' + JSON.stringify(pinned) + ',' +
    (sgn === undefined ? 1 : sgn) + ',' + wantLen + ')', box);
}

// pinned at y=-200, pulling straight up (+y). Reaching the inside face means
// a length of 194. Anything more would be inside the band or through it.
ok('pulling well short of the wall is left alone', near(pull(120), 120), pull(120));
ok('pulling exactly to the inside face is allowed', near(pull(194), 194, 0.05), pull(194));
ok('pulling INTO the band is cut back to the inside face',
   near(pull(197), 194, 0.05), pull(197));
ok('pulling THROUGH the wall is cut back to the same place, not the far side',
   near(pull(400), 194, 0.05), pull(400));
ok('pulling far past the whole building still stops at the first face',
   near(pull(5000), 194, 0.05), pull(5000));

// ------------------------------------------- 2. who is held back, and who is not
const extDrag = { w: Object.assign({}, INT, { cat: 'exterior' }), b: drag.b, len: 100 };
ok('an EXTERIOR wall is the boundary and is not stopped by one',
   near(pull(400, extDrag), 400), pull(400, extDrag));
const noCat = { w: Object.assign({}, INT, { cat: undefined }), b: drag.b, len: 100 };
ok('a wall with no category written on it counts as exterior, as everywhere else',
   near(pull(400, noCat), 400), pull(400, noCat));

// the tool in his hand must not decide this - the WALL decides
box.cat = 'exterior';
ok('the interior wall is still stopped even while the tool says exterior',
   near(pull(400), 194, 0.05), pull(400));
box.cat = 'interior';

// ------------------------------------------------------ 3. it never gets in the way
ok('shortening is never touched', near(pull(30), 30), pull(30));
ok('a zero-length pull is handed back untouched', near(pull(0), 0), pull(0));
ok('a nonsense drag object does not crash it', pull(400, {}) === 400);
ok('no pinned point does not crash it',
   vm.runInContext('dragLenLimit(' + JSON.stringify(drag) + ', null, 1, 400)', box) === 400);

// with no exterior wall anywhere there is nothing to stop
box.walls = [INT];
ok('with no exterior wall in the drawing nothing is cut', near(pull(400), 400), pull(400));
box.walls = [EXT, INT];

// -------------------------------------------- 4. the drawing path is unchanged
// clampToBoundary with no third argument must behave exactly as before.
box.cat = 'interior';
let r = vm.runInContext('clampToBoundary({x:0,y:-200},{x:0,y:200})', box);
ok('drawing an interior wall still stops at the inside face',
   near(r.y, INSIDE_FACE_Y, 0.05), r);
box.cat = 'exterior';
r = vm.runInContext('clampToBoundary({x:0,y:-200},{x:0,y:200})', box);
ok('drawing an exterior wall is still not clipped', near(r.y, 200), r);
box.cat = 'interior';

// ------------------------------------------ 5. ACCESSIBILITY - is it reached?
//
// The whole reason this bug survived. Two callers must exist, and the drag
// one must apply the limit BEFORE it stores the length.
// The drag maths does not sit in the listener - the listener calls
// handleMove, and handleMove holds it. Walk that whole way down, so this
// cannot pass while the block is orphaned in a function nobody calls.
ok('a real mouse move on the canvas goes to handleMove',
   /cv\.addEventListener\('mousemove', function\(ev\) \{\s*\n?\s*handleMove\(ev\.offsetX, ev\.offsetY\);/.test(JS));
ok('and a mouse move with the button held goes there too',
   /pointermove[\s\S]{0,300}handleMove\(/.test(JS));
const md = lift('handleMove(px, py)');
ok('handleMove is still there to hold it', !!md);
const dragBlock = md.slice(md.indexOf('if (dragEnd) {'),
                           md.indexOf('if (dragDim) {'));
ok('the green-handle drag asks for the limit',
   /dragLenLimit\(dragEnd, fxp, sgn, alen\)/.test(dragBlock), dragBlock.slice(0, 400));
ok('and it asks BEFORE it stores the length, not after',
   dragBlock.indexOf('dragLenLimit(') > 0 &&
   dragBlock.indexOf('dragLenLimit(') < dragBlock.indexOf('dragEnd.len = Math.max(6'),
   { limit: dragBlock.indexOf('dragLenLimit('),
     store: dragBlock.indexOf('dragEnd.len = Math.max(6') });
ok('the drawing path still asks too, both of its branches',
   (lift('currentEnd()').match(/clampToBoundary\(/g) || []).length === 2,
   (lift('currentEnd()').match(/clampToBoundary\(/g) || []).length);
ok('the limit really goes through the shared rule, it is not a second copy',
   /clampToBoundary\(/.test(lift('dragLenLimit(d, pinned, sgn, wantLen)')));

console.log(fails ? `\n*** ${fails} FAILED ***` : '\nALL PASS');
process.exit(fails ? 1 : 0);
