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
var s1 = { x: 200 + pb.nx * pb.p, y: 100 + pb.ny * pb.p };   // FAR lip  (200, 105)
var s2 = { x: 200 + pb.nx * pb.q, y: 100 + pb.ny * pb.q };   // near lip (200, 100)
function hasPt(pts, p) {
  return pts.some(function(q) { return close(q.x, p.x) && close(q.y, p.y); });
}

// OPPOSITE-SIDE bands. The two bodies sit on opposite sides of the drawn
// line, so the two cuts share only the drawn corner and are ~10" apart at
// their far lips - well past the "same side" threshold. weld_corner! in
// wall_tool.rb therefore takes its SHOULDER branch: the touching lip is
// pulled onto the owner's FAR lip and the other stays on the natural radial
// cut. Running the Ruby on this exact pair gives corners
// (201.098, 95.122) and (200, 105) - the preview must draw the same two.
ok('the arc outline lands EXACTLY on the neighbour FAR lip', hasPt(co, s1),
   [s1, co[0], co[co.length - 1]]);
ok('the other end keeps its natural radial cut - same as weld_corner!',
   hasPt(co, { x: 201.0976, y: 95.1220 }), [co[0], co[co.length - 1]]);
ok('so the near lip is NOT also grabbed (that would twist the band into a beak)',
   !hasPt(co, s2), [s2]);

// SAME-SIDE bands: an almost-tangent arch springing off a leg. Here the two
// cuts nearly coincide, so the guest snaps EXACTLY onto the owner's cut -
// one shared seam. This is the branch tests/rt31.rb pins on the Ruby side.
var leg  = { sx: 0, sy: 0, ex: 0, ey: 100, th: 5, ha: 'left', cat: 'exterior', ops: [] };
var arch = { sx: 0, sy: 100, ex: 120, ey: 100, th: 5, ha: 'left', cat: 'exterior', ops: [], sag: 55 };
s('pending', [leg, arch]);
var coA = c('curvedOutline', arch);
var lb = c('bandQuad', leg);
var l1 = { x: 0 + lb.nx * lb.p, y: 100 + lb.ny * lb.p };
var l2 = { x: 0 + lb.nx * lb.q, y: 100 + lb.ny * lb.q };
ok('same-side: the arch snaps onto BOTH lips - one exact shared seam',
   coA && hasPt(coA, l1) && hasPt(coA, l2), [l1, l2, coA && coA[0], coA && coA[coA.length - 1]]);
s('pending', [straight, arc]);

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
