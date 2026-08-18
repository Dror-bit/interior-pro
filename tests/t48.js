// t48 - the snap marker must not disappear after a direction lock.
//
// The bug (2026-08-18, measured): `lockedNow` is only cleared at the TOP of
// chainEnd. Draw one line with Shift held - or let the automatic parallel
// inference lock the direction - and the flag is left true for the rest of
// the session. Hovering afterwards goes through snapPoint, which never
// touches the flag, so `if (snapInd && !lockedNow)` in draw() stays false and
// the green corner ring is never painted again. The point still SNAPS - you
// just cannot see where. The user: "he does not always mark me a point at the
// end of a line or a corner, and I really need it so I do not miss the start
// of a line".
//
// The fix: snapPoint clears the flag. chainEnd sets it again AFTER it calls
// snapPoint, so a real lock is unaffected.
const api = require('./run.js');
const g = (n) => api.get(n), c = (n, ...a) => api.call(n, ...a), s = (n, v) => api.set(n, v);
let fails = 0;
const ok = (n, cd, x) => { console.log((cd ? 'PASS  ' : 'FAIL  ') + n + (cd ? '' : '   << ' + JSON.stringify(x))); if (!cd) fails++; };

function blank() {
  s('walls', []); s('pending', []); s('ghosts', []); s('guides', []);
  s('sketches', []); s('pendingSketches', []); s('pendingRooms', []);
  s('curLine', null); s('drawing', false); s('shiftDown', false);
  s('lockDir', null); s('parInd', null); s('typed', '');
  s('mode', 'line'); s('lineTool', 'line');
}
const near = () => 6 / g('scale');            // 6 screen px from the target
// What draw() asks before it paints the ring, written once.
const ringShows = () => !!(g('snapInd') && !g('lockedNow'));

// --- the marker itself still works ----------------------------------------
blank();
s('sketches', [{ pts: [0, 0, 120, 0], closed: false, gid: 'g1' }]);
s('cursor', { x: 120 + near(), y: near() });
let q = c('snapPoint', g('cursor'), null);
ok('the end of a drawn line still snaps', q.snapped === true, q);
ok('and the ring shows on a clean start', ringShows(), { snapInd: g('snapInd'), lockedNow: g('lockedNow') });

// --- THE BUG: a Shift lock must not blind the marker afterwards -----------
blank();
s('sketches', [{ pts: [0, 0, 120, 0], closed: false, gid: 'g1' }]);
s('curLine', { pts: [{ x: 0, y: 200 }] });
s('shiftDown', true); s('lockDir', { x: 1, y: 0 });
s('cursor', { x: 60, y: 200 });
c('chainEnd', c('chainAnchor'));
ok('a Shift lock does report itself as locked', g('lockedNow') === true, g('lockedNow'));
// he finishes the line and lets go of Shift
s('curLine', null); s('shiftDown', false); s('lockDir', null);
s('cursor', { x: 120 + near(), y: near() });
q = c('snapPoint', g('cursor'), null);
ok('the point is still found after the lock', q.snapped === true, q);
ok('the lock flag is released by a plain hover', g('lockedNow') === false, g('lockedNow'));
ok('so the ring is painted again', ringShows(), { snapInd: g('snapInd'), lockedNow: g('lockedNow') });

// --- same, when the lock came from the AUTOMATIC parallel inference --------
blank();
s('sketches', [{ pts: [0, 0, 120, 0], closed: false, gid: 'g1' }]);
s('curLine', { pts: [{ x: 0, y: 200 }] });
s('cursor', { x: 300, y: 200.2 });            // very nearly parallel
c('chainEnd', c('chainAnchor'));
const wasLocked = g('lockedNow');
s('curLine', null);
s('cursor', { x: 120 + near(), y: near() });
c('snapPoint', g('cursor'), null);
ok('a parallel lock does not blind the marker either',
   !wasLocked || g('lockedNow') === false, { wasLocked: wasLocked, now: g('lockedNow') });
ok('and the ring is painted after it too', ringShows(), { snapInd: g('snapInd'), lockedNow: g('lockedNow') });

// --- the lock itself must keep working ------------------------------------
blank();
s('sketches', [{ pts: [0, 0, 120, 0], closed: false, gid: 'g1' }]);
s('curLine', { pts: [{ x: 0, y: 200 }] });
s('shiftDown', true); s('lockDir', { x: 1, y: 0 });
s('cursor', { x: 60, y: 260 });               // well off the locked ray
const end = c('chainEnd', c('chainAnchor'));
ok('a locked point still lands ON the locked ray', Math.abs(end.y - 200) < 1e-6, end);
ok('and it still reports locked while it holds', g('lockedNow') === true, g('lockedNow'));
ok('so the ring stays hidden while the lock holds', ringShows() === false,
   { snapInd: g('snapInd'), lockedNow: g('lockedNow') });

// --- no leak into the wall tool -------------------------------------------
blank();
s('mode', 'wall');
s('walls', [{ id: 'w1', sx: 0, sy: 0, ex: 120, ey: 0, th: 5, cat: 'exterior' }]);
s('cursor', { x: 120 + near(), y: near() });
q = c('snapPoint', g('cursor'), null);
ok('a wall end still snaps in wall mode', q.snapped === true, q);
ok('and its marker is not blinded', g('lockedNow') === false, g('lockedNow'));

console.log(fails ? '\n*** ' + fails + ' FAILED ***' : '\nALL PASS');
process.exit(fails ? 1 : 0);
