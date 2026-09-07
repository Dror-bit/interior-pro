// t58 - THE RIGHT ANGLE WINS OVER THE POINT (2026-09-24).
//
// He kept finishing a house whose corners were 89 and not 90, could not say
// when it happened, and straightening them afterwards left the whole house
// off the red/green axes. Measured cause: every point snap in snapPoint
// RETURNED before the angle snap ever ran. Catch a corner, a midpoint, a
// wall face - or one of the ~7000 endpoints a traced PDF puts on the canvas -
// and the wall took that point's angle, whatever it was.
//
// The rule now: the point sets the LENGTH, the axis sets the DIRECTION.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

function blank() {
  s('walls', []); s('pending', []); s('ghosts', []); s('guides', []);
  s('sketches', []); s('pendingSketches', []); s('curLine', null);
  s('scale', 1); s('snapInd', null);
}
const from = { x: 0, y: 0 };
const angOf = (q) => Math.atan2(q.y - from.y, q.x - from.x) * 180 / Math.PI;

// --- a corner 2.3 degrees off the axis: the wall must still come out square
blank();
s('sketches', [{ pts: [200, 8, 200, 300], closed: false, gid: 'g1' }]);
let q = c('snapPoint', { x: 200, y: 8 }, from);
ok('a corner 2.3deg off -> the wall is square', Math.abs(angOf(q)) < 0.01, q);
ok('and it keeps the length the point gave', Math.abs(q.x - 200) < 0.01, q);
ok('the ring sits where the wall really ends',
   g('snapInd') && Math.abs(g('snapInd').y - q.y) < 1e-9 &&
   Math.abs(g('snapInd').x - q.x) < 1e-9, g('snapInd'));

// --- the same, 8 degrees off, on the green axis
blank();
s('sketches', [{ pts: [30, 200, 200, 200], closed: false, gid: 'g1' }]);
q = c('snapPoint', { x: 30, y: 200 }, from);
ok('a corner 8deg off the green axis -> square', Math.abs(angOf(q) - 90) < 0.01, q);

// --- a midpoint is no different
blank();
s('sketches', [{ pts: [100, 3, 300, 9], closed: false, gid: 'g1' }]);
q = c('snapPoint', { x: 200, y: 6 }, from);
ok('a midpoint 1.7deg off -> square', Math.abs(angOf(q)) < 0.01, q);

// --- the BODY of a line: land ON it and square, not just square
blank();
s('sketches', [{ pts: [200, -400, 210, 400], closed: false, gid: 'g1' }]);
q = c('snapPoint', { x: 202, y: 5 }, from);
ok('a wall face -> square', Math.abs(angOf(q)) < 0.01, q);
ok('and the point still lands ON the face',
   Math.abs(q.x - (200 + 10 * (q.y + 400) / 800)) < 0.05, q);

// --- a deliberate angle outside the window is left exactly alone
blank();
s('sketches', [{ pts: [200, 120, 400, 300], closed: false, gid: 'g1' }]);
q = c('snapPoint', { x: 200, y: 120 }, from);
ok('31deg off is outside the window and keeps the exact point',
   Math.abs(q.x - 200) < 1e-9 && Math.abs(q.y - 120) < 1e-9, q);

// --- an already-square corner is untouched, to the last decimal
blank();
s('sketches', [{ pts: [240, 0, 240, 300], closed: false, gid: 'g1' }]);
q = c('snapPoint', { x: 240, y: 0 }, from);
ok('a square corner is hit exactly', Math.abs(q.x - 240) < 1e-9 && Math.abs(q.y) < 1e-9, q);

// --- NOT drawing (from = null): the point is the point, nothing is bent
blank();
s('sketches', [{ pts: [200, 8, 200, 300], closed: false, gid: 'g1' }]);
q = c('snapPoint', { x: 200, y: 8 }, null);
ok('with no chain to draw from the raw point is returned',
   q.snapped === true && Math.abs(q.y - 8) < 1e-9, q);

console.log(fails ? ('*** ' + fails + ' FAILED ***') : 'all good');
process.exit(fails ? 1 : 0);
