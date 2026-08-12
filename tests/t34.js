// t34 - the BLUE (pending) arc welds onto its neighbour's square cut,
// exactly like the built model does (weld_corner!). Without this the
// preview shows a wedge notch at the seam that the model no longer has.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };
const close = (a, b, tol) => Math.abs(a - b) < (tol || 0.01);

s('sketches', []); s('pendingSketches', []); s('pendingRooms', []); s('mode', 'sel');

// The user's room, shrunk: a straight top wall ending at (200, 100), and a
// big arc from (200, 100) to (200, -100) bulging right (sag -80 = outward).
// The arc's tangent at its start is nearly parallel to the top wall.
var straight = { sx: 0, sy: 100, ex: 200, ey: 100, th: 5, ha: 'left', cat: 'exterior', ops: [] };
var arc = { sx: 200, sy: 100, ex: 200, ey: -100, th: 5, ha: 'left', cat: 'exterior', ops: [], sag: -80 };
s('walls', []);
s('pending', [straight, arc]);

var co = c('curvedOutline', arc);
ok('the pending arc still has a closed outline', co && co.length >= 6, co && co.length);

// The neighbour's square cut at the shared point (200, 100): bandQuad of the
// straight wall, faces at +n*p and +n*q from the endpoint.
var pb = c('bandQuad', straight);
var s1 = { x: 200 + pb.nx * pb.p, y: 100 + pb.ny * pb.p };
var s2 = { x: 200 + pb.nx * pb.q, y: 100 + pb.ny * pb.q };
function hasPt(pts, p) {
  return pts.some(function(q) { return close(q.x, p.x) && close(q.y, p.y); });
}
ok('the arc outline lands EXACTLY on one lip of the neighbour cut', hasPt(co, s1), [s1, co[0], co[co.length - 1]]);
ok('and EXACTLY on the other lip - one shared seam, no notch', hasPt(co, s2), [s2]);

// A steep, honest corner is NOT welded: bow the arc gently so its tangent
// really turns away from the neighbour.
var arc2 = { sx: 200, sy: 100, ex: 200, ey: -100, th: 5, ha: 'left', cat: 'exterior', ops: [], sag: -8 };
s('pending', [straight, arc2]);
var co2 = c('curvedOutline', arc2);
ok('a real corner keeps its own radial cut (no weld)',
   co2 && !(hasPt(co2, s1) && hasPt(co2, s2)), null);

// No neighbour at all -> untouched radial ends.
s('pending', [arc]); s('walls', []);
var co3 = c('curvedOutline', arc);
ok('an arc alone is untouched', co3 && co3.length >= 6, co3 && co3.length);
ok('its drawn-line side still starts on the drawn point',
   close(co3[co3.length - 1].x, 200, 0.5) && close(co3[co3.length - 1].y, 100, 0.5),
   co3[co3.length - 1]);

// The applied wall keeps using the exact footprint from Ruby.
var applied = { id: 'w1', sx: 0, sy: 0, ex: 100, ey: 0, th: 5, sag: 20, fp: [0,0, 50,30, 100,0, 100,-5, 50,25, 0,-5] };
var co4 = c('curvedOutline', applied);
ok('an applied wall still draws the shipped footprint verbatim',
   co4.length === 6 && co4[1].x === 50 && co4[1].y === 30, co4);

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
